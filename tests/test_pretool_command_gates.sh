#!/bin/bash
set -euo pipefail

source tests/helpers/assert.sh
source tests/helpers/state-fixtures.sh

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

REPO_ROOT="$(pwd)"
export CLAUDE_PROJECT_DIR="$TMP_DIR/project"
export CLAUDE_PLUGIN_ROOT="$(pwd)"

STATE_FILE="$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
mkdir -p "$CLAUDE_PROJECT_DIR/.claude"

assert_pretool_deny() {
  local output="$1"
  local reason_fragment="$2"
  [ -n "$output" ] || {
    echo "Expected PreToolUse command hook to deny, got empty output" >&2
    exit 1
  }
  assert_json_equals <(printf '%s' "$output") '.hookSpecificOutput.hookEventName' '"PreToolUse"'
  assert_json_equals <(printf '%s' "$output") '.hookSpecificOutput.permissionDecision' '"deny"'
  jq -e --arg frag "$reason_fragment" '.hookSpecificOutput.permissionDecisionReason | contains($frag)' <(printf '%s' "$output") >/dev/null 2>&1 || {
    echo "Expected deny reason to contain: $reason_fragment" >&2
    exit 1
  }
}

assert_pretool_allow() {
  local output="$1"
  [ -z "$output" ] || {
    echo "Expected PreToolUse command hook to allow with empty output, got: $output" >&2
    exit 1
  }
}

run_write_gate() {
  local file_path="$1"
  jq -n --arg path "$file_path" '{
    hook_event_name:"PreToolUse",
    tool_name:"Write",
    tool_input:{file_path:$path}
  }' | bash scripts/check-pretool-gates.sh
}

run_edit_gate_with_path() {
  local path="$1"
  jq -n --arg path "$path" '{
    hook_event_name:"PreToolUse",
    tool_name:"Edit",
    tool_input:{path:$path}
  }' | bash scripts/check-pretool-gates.sh
}

run_ask_gate() {
  jq -n '{
    hook_event_name:"PreToolUse",
    tool_name:"AskUserQuestion"
  }' | bash scripts/check-pretool-gates.sh
}

write_v2_state "$STATE_FILE"

deny_output="$(run_write_gate '.claude/flow_state.json')"
assert_pretool_deny "$deny_output" 'flow_state.json'

rm -f "$STATE_FILE"
mkdir -p "$STATE_FILE"
deny_output="$(run_write_gate 'src/bootstrap-fail.ts')"
assert_pretool_deny "$deny_output" '状态不可用'
rm -rf "$STATE_FILE"

printf '{bad json' > "$STATE_FILE"
deny_output="$(run_write_gate 'src/broken-state.ts')"
assert_pretool_deny "$deny_output" '状态不可用'

write_v2_state "$STATE_FILE"
allow_output="$(run_write_gate './docs/superpowers/specs/spec.md')"
assert_pretool_allow "$allow_output"

allow_output="$(run_write_gate "$CLAUDE_PROJECT_DIR/docs/superpowers/plans/plan.md")"
assert_pretool_allow "$allow_output"

write_v2_state "$STATE_FILE"
jq '.workflow.active = true' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"

deny_output="$(run_write_gate 'docs/superpowers/plans/plan.md')"
assert_pretool_deny "$deny_output" 'spec review'

write_v2_state "$STATE_FILE"
jq '
  .workflow.active = true
  | .exceptions.skip_planning = true
  | .exceptions.user_confirmed = true
' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"

allow_output="$(run_write_gate 'docs/superpowers/plans/plan.md')"
assert_pretool_allow "$allow_output"

write_v2_state "$STATE_FILE"
jq '.workflow.active = true' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"

deny_output="$(run_write_gate 'src/app.ts')"
assert_pretool_deny "$deny_output" 'brainstorming/SPEC'

allow_output="$(run_write_gate 'docs/notes.md')"
assert_pretool_allow "$allow_output"

