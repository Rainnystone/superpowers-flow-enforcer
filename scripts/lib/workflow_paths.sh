#!/bin/bash

workflow_paths_resolve_state_root_from_candidate() {
  local candidate="${1:-}"

  if [ -z "$candidate" ]; then
    return
  fi

  local current="$candidate"
  if [ ! -d "$current" ]; then
    current="$(dirname "$current")"
  fi

  if [ ! -d "$current" ]; then
    return
  fi

  current="$(cd "$current" 2>/dev/null && pwd -P)" || return

  while :; do
    if [ -f "$current/.claude/flow_state.json" ]; then
      printf '%s\n' "$current"
      return
    fi

    if [ "$current" = "/" ]; then
      return
    fi

    current="$(dirname "$current")"
  done
}

workflow_paths_resolve_state_root_alias_from_candidate() {
  local candidate="${1:-}"

  if [ -z "$candidate" ]; then
    return
  fi

  local current="$candidate"
  if [ ! -d "$current" ]; then
    current="$(dirname "$current")"
  fi

  if [ ! -d "$current" ]; then
    return
  fi

  while :; do
    if [ -f "$current/.claude/flow_state.json" ]; then
      printf '%s\n' "$current"
      return
    fi

    if [ "$current" = "/" ]; then
      return
    fi

    current="$(dirname "$current")"
  done
}

workflow_paths_resolve_project_root() {
  local hook_cwd="${1:-}"
  local resolved=""

  resolved="$(workflow_paths_resolve_state_root_from_candidate "${CLAUDE_PROJECT_DIR:-}")"
  if [ -n "$resolved" ]; then
    printf '%s\n' "$resolved"
    return
  fi

  resolved="$(workflow_paths_resolve_state_root_from_candidate "$hook_cwd")"
  if [ -n "$resolved" ]; then
    printf '%s\n' "$resolved"
  fi
}

workflow_paths__strip_leading_dot_slash() {
  local path="$1"
  while [[ "$path" == ./* ]]; do
    path="${path#./}"
  done
  printf '%s\n' "$path"
}

workflow_paths__normalize_relative_path() {
  local path="$1"
  python3 - "$path" <<'PY'
import os
import sys

path = sys.argv[1]
normalized = os.path.normpath(path)
if normalized == ".":
    print("")
else:
    print(normalized)
PY
}

workflow_paths__normalize_absolute_path() {
  local path="$1"
  if [[ "$path" != /* ]]; then
    return
  fi

  python3 - "$path" <<'PY'
import os
import sys

path = sys.argv[1]
print(os.path.realpath(os.path.normpath(path)))
PY
}

workflow_paths_normalize_project_relative_path() {
  local candidate_path="$1"
  local project_root="$2"
  local hook_cwd="${3:-}"
  local candidate=""
  local candidate_physical=""
  local physical_outside_project="false"
  local hook_cwd_physical=""
  local base_dir_physical=""
  local rel_path=""
  local root_alias=""

  if [ -z "$project_root" ] || [ -z "$candidate_path" ]; then
    return
  fi

  candidate="$(workflow_paths__strip_leading_dot_slash "$candidate_path")"

  if [[ "$candidate" = /* ]]; then
    candidate_physical="$(workflow_paths__normalize_absolute_path "$candidate" || true)"
    if [ -n "$candidate_physical" ] && [[ "$candidate_physical" == "$project_root"/* ]]; then
      rel_path="${candidate_physical#"$project_root"/}"
    elif [ -n "$candidate_physical" ]; then
      physical_outside_project="true"
    else
      for root_alias in \
        "$(workflow_paths_resolve_state_root_alias_from_candidate "${CLAUDE_PROJECT_DIR:-}")" \
        "$(workflow_paths_resolve_state_root_alias_from_candidate "$hook_cwd")"
      do
        if [ -n "$root_alias" ] && [[ "$candidate" == "$root_alias"/* ]]; then
          rel_path="${candidate#"$root_alias"/}"
          break
        fi
      done
    fi
  else
    if [ -n "$hook_cwd" ] && [ -d "$hook_cwd" ]; then
      hook_cwd_physical="$(cd "$hook_cwd" 2>/dev/null && pwd -P)" || hook_cwd_physical=""
    fi

    base_dir_physical="$hook_cwd_physical"
    if [ -z "$base_dir_physical" ]; then
      base_dir_physical="$project_root"
    fi

    if [ -n "$base_dir_physical" ]; then
      candidate_physical="$(workflow_paths__normalize_absolute_path "$base_dir_physical/$candidate" || true)"
      if [ -n "$candidate_physical" ] && [[ "$candidate_physical" == "$project_root"/* ]]; then
        rel_path="${candidate_physical#"$project_root"/}"
      elif [ -n "$candidate_physical" ]; then
        physical_outside_project="true"
      fi
    fi

    if [ -z "$rel_path" ]; then
      rel_path="$candidate"
    fi
  fi

  if [ "$physical_outside_project" = "true" ]; then
    return
  fi

  if [ -z "$rel_path" ]; then
    return
  fi

  rel_path="$(workflow_paths__normalize_relative_path "$rel_path")"
  if [ -z "$rel_path" ]; then
    return
  fi

  if [ "$rel_path" = ".." ] || [[ "$rel_path" == ../* ]]; then
    return
  fi

  printf '%s\n' "$rel_path"
}

workflow_paths_is_excluded_prefix() {
  local rel_path="$1"

  case "$rel_path" in
    .git/*|*/.git/*|\
    .worktrees/*|*/.worktrees/*|\
    node_modules/*|*/node_modules/*|\
    vendor/*|*/vendor/*|\
    .simulation/*|*/.simulation/*|\
    testdata/*|*/testdata/*|\
    fixture/*|*/fixture/*|\
    fixtures/*|*/fixtures/*|\
    __fixtures__/*|*/__fixtures__/*|\
    tests/testdata/*|*/tests/testdata/*|\
    tests/fixture/*|*/tests/fixture/*|\
    tests/fixtures/*|*/tests/fixtures/*|\
    tests/__fixtures__/*|*/tests/__fixtures__/*)
      return 0
      ;;
  esac

  return 1
}

workflow_paths_classify_canonical_write() {
  local rel_path="$1"

  if [ -z "$rel_path" ]; then
    printf 'none\n'
    return
  fi

  if workflow_paths_is_excluded_prefix "$rel_path"; then
    printf 'none\n'
    return
  fi

  if echo "$rel_path" | grep -qE '(^|.*/)docs/superpowers/specs/[^/]+\.md$'; then
    printf 'spec\n'
    return
  fi

  if echo "$rel_path" | grep -qE '(^|.*/)docs/superpowers/plans/[^/]+\.md$'; then
    printf 'plan\n'
    return
  fi

  printf 'none\n'
}
