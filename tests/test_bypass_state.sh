#!/bin/bash
set -euo pipefail

source tests/helpers/assert.sh
source tests/helpers/state-fixtures.sh

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export CLAUDE_PROJECT_DIR="$TMP_DIR/project"
mkdir -p "$CLAUDE_PROJECT_DIR/.claude"
write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

printf '{"user_prompt":"confirm skip planning"}' | bash scripts/sync-user-prompt-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.skip_planning' 'false'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.pending_confirmation_for' 'null'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.user_confirmed' 'false'

printf '{"user_prompt":"skip planning - spec approved"}' | bash scripts/sync-user-prompt-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.skip_planning' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.pending_confirmation_for' '"planning"'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.user_confirmed' 'false'

printf '{"user_prompt":"confirm skip review"}' | bash scripts/sync-user-prompt-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.skip_review' 'false'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.pending_confirmation_for' '"planning"'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.user_confirmed' 'false'

printf '{"user_prompt":"confirm skip planning"}' | bash scripts/sync-user-prompt-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.user_confirmed' 'true'

write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

printf '{"user_prompt":"skip review"}' | bash scripts/sync-user-prompt-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.skip_review' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.pending_confirmation_for' '"review"'

printf '{"user_prompt":"skip planning"}' | bash scripts/sync-user-prompt-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.skip_review' 'false'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.skip_planning' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.pending_confirmation_for' '"planning"'

printf '{"user_prompt":"confirm skip planning"}' | bash scripts/sync-user-prompt-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.user_confirmed' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.skip_review' 'false'

write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

printf '{"user_prompt":"skip test - spec approved"}' | bash scripts/sync-user-prompt-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.skip_tdd' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.pending_confirmation_for' '"tdd"'

printf '{"user_prompt":"confirm skip test"}' | bash scripts/sync-user-prompt-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.user_confirmed' 'true'
