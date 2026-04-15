#!/bin/bash
set -euo pipefail

source tests/helpers/assert.sh
source tests/helpers/state-fixtures.sh

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

assert_fresh_v2_state() {
  local file="$1"
  assert_json_equals "$file" '.state_version' '2'
  assert_json_equals "$file" '.current_phase' '"init"'
  assert_json_equals "$file" '.brainstorming.question_asked' 'false'
  assert_json_equals "$file" '.brainstorming.findings_updated_after_question' 'false'
  assert_json_equals "$file" '.worktree.baseline_verified' 'false'
  assert_json_equals "$file" '.tdd.pending_failure_record' 'false'
  assert_json_equals "$file" '.tdd.last_failed_command' 'null'
  assert_json_equals "$file" '.workflow.active' 'false'
  assert_json_equals "$file" '.workflow.activated_by' 'null'
  assert_json_equals "$file" '.workflow.activated_at' 'null'
  assert_json_equals "$file" '.workflow.override' 'null'
  assert_json_equals "$file" '.workflow.deactivated_by' 'null'
  assert_json_equals "$file" '.workflow.deactivated_at' 'null'
  assert_json_equals "$file" '.task_flow.active_task_id' 'null'
  assert_json_equals "$file" '.task_flow.active_packet_role' 'null'
  assert_json_equals "$file" '.task_flow.last_dispatch_at' 'null'
  assert_json_equals "$file" '.resume.recovery_required' 'false'
  assert_json_equals "$file" '.resume.recovery_completed_at' 'null'
  assert_json_equals "$file" '.resume.last_resume_source' 'null'
}

assert_backup_matches_original() {
  local original="$1" backup="$2"
  cmp -s "$original" "$backup" || {
    echo "Expected backup $backup to match original $original" >&2
    exit 1
  }
}

write_resume_candidate_state() {
  local file="$1"
  write_v2_state "$file"
  jq '
    .current_phase = "planning"
    | .planning.plan_written = true
    | .workflow.active = true
    | .workflow.activated_by = "manual-control"
    | .workflow.activated_at = "2026-04-15T10:00:00Z"
    | .task_flow.active_task_id = "task-001"
    | .task_flow.active_packet_role = "implementer"
    | .task_flow.last_dispatch_at = "2026-04-15T10:10:00Z"
    | .review.tasks["task-001"] = {
        "spec_review_passed": false,
        "code_review_passed": false
      }
    | .tdd.test_files_created = ["tests/example.test.sh"]
  ' "$file" > "$file.tmp"
  mv "$file.tmp" "$file"
}

write_clean_finished_workflow_state() {
  local file="$1"
  write_resume_candidate_state "$file"
  jq '
    .finishing.invoked = true
    | .task_flow.active_task_id = null
    | .task_flow.active_packet_role = null
    | .review.tasks["task-001"].spec_review_passed = true
    | .review.tasks["task-001"].code_review_passed = true
  ' "$file" > "$file.tmp"
  mv "$file.tmp" "$file"
}

write_active_no_progress_state() {
  local file="$1"
  write_v2_state "$file"
  jq '
    .workflow.active = true
    | .workflow.activated_by = "manual-control"
    | .workflow.activated_at = "2026-04-15T10:00:00Z"
  ' "$file" > "$file.tmp"
  mv "$file.tmp" "$file"
}

export CLAUDE_PLUGIN_ROOT="$(pwd)"

unset CLAUDE_PROJECT_DIR

SESSION_CWD="$TMP_DIR/session-start"
mkdir -p "$SESSION_CWD"

printf '{"hook_event_name":"SessionStart","cwd":"%s"}' "$SESSION_CWD" \
  | bash scripts/init-state.sh >/dev/null

assert_file_exists "$SESSION_CWD/.claude/flow_state.json"
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.workflow.active' 'false'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.workflow.override' 'null'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.workflow.deactivated_by' 'null'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.workflow.deactivated_at' 'null'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.task_flow.active_task_id' 'null'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.task_flow.active_packet_role' 'null'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.task_flow.last_dispatch_at' 'null'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.resume.recovery_required' 'false'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.resume.recovery_completed_at' 'null'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.resume.last_resume_source' 'null'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.project_dir' "\"$SESSION_CWD\""

write_v2_state_without_workflow "$SESSION_CWD/.claude/flow_state.json"

printf '{"hook_event_name":"SessionStart","cwd":"%s"}' "$SESSION_CWD" \
  | bash scripts/init-state.sh >/dev/null

assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.state_version' '2'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.workflow.active' 'false'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.workflow.activated_by' 'null'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.workflow.override' 'null'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.workflow.deactivated_by' 'null'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.workflow.deactivated_at' 'null'

write_v2_state_with_partial_workflow_override "$SESSION_CWD/.claude/flow_state.json"
rm -f "$SESSION_CWD/.claude/flow_state.json.bak"

printf '{"hook_event_name":"SessionStart","cwd":"%s"}' "$SESSION_CWD" \
  | bash scripts/init-state.sh >/dev/null

assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.state_version' '2'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.workflow.active' 'false'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.workflow.activated_by' 'null'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.workflow.activated_at' 'null'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.workflow.override' 'null'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.workflow.deactivated_by' 'null'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.workflow.deactivated_at' 'null'
if [ -e "$SESSION_CWD/.claude/flow_state.json.bak" ]; then
  echo "Expected old v2 workflow state to normalize missing new workflow fields in place" >&2
  exit 1
fi

write_v2_state_without_task_flow "$SESSION_CWD/.claude/flow_state.json"
rm -f "$SESSION_CWD/.claude/flow_state.json.bak"

printf '{"hook_event_name":"SessionStart","cwd":"%s"}' "$SESSION_CWD" \
  | bash scripts/init-state.sh >/dev/null

assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.state_version' '2'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.task_flow.active_task_id' 'null'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.task_flow.active_packet_role' 'null'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.task_flow.last_dispatch_at' 'null'
if [ -e "$SESSION_CWD/.claude/flow_state.json.bak" ]; then
  echo "Expected missing task_flow state to normalize in place without backup" >&2
  exit 1
fi

write_v2_state_with_partial_task_flow "$SESSION_CWD/.claude/flow_state.json"
rm -f "$SESSION_CWD/.claude/flow_state.json.bak"

printf '{"hook_event_name":"SessionStart","cwd":"%s"}' "$SESSION_CWD" \
  | bash scripts/init-state.sh >/dev/null

assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.state_version' '2'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.task_flow.active_task_id' 'null'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.task_flow.active_packet_role' 'null'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.task_flow.last_dispatch_at' 'null'
if [ -e "$SESSION_CWD/.claude/flow_state.json.bak" ]; then
  echo "Expected partial task_flow state to normalize in place without backup" >&2
  exit 1
fi

write_v2_state_without_resume "$SESSION_CWD/.claude/flow_state.json"
rm -f "$SESSION_CWD/.claude/flow_state.json.bak"

printf '{"hook_event_name":"SessionStart","cwd":"%s"}' "$SESSION_CWD" \
  | bash scripts/init-state.sh >/dev/null

assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.state_version' '2'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.resume.recovery_required' 'false'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.resume.recovery_completed_at' 'null'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.resume.last_resume_source' 'null'
if [ -e "$SESSION_CWD/.claude/flow_state.json.bak" ]; then
  echo "Expected missing resume state to normalize in place without backup" >&2
  exit 1
fi

write_v2_state_with_partial_resume "$SESSION_CWD/.claude/flow_state.json"
rm -f "$SESSION_CWD/.claude/flow_state.json.bak"

printf '{"hook_event_name":"SessionStart","cwd":"%s"}' "$SESSION_CWD" \
  | bash scripts/init-state.sh >/dev/null

assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.state_version' '2'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.resume.recovery_required' 'false'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.resume.recovery_completed_at' 'null'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.resume.last_resume_source' 'null'
if [ -e "$SESSION_CWD/.claude/flow_state.json.bak" ]; then
  echo "Expected partial resume state to normalize in place without backup" >&2
  exit 1
fi

write_v2_state "$SESSION_CWD/.claude/flow_state.json"
jq '
  .workflow.activated_by = "system"
  | .workflow.activated_at = "2026-04-15T10:00:00Z"
  | .workflow.override = "manual-control"
  | .workflow.deactivated_by = "system"
  | .workflow.deactivated_at = "2026-04-15T10:05:00Z"
' "$SESSION_CWD/.claude/flow_state.json" > "$SESSION_CWD/.claude/flow_state.json.tmp"
mv "$SESSION_CWD/.claude/flow_state.json.tmp" "$SESSION_CWD/.claude/flow_state.json"
cp "$SESSION_CWD/.claude/flow_state.json" "$SESSION_CWD/.claude/flow_state.before.json"
rm -f "$SESSION_CWD/.claude/flow_state.json.bak"

printf '{"hook_event_name":"SessionStart","cwd":"%s"}' "$SESSION_CWD" \
  | bash scripts/init-state.sh >/dev/null

cmp -s \
  "$SESSION_CWD/.claude/flow_state.json" \
  "$SESSION_CWD/.claude/flow_state.before.json" || {
  echo "Expected valid default resume state to remain unchanged during init normalization" >&2
  exit 1
}
if [ -e "$SESSION_CWD/.claude/flow_state.json.bak" ]; then
  echo "Expected valid default resume state to remain valid without backup" >&2
  exit 1
fi

write_v2_state_with_partial_workflow "$SESSION_CWD/.claude/flow_state.json"
rm -f "$SESSION_CWD/.claude/flow_state.json.bak"

printf '{"hook_event_name":"SessionStart","cwd":"%s"}' "$SESSION_CWD" \
  | bash scripts/init-state.sh >/dev/null

assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.state_version' '2'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.workflow.active' 'false'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.workflow.activated_by' 'null'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.workflow.activated_at' 'null'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.workflow.override' 'null'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.workflow.deactivated_by' 'null'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.workflow.deactivated_at' 'null'
if [ -e "$SESSION_CWD/.claude/flow_state.json.bak" ]; then
  echo "Expected partial workflow state to normalize in place without backup" >&2
  exit 1
fi

write_v2_state_with_missing_active "$SESSION_CWD/.claude/flow_state.json"
rm -f "$SESSION_CWD/.claude/flow_state.json.bak"

printf '{"hook_event_name":"SessionStart","cwd":"%s"}' "$SESSION_CWD" \
  | bash scripts/init-state.sh >/dev/null

assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.state_version' '2'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.workflow.active' 'false'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.workflow.activated_by' 'null'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.workflow.activated_at' 'null'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.workflow.override' 'null'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.workflow.deactivated_by' 'null'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.workflow.deactivated_at' 'null'
if [ -e "$SESSION_CWD/.claude/flow_state.json.bak" ]; then
  echo "Expected missing-active workflow state to normalize in place without backup" >&2
  exit 1
fi

write_v2_state_with_broken_workflow "$SESSION_CWD/.claude/flow_state.json"
export CLAUDE_PROJECT_DIR="$SESSION_CWD"
cp "$SESSION_CWD/.claude/flow_state.json" "$TMP_DIR/unsafe-workflow.original"

if ! bash scripts/init-state.sh >/tmp/test-init-state.out 2>/tmp/test-init-state.err; then
  echo "Expected init-state.sh to recover from unsafe v2 workflow scalar" >&2
  cat /tmp/test-init-state.err >&2
  exit 1
fi

assert_file_exists "$SESSION_CWD/.claude/flow_state.json.bak"
assert_backup_matches_original "$TMP_DIR/unsafe-workflow.original" "$SESSION_CWD/.claude/flow_state.json.bak"
assert_fresh_v2_state "$SESSION_CWD/.claude/flow_state.json"

write_v2_state_with_invalid_workflow_override_types "$SESSION_CWD/.claude/flow_state.json"
cp "$SESSION_CWD/.claude/flow_state.json" "$TMP_DIR/unsafe-workflow-override-fields.original"

if ! bash scripts/init-state.sh >/tmp/test-init-state.out 2>/tmp/test-init-state.err; then
  echo "Expected init-state.sh to recover from unsafe v2 workflow override field types" >&2
  cat /tmp/test-init-state.err >&2
  exit 1
fi

assert_file_exists "$SESSION_CWD/.claude/flow_state.json.bak"
assert_backup_matches_original "$TMP_DIR/unsafe-workflow-override-fields.original" "$SESSION_CWD/.claude/flow_state.json.bak"
assert_fresh_v2_state "$SESSION_CWD/.claude/flow_state.json"

write_v2_state_with_invalid_workflow_types "$SESSION_CWD/.claude/flow_state.json"
cp "$SESSION_CWD/.claude/flow_state.json" "$TMP_DIR/unsafe-workflow-fields.original"

if ! bash scripts/init-state.sh >/tmp/test-init-state.out 2>/tmp/test-init-state.err; then
  echo "Expected init-state.sh to recover from unsafe v2 workflow field types" >&2
  cat /tmp/test-init-state.err >&2
  exit 1
fi

assert_file_exists "$SESSION_CWD/.claude/flow_state.json.bak"
assert_backup_matches_original "$TMP_DIR/unsafe-workflow-fields.original" "$SESSION_CWD/.claude/flow_state.json.bak"
assert_fresh_v2_state "$SESSION_CWD/.claude/flow_state.json"

write_v2_state_with_invalid_task_flow_role_string "$SESSION_CWD/.claude/flow_state.json"
rm -f "$SESSION_CWD/.claude/flow_state.json.bak"
cp "$SESSION_CWD/.claude/flow_state.json" "$TMP_DIR/unsafe-task-flow-role-string.original"

if ! bash scripts/init-state.sh >/tmp/test-init-state.out 2>/tmp/test-init-state.err; then
  echo "Expected init-state.sh to recover from invalid task_flow role string" >&2
  cat /tmp/test-init-state.err >&2
  exit 1
fi

assert_file_exists "$SESSION_CWD/.claude/flow_state.json.bak"
assert_backup_matches_original "$TMP_DIR/unsafe-task-flow-role-string.original" "$SESSION_CWD/.claude/flow_state.json.bak"
assert_fresh_v2_state "$SESSION_CWD/.claude/flow_state.json"

write_v2_state_with_invalid_task_flow_role_type "$SESSION_CWD/.claude/flow_state.json"
rm -f "$SESSION_CWD/.claude/flow_state.json.bak"
cp "$SESSION_CWD/.claude/flow_state.json" "$TMP_DIR/unsafe-task-flow-role-type.original"

if ! bash scripts/init-state.sh >/tmp/test-init-state.out 2>/tmp/test-init-state.err; then
  echo "Expected init-state.sh to recover from invalid task_flow role type" >&2
  cat /tmp/test-init-state.err >&2
  exit 1
fi

