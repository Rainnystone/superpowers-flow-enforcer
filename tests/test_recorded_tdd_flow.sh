#!/bin/bash
set -euo pipefail

source tests/helpers/assert.sh
source tests/helpers/state-fixtures.sh

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export CLAUDE_PROJECT_DIR="$TMP_DIR/project"
export CLAUDE_PLUGIN_ROOT="$(pwd)"

mkdir -p "$CLAUDE_PROJECT_DIR/.claude"
STATE_FILE="$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
write_v2_state "$STATE_FILE"

assert_json_equals "$STATE_FILE" '.tdd.pending_failure_record' 'false'
assert_json_equals "$STATE_FILE" '.tdd.last_failed_command' 'null'
assert_json_equals "$STATE_FILE" '.tdd.tests_verified_fail' '[]'

jq '.tdd.pending_failure_record = true | .tdd.last_failed_command = "pnpm -r test"' \
  "$STATE_FILE" > "$STATE_FILE.tmp"
mv "$STATE_FILE.tmp" "$STATE_FILE"

bash scripts/record-tdd-state.sh fail tests/unit/example.test.ts

assert_json_equals "$STATE_FILE" '.tdd.pending_failure_record' 'false'
assert_json_equals "$STATE_FILE" '.tdd.last_failed_command' 'null'
assert_json_equals "$STATE_FILE" '.tdd.tests_verified_fail | index("tests/unit/example.test.ts") != null' 'true'
assert_json_equals "$STATE_FILE" '.tdd.tests_verified_fail' '["tests/unit/example.test.ts"]'

bash scripts/record-tdd-state.sh fail tests/unit/other.test.ts

assert_json_equals "$STATE_FILE" '.tdd.tests_verified_fail | index("tests/unit/other.test.ts") != null' 'true'
assert_json_equals "$STATE_FILE" '.tdd.tests_verified_fail' '["tests/unit/example.test.ts","tests/unit/other.test.ts"]'

jq '.tdd.tests_verified_fail = ["zeta","alpha"]' "$STATE_FILE" > "$STATE_FILE.tmp"
mv "$STATE_FILE.tmp" "$STATE_FILE"

bash scripts/record-tdd-state.sh fail beta

assert_json_equals "$STATE_FILE" '.tdd.tests_verified_fail' '["zeta","alpha","beta"]'

bash scripts/record-tdd-state.sh fail tests/unit/example.test.ts

assert_json_equals "$STATE_FILE" '[.tdd.tests_verified_fail[] | select(. == "tests/unit/example.test.ts")] | length' '1'

cp "$STATE_FILE" "$STATE_FILE.before-invalid-empty"
if bash scripts/record-tdd-state.sh fail "" >/dev/null 2>&1; then
  echo 'Expected record-tdd-state.sh fail to reject an empty target' >&2
  exit 1
fi
if ! cmp -s "$STATE_FILE.before-invalid-empty" "$STATE_FILE"; then
  echo 'Expected flow state to stay unchanged after invalid empty-target input' >&2
  exit 1
fi

cp "$STATE_FILE" "$STATE_FILE.before-invalid-action"
if bash scripts/record-tdd-state.sh pass tests/unit/example.test.ts >/dev/null 2>&1; then
  echo 'Expected record-tdd-state.sh to reject unsupported actions' >&2
  exit 1
fi
if ! cmp -s "$STATE_FILE.before-invalid-action" "$STATE_FILE"; then
  echo 'Expected flow state to stay unchanged after unsupported-action input' >&2
  exit 1
fi
