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

MANUAL_PROMPT_PROJECT="$TMP_DIR/manual-prompt-project"
mkdir -p "$MANUAL_PROMPT_PROJECT/.claude"
STATE_FILE="$MANUAL_PROMPT_PROJECT/.claude/flow_state.json"
write_v2_state "$STATE_FILE"

STATE_SNAPSHOT_BEFORE_NEGATIVE_PROMPTS="$(jq -c . "$STATE_FILE")"

NEGATIVE_DEACTIVATE_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"不要关闭 superpowers enforcer，我是在解释命令"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$NEGATIVE_DEACTIVATE_OUTPUT" ]; then
  echo "Expected explanatory negative deactivate prompt to be silent allow" >&2
  exit 1
fi
STATE_SNAPSHOT_AFTER_NEGATIVE_DEACTIVATE="$(jq -c . "$STATE_FILE")"
if [ "$STATE_SNAPSHOT_AFTER_NEGATIVE_DEACTIVATE" != "$STATE_SNAPSHOT_BEFORE_NEGATIVE_PROMPTS" ]; then
  echo "Expected explanatory negative deactivate prompt to keep state unchanged" >&2
  exit 1
fi

NEGATIVE_ACTIVATE_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"如果用户输入 激活 superpowers enforcer，这个 hook 会做什么？"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$NEGATIVE_ACTIVATE_OUTPUT" ]; then
  echo "Expected explanatory activate question prompt to be silent allow" >&2
  exit 1
fi
STATE_SNAPSHOT_AFTER_NEGATIVE_ACTIVATE="$(jq -c . "$STATE_FILE")"
if [ "$STATE_SNAPSHOT_AFTER_NEGATIVE_ACTIVATE" != "$STATE_SNAPSHOT_BEFORE_NEGATIVE_PROMPTS" ]; then
  echo "Expected explanatory activate question prompt to keep state unchanged" >&2
  exit 1
fi

NEGATIVE_EXPLAINING_ACTIVATE_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"请说明 激活 superpowers enforcer 这样写的含义"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$NEGATIVE_EXPLAINING_ACTIVATE_OUTPUT" ]; then
  echo "Expected explaining activate prompt to be silent allow" >&2
  exit 1
fi
STATE_SNAPSHOT_AFTER_NEGATIVE_EXPLAINING_ACTIVATE="$(jq -c . "$STATE_FILE")"
if [ "$STATE_SNAPSHOT_AFTER_NEGATIVE_EXPLAINING_ACTIVATE" != "$STATE_SNAPSHOT_BEFORE_NEGATIVE_PROMPTS" ]; then
  echo "Expected explaining activate prompt to keep state unchanged" >&2
  exit 1
fi

NEGATIVE_EXAMPLE_DEACTIVATE_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"不是要关闭 superpowers enforcer，只是举个例子"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$NEGATIVE_EXAMPLE_DEACTIVATE_OUTPUT" ]; then
  echo "Expected example deactivate prompt to be silent allow" >&2
  exit 1
fi
STATE_SNAPSHOT_AFTER_NEGATIVE_EXAMPLE_DEACTIVATE="$(jq -c . "$STATE_FILE")"
if [ "$STATE_SNAPSHOT_AFTER_NEGATIVE_EXAMPLE_DEACTIVATE" != "$STATE_SNAPSHOT_BEFORE_NEGATIVE_PROMPTS" ]; then
  echo "Expected example deactivate prompt to keep state unchanged" >&2
  exit 1
fi

NEGATIVE_COLON_EXPLAIN_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"请说明这句：激活 superpowers enforcer"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$NEGATIVE_COLON_EXPLAIN_OUTPUT" ]; then
  echo "Expected colon explanation activate prompt to be silent allow" >&2
  exit 1
