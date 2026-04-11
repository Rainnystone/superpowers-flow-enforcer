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

bash scripts/record-worktree-state.sh baseline pass

cat <<EOF | bash scripts/sync-post-tool-state.sh >"$TMP_DIR/worktree-chain-output.json"
{"tool_name":"Bash","tool_input":{"command":"cd repo && git worktree add .worktrees/chained HEAD"},"tool_result":"Preparing worktree (new branch 'chained')"}
EOF

assert_json_equals <(printf '%s' "$(cat "$TMP_DIR/worktree-chain-output.json")") '.decision' '"block"'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.created' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.path' '".worktrees/chained"'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.baseline_verified' 'false'

bash scripts/record-worktree-state.sh baseline pass

cat <<EOF | bash scripts/sync-post-tool-state.sh >"$TMP_DIR/worktree-shell-chain-output.json"
{"tool_name":"Bash","tool_input":{"command":"bash -lc \"cd repo && git worktree add .worktrees/shell-chain HEAD\""},"tool_result":"Preparing worktree (new branch 'shell-chain')"}
EOF

assert_json_equals <(printf '%s' "$(cat "$TMP_DIR/worktree-shell-chain-output.json")") '.decision' '"block"'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.created' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.path' '".worktrees/shell-chain"'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.baseline_verified' 'false'

bash scripts/record-worktree-state.sh baseline pass

cat <<EOF | bash scripts/sync-post-tool-state.sh >"$TMP_DIR/worktree-git-c-output.json"
{"tool_name":"Bash","tool_input":{"command":"git -C repo worktree add .worktrees/git-c HEAD"},"tool_result":"Preparing worktree (new branch 'git-c')"}
EOF

assert_json_equals <(printf '%s' "$(cat "$TMP_DIR/worktree-git-c-output.json")") '.decision' '"block"'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.created' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.path' '".worktrees/git-c"'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.baseline_verified' 'false'

cat <<'EOF' | bash scripts/sync-post-tool-state.sh >/dev/null
{"tool_name":"Bash","tool_input":{"command":"bash tests/test_init_state.sh"},"tool_result":"passed"}
EOF

assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.baseline_verified' 'false'

cat <<EOF | bash scripts/sync-post-tool-state.sh >"$TMP_DIR/worktree-echo-output.json"
{"tool_name":"Bash","tool_input":{"command":"echo git worktree add .worktrees/fake HEAD"},"tool_result":"git worktree add .worktrees/fake HEAD"}
EOF

assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.created' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.path' '".worktrees/git-c"'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.baseline_verified' 'false'

if [ -s "$TMP_DIR/worktree-echo-output.json" ]; then
  echo 'Expected echo-only worktree phrase not to trigger PostToolUse block output' >&2
  exit 1
fi
rm -f "$TMP_DIR/worktree-echo-output.json"

pretool_edit_hook_type="$(
  jq -r '
    .hooks.PreToolUse[]
    | select(.matcher == "Edit|Write")
    | .hooks[0].type // ""
  ' hooks/hooks.json
)"

pretool_edit_hook_command="$(
  jq -r '
    .hooks.PreToolUse[]
    | select(.matcher == "Edit|Write")
    | .hooks[0].command // ""
  ' hooks/hooks.json
)"

if [ "$pretool_edit_hook_type" != "command" ]; then
  echo 'Expected PreToolUse/Edit|Write gate to use command hook' >&2
  exit 1
fi

if [ "$pretool_edit_hook_command" != 'bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-pretool-gates.sh' ]; then
  echo 'Expected PreToolUse/Edit|Write gate to call scripts/check-pretool-gates.sh' >&2
  exit 1
fi

write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
jq '
  .workflow.active = true
  | .brainstorming.spec_written = true
  | .worktree.created = false
  | .worktree.baseline_verified = false
  | .tdd.pending_failure_record = false
  | .tdd.tests_verified_fail = ["src/app.test.ts"]
' "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

worktree_deny_output="$(
  jq -n --arg path 'src/app.ts' '{
    hook_event_name:"PreToolUse",
    tool_name:"Write",
    tool_input:{file_path:$path}
  }' | bash scripts/check-pretool-gates.sh
)"
[ -n "$worktree_deny_output" ] || {
  echo 'Expected command gate to deny production writes before worktree baseline verification' >&2
  exit 1
}
assert_json_equals <(printf '%s' "$worktree_deny_output") '.hookSpecificOutput.permissionDecision' '"deny"'
assert_json_equals <(printf '%s' "$worktree_deny_output") '.hookSpecificOutput.permissionDecisionReason | contains("worktree.created")' 'true'
assert_json_equals <(printf '%s' "$worktree_deny_output") '.hookSpecificOutput.permissionDecisionReason | contains("worktree.baseline_verified")' 'true'

jq '
  .worktree.created = true
  | .worktree.baseline_verified = true
' "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

worktree_allow_output="$(
  jq -n --arg path 'src/app.ts' '{
    hook_event_name:"PreToolUse",
    tool_name:"Write",
    tool_input:{file_path:$path}
  }' | bash scripts/check-pretool-gates.sh
)"
[ -z "$worktree_allow_output" ] || {
  echo 'Expected command gate to allow production writes after worktree baseline verification' >&2
  exit 1
}
