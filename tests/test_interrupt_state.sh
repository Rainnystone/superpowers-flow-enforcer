#!/bin/bash
set -euo pipefail

source tests/helpers/assert.sh

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export CLAUDE_PLUGIN_ROOT="$(pwd)"
unset CLAUDE_PROJECT_DIR

mkdir -p "$TMP_DIR/project"

printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"暂停，明天继续"}' "$TMP_DIR/project" \
  | bash scripts/sync-user-prompt-state.sh >/dev/null

assert_file_exists "$TMP_DIR/project/.claude/flow_state.json"
assert_json_equals "$TMP_DIR/project/.claude/flow_state.json" '.interrupt.allowed' 'true'
assert_json_equals "$TMP_DIR/project/.claude/flow_state.json" '.interrupt.reason' '"暂停，明天继续"'
assert_json_equals "$TMP_DIR/project/.claude/flow_state.json" '.workflow.active' 'false'
assert_json_equals "$TMP_DIR/project/.claude/flow_state.json" '.workflow.activated_by' 'null'
