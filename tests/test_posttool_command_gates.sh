#!/bin/bash
set -euo pipefail

source tests/helpers/assert.sh
source tests/helpers/state-fixtures.sh

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export CLAUDE_PROJECT_DIR="$TMP_DIR/project"
export CLAUDE_PLUGIN_ROOT="$(pwd)"

STATE_FILE="$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
mkdir -p "$CLAUDE_PROJECT_DIR/.claude"

assert_posttool_block() {
  local output="$1"
  local reason_fragment="$2"
  [ -n "$output" ] || {
    echo "Expected PostToolUse command hook to block, got empty output" >&2
    exit 1
  }
  assert_json_equals <(printf '%s' "$output") '.decision' '"block"'
  jq -e --arg frag "$reason_fragment" '.reason | contains($frag)' <(printf '%s' "$output") >/dev/null 2>&1 || {
    echo "Expected PostToolUse block reason to contain: $reason_fragment" >&2
    exit 1
  }
}

assert_posttool_allow() {
  local output="$1"
  [ -z "$output" ] || {
    echo "Expected PostToolUse command hook to allow with empty output, got: $output" >&2
    exit 1
  }
}

run_posttool_write() {
  local file_path="$1"
  local tool_name="${2:-Write}"
  jq -n --arg tool_name "$tool_name" --arg path "$file_path" '{
    hook_event_name:"PostToolUse",
    tool_name:$tool_name,
    tool_input:{file_path:$path}
  }' | bash scripts/sync-post-tool-state.sh
}

run_posttool_bash() {
  local command="$1"
  local result_text="${2:-Preparing worktree}"
  jq -n --arg command "$command" --arg result "$result_text" '{
    hook_event_name:"PostToolUse",
    tool_name:"Bash",
    tool_input:{command:$command},
    tool_result:$result
  }' | bash scripts/sync-post-tool-state.sh
}

run_posttool_write_with_cwd() {
  local cwd="$1"
  local file_path="$2"
  local tool_name="${3:-Write}"
  jq -n --arg cwd "$cwd" --arg tool_name "$tool_name" --arg path "$file_path" '{
    hook_event_name:"PostToolUse",
    cwd:$cwd,
    tool_name:$tool_name,
    tool_input:{file_path:$path}
  }' | bash scripts/sync-post-tool-state.sh
}

run_task_completed() {
  local output_file="$1"
  local error_file="$2"
  local task_id="${3:-task-001}"
  local task_subject="${4:-demo task}"

  set +e
  jq -n --arg cwd "$CLAUDE_PROJECT_DIR" --arg task_id "$task_id" --arg task_subject "$task_subject" '{
    hook_event_name:"TaskCompleted",
    cwd:$cwd,
    task_id:$task_id,
    task_subject:$task_subject
  }' | bash scripts/check-task-completed.sh >"$output_file" 2>"$error_file"
  local status=$?
  set -e

  printf '%s\n' "$status"
}

write_v2_state "$STATE_FILE"
spec_block_output="$(run_posttool_write 'docs/superpowers/specs/demo.md')"
assert_posttool_block "$spec_block_output" 'Self-Review'
assert_json_equals "$STATE_FILE" '.brainstorming.spec_written' 'true'
assert_json_equals "$STATE_FILE" '.brainstorming.spec_file' '"docs/superpowers/specs/demo.md"'

unset CLAUDE_PROJECT_DIR
mkdir -p "$TMP_DIR/cwd-project/.claude"
mkdir -p "$TMP_DIR/cwd-project/nested/child"
CWD_STATE_FILE="$TMP_DIR/cwd-project/.claude/flow_state.json"
write_v2_state "$CWD_STATE_FILE"
spec_block_output="$(run_posttool_write_with_cwd "$TMP_DIR/cwd-project/nested/child" 'docs/superpowers/specs/from-cwd.md')"
assert_posttool_block "$spec_block_output" 'Self-Review'
assert_json_equals "$CWD_STATE_FILE" '.brainstorming.spec_written' 'true'
assert_json_equals "$CWD_STATE_FILE" '.brainstorming.spec_file' '"docs/superpowers/specs/from-cwd.md"'
export CLAUDE_PROJECT_DIR="$TMP_DIR/project"