fi
STATE_SNAPSHOT_AFTER_NEGATIVE_COLON_EXPLAIN="$(jq -c . "$STATE_FILE")"
if [ "$STATE_SNAPSHOT_AFTER_NEGATIVE_COLON_EXPLAIN" != "$STATE_SNAPSHOT_BEFORE_NEGATIVE_PROMPTS" ]; then
  echo "Expected colon explanation activate prompt to keep state unchanged" >&2
  exit 1
fi

NEGATIVE_ENGLISH_QUESTION_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"If the user says activate superpowers enforcer, what will this hook do?"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$NEGATIVE_ENGLISH_QUESTION_OUTPUT" ]; then
  echo "Expected English explanatory activate prompt to be silent allow" >&2
  exit 1
fi
STATE_SNAPSHOT_AFTER_NEGATIVE_ENGLISH_QUESTION="$(jq -c . "$STATE_FILE")"
if [ "$STATE_SNAPSHOT_AFTER_NEGATIVE_ENGLISH_QUESTION" != "$STATE_SNAPSHOT_BEFORE_NEGATIVE_PROMPTS" ]; then
  echo "Expected English explanatory activate prompt to keep state unchanged" >&2
  exit 1
fi

NEGATIVE_ENGLISH_COLON_EXPLAIN_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"Please explain: deactivate superpowers enforcer"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$NEGATIVE_ENGLISH_COLON_EXPLAIN_OUTPUT" ]; then
  echo "Expected English explanatory deactivate prompt to be silent allow" >&2
  exit 1
fi
STATE_SNAPSHOT_AFTER_NEGATIVE_ENGLISH_COLON_EXPLAIN="$(jq -c . "$STATE_FILE")"
if [ "$STATE_SNAPSHOT_AFTER_NEGATIVE_ENGLISH_COLON_EXPLAIN" != "$STATE_SNAPSHOT_BEFORE_NEGATIVE_PROMPTS" ]; then
  echo "Expected English explanatory deactivate prompt to keep state unchanged" >&2
  exit 1
fi

MID_SENTENCE_ACTIVATE_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"先整理上下文，然后激活 superpowers enforcer 再继续"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$MID_SENTENCE_ACTIVATE_OUTPUT" ]; then
  echo "Expected mid-sentence activate prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.workflow.active' 'true'
assert_json_equals "$STATE_FILE" '.workflow.override' '"manual_on"'
assert_json_equals "$STATE_FILE" '.workflow.activated_by' '"manual_prompt"'

ENGLISH_MID_SENTENCE_ACTIVATE_OUTPUT="$(
  write_v2_state "$STATE_FILE"
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"First summarize context, then activate superpowers enforcer and continue"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$ENGLISH_MID_SENTENCE_ACTIVATE_OUTPUT" ]; then
  echo "Expected English mid-sentence activate prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.workflow.active' 'true'
assert_json_equals "$STATE_FILE" '.workflow.override' '"manual_on"'
assert_json_equals "$STATE_FILE" '.workflow.activated_by' '"manual_prompt"'

POLITE_ACTIVATE_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"请激活 superpowers enforcer，谢谢"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$POLITE_ACTIVATE_OUTPUT" ]; then
  echo "Expected polite activate prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.workflow.active' 'true'
assert_json_equals "$STATE_FILE" '.workflow.override' '"manual_on"'
assert_json_equals "$STATE_FILE" '.workflow.activated_by' '"manual_prompt"'

ENGLISH_POLITE_ACTIVATE_OUTPUT="$(
  write_v2_state "$STATE_FILE"
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"Please activate superpowers enforcer, thanks"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$ENGLISH_POLITE_ACTIVATE_OUTPUT" ]; then
  echo "Expected English polite activate prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.workflow.active' 'true'
assert_json_equals "$STATE_FILE" '.workflow.override' '"manual_on"'
assert_json_equals "$STATE_FILE" '.workflow.activated_by' '"manual_prompt"'

MID_SENTENCE_DEACTIVATE_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"先完成收尾，然后关闭 superpowers enforcer 再返回"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$MID_SENTENCE_DEACTIVATE_OUTPUT" ]; then
  echo "Expected mid-sentence deactivate prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.workflow.active' 'false'
