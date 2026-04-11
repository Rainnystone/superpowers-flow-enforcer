#!/bin/bash
set -euo pipefail

HOOK_INPUT="$(cat)"
TEMPLATE="${CLAUDE_PLUGIN_ROOT}/templates/flow_state.json.tmpl"
MIGRATE_SCRIPT="${CLAUDE_PLUGIN_ROOT}/scripts/migrate-state.sh"

resolve_project_dir() {
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    printf '%s\n' "$CLAUDE_PROJECT_DIR"
    return
  fi

  if [ -n "$HOOK_INPUT" ]; then
    local hook_cwd
    hook_cwd="$(printf '%s' "$HOOK_INPUT" | jq -r '
      if .hook_event_name == "SessionStart" and (.cwd | type) == "string" and .cwd != "" then
        .cwd
      else
        empty
      end
    ' 2>/dev/null || true)"

    if [ -n "$hook_cwd" ]; then
      printf '%s\n' "$hook_cwd"
      return
    fi
  fi

  printf '%s\n' "$PWD"
}

PROJECT_DIR="$(resolve_project_dir)"
STATE_FILE="$PROJECT_DIR/.claude/flow_state.json"

initialize_state() {
  mkdir -p "$PROJECT_DIR/.claude"

  SESSION_ID=$(date +%s | shasum -a 256 | head -c 16)
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  jq --arg session "$SESSION_ID" \
     --arg project "$PROJECT_DIR" \
     --arg timestamp "$TIMESTAMP" \
     '.session_id = $session | .project_dir = $project | .initialized_at = $timestamp' \
     "$TEMPLATE" > "$STATE_FILE"
}

normalize_workflow_state() {
  jq '
    if (.workflow | type) == "object" then
      .workflow.active = (.workflow.active // false)
      | .workflow.activated_by = (.workflow.activated_by // null)
      | .workflow.activated_at = (.workflow.activated_at // null)
    else
      .workflow = {
        "active": false,
        "activated_by": null,
        "activated_at": null
      }
    end
  ' "$STATE_FILE" > "${STATE_FILE}.tmp"
  mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

backup_and_reset_state() {
  cp "$STATE_FILE" "${STATE_FILE}.bak"
  initialize_state
}

if [ -f "$STATE_FILE" ]; then
  if ! jq empty "$STATE_FILE" >/dev/null 2>&1; then
    backup_and_reset_state
    echo "{\"continue\": true, \"systemMessage\": \"Flow state backed up and reset at $STATE_FILE\"}"
    exit 0
  fi

  VERSION="$(jq -r '.state_version // 1' "$STATE_FILE")"

  if ! [[ "$VERSION" =~ ^[0-9]+$ ]]; then
    echo "unsupported flow state version: $VERSION" >&2
    exit 1
  fi

  if [ "$VERSION" -gt 2 ]; then
    echo "unsupported flow state version: $VERSION" >&2
    exit 1
  fi

  if ! bash "$MIGRATE_SCRIPT" --check-safe "$STATE_FILE"; then
    backup_and_reset_state
    echo "{\"continue\": true, \"systemMessage\": \"Flow state backed up and reset at $STATE_FILE\"}"
    exit 0
  fi

  if [ "$VERSION" -lt 2 ]; then
    bash "$MIGRATE_SCRIPT" "$STATE_FILE"
    normalize_workflow_state
    echo "{\"continue\": true, \"systemMessage\": \"Flow state migrated to v2 at $STATE_FILE\"}"
    exit 0
  fi

  WORKFLOW_TYPE="$(jq -r 'if has("workflow") then (.workflow | type) else "missing" end' "$STATE_FILE")"

  if [ "$WORKFLOW_TYPE" = "missing" ]; then
    normalize_workflow_state
  elif [ "$WORKFLOW_TYPE" != "object" ]; then
    backup_and_reset_state
    echo "{\"continue\": true, \"systemMessage\": \"Flow state backed up and reset at $STATE_FILE\"}"
    exit 0
  fi

  echo '{"continue": true, "systemMessage": "Flow state file exists and valid"}'
  exit 0
fi

initialize_state

echo "{\"continue\": true, \"systemMessage\": \"Flow state initialized at $STATE_FILE\"}"
exit 0
