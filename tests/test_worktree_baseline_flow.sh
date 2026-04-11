#!/bin/bash
set -euo pipefail

source tests/helpers/assert.sh
source tests/helpers/state-fixtures.sh

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export CLAUDE_PROJECT_DIR="$TMP_DIR/project"
export CLAUDE_PLUGIN_ROOT="$(pwd)"

mkdir -p "$CLAUDE_PROJECT_DIR/.claude"
write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

bash scripts/record-worktree-state.sh created /tmp/wt-1
bash scripts/record-worktree-state.sh baseline pass

assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.created' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.path' '"/tmp/wt-1"'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.baseline_verified' 'true'

bash scripts/record-worktree-state.sh created /tmp/wt-2

assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.created' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.path' '"/tmp/wt-2"'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.baseline_verified' 'false'

bash scripts/record-worktree-state.sh baseline pass

assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.baseline_verified' 'true'

cat <<'EOF' | bash scripts/sync-post-tool-state.sh >/dev/null
{"tool_name":"Bash","tool_input":{"command":"git worktree add .worktrees/test HEAD"},"tool_result":"fatal: '.worktrees/test' already exists"}
EOF

assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.created' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.path' '"/tmp/wt-2"'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.baseline_verified' 'true'

cat <<'EOF' | bash scripts/sync-post-tool-state.sh >/dev/null
{"tool_name":"Bash","tool_input":{"command":"git worktree add -B feature .worktrees/test HEAD"},"tool_result":"Preparing worktree (reset branch 'feature'; was at abc1234)"}
EOF

assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.created' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.path' '".worktrees/test"'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.baseline_verified' 'false'

bash scripts/record-worktree-state.sh baseline pass

assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.baseline_verified' 'true'

cat <<'EOF' | bash scripts/sync-post-tool-state.sh >/dev/null
{"tool_name":"Bash","tool_input":{"command":"git worktree add --lock --reason \"hotfix reason\" .worktrees/test HEAD"},"tool_result":"Preparing worktree (new branch 'hotfix')"}
EOF

assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.created' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.path' '".worktrees/test"'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.baseline_verified' 'false'

cat <<'EOF' | bash scripts/sync-post-tool-state.sh >/dev/null
{"tool_name":"Bash","tool_input":{"command":"bash tests/test_init_state.sh"},"tool_result":"passed"}
EOF

assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.baseline_verified' 'false'

tdd_gate_prompt="$(
  jq -r '
    .hooks.PreToolUse[]
    | select(.matcher == "Edit|Write")
    | .hooks[0].prompt
  ' hooks/hooks.json
)"

case "$tdd_gate_prompt" in
  *"worktree.created"*) : ;;
  *)
    echo 'Expected TDD gate prompt to reference worktree.created' >&2
    exit 1
    ;;
esac

case "$tdd_gate_prompt" in
  *"worktree.baseline_verified"*) : ;;
  *)
    echo 'Expected TDD gate prompt to reference worktree.baseline_verified' >&2
    exit 1
    ;;
esac

case "$tdd_gate_prompt" in
  *"baseline_tests_passed"*)
    echo 'Expected TDD gate prompt not to reference worktree.baseline_tests_passed' >&2
    exit 1
    ;;
esac
