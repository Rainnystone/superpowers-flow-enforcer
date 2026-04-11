#!/bin/bash
set -euo pipefail

source tests/helpers/assert.sh
source tests/helpers/state-fixtures.sh

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

REPO_ROOT="$(pwd)"
export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"

export CLAUDE_PROJECT_DIR="$TMP_DIR/project-existing"
mkdir -p "$CLAUDE_PROJECT_DIR/.claude"
write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
jq '.interrupt.keywords_detected = ["legacy keyword"]' "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"暂停，明天继续"}' "$CLAUDE_PROJECT_DIR" \
  | bash scripts/sync-user-prompt-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.interrupt.allowed' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.interrupt.reason' '"暂停，明天继续"'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.interrupt.keywords_detected' 'null'

unset CLAUDE_PROJECT_DIR
SELF_HEAL_PROJECT="$TMP_DIR/project-self-heal"
mkdir -p "$SELF_HEAL_PROJECT"

printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"暂停，明天继续"}' "$SELF_HEAL_PROJECT" \
  | bash scripts/sync-user-prompt-state.sh >/dev/null

assert_file_exists "$SELF_HEAL_PROJECT/.claude/flow_state.json"
assert_json_equals "$SELF_HEAL_PROJECT/.claude/flow_state.json" '.interrupt.allowed' 'true'
assert_json_equals "$SELF_HEAL_PROJECT/.claude/flow_state.json" '.interrupt.reason' '"暂停，明天继续"'
assert_json_equals "$SELF_HEAL_PROJECT/.claude/flow_state.json" '.workflow.active' 'false'
assert_json_equals "$SELF_HEAL_PROJECT/.claude/flow_state.json" '.workflow.activated_by' 'null'
