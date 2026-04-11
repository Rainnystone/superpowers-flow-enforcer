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

bash scripts/record-spec-state.sh self-review pass
bash scripts/record-spec-state.sh user-approval pass
bash scripts/record-review-state.sh task-001 spec pass
bash scripts/record-review-state.sh task-001 code pass
bash scripts/record-finishing-state.sh invoked

if bash scripts/record-review-state.sh "" spec pass >/dev/null 2>&1; then
  echo 'Expected record-review-state.sh to reject an empty task-id' >&2
  exit 1
fi

assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.brainstorming.spec_reviewed' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.brainstorming.user_approved_spec' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.review.tasks["task-001"].spec_review_passed' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.review.tasks["task-001"].code_review_passed' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.finishing.invoked' 'true'

if jq -e '.review.tasks | has("")' "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" >/dev/null 2>&1; then
  echo 'Expected flow_state.json not to contain an empty review task key' >&2
  exit 1
fi
