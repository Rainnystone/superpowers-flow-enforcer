#!/bin/bash
set -euo pipefail

source tests/helpers/assert.sh
source tests/helpers/state-fixtures.sh

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export CLAUDE_PROJECT_DIR="$TMP_DIR/project"
export CLAUDE_PLUGIN_ROOT="$(pwd)"

mkdir -p "$CLAUDE_PROJECT_DIR/.claude"

assert_file_contains hooks/hooks.json 'PostToolUseFailure'

HOOK_COMMAND="$(
  jq -r '
    .hooks.PostToolUseFailure[]
    | select(.matcher == "Bash")
    | .hooks[]
    | select(.type == "command")
    | .command
  ' hooks/hooks.json
)"

case "$HOOK_COMMAND" in
  *"HOOK_EVENT=PostToolUseFailure"*) : ;;
  *)
    echo 'Expected PostToolUseFailure Bash hook to invoke sync-post-tool-state.sh with HOOK_EVENT=PostToolUseFailure' >&2
    exit 1
    ;;
esac

STATE_FILE="$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
OUTPUT_FILE="$TMP_DIR/output.json"

reset_state() {
  local active="${1:-false}"

  write_v2_state "$STATE_FILE"
  jq '
    .debugging = {
      active: false,
      phase: null,
      fixes_attempted: 0,
      root_cause_found: false
    }
  ' "$STATE_FILE" > "$STATE_FILE.tmp"
  mv "$STATE_FILE.tmp" "$STATE_FILE"

  if [ "$active" = "true" ]; then
    jq '.debugging.active = true' "$STATE_FILE" > "$STATE_FILE.tmp"
    mv "$STATE_FILE.tmp" "$STATE_FILE"
  fi
}

run_sync() {
  local command="$1"
  local result="$2"
  local active="${3:-false}"

  reset_state "$active"

  jq -n --arg command "$command" --arg result "$result" \
    '{tool_name:"Bash", tool_input:{command:$command}, tool_result:$result}' \
    | HOOK_EVENT=PostToolUseFailure bash scripts/sync-post-tool-state.sh >"$OUTPUT_FILE"
}

run_sync_with_cwd() {
  local cwd="$1"
  local command="$2"
  local result="$3"
  local active="${4:-false}"

  reset_state "$active"

  jq -n --arg cwd "$cwd" --arg command "$command" --arg result "$result" \
    '{cwd:$cwd, tool_name:"Bash", tool_input:{command:$command}, tool_result:$result}' \
    | HOOK_EVENT=PostToolUseFailure bash scripts/sync-post-tool-state.sh >"$OUTPUT_FILE"
}

assert_debugging_blocked() {
  assert_json_equals "$OUTPUT_FILE" '.continue' 'false'
  assert_json_equals "$OUTPUT_FILE" '.systemMessage' '"检测到测试失败，请先执行 systematic-debugging 再改代码。"'
  assert_json_equals "$STATE_FILE" '.current_phase' '"debugging"'
  assert_json_equals "$STATE_FILE" '.debugging.active' 'true'
}

assert_auto_recorded_failure() {
  local expected_target="$1"

  assert_debugging_blocked
  assert_json_equals "$STATE_FILE" '.tdd.pending_failure_record' 'false'
  assert_json_equals "$STATE_FILE" '.tdd.last_failed_command' 'null'
  assert_json_equals "$STATE_FILE" ".tdd.tests_verified_fail == [\"$expected_target\"]" 'true'
}

assert_pending_failure_record() {
  local expected_command="$1"

  assert_debugging_blocked
  assert_json_equals "$STATE_FILE" '.tdd.pending_failure_record' 'true'
  assert_json_equals "$STATE_FILE" ".tdd.last_failed_command" "$(printf '%s' "$expected_command" | jq -R .)"
  assert_json_equals "$STATE_FILE" '.tdd.tests_verified_fail' '[]'
}

run_sync 'vitest src/foo.test.ts' 'exited 1'
assert_auto_recorded_failure 'src/foo.test.ts'

unset CLAUDE_PROJECT_DIR
mkdir -p "$TMP_DIR/cwd-project/.claude"
mkdir -p "$TMP_DIR/cwd-project/nested/child"
CWD_STATE_FILE="$TMP_DIR/cwd-project/.claude/flow_state.json"
STATE_FILE="$CWD_STATE_FILE"
run_sync_with_cwd "$TMP_DIR/cwd-project/nested/child" 'vitest src/cwd-fallback.test.ts' 'exited 1'
assert_auto_recorded_failure 'src/cwd-fallback.test.ts'
STATE_FILE="$TMP_DIR/project/.claude/flow_state.json"
export CLAUDE_PROJECT_DIR="$TMP_DIR/project"