assert_file_exists "$SESSION_CWD/.claude/flow_state.json.bak"
assert_backup_matches_original "$TMP_DIR/unsafe-task-flow-role-type.original" "$SESSION_CWD/.claude/flow_state.json.bak"
assert_fresh_v2_state "$SESSION_CWD/.claude/flow_state.json"

write_v2_state_with_non_object_task_flow "$SESSION_CWD/.claude/flow_state.json"
rm -f "$SESSION_CWD/.claude/flow_state.json.bak"
cp "$SESSION_CWD/.claude/flow_state.json" "$TMP_DIR/unsafe-task-flow-non-object.original"

if ! bash scripts/init-state.sh >/tmp/test-init-state.out 2>/tmp/test-init-state.err; then
  echo "Expected init-state.sh to recover from non-object task_flow" >&2
  cat /tmp/test-init-state.err >&2
  exit 1
fi

assert_file_exists "$SESSION_CWD/.claude/flow_state.json.bak"
assert_backup_matches_original "$TMP_DIR/unsafe-task-flow-non-object.original" "$SESSION_CWD/.claude/flow_state.json.bak"
assert_fresh_v2_state "$SESSION_CWD/.claude/flow_state.json"

write_v2_state_with_invalid_resume_types "$SESSION_CWD/.claude/flow_state.json"
rm -f "$SESSION_CWD/.claude/flow_state.json.bak"
cp "$SESSION_CWD/.claude/flow_state.json" "$TMP_DIR/unsafe-resume-fields.original"

if ! bash scripts/init-state.sh >/tmp/test-init-state.out 2>/tmp/test-init-state.err; then
  echo "Expected init-state.sh to recover from unsafe v2 resume field types" >&2
  cat /tmp/test-init-state.err >&2
  exit 1
fi

assert_file_exists "$SESSION_CWD/.claude/flow_state.json.bak"
assert_backup_matches_original "$TMP_DIR/unsafe-resume-fields.original" "$SESSION_CWD/.claude/flow_state.json.bak"
assert_fresh_v2_state "$SESSION_CWD/.claude/flow_state.json"

write_resume_candidate_state "$SESSION_CWD/.claude/flow_state.json"
resume_output="$(printf '{"hook_event_name":"SessionStart","cwd":"%s","source":"resume"}' "$SESSION_CWD" \
  | bash scripts/init-state.sh)"

assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.resume.recovery_required' 'true'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.resume.last_resume_source' '"resume"'
printf '%s' "$resume_output" > "$TMP_DIR/resume-output.json"
assert_json_equals "$TMP_DIR/resume-output.json" '.continue' 'true'
assert_file_contains "$TMP_DIR/resume-output.json" '/superpowers-flow-enforcer:resume-enforcer'

write_active_no_progress_state "$SESSION_CWD/.claude/flow_state.json"
resume_without_progress_output="$(printf '{"hook_event_name":"SessionStart","cwd":"%s","source":"resume"}' "$SESSION_CWD" \
  | bash scripts/init-state.sh)"

assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.resume.recovery_required' 'false'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.resume.last_resume_source' '"resume"'
printf '%s' "$resume_without_progress_output" > "$TMP_DIR/resume-without-progress-output.json"
if grep -Fq '/superpowers-flow-enforcer:resume-enforcer' "$TMP_DIR/resume-without-progress-output.json"; then
  echo "Expected resume without workflow progress to stay quiet about recovery" >&2
  exit 1
fi

write_resume_candidate_state "$SESSION_CWD/.claude/flow_state.json"
startup_output="$(printf '{"hook_event_name":"SessionStart","cwd":"%s","source":"startup"}' "$SESSION_CWD" \
  | bash scripts/init-state.sh)"

assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.resume.recovery_required' 'false'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.resume.last_resume_source' 'null'
printf '%s' "$startup_output" > "$TMP_DIR/startup-output.json"
if grep -Fq '/superpowers-flow-enforcer:resume-enforcer' "$TMP_DIR/startup-output.json"; then
  echo "Expected non-resume SessionStart to stay quiet about resume recovery" >&2
  exit 1
fi

write_resume_candidate_state "$SESSION_CWD/.claude/flow_state.json"
jq '.workflow.active = false | .resume.recovery_required = true | .resume.last_resume_source = "resume"' \
  "$SESSION_CWD/.claude/flow_state.json" > "$SESSION_CWD/.claude/flow_state.json.tmp"
mv "$SESSION_CWD/.claude/flow_state.json.tmp" "$SESSION_CWD/.claude/flow_state.json"

printf '{"hook_event_name":"SessionStart","cwd":"%s","source":"resume"}' "$SESSION_CWD" \
  | bash scripts/init-state.sh >/dev/null

assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.resume.recovery_required' 'false'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.resume.last_resume_source' '"resume"'

write_resume_candidate_state "$SESSION_CWD/.claude/flow_state.json"
jq '.workflow.override = "manual_off" | .resume.recovery_required = true | .resume.last_resume_source = "resume"' \
  "$SESSION_CWD/.claude/flow_state.json" > "$SESSION_CWD/.claude/flow_state.json.tmp"
