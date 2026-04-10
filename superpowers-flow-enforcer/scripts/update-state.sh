#!/bin/bash
set -euo pipefail

# update-state.sh - Update flow_state.json phase fields
# Usage: update-state.sh <phase> <field> <value>
# Example: update-state.sh brainstorming skill_invoked true

STATE_FILE="$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
PHASE="${1:-}"
FIELD="${2:-}"
VALUE="${3:-}"

if [ -z "$PHASE" ] || [ -z "$FIELD" ]; then
  echo '{"error": "Usage: update-state.sh <phase> <field> <value>"}'
  exit 1
fi

if [ "$VALUE" = "true" ] || [ "$VALUE" = "false" ]; then
  jq --arg phase "$PHASE" --arg field "$FIELD" --argjson value "$VALUE" \
    '.[$phase][$field] = $value' "$STATE_FILE" > "$STATE_FILE.tmp"
else
  jq --arg phase "$PHASE" --arg field "$FIELD" --arg value "$VALUE" \
    '.[$phase][$field] = $value' "$STATE_FILE" > "$STATE_FILE.tmp"
fi

mv "$STATE_FILE.tmp" "$STATE_FILE"
echo '{"success": true}'