run_sync 'pytest tests/test_post_tool_use_failure.sh' 'exited 1'
assert_auto_recorded_failure 'tests/test_post_tool_use_failure.sh'

run_sync 'python -m pytest tests/test_post_tool_use_failure.sh' 'exited 1'
assert_auto_recorded_failure 'tests/test_post_tool_use_failure.sh'

run_sync 'pnpm exec vitest src/foo.test.ts' 'exited 1'
assert_auto_recorded_failure 'src/foo.test.ts'

run_sync 'bash tests/test_post_tool_use_failure.sh' 'exited 1'
assert_pending_failure_record 'bash tests/test_post_tool_use_failure.sh'

run_sync 'bash -lc "cd web && pnpm test"' 'exited 1'
assert_pending_failure_record 'bash -lc "cd web && pnpm test"'

run_sync 'bash -lc "cd web && vitest src/foo.test.ts"' 'exited 1'
assert_pending_failure_record 'bash -lc "cd web && vitest src/foo.test.ts"'

run_sync 'pnpm -r test' 'exited 1'
assert_pending_failure_record 'pnpm -r test'

run_sync 'pnpm --workspace foo test' 'exited 1'
assert_pending_failure_record 'pnpm --workspace foo test'

run_sync 'pnpm -F foo test' 'exited 1'
assert_pending_failure_record 'pnpm -F foo test'

run_sync 'pnpm --project foo test' 'exited 1'
assert_pending_failure_record 'pnpm --project foo test'

run_sync 'pnpm --scope foo test' 'exited 1'
assert_pending_failure_record 'pnpm --scope foo test'

run_sync 'bash -lc "pnpm --workspace foo test"' 'exited 1'
assert_pending_failure_record 'bash -lc "pnpm --workspace foo test"'

run_sync 'cargo test' 'exited 1'
assert_pending_failure_record 'cargo test'

run_sync 'go test ./...' 'exited 1'
assert_pending_failure_record 'go test ./...'

run_sync 'npm test' 'exited 1'
assert_pending_failure_record 'npm test'

run_sync 'yarn workspace @acme/web test' 'exited 1'
assert_pending_failure_record 'yarn workspace @acme/web test'

run_sync 'npm --workspace web run vitest src/foo.test.ts' 'exited 1'
assert_pending_failure_record 'npm --workspace web run vitest src/foo.test.ts'

run_sync 'yarn workspace @acme/web vitest src/foo.test.ts' 'exited 1'
assert_pending_failure_record 'yarn workspace @acme/web vitest src/foo.test.ts'

run_sync 'pnpm --filter @acme/web run vitest src/foo.test.ts' 'exited 1'
assert_pending_failure_record 'pnpm --filter @acme/web run vitest src/foo.test.ts'

run_sync 'npm install' 'exited 1'
assert_json_equals "$OUTPUT_FILE" '.continue' 'true'
assert_json_equals "$STATE_FILE" '.debugging.active' 'false'
assert_json_equals "$STATE_FILE" '.tdd.pending_failure_record' 'false'
assert_json_equals "$STATE_FILE" '.tdd.last_failed_command' 'null'

run_sync 'rg pytest missing-file' 'exited 1'
assert_json_equals "$OUTPUT_FILE" '.continue' 'true'
assert_json_equals "$STATE_FILE" '.debugging.active' 'false'
assert_json_equals "$STATE_FILE" '.tdd.pending_failure_record' 'false'
assert_json_equals "$STATE_FILE" '.tdd.last_failed_command' 'null'

run_sync 'vitest src/foo.test.ts' 'exited 1' true
assert_json_equals "$OUTPUT_FILE" '.continue' 'true'
assert_json_equals "$STATE_FILE" '.debugging.active' 'true'
assert_json_equals "$STATE_FILE" '.tdd.tests_verified_fail == ["src/foo.test.ts"]' 'true'
assert_json_equals "$STATE_FILE" '.tdd.pending_failure_record' 'false'
assert_json_equals "$STATE_FILE" '.tdd.last_failed_command' 'null'
