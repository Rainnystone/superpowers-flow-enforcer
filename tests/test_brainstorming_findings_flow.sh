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

printf '{"tool_name":"AskUserQuestion"}' | bash scripts/sync-post-tool-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.brainstorming.question_asked' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.brainstorming.findings_updated_after_question' 'false'

printf '{"tool_name":"Write","tool_input":{"file_path":"findings.md"}}' | bash scripts/sync-post-tool-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.brainstorming.findings_updated_after_question' 'true'

ask_user_question_hook_type="$(
  jq -r '
    .hooks.PreToolUse[]
    | select(.matcher == "AskUserQuestion")
    | .hooks[0].type // ""
  ' hooks/hooks.json
)"

ask_user_question_hook_command="$(
  jq -r '
    .hooks.PreToolUse[]
    | select(.matcher == "AskUserQuestion")
    | .hooks[0].command // ""
  ' hooks/hooks.json
)"

post_tool_ask_count="$(
  jq '
    [.hooks.PostToolUse[]? | select(.matcher == "AskUserQuestion")]
    | length
  ' hooks/hooks.json
)"

pre_tool_ask_count="$(
  jq '
    [.hooks.PreToolUse[]? | select(.matcher == "AskUserQuestion")]
    | length
  ' hooks/hooks.json
)"

if [ "$pre_tool_ask_count" -ne 1 ]; then
  echo "Expected AskUserQuestion hook gate to be defined in PreToolUse" >&2
  exit 1
fi

if [ "$post_tool_ask_count" -ne 0 ]; then
  echo "Expected AskUserQuestion hook gate to be removed from PostToolUse to avoid same-event races" >&2
  exit 1
fi

if [ "$ask_user_question_hook_type" != "command" ]; then
  echo "Expected AskUserQuestion hook gate to use command type" >&2
  exit 1
fi

if [ "$ask_user_question_hook_command" != 'bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-pretool-gates.sh' ]; then
  echo "Expected AskUserQuestion hook gate to call scripts/check-pretool-gates.sh" >&2
  exit 1
fi

write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
jq '
  .workflow.active = true
  | .current_phase = "brainstorming"
  | .brainstorming.question_asked = true
  | .brainstorming.findings_updated_after_question = false
' "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

deny_output="$(
  jq -n '{
    hook_event_name:"PreToolUse",
    tool_name:"AskUserQuestion"
  }' \
    | bash scripts/check-pretool-gates.sh
)"
[ -n "$deny_output" ] || {
  echo "Expected AskUserQuestion command gate to deny when findings were not updated" >&2
  exit 1
}
assert_json_equals <(printf '%s' "$deny_output") '.hookSpecificOutput.hookEventName' '"PreToolUse"'
assert_json_equals <(printf '%s' "$deny_output") '.hookSpecificOutput.permissionDecision' '"deny"'
assert_json_equals <(printf '%s' "$deny_output") '.hookSpecificOutput.permissionDecisionReason | contains("findings.md")' 'true'

jq '.workflow.active = false' "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

allow_output="$(
  jq -n '{
    hook_event_name:"PreToolUse",
    tool_name:"AskUserQuestion"
  }' \
    | bash scripts/check-pretool-gates.sh
)"
[ -z "$allow_output" ] || {
  echo "Expected AskUserQuestion command gate to allow when workflow is inactive" >&2
  exit 1
}