assert_json_equals "$STATE_FILE" '.workflow.override' '"manual_off"'
assert_json_equals "$STATE_FILE" '.workflow.deactivated_by' '"manual_prompt"'

ENGLISH_MID_SENTENCE_DEACTIVATE_OUTPUT="$(
  jq '.workflow.active = true | .workflow.override = "manual_on" | .workflow.activated_by = "manual_prompt"' "$STATE_FILE" > "$STATE_FILE.tmp"
  mv "$STATE_FILE.tmp" "$STATE_FILE"
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"First wrap up, then deactivate superpowers enforcer and return"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$ENGLISH_MID_SENTENCE_DEACTIVATE_OUTPUT" ]; then
  echo "Expected English mid-sentence deactivate prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.workflow.active' 'false'
assert_json_equals "$STATE_FILE" '.workflow.override' '"manual_off"'
assert_json_equals "$STATE_FILE" '.workflow.deactivated_by' '"manual_prompt"'

POLITE_DEACTIVATE_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"请关闭 superpowers enforcer，谢谢"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$POLITE_DEACTIVATE_OUTPUT" ]; then
  echo "Expected polite deactivate prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.workflow.active' 'false'
assert_json_equals "$STATE_FILE" '.workflow.override' '"manual_off"'
assert_json_equals "$STATE_FILE" '.workflow.deactivated_by' '"manual_prompt"'

ENGLISH_POLITE_DEACTIVATE_OUTPUT="$(
  jq '.workflow.active = true | .workflow.override = "manual_on" | .workflow.activated_by = "manual_prompt"' "$STATE_FILE" > "$STATE_FILE.tmp"
  mv "$STATE_FILE.tmp" "$STATE_FILE"
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"Please deactivate superpowers enforcer, thanks"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$ENGLISH_POLITE_DEACTIVATE_OUTPUT" ]; then
  echo "Expected English polite deactivate prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.workflow.active' 'false'
assert_json_equals "$STATE_FILE" '.workflow.override' '"manual_off"'
assert_json_equals "$STATE_FILE" '.workflow.deactivated_by' '"manual_prompt"'

MANUAL_ACTIVATE_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"  请先   激活   superpowers    enforcer  然后继续  "}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$MANUAL_ACTIVATE_OUTPUT" ]; then
  echo "Expected manual activate prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.workflow.active' 'true'
assert_json_equals "$STATE_FILE" '.workflow.override' '"manual_on"'
assert_json_equals "$STATE_FILE" '.workflow.activated_by' '"manual_prompt"'

MANUAL_DEACTIVATE_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"先   关闭   superpowers   enforcer  再说"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$MANUAL_DEACTIVATE_OUTPUT" ]; then
  echo "Expected manual deactivate prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.workflow.active' 'false'
assert_json_equals "$STATE_FILE" '.workflow.override' '"manual_off"'
assert_json_equals "$STATE_FILE" '.workflow.deactivated_by' '"manual_prompt"'

SKIP_AFTER_MANUAL_OFF_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"skip planning"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
assert_json_equals <(printf '%s' "$SKIP_AFTER_MANUAL_OFF_OUTPUT") '.decision' '"block"'
assert_json_equals "$STATE_FILE" '.workflow.active' 'true'
assert_json_equals "$STATE_FILE" '.workflow.override' 'null'
assert_json_equals "$STATE_FILE" '.workflow.activated_by' '"user_prompt_skip"'
assert_json_equals "$STATE_FILE" '.workflow.deactivated_by' 'null'
assert_json_equals "$STATE_FILE" '.workflow.deactivated_at' 'null'

write_v2_state "$STATE_FILE"
printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"关闭 superpowers enforcer"}' "$MANUAL_PROMPT_PROJECT" \
  | bash scripts/sync-user-prompt-state.sh >/dev/null
