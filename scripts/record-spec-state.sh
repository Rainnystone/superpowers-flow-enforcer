#!/bin/bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo 'Usage: record-spec-state.sh self-review|user-approval pass|fail' >&2
  exit 1
fi

ACTION="$1"
RESULT="$2"

case "$ACTION" in
  self-review)
    FIELD="spec_reviewed"
    ;;
  user-approval)
    FIELD="user_approved_spec"
    ;;
  *)
    echo "Unsupported spec action: $ACTION" >&2
    exit 1
    ;;
esac

case "$RESULT" in
  pass) VALUE=true ;;
  fail) VALUE=false ;;
  *)
    echo "Unsupported result: $RESULT" >&2
    exit 1
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

jq -n --argjson value "$VALUE" --arg field "$FIELD" '{brainstorming:{($field):$value}}' \
  | bash "$PLUGIN_ROOT/scripts/update-state.sh" --merge >/dev/null
