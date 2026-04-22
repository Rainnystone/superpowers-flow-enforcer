#!/bin/bash
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

INPUT="$(cat)"
TASK_ID="$(printf '%s' "$INPUT" | jq -r '.task_id // ""')"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/workflow_paths.sh
source "$SCRIPT_DIR/lib/workflow_paths.sh"

resolve_project_dir() {
  local resolved=""

  resolved="$(workflow_paths_resolve_state_root_from_candidate "${CLAUDE_PROJECT_DIR:-}")"
  if [ -n "$resolved" ]; then
    printf '%s\n' "$resolved"
    return
  fi

  local cwd
  cwd="$(printf '%s' "$INPUT" | jq -r '.cwd // ""')"
  resolved="$(workflow_paths_resolve_state_root_from_candidate "$cwd")"
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
