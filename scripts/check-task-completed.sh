#!/bin/bash
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

INPUT="$(cat)"
TASK_ID="$(printf '%s' "$INPUT" | jq -r '.task_id // ""')"

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

  resolved="$(resolve_state_root_from_candidate "${CLAUDE_PROJECT_DIR:-}")"
  if [ -n "$resolved" ]; then
    printf '%s\n' "$resolved"
    return
  fi

  local cwd
  cwd="$(printf '%s' "$INPUT" | jq -r '.cwd // ""')"
  resolved="$(resolve_state_root_from_candidate "$cwd")"
  if [ -n "$resolved" ]; then
    printf '%s\n' "$resolved"
  fi
}

PROJECT_DIR="$(resolve_project_dir)"

if [ -z "$TASK_ID" ]; then
  echo "TaskCompleted missing task_id" >&2
  exit 2
fi

if [ -z "$PROJECT_DIR" ]; then
  exit 0
fi

STATE_FILE="$PROJECT_DIR/.claude/flow_state.json"
if ! jq empty "$STATE_FILE" >/dev/null 2>&1; then
  exit 0
fi

if ! jq -e '.workflow.active == true' "$STATE_FILE" >/dev/null 2>&1; then
  exit 0
fi

if ! jq -e --arg task_id "$TASK_ID" '
  .review.tasks[$task_id].spec_review_passed == true
  and .review.tasks[$task_id].code_review_passed == true
' "$STATE_FILE" >/dev/null 2>&1; then
  echo "Task 标记完成前，必须完成两阶段 review。" >&2
  exit 2
fi
