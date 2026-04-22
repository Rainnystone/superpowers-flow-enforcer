#!/bin/bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/.." && pwd)"

source "$REPO_ROOT/scripts/lib/workflow_paths.sh"
source "$REPO_ROOT/tests/helpers/state-fixtures.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

write_active_state() {
  local state_file="$1"

  write_v2_state "$state_file"
  jq '
    .workflow.active = true
    | .workflow.activated_by = "spec_write"
    | .workflow.activated_at = "2026-04-22T00:00:00Z"
  ' "$state_file" > "$state_file.tmp"
  mv "$state_file.tmp" "$state_file"
}

PROJECT_DIR="$TMP_DIR/project"
mkdir -p "$PROJECT_DIR/.claude" "$PROJECT_DIR/nested/deep"
: > "$PROJECT_DIR/.claude/flow_state.json"

EXPECTED_ROOT="$(cd "$PROJECT_DIR" && pwd -P)"
RESOLVED_ROOT="$(workflow_paths_resolve_state_root_from_candidate "$PROJECT_DIR/nested/deep/file.txt")"
[ "$RESOLVED_ROOT" = "$EXPECTED_ROOT" ] || {
  echo "Expected helper to resolve nested path back to $EXPECTED_ROOT, got $RESOLVED_ROOT" >&2
  exit 1
}

if workflow_paths__next_parent "/" >/dev/null 2>&1; then
  echo "Expected workflow_paths__next_parent to fail at POSIX root" >&2
  exit 1
fi

if (
  source "$REPO_ROOT/scripts/lib/workflow_paths.sh"
  dirname() { printf 'C:/\n'; }
  workflow_paths__next_parent 'C:/' >/dev/null 2>&1
); then
  echo "Expected workflow_paths__next_parent to fail when dirname stagnates at a Windows drive root" >&2
  exit 1
fi

STALE_ENV_DIR="$TMP_DIR/stale-env"
PAYLOAD_PROJECT="$TMP_DIR/payload-project"
mkdir -p "$STALE_ENV_DIR" "$PAYLOAD_PROJECT/.claude"
write_active_state "$PAYLOAD_PROJECT/.claude/flow_state.json"

BASH_GATE_OUTPUT="$(
  jq -n --arg cwd "$PAYLOAD_PROJECT" --arg command 'cat .claude/flow_state.json' '{
    hook_event_name:"PreToolUse",
    tool_name:"Bash",
    cwd:$cwd,
    tool_input:{command:$command}
  }' | CLAUDE_PROJECT_DIR="$STALE_ENV_DIR" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$REPO_ROOT/scripts/check-bash-command-gate.sh"
)"

[ -n "$BASH_GATE_OUTPUT" ] || {
  echo "Expected Bash gate to fall back from stale CLAUDE_PROJECT_DIR to payload cwd state root" >&2
  exit 1
}

printf '%s' "$BASH_GATE_OUTPUT" | jq -e '
  .hookSpecificOutput.permissionDecision == "deny"
  and (.hookSpecificOutput.permissionDecisionReason | contains(".claude/flow_state.json"))
' >/dev/null 2>&1 || {
  echo "Expected Bash gate fallback denial for payload cwd state root, got: $BASH_GATE_OUTPUT" >&2
  exit 1
}

SYNC_PROJECT="$TMP_DIR/sync-project"
mkdir -p "$SYNC_PROJECT/.claude"
write_active_state "$SYNC_PROJECT/.claude/flow_state.json"

jq -n --arg cwd "$SYNC_PROJECT" --arg prompt 'skip planning' '{
  cwd:$cwd,
  prompt:$prompt
}' | CLAUDE_PROJECT_DIR="$STALE_ENV_DIR" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$REPO_ROOT/scripts/sync-user-prompt-state.sh" >/dev/null

jq -e '
  .exceptions.skip_planning == true
  and .exceptions.pending_confirmation_for == "planning"
  and .workflow.activated_by == "user_prompt_skip"
' "$SYNC_PROJECT/.claude/flow_state.json" >/dev/null 2>&1 || {
  echo "Expected sync-user-prompt-state to fall back from stale CLAUDE_PROJECT_DIR to payload cwd state root" >&2
  exit 1
}

if ! rg -n 'source .*platform_compat\.sh|\. .*platform_compat\.sh' \
  "$REPO_ROOT/scripts/lib/workflow_paths.sh" >/dev/null; then
  echo "Expected workflow_paths.sh to source platform_compat.sh for shared Python resolution" >&2
  exit 1
fi

if ! rg -n 'platform_compat_run_python' \
  "$REPO_ROOT/scripts/lib/workflow_paths.sh" >/dev/null; then
  echo "Expected workflow_paths.sh to use platform_compat_run_python for path normalization" >&2
  exit 1
fi

if rg -n '\bpython3\b' "$REPO_ROOT/scripts/lib/workflow_paths.sh" >/dev/null; then
  echo "Expected workflow_paths.sh to stop hard-coding python3" >&2
  exit 1
fi

if ! rg -n 'source .*workflow_paths\.sh|\. .*workflow_paths\.sh' \
  "$REPO_ROOT/scripts/check-bash-command-gate.sh" \
  "$REPO_ROOT/scripts/sync-user-prompt-state.sh" \
  "$REPO_ROOT/scripts/check-stop-review-gate.sh" \
  "$REPO_ROOT/scripts/check-task-completed.sh" >/dev/null; then
  echo "Expected owned runtime scripts to route traversal through workflow_paths.sh" >&2
  exit 1
fi

if ! rg -n 'workflow_paths_resolve_state_root_from_candidate' \
  "$REPO_ROOT/scripts/check-bash-command-gate.sh" \
  "$REPO_ROOT/scripts/sync-user-prompt-state.sh" \
  "$REPO_ROOT/scripts/check-stop-review-gate.sh" \
  "$REPO_ROOT/scripts/check-task-completed.sh" >/dev/null; then
  echo "Expected owned runtime scripts to call workflow_paths_resolve_state_root_from_candidate directly" >&2
  exit 1
fi

if rg -n '^resolve_state_root_from_candidate\(\)' \
  "$REPO_ROOT/scripts/check-bash-command-gate.sh" \
  "$REPO_ROOT/scripts/sync-user-prompt-state.sh" \
  "$REPO_ROOT/scripts/check-stop-review-gate.sh" \
  "$REPO_ROOT/scripts/check-task-completed.sh" >/dev/null; then
  echo "Expected owned runtime scripts to drop local resolve_state_root_from_candidate wrappers" >&2
  exit 1
fi
