#!/bin/bash
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo '{"continue":true,"systemMessage":"jq missing, skip post tool state sync"}'
  exit 0
fi

if [ -z "${CLAUDE_PROJECT_DIR:-}" ]; then
  echo '{"continue":true}'
  exit 0
fi

STATE_FILE="$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
if [ ! -f "$STATE_FILE" ]; then
  echo '{"continue":true}'
  exit 0
fi

INPUT="$(cat)"
TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // ""')"
NOW_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
tmp_file="${STATE_FILE}.tmp"

update_state() {
  local expr="$1"
  jq "$expr" "$STATE_FILE" > "$tmp_file"
  mv "$tmp_file" "$STATE_FILE"
}

append_unique_string_to_array() {
  local jq_path="$1"
  local value="$2"
  jq --arg path "$jq_path" --arg value "$value" '
    def setpathstr($path; $v):
      if $path == "tdd.test_files_created" then .tdd.test_files_created = ((.tdd.test_files_created // []) + [$v] | unique)
      elif $path == "tdd.production_files_written" then .tdd.production_files_written = ((.tdd.production_files_written // []) + [$v] | unique)
      elif $path == "tdd.tests_verified_fail" then .tdd.tests_verified_fail = ((.tdd.tests_verified_fail // []) + [$v] | unique)
      elif $path == "tdd.tests_verified_pass" then .tdd.tests_verified_pass = ((.tdd.tests_verified_pass // []) + [$v] | unique)
      else .
      end;
    setpathstr($path; $value)
  ' "$STATE_FILE" > "$tmp_file"
  mv "$tmp_file" "$STATE_FILE"
}

if [ "$TOOL_NAME" = "AskUserQuestion" ]; then
  update_state '.brainstorming.questions_asked = ((.brainstorming.questions_asked // 0) + 1) | .brainstorming.findings_updated = false'
fi

if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ]; then
  FILE_PATH="$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')"
  if [ -n "$FILE_PATH" ]; then
    if [ "$(basename "$FILE_PATH")" = "findings.md" ]; then
      jq --arg now "$NOW_UTC" '.brainstorming.findings_updated = true | .brainstorming.findings_last_update = $now' "$STATE_FILE" > "$tmp_file"
      mv "$tmp_file" "$STATE_FILE"
    fi

    if echo "$FILE_PATH" | grep -qE '^docs/superpowers/specs/.*\.md$'; then
      jq --arg path "$FILE_PATH" '.brainstorming.spec_written = true | .brainstorming.spec_file = $path' "$STATE_FILE" > "$tmp_file"
      mv "$tmp_file" "$STATE_FILE"
    fi

    if echo "$FILE_PATH" | grep -qE '^docs/superpowers/plans/.*\.md$'; then
      jq --arg path "$FILE_PATH" '.planning.plan_written = true | .planning.plan_file = $path' "$STATE_FILE" > "$tmp_file"
      mv "$tmp_file" "$STATE_FILE"
    fi

    if echo "$FILE_PATH" | grep -qE '(^|/)(test|tests|spec|__tests__)/|\.test\.|\.spec\.|_test\.|_spec\.'; then
      append_unique_string_to_array "tdd.test_files_created" "$FILE_PATH"
    else
      append_unique_string_to_array "tdd.production_files_written" "$FILE_PATH"
    fi
  fi
fi

if [ "$TOOL_NAME" = "Bash" ]; then
  COMMAND="$(echo "$INPUT" | jq -r '.tool_input.command // ""')"
  RESULT_TEXT="$(echo "$INPUT" | jq -r '.tool_result | if . == null then "" elif type == "string" then . else tostring end')"

  if echo "$COMMAND" | grep -q 'git worktree add'; then
    WORKTREE_PATH="$(echo "$COMMAND" | awk '{for(i=1;i<=NF;i++){if($i=="add" && (i+1)<=NF){print $(i+1); exit}}}')"
    if [ -z "$WORKTREE_PATH" ]; then
      WORKTREE_PATH="unknown"
    fi
    jq --arg path "$WORKTREE_PATH" '.worktree.created = true | .worktree.path = $path' "$STATE_FILE" > "$tmp_file"
    mv "$tmp_file" "$STATE_FILE"
  fi

  if echo "$COMMAND" | grep -qiE '(^| )(npm|pnpm|yarn|bun|pytest|cargo test|go test|vitest|jest)( |$)'; then
    if echo "$RESULT_TEXT" | grep -qiE 'pass|passed|ok'; then
      update_state '.worktree.baseline_tests_passed = true'
    fi

    if echo "$RESULT_TEXT" | grep -qiE 'fail|failed|error|assertion'; then
      update_state '.debugging.active = true'
    fi

    TEST_PATH="$(echo "$COMMAND" | grep -oE '([^[:space:]]+\.(test|spec)\.[[:alnum:]_]+)' | head -n 1 || true)"
    if [ -n "$TEST_PATH" ]; then
      if echo "$RESULT_TEXT" | grep -qiE 'fail|failed|error|assertion'; then
        append_unique_string_to_array "tdd.tests_verified_fail" "$TEST_PATH"
      elif echo "$RESULT_TEXT" | grep -qiE 'pass|passed|ok'; then
        append_unique_string_to_array "tdd.tests_verified_pass" "$TEST_PATH"
      fi
    fi
  fi
fi

echo '{"continue":true}'
