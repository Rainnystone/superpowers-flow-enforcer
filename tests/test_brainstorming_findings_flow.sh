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

ask_user_question_prompt="$(
  jq -r '
    .hooks.PreToolUse[]
    | select(.matcher == "AskUserQuestion")
    | .hooks[0].prompt
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

case "$ask_user_question_prompt" in
  *"brainstorming.skill_invoked"*)
    echo "Expected AskUserQuestion hook gate to stop depending on brainstorming.skill_invoked" >&2
    exit 1
    ;;
esac

case "$ask_user_question_prompt" in
  *"question_asked"*) : ;;
  *)
    echo "Expected AskUserQuestion hook gate to reference brainstorming.question_asked" >&2
    exit 1
    ;;
esac

case "$ask_user_question_prompt" in
  *"findings_updated_after_question"*) : ;;
  *)
    echo "Expected AskUserQuestion hook gate to reference brainstorming.findings_updated_after_question" >&2
    exit 1
    ;;
esac
