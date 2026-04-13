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

workflow_paths__to_physical_file_path_if_possible() {
  local path="$1"
  if [[ "$path" != /* ]]; then
    return
  fi

  local path_dir
  local path_name
  path_dir="$(dirname "$path")"
  path_name="${path##*/}"

  if [ -d "$path_dir" ]; then
    printf '%s/%s\n' "$(cd "$path_dir" 2>/dev/null && pwd -P)" "$path_name"
  fi
}

workflow_paths_normalize_project_relative_path() {
  local candidate_path="$1"
  local project_root="$2"
  local hook_cwd="${3:-}"
  local candidate=""
  local candidate_physical=""
  local rel_path=""
  local root_alias=""

  if [ -z "$project_root" ] || [ -z "$candidate_path" ]; then
    return
  fi

  candidate="$(workflow_paths__strip_leading_dot_slash "$candidate_path")"

  if [[ "$candidate" = /* ]]; then
    candidate_physical="$(workflow_paths__to_physical_file_path_if_possible "$candidate" || true)"
    if [ -n "$candidate_physical" ] && [[ "$candidate_physical" == "$project_root"/* ]]; then
      rel_path="${candidate_physical#"$project_root"/}"
    elif [[ "$candidate" == "$project_root"/* ]]; then
      rel_path="${candidate#"$project_root"/}"
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
    rel_path="$candidate"
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
    .git/*|.worktrees/*|node_modules/*|vendor/*|.simulation/*|\
    testdata/*|tests/testdata/*|fixture/*|fixtures/*|\
    __fixtures__/*|tests/fixture/*|tests/fixtures/*|tests/__fixtures__/*)
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
