#!/bin/bash
set -euo pipefail

source tests/helpers/assert.sh

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export CLAUDE_PLUGIN_ROOT="$(pwd)"
unset CLAUDE_PROJECT_DIR

mkdir -p "$TMP_DIR/project"

printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"skip planning - spec approved"}' "$TMP_DIR/project" \
  | bash scripts/sync-user-prompt-state.sh >/dev/null

assert_file_exists "$TMP_DIR/project/.claude/flow_state.json"
assert_json_equals "$TMP_DIR/project/.claude/flow_state.json" '.exceptions.skip_planning' 'true'
assert_json_equals "$TMP_DIR/project/.claude/flow_state.json" '.workflow.active' 'true'
assert_json_equals "$TMP_DIR/project/.claude/flow_state.json" '.workflow.activated_by' '"user_prompt_skip"'
if [ "$(jq -c '.workflow.activated_at' "$TMP_DIR/project/.claude/flow_state.json")" = "null" ]; then
  echo "Expected .workflow.activated_at to be set" >&2
  exit 1
fi
