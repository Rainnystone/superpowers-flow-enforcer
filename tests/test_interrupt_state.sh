#!/bin/bash
set -euo pipefail

source tests/helpers/assert.sh
source tests/helpers/state-fixtures.sh

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export CLAUDE_PROJECT_DIR="$TMP_DIR/project"
mkdir -p "$CLAUDE_PROJECT_DIR/.claude"
write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
jq '.interrupt.keywords_detected = ["legacy keyword"]' "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

printf '{"user_prompt":"暂停，明天继续"}' | bash scripts/sync-user-prompt-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.interrupt.allowed' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.interrupt.reason' '"暂停，明天继续"'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.interrupt.keywords_detected' 'null'
