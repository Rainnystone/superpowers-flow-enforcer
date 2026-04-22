#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

shopt -s nullglob
test_scripts=(tests/test_*.sh)

if [ "${#test_scripts[@]}" -eq 0 ]; then
  echo "No test scripts found under tests/test_*.sh" >&2
  exit 1
fi

printf 'Running %d test scripts from %s\n' "${#test_scripts[@]}" "$REPO_ROOT"

index=0
for test_script in "${test_scripts[@]}"; do
  index=$((index + 1))
  printf '\n[%d/%d] %s\n' "$index" "${#test_scripts[@]}" "$test_script"
  bash "$test_script"
done

printf '\nAll %d test scripts passed.\n' "${#test_scripts[@]}"
