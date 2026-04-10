#!/bin/bash
set -euo pipefail

# update-state.sh - Update flow_state.json fields
# Usage:
#   1) update-state.sh <phase> <field> <value>
#      Example: update-state.sh brainstorming skill_invoked true
#   2) update-state.sh --jq '<jq-expression>'
#      Example: update-state.sh --jq '.current_phase = "tdd"'
#   3) echo '{"planning":{"plan_written":true}}' | update-state.sh --merge

if ! command -v jq >/dev/null 2>&1; then
  echo '{"error":"jq is required but not installed"}'
  exit 1
fi

if [ -z "${CLAUDE_PROJECT_DIR:-}" ]; then
  echo '{"error":"CLAUDE_PROJECT_DIR not set"}'
  exit 1
fi

STATE_FILE="$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

if [ ! -f "$STATE_FILE" ]; then
  echo '{"error":"State file not found"}'
  exit 1
fi

write_tmp_and_swap() {
  local expr="$1"
  local tmp_file
  tmp_file="${STATE_FILE}.tmp"
  jq "$expr" "$STATE_FILE" > "$tmp_file"
  mv "$tmp_file" "$STATE_FILE"
}

parse_value_mode() {
  local raw="$1"
  if [ "$raw" = "true" ] || [ "$raw" = "false" ] || [ "$raw" = "null" ]; then
    echo "json"
    return 0
  fi
  if echo "$raw" | jq -e . >/dev/null 2>&1; then
    echo "json"
    return 0
  fi
  echo "string"
}

if [ "${1:-}" = "--jq" ]; then
  if [ -z "${2:-}" ]; then
    echo '{"error":"Usage: update-state.sh --jq <jq-expression>"}'
    exit 1
  fi
  write_tmp_and_swap "${2}"
  echo '{"success":true}'
  exit 0
fi

if [ "${1:-}" = "--merge" ]; then
  payload="$(cat)"
  if [ -z "$payload" ]; then
    echo '{"error":"Merge payload is empty"}'
    exit 1
  fi
  if ! echo "$payload" | jq -e 'type == "object"' >/dev/null 2>&1; then
    echo '{"error":"Merge payload must be a JSON object"}'
    exit 1
  fi
  tmp_file="${STATE_FILE}.tmp"
  jq -s '.[0] * .[1]' "$STATE_FILE" <(echo "$payload") > "$tmp_file"
  mv "$tmp_file" "$STATE_FILE"
  echo '{"success":true}'
  exit 0
fi

PHASE="${1:-}"
FIELD="${2:-}"
RAW_VALUE="${3:-}"

if [ -z "$PHASE" ] || [ -z "$FIELD" ] || [ -z "${3:-}" ]; then
  echo '{"error":"Usage: update-state.sh <phase> <field> <value> | --jq <expr> | --merge"}'
  exit 1
fi

VALID_PHASES="brainstorming|planning|worktree|tdd|review|finishing|debugging|exceptions|interrupt|current_phase"
if ! echo "$PHASE" | grep -qE "^($VALID_PHASES)$"; then
  echo '{"error":"Invalid phase name"}'
  exit 1
fi

value_mode="$(parse_value_mode "$RAW_VALUE")"

tmp_file="${STATE_FILE}.tmp"
if [ "$PHASE" = "current_phase" ]; then
  if [ "$value_mode" = "json" ]; then
    jq --arg field "$FIELD" --argjson value "$RAW_VALUE" '.[$field] = $value' "$STATE_FILE" > "$tmp_file"
  else
    jq --arg field "$FIELD" --arg value "$RAW_VALUE" '.[$field] = $value' "$STATE_FILE" > "$tmp_file"
  fi
else
  if [ "$value_mode" = "json" ]; then
    jq --arg phase "$PHASE" --arg field "$FIELD" --argjson value "$RAW_VALUE" '.[$phase][$field] = $value' "$STATE_FILE" > "$tmp_file"
  else
    jq --arg phase "$PHASE" --arg field "$FIELD" --arg value "$RAW_VALUE" '.[$phase][$field] = $value' "$STATE_FILE" > "$tmp_file"
  fi
fi
mv "$tmp_file" "$STATE_FILE"

echo '{"success":true}'
