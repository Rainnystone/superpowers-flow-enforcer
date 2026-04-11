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

CONFIRM_SKIP_PLANNING_NO_PENDING_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"confirm skip planning"}' "$CLAUDE_PROJECT_DIR" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$CONFIRM_SKIP_PLANNING_NO_PENDING_OUTPUT" ]; then
  echo "Expected confirm skip planning without pending phase to be silent allow" >&2
  exit 1
fi
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.skip_planning' 'false'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.pending_confirmation_for' 'null'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.user_confirmed' 'false'

SKIP_PLANNING_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"skip planning - spec approved"}' "$CLAUDE_PROJECT_DIR" \
    | bash scripts/sync-user-prompt-state.sh
)"
assert_json_equals <(printf '%s' "$SKIP_PLANNING_OUTPUT") '.decision' '"block"'
assert_json_equals <(printf '%s' "$SKIP_PLANNING_OUTPUT") '.reason | contains("确认跳过")' 'true'
assert_json_equals <(printf '%s' "$SKIP_PLANNING_OUTPUT") '.reason | contains("并给出原因")' 'false'
assert_json_equals <(printf '%s' "$SKIP_PLANNING_OUTPUT") '.reason | contains("可选")' 'true'
assert_json_equals <(printf '%s' "$SKIP_PLANNING_OUTPUT") '. | keys | sort' '["decision","reason"]'

skip_planning_output_objects="$(printf '%s' "$SKIP_PLANNING_OUTPUT" | jq -s 'length')"
if [ "$skip_planning_output_objects" != "1" ]; then
  echo "Expected skip planning to emit exactly one top-level JSON object, got $skip_planning_output_objects" >&2
  exit 1
fi

assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.skip_planning' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.pending_confirmation_for' '"planning"'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.user_confirmed' 'false'

printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"confirm skip review"}' "$CLAUDE_PROJECT_DIR" \
  | bash scripts/sync-user-prompt-state.sh > "$TMP_DIR/confirm-skip-review.json"
if [ -s "$TMP_DIR/confirm-skip-review.json" ]; then
  echo "Expected confirm skip review with mismatched pending phase to be silent allow" >&2
  exit 1
fi
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.skip_review' 'false'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.pending_confirmation_for' '"planning"'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.user_confirmed' 'false'

printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"confirm skip planning because spec is trivial"}' "$CLAUDE_PROJECT_DIR" \
  | bash scripts/sync-user-prompt-state.sh > "$TMP_DIR/confirm-skip-planning.json"
if [ -s "$TMP_DIR/confirm-skip-planning.json" ]; then
  echo "Expected confirm skip planning with appended reason (matching pending phase) to be silent allow" >&2
  exit 1
fi
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.user_confirmed' 'true'

write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

SKIP_REVIEW_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"skip review"}' "$CLAUDE_PROJECT_DIR" \
    | bash scripts/sync-user-prompt-state.sh
)"
assert_json_equals <(printf '%s' "$SKIP_REVIEW_OUTPUT") '.decision' '"block"'
assert_json_equals <(printf '%s' "$SKIP_REVIEW_OUTPUT") '. | keys | sort' '["decision","reason"]'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.skip_review' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.pending_confirmation_for' '"review"'

SKIP_PLANNING_RESET_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"skip planning"}' "$CLAUDE_PROJECT_DIR" \
    | bash scripts/sync-user-prompt-state.sh
)"
assert_json_equals <(printf '%s' "$SKIP_PLANNING_RESET_OUTPUT") '.decision' '"block"'
assert_json_equals <(printf '%s' "$SKIP_PLANNING_RESET_OUTPUT") '. | keys | sort' '["decision","reason"]'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.skip_review' 'false'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.skip_planning' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.pending_confirmation_for' '"planning"'

printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"confirm skip planning"}' "$CLAUDE_PROJECT_DIR" \
  | bash scripts/sync-user-prompt-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.user_confirmed' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.skip_review' 'false'

write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

SKIP_TEST_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"skip test - spec approved"}' "$CLAUDE_PROJECT_DIR" \
    | bash scripts/sync-user-prompt-state.sh
)"
assert_json_equals <(printf '%s' "$SKIP_TEST_OUTPUT") '.decision' '"block"'
assert_json_equals <(printf '%s' "$SKIP_TEST_OUTPUT") '. | keys | sort' '["decision","reason"]'
assert_json_equals <(printf '%s' "$SKIP_TEST_OUTPUT") '.reason | contains("tdd")' 'true'
assert_json_equals <(printf '%s' "$SKIP_TEST_OUTPUT") '.reason | contains("test/测试")' 'true'
assert_json_equals <(printf '%s' "$SKIP_TEST_OUTPUT") '.reason | contains("并给出原因")' 'false'
assert_json_equals <(printf '%s' "$SKIP_TEST_OUTPUT") '.reason | contains("可选")' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.skip_tdd' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.pending_confirmation_for' '"tdd"'

printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"confirm skip tdd because this task is tiny"}' "$CLAUDE_PROJECT_DIR" \
  | bash scripts/sync-user-prompt-state.sh > "$TMP_DIR/confirm-skip-tdd.json"
if [ -s "$TMP_DIR/confirm-skip-tdd.json" ]; then
  echo "Expected confirm skip tdd with appended reason to be silent allow" >&2
  exit 1
fi
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.user_confirmed' 'true'

