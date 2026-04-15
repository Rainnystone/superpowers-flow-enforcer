#!/bin/bash
set -euo pipefail

if [ "$#" -ne 2 ] || [ "${1:-}" != "completed" ] || [ -z "${2:-}" ]; then
  echo 'Usage: record-resume-state.sh completed <source>' >&2
  exit 1
fi

SOURCE="$2"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
STATE_FILE="${CLAUDE_PROJECT_DIR:-}/.claude/flow_state.json"

if [ -z "${CLAUDE_PROJECT_DIR:-}" ] || [ ! -f "$STATE_FILE" ]; then
  echo 'record-resume-state.sh requires an existing CLAUDE_PROJECT_DIR state file' >&2
  exit 1
fi

if ! jq -e '.resume.recovery_required == true' "$STATE_FILE" >/dev/null; then
  echo 'resume recovery is not currently required' >&2
  exit 1
fi

jq -n \
  --arg timestamp "$TIMESTAMP" \
  --arg source "$SOURCE" \
  '{
    resume: {
      recovery_required: false,
      recovery_completed_at: $timestamp,
      last_resume_source: $source
    }
  }' \
  | bash "$PLUGIN_ROOT/scripts/update-state.sh" --merge >/dev/null
