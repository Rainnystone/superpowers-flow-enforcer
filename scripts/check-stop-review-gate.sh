#!/bin/bash
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

INPUT="$(cat)"
if ! printf '%s' "$INPUT" | jq empty >/dev/null 2>&1; then
  exit 0
fi

resolve_state_root_from_candidate() {
  local candidate="$1"

  if [ -z "$candidate" ]; then
    return
  fi

  local current="$candidate"
  if [ ! -d "$current" ]; then
    current="$(dirname "$current")"
  fi

  if [ ! -d "$current" ]; then
    return
  fi

  current="$(cd "$current" 2>/dev/null && pwd -P)" || return

  while :; do
    if [ -f "$current/.claude/flow_state.json" ]; then
      printf '%s\n' "$current"
      return
    fi

    if [ "$current" = "/" ]; then
      return
    fi

    current="$(dirname "$current")"
  done
}

resolve_project_dir() {
  local resolved=""

  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    resolved="$(resolve_state_root_from_candidate "$CLAUDE_PROJECT_DIR")"
    if [ -n "$resolved" ]; then
      printf '%s\n' "$resolved"
      return
    fi
  fi

  local hook_cwd
  hook_cwd="$(printf '%s' "$INPUT" | jq -r '
    if (.cwd | type) == "string" and .cwd != "" then
      .cwd
    else
      empty
    end
  ' 2>/dev/null || true)"

  if [ -n "$hook_cwd" ]; then
    resolved="$(resolve_state_root_from_candidate "$hook_cwd")"
    if [ -n "$resolved" ]; then
      printf '%s\n' "$resolved"
      return
    fi
  fi
}

block_stop() {
  local reason="$1"
  jq -n --arg reason "$reason" '{
    decision: "block",
    reason: $reason
  }'
}

input_expr_is_true() {
  local expr="$1"
  printf '%s' "$INPUT" | jq -e "$expr == true" >/dev/null 2>&1
}

state_expr_is_true() {
  local expr="$1"
  jq -e "$expr == true" "$STATE_FILE" >/dev/null 2>&1
}

all_reviews_passed() {
  jq -e '
    (.review.tasks | type) == "object"
    and (.review.tasks | length) > 0
    and all(
      .review.tasks[]?;
      (.spec_review_passed == true) and (.code_review_passed == true)
    )
  ' "$STATE_FILE" >/dev/null 2>&1
}

has_review_records() {
  jq -e '
    (.review.tasks | type) == "object"
    and (.review.tasks | length) > 0
  ' "$STATE_FILE" >/dev/null 2>&1
}

PROJECT_DIR="$(resolve_project_dir)"
STATE_FILE="$PROJECT_DIR/.claude/flow_state.json"

if [ -z "$PROJECT_DIR" ]; then
  exit 0
fi

if ! jq empty "$STATE_FILE" >/dev/null 2>&1; then
  exit 0
fi

if input_expr_is_true '.stop_hook_active'; then
  exit 0
fi

if state_expr_is_true '.interrupt.allowed'; then
  exit 0
fi

if ! state_expr_is_true '.workflow.active'; then
  exit 0
fi

if state_expr_is_true '.exceptions.skip_review' && state_expr_is_true '.exceptions.user_confirmed'; then
  exit 0
fi

if ! has_review_records; then
  block_stop '还没有 review 记录，先执行 requesting-code-review 的两阶段评审。'
  exit 0
fi

if state_expr_is_true '.exceptions.skip_finishing' && state_expr_is_true '.exceptions.user_confirmed'; then
  exit 0
fi

if all_reviews_passed && ! state_expr_is_true '.finishing.invoked'; then
  block_stop '所有任务都已 review，通过后还需执行 finishing-a-development-branch。'
  exit 0
fi

exit 0
