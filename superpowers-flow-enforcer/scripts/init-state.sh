#!/bin/bash
set -euo pipefail

# SessionStart hook: Initialize flow_state.json if not exists
STATE_FILE="$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
TEMPLATE="${CLAUDE_PLUGIN_ROOT}/templates/flow_state.json.tmpl"

# Check if state file exists and is valid
if [ -f "$STATE_FILE" ]; then
  # Validate JSON structure
  if jq -e '.current_phase' "$STATE_FILE" >/dev/null 2>&1; then
    echo '{"continue": true, "systemMessage": "Flow state file exists and valid"}'
    exit 0
  else
    echo '{"systemMessage": "Flow state file corrupted, re-initializing"}' >&2
  fi
fi

# Create state file from template
mkdir -p "$CLAUDE_PROJECT_DIR/.claude"

# Generate session ID and timestamp
SESSION_ID=$(date +%s | shasum -a 256 | head -c 16)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Copy template and fill dynamic fields
jq --arg session "$SESSION_ID" \
   --arg project "$CLAUDE_PROJECT_DIR" \
   --arg timestamp "$TIMESTAMP" \
   '.session_id = $session | .project_dir = $project | .initialized_at = $timestamp' \
   "$TEMPLATE" > "$STATE_FILE"

echo "{\"continue\": true, \"systemMessage\": \"Flow state initialized at $STATE_FILE\"}"
exit 0