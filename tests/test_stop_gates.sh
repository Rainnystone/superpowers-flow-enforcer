#!/bin/bash
set -euo pipefail

source tests/helpers/assert.sh
source tests/helpers/state-fixtures.sh

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export CLAUDE_PLUGIN_ROOT="$(pwd)"

assert_stop_block() {
  local output="$1"
  local reason_fragment="$2"

  [ -n "$output" ] || {
    echo "Expected Stop gate to block, got empty output" >&2
    exit 1
  }

  assert_json_equals <(printf '%s' "$output") '.decision' '"block"'
  assert_json_equals <(printf '%s' "$output") '. | keys | sort' '["decision","reason"]'
  jq -e --arg frag "$reason_fragment" '.reason | contains($frag)' <(printf '%s' "$output") >/dev/null 2>&1 || {
    echo "Expected Stop block reason to contain: $reason_fragment" >&2
    exit 1
  }
}

assert_stop_allow_silent() {
  local output="$1"
  [ -z "$output" ] || {
    echo "Expected Stop gate allow path to be silent, got: $output" >&2
    exit 1
  }
}

run_stop_gate() {
  local cwd="$1"
  local stop_hook_active="${2:-false}"
  local last_assistant_message="${3:-}"
  jq -n --arg cwd "$cwd" --argjson stop_hook_active "$stop_hook_active" --arg last_assistant_message "$last_assistant_message" '{
    hook_event_name:"Stop",
    cwd:$cwd,
    stop_hook_active:$stop_hook_active,
    last_assistant_message:$last_assistant_message
  }' | bash scripts/check-stop-review-gate.sh
}

PRIMARY_PROJECT="$TMP_DIR/project"
mkdir -p "$PRIMARY_PROJECT/.claude"
STATE_FILE="$PRIMARY_PROJECT/.claude/flow_state.json"

FALLBACK_PROJECT="$TMP_DIR/fallback-project"
mkdir -p "$FALLBACK_PROJECT/.claude"
write_v2_state "$FALLBACK_PROJECT/.claude/flow_state.json"
jq '
  .workflow.active = true
  | .review.tasks = {
      "task-001": {
        "spec_review_passed": true,
        "code_review_passed": true
      }
    }
  | .finishing.invoked = true
' "$FALLBACK_PROJECT/.claude/flow_state.json" > "$TMP_DIR/fallback-state.json"
mv "$TMP_DIR/fallback-state.json" "$FALLBACK_PROJECT/.claude/flow_state.json"

export CLAUDE_PROJECT_DIR="$PRIMARY_PROJECT"
write_v2_state "$STATE_FILE"
jq '.workflow.active = true' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"

deny_output="$(run_stop_gate "$FALLBACK_PROJECT")"
assert_stop_block "$deny_output" 'review'

write_v2_state "$STATE_FILE"
jq '
  .workflow.active = true
' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"

allow_output="$(run_stop_gate "$PRIMARY_PROJECT" true)"
assert_stop_allow_silent "$allow_output"

write_v2_state "$STATE_FILE"
jq '
  .workflow.active = true
  | .interrupt.allowed = true
' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"

allow_output="$(run_stop_gate "$PRIMARY_PROJECT")"
assert_stop_allow_silent "$allow_output"

write_v2_state "$STATE_FILE"
allow_output="$(run_stop_gate "$PRIMARY_PROJECT")"
assert_stop_allow_silent "$allow_output"

write_v2_state "$STATE_FILE"
jq '
  .workflow.active = true
  | .exceptions.skip_review = true
  | .exceptions.user_confirmed = true
' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"

allow_output="$(run_stop_gate "$PRIMARY_PROJECT")"
assert_stop_allow_silent "$allow_output"

deny_output="$(run_stop_gate "$PRIMARY_PROJECT" false 'Done. I fixed it and everything is working now.')"
assert_stop_block "$deny_output" 'verification'

write_v2_state "$STATE_FILE"
jq '
  .workflow.active = true
  | .review.tasks = {
      "task-001": {
        "spec_review_passed": true,
        "code_review_passed": true
      }
    }
  | .exceptions.skip_finishing = true
  | .exceptions.user_confirmed = true
' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"

allow_output="$(run_stop_gate "$PRIMARY_PROJECT")"
assert_stop_allow_silent "$allow_output"

deny_output="$(run_stop_gate "$PRIMARY_PROJECT" false 'Done. I fixed it and everything is working now.')"
assert_stop_block "$deny_output" 'verification'

write_v2_state "$STATE_FILE"
jq '.workflow.active = true' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"

deny_output="$(run_stop_gate "$PRIMARY_PROJECT")"
assert_stop_block "$deny_output" 'review'

export CLAUDE_PROJECT_DIR="$TMP_DIR/missing-project-root"
deny_output="$(run_stop_gate "$PRIMARY_PROJECT")"
assert_stop_block "$deny_output" 'review'

export CLAUDE_PROJECT_DIR="$PRIMARY_PROJECT"
write_v2_state "$STATE_FILE"
jq '
  .workflow.active = true
  | .review.tasks = {
      "task-001": {
        "spec_review_passed": true,
        "code_review_passed": true
      }
    }
' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"

deny_output="$(run_stop_gate "$PRIMARY_PROJECT")"
assert_stop_block "$deny_output" 'finishing'

write_v2_state "$STATE_FILE"
jq '
  .workflow.active = true
  | .review.tasks = {
      "task-001": {
        "spec_review_passed": true,
        "code_review_passed": true
      }
    }
  | .finishing.invoked = true
' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"

deny_output="$(run_stop_gate "$PRIMARY_PROJECT" false 'Done. I fixed it and everything is working now.')"
assert_stop_block "$deny_output" 'verification'

allow_output="$(run_stop_gate "$PRIMARY_PROJECT" false $'Done.\nVerification:\nbash tests/test_stop_gates.sh\nPASS')"
assert_stop_allow_silent "$allow_output"

allow_output="$(run_stop_gate "$PRIMARY_PROJECT" false 'I am still working on the stop gate.')"
assert_stop_allow_silent "$allow_output"

allow_output="$(run_stop_gate "$PRIMARY_PROJECT" false 'Done. 12 passed, 0 failed.')"
assert_stop_allow_silent "$allow_output"

allow_output="$(run_stop_gate "$PRIMARY_PROJECT" false 'This is a fixed-width parser issue.')"
assert_stop_allow_silent "$allow_output"

allow_output="$(run_stop_gate "$PRIMARY_PROJECT" false 'The hostname resolved after retry.')"
assert_stop_allow_silent "$allow_output"

write_v2_state "$STATE_FILE"
jq '
  .workflow.active = true
  | .review.tasks = {
      "task-001": {
        "spec_review_passed": true,
        "code_review_passed": false
      }
    }
' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"

allow_output="$(run_stop_gate "$PRIMARY_PROJECT")"
assert_stop_allow_silent "$allow_output"

printf '{"state_version":2,' > "$STATE_FILE"
allow_output="$(run_stop_gate "$PRIMARY_PROJECT")"
assert_stop_allow_silent "$allow_output"

rm -f "$STATE_FILE"
allow_output="$(run_stop_gate "$PRIMARY_PROJECT")"
assert_stop_allow_silent "$allow_output"