write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

SKIP_TEST_OUTPUT_CONFIRM_TEST="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"skip test - spec approved"}' "$CLAUDE_PROJECT_DIR" \
    | bash scripts/sync-user-prompt-state.sh
)"
assert_json_equals <(printf '%s' "$SKIP_TEST_OUTPUT_CONFIRM_TEST") '.decision' '"block"'

printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"confirm skip test because this is infra-only"}' "$CLAUDE_PROJECT_DIR" \
  | bash scripts/sync-user-prompt-state.sh > "$TMP_DIR/confirm-skip-test.json"
if [ -s "$TMP_DIR/confirm-skip-test.json" ]; then
  echo "Expected confirm skip test with appended reason to be silent allow" >&2
  exit 1
fi
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.user_confirmed' 'true'

write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

SKIP_TEST_OUTPUT_CONFIRM_CN="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"skip test - spec approved"}' "$CLAUDE_PROJECT_DIR" \
    | bash scripts/sync-user-prompt-state.sh
)"
assert_json_equals <(printf '%s' "$SKIP_TEST_OUTPUT_CONFIRM_CN") '.decision' '"block"'

printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"确认跳过测试 因为这个改动很小"}' "$CLAUDE_PROJECT_DIR" \
  | bash scripts/sync-user-prompt-state.sh > "$TMP_DIR/confirm-skip-test-cn.json"
if [ -s "$TMP_DIR/confirm-skip-test-cn.json" ]; then
  echo "Expected 确认跳过测试 with appended reason to be silent allow" >&2
  exit 1
fi
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.user_confirmed' 'true'

unset CLAUDE_PROJECT_DIR
ROOT_STATE_PROJECT="$TMP_DIR/root-state-project"
mkdir -p "$ROOT_STATE_PROJECT/.claude" "$ROOT_STATE_PROJECT/nested/child"
write_v2_state "$ROOT_STATE_PROJECT/.claude/flow_state.json"

ROOT_STATE_SKIP_PLANNING_FROM_ENV_OUTPUT="$(
  (
    export CLAUDE_PROJECT_DIR="$ROOT_STATE_PROJECT/nested/child"
    printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"skip planning"}' "$ROOT_STATE_PROJECT/nested/child" \
      | bash scripts/sync-user-prompt-state.sh
  )
)"
assert_json_equals <(printf '%s' "$ROOT_STATE_SKIP_PLANNING_FROM_ENV_OUTPUT") '.decision' '"block"'
assert_json_equals "$ROOT_STATE_PROJECT/.claude/flow_state.json" '.exceptions.skip_planning' 'true'
assert_json_equals "$ROOT_STATE_PROJECT/.claude/flow_state.json" '.exceptions.pending_confirmation_for' '"planning"'
if [ -e "$ROOT_STATE_PROJECT/nested/child/.claude/flow_state.json" ]; then
  echo "Expected CLAUDE_PROJECT_DIR child path to resolve to root flow_state.json instead of bootstrapping a new one" >&2
  exit 1
fi

write_v2_state "$ROOT_STATE_PROJECT/.claude/flow_state.json"

ROOT_STATE_SKIP_PLANNING_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"skip planning"}' "$ROOT_STATE_PROJECT/nested/child" \
    | bash scripts/sync-user-prompt-state.sh
)"
assert_json_equals <(printf '%s' "$ROOT_STATE_SKIP_PLANNING_OUTPUT") '.decision' '"block"'
assert_json_equals "$ROOT_STATE_PROJECT/.claude/flow_state.json" '.exceptions.skip_planning' 'true'
assert_json_equals "$ROOT_STATE_PROJECT/.claude/flow_state.json" '.exceptions.pending_confirmation_for' '"planning"'
if [ -e "$ROOT_STATE_PROJECT/nested/child/.claude/flow_state.json" ]; then
  echo "Expected nested child to reuse root flow_state.json instead of bootstrapping a new one" >&2
  exit 1
fi

SELF_HEAL_PROJECT="$TMP_DIR/self-heal-project"
mkdir -p "$SELF_HEAL_PROJECT"

SELF_HEAL_SKIP_PLANNING_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"skip planning - spec approved"}' "$SELF_HEAL_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
assert_json_equals <(printf '%s' "$SELF_HEAL_SKIP_PLANNING_OUTPUT") '.decision' '"block"'
assert_json_equals <(printf '%s' "$SELF_HEAL_SKIP_PLANNING_OUTPUT") '. | keys | sort' '["decision","reason"]'

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

if [ -n "$BROKEN_OUTPUT" ]; then
  echo "Expected malformed state fail-open path to be silent" >&2
  exit 1
fi

NOOP_PWD="$TMP_DIR/pwd-noop"
mkdir -p "$NOOP_PWD"
(
  cd "$NOOP_PWD"
  unset CLAUDE_PROJECT_DIR
  MALFORMED_INPUT_OUTPUT="$(printf '{bad json\n' | bash "$REPO_ROOT/scripts/sync-user-prompt-state.sh")"
  if [ -n "$MALFORMED_INPUT_OUTPUT" ]; then
    echo "Expected malformed stdin fail-open path to be silent" >&2
    exit 1
  fi
)

if [ -e "$NOOP_PWD/.claude/flow_state.json" ]; then
  echo "Expected malformed stdin to not create state in $NOOP_PWD" >&2
  exit 1
fi