mv "$SESSION_CWD/.claude/flow_state.json.tmp" "$SESSION_CWD/.claude/flow_state.json"

printf '{"hook_event_name":"SessionStart","cwd":"%s","source":"resume"}' "$SESSION_CWD" \
  | bash scripts/init-state.sh >/dev/null

assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.resume.recovery_required' 'false'

write_clean_finished_workflow_state "$SESSION_CWD/.claude/flow_state.json"
jq '.resume.recovery_required = true | .resume.last_resume_source = "resume"' \
  "$SESSION_CWD/.claude/flow_state.json" > "$SESSION_CWD/.claude/flow_state.json.tmp"
mv "$SESSION_CWD/.claude/flow_state.json.tmp" "$SESSION_CWD/.claude/flow_state.json"

printf '{"hook_event_name":"SessionStart","cwd":"%s","source":"resume"}' "$SESSION_CWD" \
  | bash scripts/init-state.sh >/dev/null

assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.resume.recovery_required' 'false'

write_resume_candidate_state "$SESSION_CWD/.claude/flow_state.json"
printf '{"hook_event_name":"SessionStart","cwd":"%s","source":"resume"}' "$SESSION_CWD" \
  | bash scripts/init-state.sh >/dev/null

assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.resume.recovery_required' 'true'

printf '{"hook_event_name":"SessionStart","cwd":"%s","source":"startup"}' "$SESSION_CWD" \
  | bash scripts/init-state.sh > "$TMP_DIR/startup-after-required-output.json"

assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.resume.recovery_required' 'true'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.resume.last_resume_source' '"resume"'
assert_file_contains "$TMP_DIR/startup-after-required-output.json" '/superpowers-flow-enforcer:resume-enforcer'

export CLAUDE_PROJECT_DIR="$TMP_DIR/project"

mkdir -p "$CLAUDE_PROJECT_DIR/.claude"

cat > "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" <<'EOF'
{
  "current_phase": "brainstorming",
  "brainstorming": {
    "spec_written": true,
    "findings_updated": false,
    "skill_invoked": true,
    "questions_asked": 2,
    "spec_self_reviewed": true
  },
  "planning": {
    "plan_written": false
  },
  "worktree": {
    "created": true,
    "path": "/tmp/worktree",
    "baseline_tests_passed": true
  },
  "tdd": {
    "tests_verified_fail": []
  },
  "finishing": {
    "skill_invoked": true,
    "tests_verified": true,
    "choice_made": true,
    "choice": "merge"
  },
  "exceptions": {
    "skip_brainstorming": false,
    "skip_tdd": false,
    "skip_review": false,
    "skip_finishing": false,
    "user_confirmed": false
  },
  "interrupt": {
    "allowed": false
  }
}
EOF

bash scripts/init-state.sh >/dev/null

assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.state_version' '2'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.brainstorming.spec_written' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.brainstorming.findings_updated_after_question' 'false'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.baseline_verified' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.task_flow.active_task_id' 'null'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.task_flow.active_packet_role' 'null'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.task_flow.last_dispatch_at' 'null'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.resume.recovery_required' 'false'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.resume.recovery_completed_at' 'null'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.resume.last_resume_source' 'null'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.tdd.pending_failure_record' 'false'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.tdd.last_failed_command' 'null'
assert_json_missing "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.brainstorming.skill_invoked'
assert_json_missing "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.brainstorming.questions_asked'
assert_json_missing "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.brainstorming.spec_self_reviewed'
assert_json_missing "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.baseline_tests_passed'
assert_json_missing "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.finishing.tests_verified'
assert_json_missing "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.finishing.choice_made'
assert_json_missing "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.finishing.choice'

cat > "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" <<'EOF'
{"current_phase":"planning","brainstorming":{"spec_written":true,"findings_updated":false},"planning":{"plan_written":false},"tdd":{"tests_verified_fail":[]}}
EOF

if ! bash scripts/init-state.sh >/tmp/test-init-state.out 2>/tmp/test-init-state.err; then
  echo "Expected init-state.sh to migrate a minimal v1 state with missing optional objects" >&2
  cat /tmp/test-init-state.err >&2
  exit 1
fi

assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.state_version' '2'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.current_phase' '"planning"'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.brainstorming.spec_written' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.baseline_verified' 'false'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.task_flow.active_task_id' 'null'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.task_flow.active_packet_role' 'null'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.task_flow.last_dispatch_at' 'null'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.tdd.pending_failure_record' 'false'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.tdd.last_failed_command' 'null'
assert_json_missing "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.brainstorming.questions_asked'

rm -rf "$CLAUDE_PROJECT_DIR"
mkdir -p "$CLAUDE_PROJECT_DIR/.claude"

bash scripts/init-state.sh >/dev/null

assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.state_version' '2'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.current_phase' '"init"'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.brainstorming.question_asked' 'false'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.brainstorming.findings_updated_after_question' 'false'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.resume.recovery_required' 'false'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.resume.recovery_completed_at' 'null'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.resume.last_resume_source' 'null'
assert_json_missing "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.brainstorming.skill_invoked'

printf '{bad json\n' > "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
cp "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" "$TMP_DIR/bad-json.original"
if ! bash scripts/init-state.sh >/tmp/test-init-state.out 2>/tmp/test-init-state.err; then
  echo "Expected init-state.sh to recover from bad JSON" >&2
  cat /tmp/test-init-state.err >&2
  exit 1
fi
assert_file_exists "$CLAUDE_PROJECT_DIR/.claude/flow_state.json.bak"
assert_backup_matches_original "$TMP_DIR/bad-json.original" "$CLAUDE_PROJECT_DIR/.claude/flow_state.json.bak"
assert_fresh_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

write_unsafe_v1_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
cp "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" "$TMP_DIR/unsafe-v1.original"
if ! bash scripts/init-state.sh >/tmp/test-init-state.out 2>/tmp/test-init-state.err; then
  echo "Expected init-state.sh to recover from unsafe v1 state" >&2
  cat /tmp/test-init-state.err >&2
  exit 1
fi
assert_file_exists "$CLAUDE_PROJECT_DIR/.claude/flow_state.json.bak"
assert_backup_matches_original "$TMP_DIR/unsafe-v1.original" "$CLAUDE_PROJECT_DIR/.claude/flow_state.json.bak"
assert_fresh_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

cat > "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" <<'EOF'
{
  "current_phase":"brainstorming",
  "brainstorming":{"spec_written":true,"findings_updated":false,"skill_invoked":true},
  "planning":{"plan_written":false},
  "worktree":"broken",
  "tdd":{"tests_verified_fail":[]},
  "exceptions":{"skip_brainstorming":false,"skip_tdd":false,"skip_review":false,"skip_finishing":false,"user_confirmed":false},
  "interrupt":{"allowed":false}
}
EOF
cp "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" "$TMP_DIR/unsafe-v1-worktree.original"
if ! bash scripts/init-state.sh >/tmp/test-init-state.out 2>/tmp/test-init-state.err; then
  echo "Expected init-state.sh to recover from unsafe v1 worktree scalar" >&2
  cat /tmp/test-init-state.err >&2
  exit 1
fi
assert_file_exists "$CLAUDE_PROJECT_DIR/.claude/flow_state.json.bak"
assert_backup_matches_original "$TMP_DIR/unsafe-v1-worktree.original" "$CLAUDE_PROJECT_DIR/.claude/flow_state.json.bak"
assert_fresh_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

cat > "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" <<'EOF'
{
  "state_version": 2,
  "current_phase": "init",
  "brainstorming": {
    "question_asked": false,
    "findings_updated_after_question": false,
    "spec_written": false,
    "spec_file": null,
    "spec_reviewed": false,
    "user_approved_spec": false
  },
  "planning": {
    "plan_written": false,
    "plan_file": null,
    "execution_mode": null
  },
  "worktree": {
    "created": false,
    "path": null,
    "baseline_verified": false
  },
  "tdd": {
    "current_task": null,
    "current_step": null,
    "test_files_created": [],
    "production_files_written": [],
    "tests_verified_fail": [],
    "tests_verified_pass": []
  },
  "review": {
    "tasks": {}
  },
  "finishing": {
    "invoked": false
  },
  "debugging": "broken",
  "exceptions": {
    "skip_brainstorming": false,
    "skip_planning": false,
    "skip_tdd": false,
    "skip_review": false,
    "skip_finishing": false,
    "pending_confirmation_for": null,
    "reason": null,
    "user_confirmed": false,
    "confirmed_at": null
  },
  "interrupt": {
    "allowed": false,
    "reason": null,
    "keywords_detected": []
  }
}
EOF
cp "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" "$TMP_DIR/unsafe-v2-debugging.original"
if ! bash scripts/init-state.sh >/tmp/test-init-state.out 2>/tmp/test-init-state.err; then
  echo "Expected init-state.sh to recover from unsafe v2 debugging scalar" >&2
  cat /tmp/test-init-state.err >&2
  exit 1
fi
assert_file_exists "$CLAUDE_PROJECT_DIR/.claude/flow_state.json.bak"
assert_backup_matches_original "$TMP_DIR/unsafe-v2-debugging.original" "$CLAUDE_PROJECT_DIR/.claude/flow_state.json.bak"
assert_fresh_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

