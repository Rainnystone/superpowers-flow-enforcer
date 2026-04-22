#!/bin/bash

platform_compat_python_is_runnable() {
  local python_bin="$1"
  "$python_bin" -c 'import sys; sys.exit(0)' >/dev/null 2>&1
}

platform_compat_resolve_python_bin() {
  local candidate=""
  local candidate_path=""

  for candidate in python3 python; do
    candidate_path="$(command -v "$candidate" 2>/dev/null || true)"
    [ -n "$candidate_path" ] || continue
    platform_compat_python_is_runnable "$candidate_path" || continue
    printf '%s\n' "$candidate_path"
    return 0
  done

  echo "No working Python interpreter found; tried python3 then python" >&2
  return 1
}

platform_compat_run_python() {
  local python_bin=""
  python_bin="$(platform_compat_resolve_python_bin)" || return 1
  "$python_bin" "$@"
}

platform_compat_hash_stdin_sha256() {
  local hash_output=""

  if command -v sha256sum >/dev/null 2>&1; then
    if hash_output="$(sha256sum)"; then
      printf '%s\n' "${hash_output%% *}"
      return 0
    fi
  fi

  if command -v shasum >/dev/null 2>&1; then
    if hash_output="$(shasum -a 256)"; then
      printf '%s\n' "${hash_output%% *}"
      return 0
    fi
  fi

  if command -v openssl >/dev/null 2>&1; then
    if hash_output="$(openssl dgst -sha256)"; then
      printf '%s\n' "${hash_output##* }"
      return 0
    fi
  fi

  platform_compat_run_python -c 'import hashlib, sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())'
}