assert_json_equals "$STATE_FILE" '.workflow.override' '"manual_off"'

MANUAL_ACTIVATE_AFTER_MANUAL_OFF_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"请  激活   superpowers enforcer"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$MANUAL_ACTIVATE_AFTER_MANUAL_OFF_OUTPUT" ]; then
  echo "Expected manual activate after manual off to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.workflow.active' 'true'
assert_json_equals "$STATE_FILE" '.workflow.override' '"manual_on"'
assert_json_equals "$STATE_FILE" '.workflow.activated_by' '"manual_prompt"'
assert_json_equals "$STATE_FILE" '.workflow.deactivated_by' 'null'
assert_json_equals "$STATE_FILE" '.workflow.deactivated_at' 'null'

write_v2_state "$STATE_FILE"

SHORT_MANUAL_ACTIVATE_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"请开启 enforcer"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$SHORT_MANUAL_ACTIVATE_OUTPUT" ]; then
  echo "Expected short manual activate prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.workflow.override' '"manual_on"'
assert_json_equals "$STATE_FILE" '.workflow.activated_by' '"manual_prompt"'
assert_json_equals "$STATE_FILE" '.interrupt.allowed' 'false'

write_v2_state "$STATE_FILE"

SHORT_MANUAL_DEACTIVATE_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"先整理上下文，然后关闭 enforcer 再继续"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$SHORT_MANUAL_DEACTIVATE_OUTPUT" ]; then
  echo "Expected short manual deactivate prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.workflow.override' '"manual_off"'
assert_json_equals "$STATE_FILE" '.workflow.deactivated_by' '"manual_prompt"'
assert_json_equals "$STATE_FILE" '.interrupt.allowed' 'false'

write_v2_state "$STATE_FILE"

ENGLISH_SHORT_MANUAL_ACTIVATE_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"Please enable enforcer, thanks"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$ENGLISH_SHORT_MANUAL_ACTIVATE_OUTPUT" ]; then
  echo "Expected English short manual activate prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.workflow.override' '"manual_on"'
assert_json_equals "$STATE_FILE" '.workflow.activated_by' '"manual_prompt"'
assert_json_equals "$STATE_FILE" '.interrupt.allowed' 'false'

write_v2_state "$STATE_FILE"

SHORT_MANUAL_DEACTIVATE_WITH_STOP_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"disable enforcer and stop for now"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$SHORT_MANUAL_DEACTIVATE_WITH_STOP_OUTPUT" ]; then
  echo "Expected short manual deactivate prompt with stop to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.workflow.override' '"manual_off"'
assert_json_equals "$STATE_FILE" '.workflow.deactivated_by' '"manual_prompt"'
assert_json_equals "$STATE_FILE" '.interrupt.allowed' 'false'

write_v2_state "$STATE_FILE"

NEGATIVE_STOPPED_WORKING_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"disable enforcer stopped working after the patch"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$NEGATIVE_STOPPED_WORKING_OUTPUT" ]; then
  echo "Expected discussion prompt with stopped working to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.workflow.override' 'null'
assert_json_equals "$STATE_FILE" '.workflow.deactivated_by' 'null'
assert_json_equals "$STATE_FILE" '.workflow.active' 'false'
assert_json_equals "$STATE_FILE" '.interrupt.allowed' 'false'
assert_json_equals "$STATE_FILE" '.interrupt.reason' 'null'
assert_json_equals "$STATE_FILE" '.interrupt.keywords_detected' '[]'

write_v2_state "$STATE_FILE"

NEGATIVE_EXPLANATORY_STOP_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"Please explain disable enforcer stop semantics"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$NEGATIVE_EXPLANATORY_STOP_OUTPUT" ]; then
  echo "Expected explanatory short-command prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.workflow.override' 'null'
