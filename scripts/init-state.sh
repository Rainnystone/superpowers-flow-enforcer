#!/bin/bash
set -euo pipefail

# SessionStart hook: Initialize flow_state.json if not exists
STATE_FILE="$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
TEMPLATE="${CLAUDE_PLUGIN_ROOT}/templates/flow_state.json.tmpl"
MIGRATE_SCRIPT="${CLAUDE_PLUGIN_ROOT}/scripts/migrate-state.sh"

initialize_state() {
  mkdir -p "$CLAUDE_PROJECT_DIR/.claude"

  SESSION_ID=$(date +%s | shasum -a 256 | head -c 16)
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  jq --arg session "$SESSION_ID" \
     --arg project "$CLAUDE_PROJECT_DIR" \
     --arg timestamp "$TIMESTAMP" \
     '.session_id = $session | .project_dir = $project | .initialized_at = $timestamp' \
     "$TEMPLATE" > "$STATE_FILE"
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
    echo "{\"continue\": true, \"systemMessage\": \"Flow state migrated to v2 at $STATE_FILE\"}"
    exit 0
  fi

  echo '{"continue": true, "systemMessage": "Flow state file exists and valid"}'
  exit 0
fi

initialize_state

echo "{\"continue\": true, \"systemMessage\": \"Flow state initialized at $STATE_FILE\"}"
exit 0