write_v2_state "$STATE_FILE"
jq '
  .workflow.active = true
  | .exceptions.skip_brainstorming = true
  | .exceptions.user_confirmed = true
  | .worktree.created = true
  | .worktree.baseline_verified = true
  | .tdd.pending_failure_record = false
  | .tdd.tests_verified_fail = ["src/app.test.ts"]
' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"

allow_output="$(run_write_gate 'src/app.ts')"
assert_pretool_allow "$allow_output"

write_v2_state "$STATE_FILE"
jq '
  .workflow.active = true
  | .brainstorming.spec_written = true
  | .exceptions.skip_tdd = true
  | .exceptions.user_confirmed = true
  | .worktree.created = false
  | .worktree.baseline_verified = false
' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"

allow_output="$(run_write_gate 'src/skip-tdd.ts')"
assert_pretool_allow "$allow_output"

write_v2_state "$STATE_FILE"
jq '
  .workflow.active = true
  | .brainstorming.spec_written = true
  | .worktree.created = false
  | .worktree.baseline_verified = false
' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"

deny_output="$(run_write_gate 'src/worktree.ts')"
assert_pretool_deny "$deny_output" 'worktree.created'

deny_output="$(run_write_gate 'tests/unit/example.test.ts')"
assert_pretool_deny "$deny_output" 'worktree.created'

ROOT_STATE_PROJECT="$TMP_DIR/root-state-project"
mkdir -p "$ROOT_STATE_PROJECT/.claude" "$ROOT_STATE_PROJECT/nested/child"
write_v2_state "$ROOT_STATE_PROJECT/.claude/flow_state.json"
jq '
  .workflow.active = true
  | .brainstorming.spec_written = true
  | .worktree.created = false
  | .worktree.baseline_verified = false
' "$ROOT_STATE_PROJECT/.claude/flow_state.json" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$ROOT_STATE_PROJECT/.claude/flow_state.json"

deny_output="$(
  (
    export CLAUDE_PROJECT_DIR="$ROOT_STATE_PROJECT/nested/child"
    jq -n --arg cwd "$ROOT_STATE_PROJECT/nested/child" --arg path "src/app.ts" '{
      hook_event_name:"PreToolUse",
      cwd:$cwd,
      tool_name:"Write",
      tool_input:{file_path:$path}
    }' | bash "$REPO_ROOT/scripts/check-pretool-gates.sh"
  )
)"
assert_pretool_deny "$deny_output" 'worktree.created'
assert_json_equals "$ROOT_STATE_PROJECT/.claude/flow_state.json" '.workflow.active' 'true'
if [ -e "$ROOT_STATE_PROJECT/nested/child/.claude/flow_state.json" ]; then
  echo "Expected CLAUDE_PROJECT_DIR child path to resolve to root flow_state.json instead of bootstrapping a new one" >&2
  exit 1
fi

deny_output="$(
  (
    unset CLAUDE_PROJECT_DIR
    jq -n --arg cwd "$ROOT_STATE_PROJECT/nested/child" --arg path "src/app.ts" '{
      hook_event_name:"PreToolUse",
      cwd:$cwd,
      tool_name:"Write",
      tool_input:{file_path:$path}
    }' | bash "$REPO_ROOT/scripts/check-pretool-gates.sh"
  )
)"
assert_pretool_deny "$deny_output" 'worktree.created'
assert_json_equals "$ROOT_STATE_PROJECT/.claude/flow_state.json" '.workflow.active' 'true'
if [ -e "$ROOT_STATE_PROJECT/nested/child/.claude/flow_state.json" ]; then
  echo "Expected nested child to reuse root flow_state.json instead of bootstrapping a new one" >&2
  exit 1
fi

write_v2_state "$STATE_FILE"
jq '
  .workflow.active = true
  | .brainstorming.spec_written = true
  | .worktree.created = true
  | .worktree.baseline_verified = true
' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"

allow_output="$(run_write_gate 'tests/unit/worktree.test.ts')"
assert_pretool_allow "$allow_output"

write_v2_state "$STATE_FILE"
jq '
  .workflow.active = true
  | .brainstorming.spec_written = true
  | .worktree.created = true
  | .worktree.baseline_verified = true
  | .tdd.pending_failure_record = true
' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"

deny_output="$(run_write_gate 'src/pending.ts')"
assert_pretool_deny "$deny_output" '待记录'

write_v2_state "$STATE_FILE"
jq '
  .workflow.active = true
  | .brainstorming.spec_written = true
  | .worktree.created = true
  | .worktree.baseline_verified = true
  | .tdd.pending_failure_record = false
  | .tdd.tests_verified_fail = []
' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"

deny_output="$(run_write_gate 'src/candidate.ts')"
assert_pretool_deny "$deny_output" 'FAILING TEST'

write_v2_state "$STATE_FILE"
jq '
  .workflow.active = true
  | .brainstorming.spec_written = true
  | .worktree.created = true
  | .worktree.baseline_verified = true
  | .tdd.pending_failure_record = false
  | .tdd.tests_verified_fail = []
' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"

deny_output="$(run_edit_gate_with_path 'src/edit-path.ts')"
assert_pretool_deny "$deny_output" 'FAILING TEST'

write_v2_state "$STATE_FILE"
jq '
  .workflow.active = true
  | .brainstorming.spec_written = true
  | .worktree.created = true
  | .worktree.baseline_verified = true
  | .tdd.pending_failure_record = false
  | .tdd.tests_verified_fail = ["./src/candidate.test.ts"]
' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"

allow_output="$(run_write_gate "$CLAUDE_PROJECT_DIR/src/candidate.ts")"
assert_pretool_allow "$allow_output"

REAL_PROJECT="$TMP_DIR/real-project"
ALIAS_PARENT="$TMP_DIR/alias-parent"
ALIAS_PROJECT="$ALIAS_PARENT/project-link"
mkdir -p "$REAL_PROJECT/.claude" "$REAL_PROJECT/nested/child" "$ALIAS_PARENT"
ln -s "$REAL_PROJECT" "$ALIAS_PROJECT"
write_v2_state "$REAL_PROJECT/.claude/flow_state.json"
jq '
  .workflow.active = true
  | .brainstorming.spec_written = true
  | .worktree.created = true
  | .worktree.baseline_verified = true
  | .tdd.pending_failure_record = false
  | .tdd.tests_verified_fail = ["./src/candidate.test.ts"]
' "$REAL_PROJECT/.claude/flow_state.json" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$REAL_PROJECT/.claude/flow_state.json"

allow_output="$(
  (
    export CLAUDE_PROJECT_DIR="$ALIAS_PROJECT/nested/child"
    jq -n --arg cwd "$ALIAS_PROJECT/nested/child" --arg path "$ALIAS_PROJECT/src/candidate.ts" '{
      hook_event_name:"PreToolUse",
      cwd:$cwd,
      tool_name:"Write",
      tool_input:{file_path:$path}
    }' | bash "$REPO_ROOT/scripts/check-pretool-gates.sh"
  )
)"
assert_pretool_allow "$allow_output"

write_v2_state "$STATE_FILE"
allow_output="$(run_ask_gate)"
assert_pretool_allow "$allow_output"

write_v2_state "$STATE_FILE"
jq '
  .workflow.active = true
  | .current_phase = "brainstorming"
  | .brainstorming.question_asked = true
  | .brainstorming.findings_updated_after_question = false
' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"

deny_output="$(run_ask_gate)"
assert_pretool_deny "$deny_output" 'findings.md'

jq '.brainstorming.findings_updated_after_question = true' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"

allow_output="$(run_ask_gate)"
assert_pretool_allow "$allow_output"