cat > "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" <<'EOF'
{
  "state_version": 2,
  "current_phase": "init",
  "brainstorming": {
    "question_asked": false,
    "findings_updated_after_question": false,
    "spec_written": false,
    "spec_file": null,
    "spec_reviewed": false,
    "user_approved_spec": false
  },
  "planning": {
    "plan_written": false,
    "plan_file": null,
    "execution_mode": null
  },
  "worktree": {
    "created": false,
    "path": null,
    "baseline_verified": false
  },
  "tdd": {
    "current_task": null,
    "current_step": null,
    "pending_failure_record": "bad",
    "last_failed_command": [],
    "test_files_created": [],
    "production_files_written": [],
    "tests_verified_fail": [],
    "tests_verified_pass": []
  },
  "review": {
    "tasks": {}
  },
  "finishing": {
    "invoked": false
  },
  "debugging": {
    "active": false,
    "phase": null,
    "fixes_attempted": 0,
    "root_cause_found": false
  },
  "exceptions": {
    "skip_brainstorming": false,
    "skip_planning": false,
    "skip_tdd": false,
    "skip_review": false,
    "skip_finishing": false,
    "pending_confirmation_for": null,
    "reason": null,
    "user_confirmed": false,
    "confirmed_at": null
  },
  "interrupt": {
    "allowed": false,
    "reason": null,
    "keywords_detected": []
  }
}
EOF
cp "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" "$TMP_DIR/unsafe-v2-tdd-recording.original"
if ! bash scripts/init-state.sh >/tmp/test-init-state.out 2>/tmp/test-init-state.err; then
  echo "Expected init-state.sh to recover from unsafe v2 tdd recording types" >&2
  cat /tmp/test-init-state.err >&2
  exit 1
fi
assert_file_exists "$CLAUDE_PROJECT_DIR/.claude/flow_state.json.bak"
assert_backup_matches_original "$TMP_DIR/unsafe-v2-tdd-recording.original" "$CLAUDE_PROJECT_DIR/.claude/flow_state.json.bak"
assert_fresh_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

cat > "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" <<'EOF'
{
  "state_version": 2,
  "current_phase": "init",
  "brainstorming": {
    "question_asked": false,
    "findings_updated_after_question": false,
    "spec_written": false,
    "spec_file": null,
    "spec_reviewed": false,
    "user_approved_spec": false
  },
  "planning": {
    "plan_written": false,
    "plan_file": null,
    "execution_mode": null
  },
  "worktree": {
    "created": false,
    "path": null,
    "baseline_verified": false
  },
  "tdd": {
    "current_task": null,
    "current_step": null,
    "test_files_created": [],
    "production_files_written": [],
    "tests_verified_fail": [],
    "tests_verified_pass": []
  },
  "review": {
    "tasks": {}
  },
  "finishing": {
    "invoked": false
  },
  "debugging": {
    "active": false,
    "phase": null,
    "fixes_attempted": 0,
    "root_cause_found": false
  },
  "exceptions": {
    "skip_brainstorming": false,
    "skip_planning": false,
    "skip_tdd": false,
    "skip_review": false,
    "skip_finishing": false,
    "pending_confirmation_for": null,
    "reason": null,
    "user_confirmed": false,
    "confirmed_at": null
  },
  "interrupt": {
    "allowed": false,
    "reason": null,
    "keywords_detected": "bad"
  }
}
EOF
cp "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" "$TMP_DIR/unsafe-v2-interrupt.original"
if ! bash scripts/init-state.sh >/tmp/test-init-state.out 2>/tmp/test-init-state.err; then
  echo "Expected init-state.sh to recover from unsafe v2 interrupt scalar" >&2
  cat /tmp/test-init-state.err >&2
  exit 1
fi
assert_file_exists "$CLAUDE_PROJECT_DIR/.claude/flow_state.json.bak"
assert_backup_matches_original "$TMP_DIR/unsafe-v2-interrupt.original" "$CLAUDE_PROJECT_DIR/.claude/flow_state.json.bak"
assert_fresh_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

cat > "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" <<'EOF'
{
  "state_version": 2,
  "current_phase": "planning",
  "brainstorming": "broken",
  "planning": {
    "plan_written": true
  },
  "tdd": {
    "tests_verified_fail": "bad"
  }
}
EOF
if ! bash scripts/init-state.sh >/tmp/test-init-state.out 2>/tmp/test-init-state.err; then
  echo "Expected init-state.sh to recover from unsafe v2 structure" >&2
  cat /tmp/test-init-state.err >&2
  exit 1
fi
assert_file_exists "$CLAUDE_PROJECT_DIR/.claude/flow_state.json.bak"
assert_fresh_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

cat > "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" <<'EOF'
{
  "state_version": 2,
  "current_phase": "archived",
  "brainstorming": {
    "question_asked": false,
    "findings_updated_after_question": false,
    "spec_written": false,
    "spec_file": null,
    "spec_reviewed": false,
    "user_approved_spec": false
  },
  "planning": {
    "plan_written": false,
    "plan_file": null,
    "execution_mode": null
  },
  "worktree": {
    "created": false,
    "path": null,
    "baseline_verified": false
  },
  "tdd": {
    "current_task": null,
    "current_step": null,
    "test_files_created": [],
    "production_files_written": [],
    "tests_verified_fail": [],
    "tests_verified_pass": []
  },
  "review": {
    "tasks": {}
  },
  "finishing": {
    "invoked": false
  },
  "exceptions": {
    "skip_brainstorming": false,
    "skip_planning": false,
    "skip_tdd": false,
    "skip_review": false,
    "skip_finishing": false,
    "pending_confirmation_for": null,
    "reason": null,
    "user_confirmed": false,
    "confirmed_at": null
  },
  "interrupt": {
    "allowed": false,
    "reason": null,
    "keywords_detected": []
  }
}
EOF
if ! bash scripts/init-state.sh >/tmp/test-init-state.out 2>/tmp/test-init-state.err; then
  echo "Expected init-state.sh to recover from contradictory phase state" >&2
  cat /tmp/test-init-state.err >&2
  exit 1
