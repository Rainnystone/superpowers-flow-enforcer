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

assert_json_matches_utc_iso8601() {
  local file="$1" jq_expr="$2"

  if ! jq -e "$jq_expr | type == \"string\" and test(\"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$\")" "$file" >/dev/null; then
    echo "Expected $jq_expr to be a UTC ISO-8601 timestamp" >&2
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
bash scripts/update-state.sh --jq '.resume.recovery_required = false | .resume.recovery_completed_at = null | .resume.last_resume_source = null' >/dev/null
before_no_recovery="$(cat "$STATE_FILE")"
assert_command_fails "recovery not required" bash scripts/record-resume-state.sh completed resume
after_no_recovery="$(cat "$STATE_FILE")"
if [ "$before_no_recovery" != "$after_no_recovery" ]; then
  echo "Expected state to remain unchanged when recovery is not required" >&2
  exit 1
fi

assert_file_exists "$SKILL_FILE"
assert_file_contains_all "$SKILL_FILE" \
  ".claude/flow_state.json" \
  "If any of \`task_plan.md\`, \`progress.md\`, or \`findings.md\` exist at the project root, read the root-level planning files that exist." \
  "Only if none of those root-level planning files exist, read \`.planning-with-files/task_plan.md\`, \`.planning-with-files/progress.md\`, and \`.planning-with-files/findings.md\` when present." \
  "If neither planning location exists, continue recovery using state plus git context." \
  "git status --short" \
  "git diff --stat" \
  "current phase" \
  "open task / review state" \
  "last confirmed progress point" \
  "next required action" \
  'bash "${CLAUDE_PLUGIN_ROOT}/scripts/record-resume-state.sh" completed resume'

bash scripts/update-state.sh --jq '.resume.recovery_required = true | .resume.recovery_completed_at = null | .resume.last_resume_source = "resume"' >/dev/null
bash scripts/record-resume-state.sh completed resume

assert_json_equals "$STATE_FILE" '.resume.recovery_required' 'false'
assert_json_equals "$STATE_FILE" '.resume.last_resume_source' '"resume"'
assert_json_matches_utc_iso8601 "$STATE_FILE" '.resume.recovery_completed_at'
