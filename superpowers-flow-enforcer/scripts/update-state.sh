#!/bin/bash
set -euo pipefail

# update-state.sh - Update flow_state.json phase fields
# Usage: update-state.sh <phase> <field> <value>
# Example: update-state.sh brainstorming skill_invoked true

# Dependency check
if ! command -v jq &>/dev/null; then
  echo '{"error": "jq is required but not installed"}'
  exit 1
fi

# Environment validation
if [ -z "${CLAUDE_PROJECT_DIR:-}" ]; then
  echo '{"error": "CLAUDE_PROJECT_DIR not set"}'
  exit 1
fi

STATE_FILE="$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

# State file existence check
if [ ! -f "$STATE_FILE" ]; then
  echo '{"error": "State file not found"}'
  exit 1
fi

PHASE="${1:-}"
FIELD="${2:-}"
VALUE="${3:-}"

if [ -z "$PHASE" ] || [ -z "$FIELD" ]; then
  echo '{"error": "Usage: update-state.sh <phase> <field> <value>"}'
  exit 1
fi

# Phase validation
VALID_PHASES="brainstorming|planning|worktree|tdd|review|finishing|debugging|exceptions|interrupt|current_phase"
if ! echo "$PHASE" | grep -qE "^($VALID_PHASES)$"; then
  echo '{"error": "Invalid phase name"}'
  exit 1
fi

# Update with error capture
if [ "$VALUE" = "true" ] || [ "$VALUE" = "false" ]; then
  jq_output=$(jq --arg phase "$PHASE" --arg field "$FIELD" --argjson value "$VALUE" \
    '.[$phase][$field] = $value' "$STATE_FILE" 2>&1) || {
    echo "{\"error\": \"jq failed: $jq_output\"}"
    exit 1
  }
else
  jq_output=$(jq --arg phase "$PHASE" --arg field "$FIELD" --arg value "$VALUE" \
    '.[$phase][$field] = $value' "$STATE_FILE" 2>&1) || {
    echo "{\"error\": \"jq failed: $jq_output\"}"
    exit 1
  }
fi

echo "$jq_output" > "$STATE_FILE.tmp"
mv "$STATE_FILE.tmp" "$STATE_FILE"
echo '{"success": true}'