fi
assert_file_exists "$CLAUDE_PROJECT_DIR/.claude/flow_state.json.bak"
assert_fresh_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

cat > "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" <<'EOF'
{"state_version":"two","current_phase":"init"}
EOF
if bash scripts/init-state.sh >/tmp/test-init-state.out 2>/tmp/test-init-state.err; then
  echo "Expected init-state.sh to fail for non-numeric state_version" >&2
  exit 1
fi
assert_file_contains /tmp/test-init-state.err "unsupported"

cat > "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" <<'EOF'
{"state_version":3,"current_phase":"init"}
EOF
if bash scripts/init-state.sh >/tmp/test-init-state.out 2>/tmp/test-init-state.err; then
  echo "Expected init-state.sh to fail for unknown higher state_version" >&2
  exit 1
fi
assert_file_contains /tmp/test-init-state.err "unsupported"

write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
cp "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" "$CLAUDE_PROJECT_DIR/.claude/flow_state.before.json"
if bash scripts/migrate-state.sh "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" >/tmp/test-migrate-state.out 2>/tmp/test-migrate-state.err; then
  echo "Expected migrate-state.sh to reject v2 state" >&2
  exit 1
fi
assert_file_contains /tmp/test-migrate-state.err "v1"
cmp -s \
  "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" \
  "$CLAUDE_PROJECT_DIR/.claude/flow_state.before.json" || {
  echo "Expected v2 state to remain unchanged after rejected migration" >&2
  exit 1
}

write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
if ! bash scripts/migrate-state.sh --check-safe "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" >/tmp/test-migrate-safe.out 2>/tmp/test-migrate-safe.err; then
  echo "Expected migrate-state.sh --check-safe to accept valid task_flow and resume in v2 state" >&2
  cat /tmp/test-migrate-safe.err >&2
  exit 1
fi

write_v2_state_without_task_flow "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
if ! bash scripts/migrate-state.sh --check-safe "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" >/tmp/test-migrate-safe.out 2>/tmp/test-migrate-safe.err; then
  echo "Expected migrate-state.sh --check-safe to allow missing task_flow for in-place normalization" >&2
  cat /tmp/test-migrate-safe.err >&2
  exit 1
fi

write_v2_state_without_resume "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
if ! bash scripts/migrate-state.sh --check-safe "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" >/tmp/test-migrate-safe.out 2>/tmp/test-migrate-safe.err; then
  echo "Expected migrate-state.sh --check-safe to allow missing resume for in-place normalization" >&2
  cat /tmp/test-migrate-safe.err >&2
  exit 1
fi

write_v2_state_with_partial_resume "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
if ! bash scripts/migrate-state.sh --check-safe "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" >/tmp/test-migrate-safe.out 2>/tmp/test-migrate-safe.err; then
  echo "Expected migrate-state.sh --check-safe to allow partial resume for in-place normalization" >&2
  cat /tmp/test-migrate-safe.err >&2
  exit 1
fi

write_v2_state_with_string_resume_fields "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
if ! bash scripts/migrate-state.sh --check-safe "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" >/tmp/test-migrate-safe.out 2>/tmp/test-migrate-safe.err; then
  echo "Expected migrate-state.sh --check-safe to accept non-null string resume fields" >&2
  cat /tmp/test-migrate-safe.err >&2
  exit 1
fi

write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
jq '.task_flow = null' "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" > "$CLAUDE_PROJECT_DIR/.claude/flow_state.json.tmp"
mv "$CLAUDE_PROJECT_DIR/.claude/flow_state.json.tmp" "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
if bash scripts/migrate-state.sh --check-safe "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" >/tmp/test-migrate-safe.out 2>/tmp/test-migrate-safe.err; then
  echo "Expected migrate-state.sh --check-safe to reject null task_flow" >&2
  exit 1
fi

write_v2_state_with_invalid_task_flow_role_string "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
if bash scripts/migrate-state.sh --check-safe "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" >/tmp/test-migrate-safe.out 2>/tmp/test-migrate-safe.err; then
  echo "Expected migrate-state.sh --check-safe to reject invalid task_flow role value" >&2
  exit 1
fi

write_v2_state_with_invalid_resume_types "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
if bash scripts/migrate-state.sh --check-safe "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" >/tmp/test-migrate-safe.out 2>/tmp/test-migrate-safe.err; then
  echo "Expected migrate-state.sh --check-safe to reject invalid resume field types" >&2
  exit 1
fi
