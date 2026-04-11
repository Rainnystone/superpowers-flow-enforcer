#!/bin/bash
set -euo pipefail

assert_json_equals() {
  local file="$1" jq_expr="$2" expected="$3"
  local actual
  actual="$(jq -c "$jq_expr" "$file")"
  [ "$actual" = "$expected" ] || {
    echo "Expected $jq_expr = $expected, got $actual" >&2
    exit 1
  }
}

assert_json_missing() {
  local file="$1" jq_expr="$2"
  local path="${jq_expr#.}"
  local -a parts=()
  local jq_filter=""
  local current_path="."

  if ! [[ "$jq_expr" =~ ^\.[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$ ]]; then
    echo "assert_json_missing supports simple dotted paths only, like .brainstorming.skill_invoked" >&2
    exit 1
  fi

  local IFS='.'
  read -r -a parts <<< "$path"
  jq empty "$file" >/dev/null

  for part in "${parts[@]}"; do
    if [[ -z "$jq_filter" ]]; then
      jq_filter="has(\"$part\")"
      current_path=".$part"
    else
      jq_filter="$jq_filter and ($current_path | type == \"object\" and has(\"$part\"))"
      current_path="$current_path.$part"
    fi
  done

  if jq -e "$jq_filter" "$file" >/dev/null; then
    echo "Expected $jq_expr to be missing" >&2
    exit 1
  fi
}

assert_file_contains() {
  local file="$1" pattern="$2"
  grep -Fq "$pattern" "$file" || {
    echo "Expected $file to contain $pattern" >&2
    exit 1
  }
}

assert_file_exists() {
  [ -f "$1" ] || {
    echo "Expected file $1 to exist" >&2
    exit 1
  }
}
