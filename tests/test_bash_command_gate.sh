#!/bin/bash
set -euo pipefail

source tests/helpers/assert.sh
source tests/helpers/state-fixtures.sh

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

REPO_ROOT="$(pwd)"
export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"

assert_file_exists "$REPO_ROOT/vendor/bash-traverse/upstream.json"

assert_deny() {
  local output="$1"
  local reason_fragment="$2"

  [ -n "$output" ] || {
    echo "Expected Bash command gate to deny, got empty output" >&2
    exit 1
  }

  assert_json_equals <(printf '%s' "$output") '.hookSpecificOutput.hookEventName' '"PreToolUse"'
  assert_json_equals <(printf '%s' "$output") '.hookSpecificOutput.permissionDecision' '"deny"'
  jq -e --arg frag "$reason_fragment" '.hookSpecificOutput.permissionDecisionReason | contains($frag)' <(printf '%s' "$output") >/dev/null 2>&1 || {
    echo "Expected deny reason to contain: $reason_fragment" >&2
    exit 1
  }
}

assert_allow() {
  local output="$1"

  [ -z "$output" ] || {
    echo "Expected Bash command gate to allow with empty output, got: $output" >&2
    exit 1
  }
}

set_workflow_active() {
  local state_file="$1"

  jq '
    .workflow.active = true
    | .workflow.activated_by = "spec_write"
    | .workflow.activated_at = "2026-04-12T00:00:00Z"
  ' "$state_file" > "$TMP_DIR/state.json"
  mv "$TMP_DIR/state.json" "$state_file"
}

run_gate() {
  local cwd="$1"
  local command="$2"

  jq -n --arg cwd "$cwd" --arg command "$command" '{
    hook_event_name:"PreToolUse",
    tool_name:"Bash",
    cwd:$cwd,
    tool_input:{command:$command}
  }' | bash "$REPO_ROOT/scripts/check-bash-command-gate.sh"
}

INACTIVE_PROJECT="$TMP_DIR/inactive-project"
mkdir -p "$INACTIVE_PROJECT/.claude"
write_v2_state "$INACTIVE_PROJECT/.claude/flow_state.json"
export CLAUDE_PROJECT_DIR="$INACTIVE_PROJECT"

allow_output="$(run_gate "$INACTIVE_PROJECT" 'cat .claude/flow_state.json')"
assert_allow "$allow_output"

NO_STATE_PROJECT="$TMP_DIR/no-state-project"
mkdir -p "$NO_STATE_PROJECT/.claude"
export CLAUDE_PROJECT_DIR="$NO_STATE_PROJECT"

allow_output="$(run_gate "$NO_STATE_PROJECT" 'cat .claude/flow_state.json')"
assert_allow "$allow_output"
if [ -e "$NO_STATE_PROJECT/.claude/flow_state.json" ]; then
  echo "Expected Bash gate to avoid bootstrapping a missing flow_state.json when only .claude/ exists" >&2
  exit 1
fi

ACTIVE_PROJECT="$TMP_DIR/active-project"
mkdir -p "$ACTIVE_PROJECT/.claude"
write_v2_state "$ACTIVE_PROJECT/.claude/flow_state.json"
set_workflow_active "$ACTIVE_PROJECT/.claude/flow_state.json"
export CLAUDE_PROJECT_DIR="$ACTIVE_PROJECT"

deny_output="$(
  BASH_GATE_NODE_BIN='/nonexistent/node' \
    run_gate "$ACTIVE_PROJECT" 'cat .claude/flow_state.json'
)"
assert_deny "$deny_output" 'Node'

TRACE_FILE="$TMP_DIR/node-trace.log"
NODE_WRAPPER="$TMP_DIR/node-wrapper.sh"
cat > "$NODE_WRAPPER" <<EOF
#!/bin/bash
set -euo pipefail
printf '%s\n' "\$*" >> "$TRACE_FILE"
exec "$(command -v node)" "\$@"
EOF
chmod +x "$NODE_WRAPPER"

allow_output="$(
  BASH_GATE_NODE_BIN="$NODE_WRAPPER" \
    run_gate "$ACTIVE_PROJECT" 'echo hello world'
)"
assert_allow "$allow_output"
assert_file_contains "$TRACE_FILE" 'check-bash-command-gate-node.cjs'

allow_output="$(
  BASH_GATE_NODE_BIN="$NODE_WRAPPER" \
    run_gate "$ACTIVE_PROJECT" 'if true; then echo ok; fi'
)"
assert_allow "$allow_output"

allow_output="$(
  BASH_GATE_NODE_BIN="$NODE_WRAPPER" \
    run_gate "$ACTIVE_PROJECT" 'cat <<< "hi"'
)"
assert_allow "$allow_output"

RECOVERABLE_PROJECT="$TMP_DIR/recoverable-project"
mkdir -p "$RECOVERABLE_PROJECT/.claude"
printf '{bad json\n' > "$RECOVERABLE_PROJECT/.claude/flow_state.json"
export CLAUDE_PROJECT_DIR="$RECOVERABLE_PROJECT"

allow_output="$(run_gate "$RECOVERABLE_PROJECT" 'cat .claude/flow_state.json')"
assert_allow "$allow_output"
assert_json_equals "$RECOVERABLE_PROJECT/.claude/flow_state.json" '.state_version' '2'
assert_json_equals "$RECOVERABLE_PROJECT/.claude/flow_state.json" '.workflow.active' 'false'

CORRUPT_PROJECT="$TMP_DIR/corrupt-project"
mkdir -p "$CORRUPT_PROJECT/.claude/flow_state.json"
export CLAUDE_PROJECT_DIR="$CORRUPT_PROJECT"

deny_output="$(run_gate "$CORRUPT_PROJECT" 'cat .claude/flow_state.json')"
assert_deny "$deny_output" '状态不可用'

unset CLAUDE_PROJECT_DIR
MISSING_CWD="$TMP_DIR/missing-project"
allow_output="$(run_gate "$MISSING_CWD" 'cat .claude/flow_state.json')"
assert_allow "$allow_output"
