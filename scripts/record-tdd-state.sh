#!/bin/bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo 'Usage: record-tdd-state.sh fail <target>' >&2
  exit 1
fi

ACTION="$1"
TARGET="$2"

case "$ACTION" in
  fail) ;;
  *)
    echo "Unsupported TDD action: $ACTION" >&2
    exit 1
    ;;
esac

if [ -z "$TARGET" ]; then
  echo 'record-tdd-state.sh fail requires a non-empty target' >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

TARGET_JSON="$(jq -Rn --arg target "$TARGET" '$target')"
EXPR=".tdd.pending_failure_record = false | .tdd.last_failed_command = null | .tdd.tests_verified_fail = ((.tdd.tests_verified_fail // []) as \$items | if (\$items | index($TARGET_JSON)) == null then (\$items + [$TARGET_JSON]) else \$items end)"

bash "$PLUGIN_ROOT/scripts/update-state.sh" --jq "$EXPR" >/dev/null
