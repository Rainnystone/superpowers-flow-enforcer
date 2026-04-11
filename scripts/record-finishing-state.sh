#!/bin/bash
set -euo pipefail

if [ "${1:-}" != "invoked" ] || [ "$#" -ne 1 ]; then
  echo 'Usage: record-finishing-state.sh invoked' >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

jq -n '{finishing:{invoked:true}}' \
  | bash "$PLUGIN_ROOT/scripts/update-state.sh" --merge >/dev/null