write_v2_state "$STATE_FILE"
jq '.brainstorming.spec_reviewed = true' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"
spec_allow_output="$(run_posttool_write 'docs/superpowers/specs/demo.md')"
assert_posttool_allow "$spec_allow_output"

write_v2_state "$STATE_FILE"
jq '.brainstorming.spec_reviewed = true' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"
plan_block_output="$(run_posttool_write 'docs/superpowers/plans/demo.md')"
assert_posttool_block "$plan_block_output" 'using-git-worktrees'
assert_json_equals "$STATE_FILE" '.planning.plan_written' 'true'
assert_json_equals "$STATE_FILE" '.planning.plan_file' '"docs/superpowers/plans/demo.md"'

write_v2_state "$STATE_FILE"
jq '
  .brainstorming.spec_reviewed = true
  | .worktree.created = true
' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"
plan_allow_output="$(run_posttool_write 'docs/superpowers/plans/demo.md')"
assert_posttool_allow "$plan_allow_output"

write_v2_state "$STATE_FILE"
worktree_block_output="$(run_posttool_bash 'git worktree add .worktrees/demo HEAD' 'Preparing worktree (new branch '\''demo'\'')')"
assert_posttool_block "$worktree_block_output" 'baseline verification'
assert_json_equals "$STATE_FILE" '.worktree.created' 'true'
assert_json_equals "$STATE_FILE" '.worktree.path' '".worktrees/demo"'
assert_json_equals "$STATE_FILE" '.worktree.baseline_verified' 'false'

write_v2_state "$STATE_FILE"
jq '
  .worktree.created = true
  | .worktree.path = ".worktrees/existing"
  | .worktree.baseline_verified = true
' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"
worktree_allow_output="$(run_posttool_bash 'git worktree add .worktrees/demo HEAD' 'fatal: '\''.worktrees/demo'\'' already exists')"
assert_posttool_allow "$worktree_allow_output"
assert_json_equals "$STATE_FILE" '.worktree.path' '".worktrees/existing"'
assert_json_equals "$STATE_FILE" '.worktree.baseline_verified' 'true'

write_v2_state "$STATE_FILE"
jq '.workflow.active = true' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"
task_output_file="$TMP_DIR/task-completed.out"
task_error_file="$TMP_DIR/task-completed.err"
status="$(run_task_completed "$task_output_file" "$task_error_file")"
[ "$status" -eq 2 ] || {
  echo "Expected TaskCompleted hook to exit 2 when review is missing, got $status" >&2
  exit 1
}
[ ! -s "$task_output_file" ] || {
  echo 'Expected TaskCompleted failure path to keep stdout empty' >&2
  exit 1
}
grep -q '必须完成两阶段 review' "$task_error_file" || {
  echo 'Expected TaskCompleted failure stderr to mention missing review stages' >&2
  exit 1
}

write_v2_state "$STATE_FILE"
jq '
  .workflow.active = true
  | .review.tasks["task-001"].spec_review_passed = true
  | .review.tasks["task-001"].code_review_passed = true
' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"
status="$(run_task_completed "$task_output_file" "$task_error_file")"
[ "$status" -eq 0 ] || {
  echo "Expected TaskCompleted hook to allow when review passes, got $status" >&2
  exit 1
}
[ ! -s "$task_output_file" ] || {
  echo 'Expected TaskCompleted allow path to keep stdout empty' >&2
  exit 1
}
[ ! -s "$task_error_file" ] || {
  echo 'Expected TaskCompleted allow path to keep stderr empty' >&2
  exit 1
}

set +e
jq -n --arg cwd "$CLAUDE_PROJECT_DIR" --arg task_id "task-001" '{
  hook_event_name:"TaskCompleted",
  cwd:$cwd,
  task_id:$task_id
}' | bash scripts/check-task-completed.sh >"$task_output_file" 2>"$task_error_file"
status=$?
set -e
[ "$status" -eq 0 ] || {
  echo "Expected TaskCompleted hook to allow when only task_id is present and review passes, got $status" >&2
  exit 1
}
[ ! -s "$task_output_file" ] || {
  echo 'Expected task_id-only allow path to keep stdout empty' >&2
  exit 1
}
[ ! -s "$task_error_file" ] || {
  echo 'Expected task_id-only allow path to keep stderr empty' >&2
  exit 1
}