assert_json_equals "$STATE_FILE" '.workflow.deactivated_by' 'null'
assert_json_equals "$STATE_FILE" '.workflow.active' 'false'
assert_json_equals "$STATE_FILE" '.interrupt.allowed' 'false'
assert_json_equals "$STATE_FILE" '.interrupt.reason' 'null'
assert_json_equals "$STATE_FILE" '.interrupt.keywords_detected' '[]'

write_v2_state "$STATE_FILE"

POSITIVE_STOP_INTERRUPT_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"Please stop for now"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$POSITIVE_STOP_INTERRUPT_OUTPUT" ]; then
  echo "Expected real stop pause prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.interrupt.allowed' 'true'
assert_json_equals "$STATE_FILE" '.interrupt.reason' '"Please stop for now"'
assert_json_equals "$STATE_FILE" '.interrupt.keywords_detected' 'null'

write_v2_state "$STATE_FILE"

POSITIVE_STOP_HERE_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"Please stop here and continue tomorrow"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$POSITIVE_STOP_HERE_OUTPUT" ]; then
  echo "Expected stop here pause prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.interrupt.allowed' 'true'
assert_json_equals "$STATE_FILE" '.interrupt.reason' '"Please stop here and continue tomorrow"'
assert_json_equals "$STATE_FILE" '.interrupt.keywords_detected' 'null'

write_v2_state "$STATE_FILE"

POSITIVE_STOP_AFTER_STEP_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"Please stop after this step"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$POSITIVE_STOP_AFTER_STEP_OUTPUT" ]; then
  echo "Expected stop after this step prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.interrupt.allowed' 'true'
assert_json_equals "$STATE_FILE" '.interrupt.reason' '"Please stop after this step"'
assert_json_equals "$STATE_FILE" '.interrupt.keywords_detected' 'null'

write_v2_state "$STATE_FILE"

POSITIVE_STOP_DO_NOT_CONTINUE_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"Please stop and do not continue"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$POSITIVE_STOP_DO_NOT_CONTINUE_OUTPUT" ]; then
  echo "Expected stop and do not continue prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.interrupt.allowed' 'true'
assert_json_equals "$STATE_FILE" '.interrupt.reason' '"Please stop and do not continue"'
assert_json_equals "$STATE_FILE" '.interrupt.keywords_detected' 'null'

write_v2_state "$STATE_FILE"

POSITIVE_STOP_IF_TOO_LONG_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"Please stop if this takes too long"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$POSITIVE_STOP_IF_TOO_LONG_OUTPUT" ]; then
  echo "Expected stop if this takes too long prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.interrupt.allowed' 'true'
assert_json_equals "$STATE_FILE" '.interrupt.reason' '"Please stop if this takes too long"'
assert_json_equals "$STATE_FILE" '.interrupt.keywords_detected' 'null'

write_v2_state "$STATE_FILE"

POSITIVE_STOP_AND_EXPLAIN_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"Please stop and explain the current status"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$POSITIVE_STOP_AND_EXPLAIN_OUTPUT" ]; then
  echo "Expected stop and explain prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.interrupt.allowed' 'true'
assert_json_equals "$STATE_FILE" '.interrupt.reason' '"Please stop and explain the current status"'
assert_json_equals "$STATE_FILE" '.interrupt.keywords_detected' 'null'

write_v2_state "$STATE_FILE"

POSITIVE_STOP_AND_TELL_ME_WHY_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"Please stop after this step and tell me why"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$POSITIVE_STOP_AND_TELL_ME_WHY_OUTPUT" ]; then
  echo "Expected stop and tell me why prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.interrupt.allowed' 'true'
assert_json_equals "$STATE_FILE" '.interrupt.reason' '"Please stop after this step and tell me why"'
assert_json_equals "$STATE_FILE" '.interrupt.keywords_detected' 'null'

write_v2_state "$STATE_FILE"

POSITIVE_STOP_IF_NOT_MEANINGFUL_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"Please stop if the results are not meaningful"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$POSITIVE_STOP_IF_NOT_MEANINGFUL_OUTPUT" ]; then
  echo "Expected stop if not meaningful prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.interrupt.allowed' 'true'
