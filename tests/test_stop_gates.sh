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
  jq -n --arg cwd "$cwd" --argjson stop_hook_active "$stop_hook_active" '{
    hook_event_name:"Stop",
    cwd:$cwd,
    stop_hook_active:$stop_hook_active
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

unset CLAUDE_PROJECT_DIR

python3 - <<'PY'
import json
import sys
from pathlib import Path

hooks = json.loads(Path('hooks/hooks.json').read_text(encoding='utf-8'))['hooks']
stop_prompt = None
for group in hooks.get('Stop', []):
    for hook in group.get('hooks', []):
        if hook.get('type') == 'prompt':
            stop_prompt = hook.get('prompt', '')
            break
    if stop_prompt is not None:
        break

if stop_prompt is None:
    sys.stderr.write('Expected Stop prompt hook to exist\n')
    raise SystemExit(1)

required_tokens = [
    '$ARGUMENTS',
    'Only use input values from $ARGUMENTS',
    'Do not assume any file access.',
    'last_assistant_message',
    'stop_hook_active',
    'completion keywords appear',
    'fresh passing verification evidence',
    'without fresh passing verification evidence in last_assistant_message',
    'If completion keywords do not appear, return {"ok": true}.',
    'If completion keywords appear and fresh passing verification evidence appears in last_assistant_message, return {"ok": true}.',
]

for token in required_tokens:
    if token not in stop_prompt:
        sys.stderr.write(f'Missing Stop prompt hook token: {token}\n')
        raise SystemExit(1)

if 'transcript' in stop_prompt.lower():
    sys.stderr.write('Expected Stop prompt hook to remain input-only and avoid transcript references\n')
    raise SystemExit(1)

forbidden_tokens = [
    'read the referenced state file',
    'derive the state path',
    'read the referenced transcript file',
    'derive the transcript path',
    'read cwd',
    'read file',
]

for token in forbidden_tokens:
    if token in stop_prompt:
        sys.stderr.write(f'Expected Stop prompt hook to avoid file/cwd access hint: {token}\n')
        raise SystemExit(1)
PY
