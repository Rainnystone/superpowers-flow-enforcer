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
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"docs/superpowers/specs/2026-04-11-demo.md"}}' \
  | bash scripts/sync-post-tool-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.workflow.active' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.workflow.activated_by' '"spec_write"'

write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"docs/superpowers/plans/2026-04-11-demo.md"}}' \
  | bash scripts/sync-post-tool-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.workflow.active' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.workflow.activated_by' '"plan_write"'

write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"README.md"}}' \
  | bash scripts/sync-post-tool-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.workflow.active' 'false'