assert_json_equals "$STATE_FILE" '.interrupt.reason' '"Please stop if the results are not meaningful"'
assert_json_equals "$STATE_FILE" '.interrupt.keywords_detected' 'null'

write_v2_state "$STATE_FILE"

NEGATIVE_QUOTED_STOP_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"Please explain \\\"stop\\\" semantics"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$NEGATIVE_QUOTED_STOP_OUTPUT" ]; then
  echo "Expected quoted stop explanation prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.interrupt.allowed' 'false'
assert_json_equals "$STATE_FILE" '.interrupt.reason' 'null'
assert_json_equals "$STATE_FILE" '.interrupt.keywords_detected' '[]'

write_v2_state "$STATE_FILE"

MIXED_EXPLAIN_THEN_STOP_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"Please explain \\\"stop\\\" semantics, then stop for now"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$MIXED_EXPLAIN_THEN_STOP_OUTPUT" ]; then
  echo "Expected mixed explain-then-stop prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.interrupt.allowed' 'true'
assert_json_equals "$STATE_FILE" '.interrupt.reason' '"Please explain \"stop\" semantics, then stop for now"'
assert_json_equals "$STATE_FILE" '.interrupt.keywords_detected' 'null'

write_v2_state "$STATE_FILE"

SAME_CLAUSE_EXPLAIN_THEN_STOP_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"Please explain \\\"stop\\\" semantics and then stop for now"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$SAME_CLAUSE_EXPLAIN_THEN_STOP_OUTPUT" ]; then
  echo "Expected same-clause explain-then-stop prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.interrupt.allowed' 'true'
assert_json_equals "$STATE_FILE" '.interrupt.reason' '"Please explain \"stop\" semantics and then stop for now"'
assert_json_equals "$STATE_FILE" '.interrupt.keywords_detected' 'null'

write_v2_state "$STATE_FILE"

MIXED_EXPLAIN_THEN_PAUSE_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"Please explain \\\"stop\\\" semantics, then pause for now"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$MIXED_EXPLAIN_THEN_PAUSE_OUTPUT" ]; then
  echo "Expected mixed explain-then-pause prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.interrupt.allowed' 'true'
assert_json_equals "$STATE_FILE" '.interrupt.reason' '"Please explain \"stop\" semantics, then pause for now"'
assert_json_equals "$STATE_FILE" '.interrupt.keywords_detected' 'null'

write_v2_state "$STATE_FILE"

MIXED_DO_NOT_STOP_THEN_STOP_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"Please do not stop yet, stop after this step"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$MIXED_DO_NOT_STOP_THEN_STOP_OUTPUT" ]; then
  echo "Expected mixed negation-then-stop prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.interrupt.allowed' 'true'
assert_json_equals "$STATE_FILE" '.interrupt.reason' '"Please do not stop yet, stop after this step"'
assert_json_equals "$STATE_FILE" '.interrupt.keywords_detected' 'null'

write_v2_state "$STATE_FILE"

SAME_CLAUSE_DO_NOT_STOP_THEN_STOP_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"Please do not stop yet and then stop after this step"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$SAME_CLAUSE_DO_NOT_STOP_THEN_STOP_OUTPUT" ]; then
  echo "Expected same-clause negation-then-stop prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.interrupt.allowed' 'true'
assert_json_equals "$STATE_FILE" '.interrupt.reason' '"Please do not stop yet and then stop after this step"'
assert_json_equals "$STATE_FILE" '.interrupt.keywords_detected' 'null'

write_v2_state "$STATE_FILE"

NEGATIVE_CHINESE_EXPLAIN_MEANING_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"解释 stop 的含义"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$NEGATIVE_CHINESE_EXPLAIN_MEANING_OUTPUT" ]; then
  echo "Expected Chinese explanation of stop to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.interrupt.allowed' 'false'
