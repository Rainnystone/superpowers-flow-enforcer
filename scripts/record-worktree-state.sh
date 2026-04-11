#!/bin/bash
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo 'Usage: record-worktree-state.sh created <path> | baseline pass|fail' >&2
  exit 1
fi

MODE="$1"
VALUE="${2:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

case "$MODE" in
  created)
    if [ -z "$VALUE" ]; then
      echo 'record-worktree-state.sh created requires a worktree path' >&2
      exit 1
    fi

    jq -n --arg path "$VALUE" '{worktree:{created:true,path:$path,baseline_verified:false}}' \
      | bash "$PLUGIN_ROOT/scripts/update-state.sh" --merge >/dev/null
    ;;
  baseline)
    case "$VALUE" in
      pass) VERIFIED=true ;;
      fail) VERIFIED=false ;;
      *)
        echo "Unsupported result: $VALUE" >&2
        exit 1
        ;;
    esac

    jq -n --argjson verified "$VERIFIED" '{worktree:{baseline_verified:$verified}}' \
      | bash "$PLUGIN_ROOT/scripts/update-state.sh" --merge >/dev/null
    ;;
  *)
    echo "Unsupported worktree action: $MODE" >&2
    exit 1
    ;;
esac
