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
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.current_phase' '"brainstorming"'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.workflow.active' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.workflow.activated_by' '"spec_write"'
if [ "$(jq -c '.workflow.activated_at' "$CLAUDE_PROJECT_DIR/.claude/flow_state.json")" = "null" ]; then
  echo "Expected spec write to set .workflow.activated_at" >&2
  exit 1
fi

write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"./docs/superpowers/specs/2026-04-11-demo.md"}}' \
  | bash scripts/sync-post-tool-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.current_phase' '"brainstorming"'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.workflow.active' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.workflow.activated_by' '"spec_write"'
if [ "$(jq -c '.workflow.activated_at' "$CLAUDE_PROJECT_DIR/.claude/flow_state.json")" = "null" ]; then
  echo "Expected dotted spec write to set .workflow.activated_at" >&2
  exit 1
fi

write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"'$CLAUDE_PROJECT_DIR'/docs/superpowers/specs/2026-04-11-demo.md"}}' \
  | bash scripts/sync-post-tool-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.current_phase' '"brainstorming"'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.workflow.active' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.workflow.activated_by' '"spec_write"'
if [ "$(jq -c '.workflow.activated_at' "$CLAUDE_PROJECT_DIR/.claude/flow_state.json")" = "null" ]; then
  echo "Expected absolute spec write to set .workflow.activated_at" >&2
  exit 1
fi

write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"./docs/superpowers/plans/2026-04-11-demo.md"}}' \
  | bash scripts/sync-post-tool-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.current_phase' '"planning"'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.workflow.active' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.workflow.activated_by' '"plan_write"'
if [ "$(jq -c '.workflow.activated_at' "$CLAUDE_PROJECT_DIR/.claude/flow_state.json")" = "null" ]; then
  echo "Expected dotted plan write to set .workflow.activated_at" >&2
  exit 1
fi

write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"docs/superpowers/plans/2026-04-11-demo.md"}}' \
  | bash scripts/sync-post-tool-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.current_phase' '"planning"'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.workflow.active' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.workflow.activated_by' '"plan_write"'
if [ "$(jq -c '.workflow.activated_at' "$CLAUDE_PROJECT_DIR/.claude/flow_state.json")" = "null" ]; then
  echo "Expected plan write to set .workflow.activated_at" >&2
  exit 1
fi

write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"'$CLAUDE_PROJECT_DIR'/docs/superpowers/plans/2026-04-11-demo.md"}}' \
  | bash scripts/sync-post-tool-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.current_phase' '"planning"'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.workflow.active' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.workflow.activated_by' '"plan_write"'
if [ "$(jq -c '.workflow.activated_at' "$CLAUDE_PROJECT_DIR/.claude/flow_state.json")" = "null" ]; then
  echo "Expected absolute plan write to set .workflow.activated_at" >&2
  exit 1
fi

write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"README.md"}}' \
  | bash scripts/sync-post-tool-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.current_phase' '"init"'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.workflow.active' 'false'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.workflow.activated_by' 'null'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.workflow.activated_at' 'null'

write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/tmp/outside/docs/superpowers/specs/2026-04-11-demo.md"}}' \
  | bash scripts/sync-post-tool-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.current_phase' '"init"'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.workflow.active' 'false'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.workflow.activated_by' 'null'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.workflow.activated_at' 'null'
