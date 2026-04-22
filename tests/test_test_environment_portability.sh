#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

OWNED_FILES=(
  tests/helpers/platform.sh
  tests/test_init_state.sh
  tests/test_workflow_activation.sh
  tests/test_pretool_command_gates.sh
  tests/test_worktree_baseline_flow.sh
  tests/test_test_environment_portability.sh
)

TEMP_PATH_CHECK_FILES=(
  tests/helpers/platform.sh
  tests/test_init_state.sh
  tests/test_workflow_activation.sh
  tests/test_pretool_command_gates.sh
  tests/test_worktree_baseline_flow.sh
)

for file in "${OWNED_FILES[@]}"; do
  if [ ! -f "$REPO_ROOT/$file" ]; then
    echo "Expected $file to exist" >&2
    exit 1
  fi
done

for file in "${TEMP_PATH_CHECK_FILES[@]}"; do
  if rg -n '/tmp/' "$REPO_ROOT/$file"; then
    echo "Expected $file to avoid hard-coded temp-root paths" >&2
    exit 1
  fi
done

for file in tests/test_workflow_activation.sh tests/test_pretool_command_gates.sh; do
  if ! rg -n 'source tests/helpers/platform\.sh' "$REPO_ROOT/$file" >/dev/null; then
    echo "Expected $file to source tests/helpers/platform.sh" >&2
    exit 1
  fi

  if ! rg -n 'platform_require_symlink_support_or_skip' "$REPO_ROOT/$file" >/dev/null; then
    echo "Expected $file to gate symlink-sensitive cases with platform_require_symlink_support_or_skip" >&2
    exit 1
  fi
done

if ! rg -n '^platform_require_symlink_support_or_skip\(\)' "$REPO_ROOT/tests/helpers/platform.sh" >/dev/null; then
  echo "Expected tests/helpers/platform.sh to define platform_require_symlink_support_or_skip" >&2
  exit 1
fi
