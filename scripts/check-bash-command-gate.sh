#!/bin/bash
set -euo pipefail

TARGET_PATH='.claude/flow_state.json'
STATE_UNAVAILABLE_REASON='Bash gate 状态不可用：尝试自愈后仍无法读取 .claude/flow_state.json。'
NODE_REQUIRED_REASON='激活中的 Bash gate 需要可用的 Node.js 来运行 vendored bash-traverse。请安装 Node 18+ 后重试。'
HELPER_FAILURE_REASON='Bash gate 无法完成命令分析：vendored bash-traverse 运行失败。'

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

INPUT="$(cat)"
if ! printf '%s' "$INPUT" | jq empty >/dev/null 2>&1; then
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
INIT_STATE_SCRIPT="$SCRIPT_DIR/init-state.sh"
NODE_HELPER="$SCRIPT_DIR/check-bash-command-gate-node.cjs"

hook_cwd_from_input() {
  printf '%s' "$INPUT" | jq -r '
    if (.cwd | type) == "string" and .cwd != "" then
      .cwd
    else
      empty
    end
  ' 2>/dev/null || true
}

resolve_state_root_from_candidate() {
  local candidate="$1"

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

canonicalize_existing_dir() {
  local candidate="$1"

  if [ -z "$candidate" ] || [ ! -d "$candidate" ]; then
    return
  fi

  cd "$candidate" 2>/dev/null && pwd -P
}

resolve_project_dir() {
  local resolved=""
  local hook_cwd=""

  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    resolved="$(resolve_state_root_from_candidate "$CLAUDE_PROJECT_DIR")"
    if [ -n "$resolved" ]; then
      printf '%s\n' "$resolved"
      return
    fi

    resolved="$(canonicalize_existing_dir "$CLAUDE_PROJECT_DIR")"
    if [ -n "$resolved" ]; then
      printf '%s\n' "$resolved"
      return
    fi

    return
  fi

  hook_cwd="$(hook_cwd_from_input)"
  if [ -z "$hook_cwd" ]; then
    return
  fi

  resolved="$(resolve_state_root_from_candidate "$hook_cwd")"
  if [ -n "$resolved" ]; then
    printf '%s\n' "$resolved"
    return
  fi

  if [ -d "$hook_cwd/.claude" ]; then
    canonicalize_existing_dir "$hook_cwd"
  fi
}

deny_pretool() {
  local reason="$1"
  jq -n --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
}

attempt_state_recovery_once() {
  if [ -z "$PROJECT_DIR" ] || [ ! -e "$STATE_FILE" ]; then
    return
  fi

  if [ -x "$INIT_STATE_SCRIPT" ] || [ -f "$INIT_STATE_SCRIPT" ]; then
    printf '%s' "$INPUT" | CLAUDE_PROJECT_DIR="$PROJECT_DIR" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$INIT_STATE_SCRIPT" >/dev/null 2>&1 || true
  fi
}

state_is_readable() {
  [ -f "$STATE_FILE" ] && jq empty "$STATE_FILE" >/dev/null 2>&1
}

state_is_active() {
  jq -e '.workflow.active == true' "$STATE_FILE" >/dev/null 2>&1
}

resolve_node_bin() {
  if [ -n "${BASH_GATE_NODE_BIN:-}" ]; then
    if [ -x "$BASH_GATE_NODE_BIN" ]; then
      printf '%s\n' "$BASH_GATE_NODE_BIN"
      return 0
    fi

    if command -v "$BASH_GATE_NODE_BIN" >/dev/null 2>&1; then
      command -v "$BASH_GATE_NODE_BIN"
      return 0
    fi

    return 1
  fi

  command -v node >/dev/null 2>&1 || return 1
  command -v node
}

PROJECT_DIR="$(resolve_project_dir)"
if [ -z "$PROJECT_DIR" ]; then
  exit 0
fi

STATE_FILE="$PROJECT_DIR/.claude/flow_state.json"
attempt_state_recovery_once

if [ ! -e "$STATE_FILE" ]; then
  exit 0
fi

if ! state_is_readable; then
  deny_pretool "$STATE_UNAVAILABLE_REASON"
  exit 0
fi

if ! state_is_active; then
  exit 0
fi

NODE_BIN="$(resolve_node_bin || true)"
if [ -z "$NODE_BIN" ]; then
  deny_pretool "$NODE_REQUIRED_REASON"
  exit 0
fi

STATE_JSON="$(jq -c '.' "$STATE_FILE" 2>/dev/null || true)"
if [ -z "$STATE_JSON" ]; then
  deny_pretool "$STATE_UNAVAILABLE_REASON"
  exit 0
fi

HELPER_OUTPUT="$(
  printf '%s' "$INPUT" | \
    BASH_GATE_PROJECT_DIR="$PROJECT_DIR" \
    BASH_GATE_STATE_JSON="$STATE_JSON" \
    BASH_GATE_TARGET_PATH="$TARGET_PATH" \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    "$NODE_BIN" "$NODE_HELPER" 2>/dev/null
)" || {
  deny_pretool "$HELPER_FAILURE_REASON"
  exit 0
}

if [ -n "$HELPER_OUTPUT" ] && ! printf '%s' "$HELPER_OUTPUT" | jq empty >/dev/null 2>&1; then
  deny_pretool "$HELPER_FAILURE_REASON"
  exit 0
fi

printf '%s' "$HELPER_OUTPUT"