assert_json_equals "$STATE_FILE" '.interrupt.reason' 'null'
assert_json_equals "$STATE_FILE" '.interrupt.keywords_detected' '[]'

write_v2_state "$STATE_FILE"

NEGATIVE_CHINESE_STOP_MEANING_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"stop 是什么意思"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$NEGATIVE_CHINESE_STOP_MEANING_OUTPUT" ]; then
  echo "Expected Chinese stop meaning prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.interrupt.allowed' 'false'
assert_json_equals "$STATE_FILE" '.interrupt.reason' 'null'
assert_json_equals "$STATE_FILE" '.interrupt.keywords_detected' '[]'

write_v2_state "$STATE_FILE"

NEGATIVE_SINGLE_QUOTED_STOP_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"Please explain '\''stop'\'' semantics"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$NEGATIVE_SINGLE_QUOTED_STOP_OUTPUT" ]; then
  echo "Expected single-quoted stop explanation prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.interrupt.allowed' 'false'
assert_json_equals "$STATE_FILE" '.interrupt.reason' 'null'
assert_json_equals "$STATE_FILE" '.interrupt.keywords_detected' '[]'

write_v2_state "$STATE_FILE"

NEGATIVE_IF_I_SAY_STOP_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"If I say stop after this step, what happens?"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$NEGATIVE_IF_I_SAY_STOP_OUTPUT" ]; then
  echo "Expected if-I-say-stop discussion prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.interrupt.allowed' 'false'
assert_json_equals "$STATE_FILE" '.interrupt.reason' 'null'
assert_json_equals "$STATE_FILE" '.interrupt.keywords_detected' '[]'

write_v2_state "$STATE_FILE"

NEGATIVE_DO_NOT_STOP_YET_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"Please do not stop yet"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$NEGATIVE_DO_NOT_STOP_YET_OUTPUT" ]; then
  echo "Expected negated stop prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.interrupt.allowed' 'false'
assert_json_equals "$STATE_FILE" '.interrupt.reason' 'null'
assert_json_equals "$STATE_FILE" '.interrupt.keywords_detected' '[]'

write_v2_state "$STATE_FILE"

NEGATIVE_CHINESE_EXPLAIN_STOP_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"不要 stop，我是在解释这个词"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$NEGATIVE_CHINESE_EXPLAIN_STOP_OUTPUT" ]; then
  echo "Expected Chinese explanatory stop prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.interrupt.allowed' 'false'
assert_json_equals "$STATE_FILE" '.interrupt.reason' 'null'
assert_json_equals "$STATE_FILE" '.interrupt.keywords_detected' '[]'

write_v2_state "$STATE_FILE"

NEGATIVE_WHAT_HAPPENS_STOP_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"What happens if I say stop?"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$NEGATIVE_WHAT_HAPPENS_STOP_OUTPUT" ]; then
  echo "Expected stop discussion question prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.interrupt.allowed' 'false'
assert_json_equals "$STATE_FILE" '.interrupt.reason' 'null'
assert_json_equals "$STATE_FILE" '.interrupt.keywords_detected' '[]'

write_v2_state "$STATE_FILE"

NEGATIVE_IF_WRITE_STOP_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"If I write stop here, what happens?"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$NEGATIVE_IF_WRITE_STOP_OUTPUT" ]; then
  echo "Expected conditional stop discussion prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.interrupt.allowed' 'false'
assert_json_equals "$STATE_FILE" '.interrupt.reason' 'null'
assert_json_equals "$STATE_FILE" '.interrupt.keywords_detected' '[]'

write_v2_state "$STATE_FILE"
jq '.workflow.active = true | .workflow.override = "manual_on" | .workflow.activated_by = "manual_prompt"' "$STATE_FILE" > "$STATE_FILE.tmp"
mv "$STATE_FILE.tmp" "$STATE_FILE"

