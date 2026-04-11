#!/bin/bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo 'Usage: record-review-state.sh <task-id> spec|code pass|fail' >&2
  exit 1
fi

TASK_ID="$1"
STAGE="$2"
RESULT="$3"

if [ -z "$TASK_ID" ]; then
  echo 'task-id must not be empty' >&2
  exit 1
fi

case "$STAGE" in
  spec)
    FIELD="spec_review_passed"
    ;;
  code)
    FIELD="code_review_passed"
    ;;
  *)
    echo "Unsupported review stage: $STAGE" >&2
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

jq -n --arg task_id "$TASK_ID" --arg field "$FIELD" --argjson value "$VALUE" \
  '{review:{tasks:{($task_id):{($field):$value}}}}' \
  | bash "$PLUGIN_ROOT/scripts/update-state.sh" --merge >/dev/null
