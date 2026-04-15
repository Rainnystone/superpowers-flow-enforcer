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
