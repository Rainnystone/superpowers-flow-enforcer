#!/bin/bash
set -euo pipefail

source tests/helpers/assert.sh
source tests/helpers/state-fixtures.sh

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

REPO_ROOT="$(pwd)"
export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"

export CLAUDE_PROJECT_DIR="$TMP_DIR/project"
mkdir -p "$CLAUDE_PROJECT_DIR/.claude"
write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"confirm skip planning"}' "$CLAUDE_PROJECT_DIR" \
  | bash scripts/sync-user-prompt-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.skip_planning' 'false'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.pending_confirmation_for' 'null'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.user_confirmed' 'false'

printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"skip planning - spec approved"}' "$CLAUDE_PROJECT_DIR" \
  | bash scripts/sync-user-prompt-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.skip_planning' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.pending_confirmation_for' '"planning"'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.user_confirmed' 'false'

printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"confirm skip review"}' "$CLAUDE_PROJECT_DIR" \
  | bash scripts/sync-user-prompt-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.skip_review' 'false'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.pending_confirmation_for' '"planning"'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.user_confirmed' 'false'

printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"confirm skip planning"}' "$CLAUDE_PROJECT_DIR" \
  | bash scripts/sync-user-prompt-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.user_confirmed' 'true'

write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"skip review"}' "$CLAUDE_PROJECT_DIR" \
  | bash scripts/sync-user-prompt-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.skip_review' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.pending_confirmation_for' '"review"'

printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"skip planning"}' "$CLAUDE_PROJECT_DIR" \
  | bash scripts/sync-user-prompt-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.skip_review' 'false'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.skip_planning' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.pending_confirmation_for' '"planning"'

printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"confirm skip planning"}' "$CLAUDE_PROJECT_DIR" \
  | bash scripts/sync-user-prompt-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.user_confirmed' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.skip_review' 'false'

write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"skip test - spec approved"}' "$CLAUDE_PROJECT_DIR" \
  | bash scripts/sync-user-prompt-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.skip_tdd' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.pending_confirmation_for' '"tdd"'

printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"confirm skip test"}' "$CLAUDE_PROJECT_DIR" \
  | bash scripts/sync-user-prompt-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.user_confirmed' 'true'

unset CLAUDE_PROJECT_DIR
SELF_HEAL_PROJECT="$TMP_DIR/self-heal-project"
mkdir -p "$SELF_HEAL_PROJECT"

printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"skip planning - spec approved"}' "$SELF_HEAL_PROJECT" \
  | bash scripts/sync-user-prompt-state.sh >/dev/null

assert_file_exists "$SELF_HEAL_PROJECT/.claude/flow_state.json"
assert_json_equals "$SELF_HEAL_PROJECT/.claude/flow_state.json" '.exceptions.skip_planning' 'true'
assert_json_equals "$SELF_HEAL_PROJECT/.claude/flow_state.json" '.workflow.active' 'true'
assert_json_equals "$SELF_HEAL_PROJECT/.claude/flow_state.json" '.workflow.activated_by' '"user_prompt_skip"'
if [ "$(jq -c '.workflow.activated_at' "$SELF_HEAL_PROJECT/.claude/flow_state.json")" = "null" ]; then
  echo "Expected .workflow.activated_at to be set" >&2
  exit 1
fi

BROKEN_PROJECT="$TMP_DIR/project-broken-state"
mkdir -p "$BROKEN_PROJECT/.claude"
printf '{"state_version":2,' > "$BROKEN_PROJECT/.claude/flow_state.json"

set +e
BROKEN_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"skip planning"}' "$BROKEN_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
BROKEN_STATUS=$?
set -e

if [ "$BROKEN_STATUS" -ne 0 ]; then
  echo "Expected exit 0 on malformed state, got $BROKEN_STATUS" >&2
  exit 1
fi

if [ -n "$BROKEN_OUTPUT" ] && ! printf '%s' "$BROKEN_OUTPUT" | jq empty >/dev/null 2>&1; then
  echo "Expected empty stdout or valid JSON on malformed state path" >&2
  exit 1
fi

NOOP_PWD="$TMP_DIR/pwd-noop"
mkdir -p "$NOOP_PWD"
(
  cd "$NOOP_PWD"
  unset CLAUDE_PROJECT_DIR
  printf '{bad json\n' | bash "$REPO_ROOT/scripts/sync-user-prompt-state.sh" >/dev/null
)

if [ -e "$NOOP_PWD/.claude/flow_state.json" ]; then
  echo "Expected malformed stdin to not create state in $NOOP_PWD" >&2
  exit 1
fi