unset CLAUDE_PROJECT_DIR
mkdir -p "$TMP_DIR/project/nested/child"
write_v2_state "$TMP_DIR/project/.claude/flow_state.json"
jq '.workflow.active = true' "$TMP_DIR/project/.claude/flow_state.json" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$TMP_DIR/project/.claude/flow_state.json"

set +e
jq -n --arg cwd "$TMP_DIR/project/nested/child" '{
  hook_event_name:"TaskCompleted",
  cwd:$cwd,
  task_id:"task-subdir"
}' | bash scripts/check-task-completed.sh >"$task_output_file" 2>"$task_error_file"
status=$?
set -e
[ "$status" -eq 2 ] || {
  echo "Expected TaskCompleted hook to block when cwd is a repo subdirectory and root review is missing, got $status" >&2
  exit 1
}
grep -q '必须完成两阶段 review' "$task_error_file" || {
  echo 'Expected subdirectory cwd failure to mention missing review stages' >&2
  exit 1
}

export CLAUDE_PROJECT_DIR="$TMP_DIR/project/nested/child"
set +e
jq -n --arg cwd "$TMP_DIR/project/other/place" '{
  hook_event_name:"TaskCompleted",
  cwd:$cwd,
  task_id:"task-subdir-env"
}' | bash scripts/check-task-completed.sh >"$task_output_file" 2>"$task_error_file"
status=$?
set -e
[ "$status" -eq 2 ] || {
  echo "Expected TaskCompleted hook to block when CLAUDE_PROJECT_DIR is a repo subdirectory and root review is missing, got $status" >&2
  exit 1
}
grep -q '必须完成两阶段 review' "$task_error_file" || {
  echo 'Expected CLAUDE_PROJECT_DIR subdirectory failure to mention missing review stages' >&2
  exit 1
}

unset CLAUDE_PROJECT_DIR
mkdir -p "$TMP_DIR/alt-project/.claude"
write_v2_state "$TMP_DIR/alt-project/.claude/flow_state.json"
jq '
  .review.tasks["task-cwd"].spec_review_passed = true
  | .review.tasks["task-cwd"].code_review_passed = true
' "$TMP_DIR/alt-project/.claude/flow_state.json" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$TMP_DIR/alt-project/.claude/flow_state.json"

set +e
jq -n --arg cwd "$TMP_DIR/alt-project" '{
  hook_event_name:"TaskCompleted",
  cwd:$cwd,
  task_id:"task-cwd",
  task_subject:"cwd fallback"
}' | bash scripts/check-task-completed.sh >"$task_output_file" 2>"$task_error_file"
status=$?
set -e
[ "$status" -eq 0 ] || {
  echo "Expected TaskCompleted hook to resolve cwd fallback, got $status" >&2
  exit 1
}
[ ! -s "$task_error_file" ] || {
  echo 'Expected cwd fallback allow path to keep stderr empty' >&2
  exit 1
}

rm -rf "$TMP_DIR/alt-project/.claude"
set +e
jq -n --arg cwd "$TMP_DIR/alt-project" '{
  hook_event_name:"TaskCompleted",
  cwd:$cwd,
  task_id:"task-cwd",
  task_subject:"missing state fail open"
}' | bash scripts/check-task-completed.sh >"$task_output_file" 2>"$task_error_file"
status=$?
set -e
[ "$status" -eq 0 ] || {
  echo "Expected TaskCompleted hook to fail open when state is missing, got $status" >&2
  exit 1
}
[ ! -s "$task_output_file" ] || {
  echo 'Expected missing state fail-open path to keep stdout empty' >&2
  exit 1
}
[ ! -s "$task_error_file" ] || {
  echo 'Expected missing state fail-open path to keep stderr empty' >&2
  exit 1
}
