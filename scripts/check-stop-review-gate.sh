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

input_string() {
  local expr="$1"
  printf '%s' "$INPUT" | jq -r "
    if ($expr | type) == \"string\" then
      $expr
    else
      \"\"
    end
  " 2>/dev/null || true
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

completion_claim_detected() {
  local message="$1"
  [ -n "$message" ] || return 1
  printf '%s' "$message" | grep -Eiq '(^|[^[:alpha:]])(done|complete|completed|finished)([^[:alpha:]]|$)|完成|修复|已完成|已修复|搞定'
}

fresh_passing_evidence_detected() {
  local message="$1"
  [ -n "$message" ] || return 1

  if printf '%s' "$message" | grep -Eiq '(^|[^[:alpha:]])[0-9]+ passed([^[:alpha:]]|$)|(^|[^[:alpha:]])PASS([^[:alpha:]]|$)|0 failed|0 failures'; then
    return 0
  fi

  printf '%s' "$message" | grep -Eiq \
    '(bash |sh |npm (test|run)|pnpm (test|lint|build|exec)|yarn (test|lint|build)|pytest|python -m pytest|uv run|go test|cargo test|make test|ctest|vitest|jest|deno test)' \
    || return 1

  printf '%s' "$message" | grep -Eiq \
    '(^|[^[:alpha:]])(pass|passed|success|successful|succeeded|green)([^[:alpha:]]|$)|0 failed|0 failures|exit 0|通过|成功' \
    || return 1
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

SKIP_REVIEW_CONFIRMED=false
if state_expr_is_true '.exceptions.skip_review' && state_expr_is_true '.exceptions.user_confirmed'; then
  SKIP_REVIEW_CONFIRMED=true
fi

if [ "$SKIP_REVIEW_CONFIRMED" != true ] && ! has_review_records; then
  block_stop '还没有 review 记录，先执行 requesting-code-review 的两阶段评审。'
  exit 0
fi

SKIP_FINISHING_CONFIRMED=false
if state_expr_is_true '.exceptions.skip_finishing' && state_expr_is_true '.exceptions.user_confirmed'; then
  SKIP_FINISHING_CONFIRMED=true
fi

if [ "$SKIP_FINISHING_CONFIRMED" != true ] && all_reviews_passed && ! state_expr_is_true '.finishing.invoked'; then
  block_stop '所有任务都已 review，通过后还需执行 finishing-a-development-branch。'
  exit 0
fi

LAST_ASSISTANT_MESSAGE="$(input_string '.last_assistant_message')"
if completion_claim_detected "$LAST_ASSISTANT_MESSAGE" && ! fresh_passing_evidence_detected "$LAST_ASSISTANT_MESSAGE"; then
  block_stop 'Completion claimed without fresh verification evidence. Run verification now and show output.'
  exit 0
fi

exit 0