NEGATIVE_MANUAL_CONTROL_SEMANTICS_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"Please disable enforcer stop for now semantics"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$NEGATIVE_MANUAL_CONTROL_SEMANTICS_OUTPUT" ]; then
  echo "Expected manual-control discussion prompt to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.workflow.active' 'true'
assert_json_equals "$STATE_FILE" '.workflow.override' '"manual_on"'
assert_json_equals "$STATE_FILE" '.workflow.activated_by' '"manual_prompt"'
assert_json_equals "$STATE_FILE" '.workflow.deactivated_by' 'null'
assert_json_equals "$STATE_FILE" '.interrupt.allowed' 'false'
assert_json_equals "$STATE_FILE" '.interrupt.reason' 'null'
assert_json_equals "$STATE_FILE" '.interrupt.keywords_detected' '[]'

write_v2_state "$STATE_FILE"
jq '.interrupt.allowed = true | .interrupt.reason = "stale interrupt" | .interrupt.keywords_detected = ["legacy keyword"]' "$STATE_FILE" > "$STATE_FILE.tmp"
mv "$STATE_FILE.tmp" "$STATE_FILE"

ENABLE_CLEARS_STALE_INTERRUPT_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"enable enforcer"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$ENABLE_CLEARS_STALE_INTERRUPT_OUTPUT" ]; then
  echo "Expected enable enforcer to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.workflow.override' '"manual_on"'
assert_json_equals "$STATE_FILE" '.workflow.activated_by' '"manual_prompt"'
assert_json_equals "$STATE_FILE" '.interrupt.allowed' 'false'
assert_json_equals "$STATE_FILE" '.interrupt.reason' 'null'
assert_json_equals "$STATE_FILE" '.interrupt.keywords_detected' '[]'

write_v2_state "$STATE_FILE"
jq '.interrupt.allowed = true | .interrupt.reason = "stale interrupt" | .interrupt.keywords_detected = ["legacy keyword"]' "$STATE_FILE" > "$STATE_FILE.tmp"
mv "$STATE_FILE.tmp" "$STATE_FILE"

DISABLE_CLEARS_STALE_INTERRUPT_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"disable enforcer and stop for now"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$DISABLE_CLEARS_STALE_INTERRUPT_OUTPUT" ]; then
  echo "Expected disable enforcer and stop for now to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.workflow.override' '"manual_off"'
assert_json_equals "$STATE_FILE" '.workflow.deactivated_by' '"manual_prompt"'
assert_json_equals "$STATE_FILE" '.interrupt.allowed' 'false'
assert_json_equals "$STATE_FILE" '.interrupt.reason' 'null'
assert_json_equals "$STATE_FILE" '.interrupt.keywords_detected' '[]'

write_v2_state "$STATE_FILE"
STATE_SNAPSHOT_BEFORE_MALFORMED_PROMPT="$(jq -c . "$STATE_FILE")"

MISSING_PROMPT_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$MISSING_PROMPT_OUTPUT" ]; then
  echo "Expected missing prompt to be silent allow" >&2
  exit 1
fi
STATE_SNAPSHOT_AFTER_MISSING_PROMPT="$(jq -c . "$STATE_FILE")"
if [ "$STATE_SNAPSHOT_AFTER_MISSING_PROMPT" != "$STATE_SNAPSHOT_BEFORE_MALFORMED_PROMPT" ]; then
  echo "Expected missing prompt to keep state unchanged" >&2
  exit 1
fi

NON_STRING_PROMPT_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":{"raw":"激活 superpowers enforcer"}}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$NON_STRING_PROMPT_OUTPUT" ]; then
  echo "Expected non-string prompt to be silent allow" >&2
  exit 1
fi
STATE_SNAPSHOT_AFTER_NON_STRING_PROMPT="$(jq -c . "$STATE_FILE")"
if [ "$STATE_SNAPSHOT_AFTER_NON_STRING_PROMPT" != "$STATE_SNAPSHOT_BEFORE_MALFORMED_PROMPT" ]; then
  echo "Expected non-string prompt to keep state unchanged" >&2
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
