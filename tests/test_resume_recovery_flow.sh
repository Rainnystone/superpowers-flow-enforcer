#!/bin/bash
set -euo pipefail

source tests/helpers/assert.sh
source tests/helpers/state-fixtures.sh

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

assert_command_fails() {
  local description="$1"
  shift

  if "$@" >/dev/null 2>&1; then
    echo "Expected failure: $description" >&2
    exit 1
  fi
}

assert_json_is_non_empty_string() {
  local file="$1" jq_expr="$2"

  if ! jq -e "$jq_expr | type == \"string\" and length > 0" "$file" >/dev/null; then
    echo "Expected $jq_expr to be a non-empty string" >&2
    exit 1
  fi
}

assert_file_contains_all() {
  local file="$1"
  shift

  local pattern
  for pattern in "$@"; do
    assert_file_contains "$file" "$pattern"
  done
}

export CLAUDE_PLUGIN_ROOT="$(pwd)"
export CLAUDE_PROJECT_DIR="$TMP_DIR/project"

STATE_FILE="$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
SKILL_FILE="skills/resume-enforcer/SKILL.md"

mkdir -p "$CLAUDE_PROJECT_DIR/.claude"
write_v2_state "$STATE_FILE"
jq '
  .current_phase = "review"
  | .workflow.active = true
  | .planning.plan_written = true
  | .task_flow.active_task_id = "task-005"
  | .review.tasks["task-005"] = {
      "spec_review_passed": true,
      "code_review_passed": false
    }
  | .resume.recovery_required = true
  | .resume.last_resume_source = "resume"
' "$STATE_FILE" > "$STATE_FILE.tmp"
mv "$STATE_FILE.tmp" "$STATE_FILE"

assert_command_fails "missing arguments" bash scripts/record-resume-state.sh
assert_command_fails "missing source argument" bash scripts/record-resume-state.sh completed
assert_command_fails "unsupported action" bash scripts/record-resume-state.sh pending resume

assert_file_exists "$SKILL_FILE"
assert_file_contains_all "$SKILL_FILE" \
  ".claude/flow_state.json" \
  ".planning-with-files/task_plan.md" \
  ".planning-with-files/progress.md" \
  ".planning-with-files/findings.md" \
  "git status --short" \
  "git diff --stat" \
  "current phase" \
  "open task / review state" \
  "last confirmed progress point" \
  "next required action" \
  'bash ${CLAUDE_PLUGIN_ROOT}/scripts/record-resume-state.sh completed resume'

bash scripts/record-resume-state.sh completed resume

assert_json_equals "$STATE_FILE" '.resume.recovery_required' 'false'
assert_json_equals "$STATE_FILE" '.resume.last_resume_source' '"resume"'
assert_json_is_non_empty_string "$STATE_FILE" '.resume.recovery_completed_at'
