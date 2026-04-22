#!/bin/bash

platform_require_symlink_support_or_skip() {
  local probe_dir="${1:-}"
  local target=""
  local link=""

  if [ -z "$probe_dir" ]; then
    echo "SKIP: symlink prerequisites unavailable"
    return 1
  fi

  mkdir -p "$probe_dir"
  target="$probe_dir/symlink-target"
  link="$probe_dir/symlink-link"
  rm -f "$link"

  if ln -s "$target" "$link" 2>/dev/null && [ -L "$link" ]; then
    rm -f "$link"
    return 0
  fi

  echo "SKIP: symlink prerequisites unavailable"
  return 1
}
