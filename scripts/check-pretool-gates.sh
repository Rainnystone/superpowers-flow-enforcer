#!/bin/bash
set -euo pipefail

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

resolve_logical_state_root_from_candidate() {
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

  current="$(cd "$current" 2>/dev/null && pwd)" || return

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

resolve_project_dir() {
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    local resolved
    resolved="$(resolve_state_root_from_candidate "$CLAUDE_PROJECT_DIR")"
    if [ -n "$resolved" ]; then
      printf '%s\n' "$resolved"
      return
    fi

    printf '%s\n' "$CLAUDE_PROJECT_DIR"
    return
  fi

  local hook_cwd
  hook_cwd="$(hook_cwd_from_input)"
  if [ -n "$hook_cwd" ]; then
    local resolved
    resolved="$(resolve_state_root_from_candidate "$hook_cwd")"
    if [ -n "$resolved" ]; then
      printf '%s\n' "$resolved"
      return
    fi

    printf '%s\n' "$hook_cwd"
    return
  fi

  printf '%s\n' "$PWD"
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

normalize_path() {
  local path="$1"
  local path_physical=""
  local path_dir=""
  local path_name=""
  local root=""
  local -a candidate_roots=()

  while [[ "$path" == ./* ]]; do
    path="${path#./}"
  done

  if [[ "$path" = /* ]]; then
    path_dir="$(dirname "$path")"
    path_name="${path##*/}"
    if [ -d "$path_dir" ]; then
      path_physical="$(cd "$path_dir" 2>/dev/null && pwd -P)/$path_name"
    fi
  fi

  candidate_roots+=("$PROJECT_DIR")
  if [ -n "${PROJECT_DIR_LOGICAL_ROOT:-}" ] && [ "$PROJECT_DIR_LOGICAL_ROOT" != "$PROJECT_DIR" ]; then
    candidate_roots+=("$PROJECT_DIR_LOGICAL_ROOT")
  fi
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    candidate_roots+=("$CLAUDE_PROJECT_DIR")
  fi

  for root in "${candidate_roots[@]}"; do
    if [ -n "$root" ] && [[ "$path" == "$root"/* ]]; then
      printf '%s\n' "${path#"$root"/}"
      return
    fi
  done

  if [ -n "$path_physical" ] && [ -n "$PROJECT_DIR" ] && [[ "$path_physical" == "$PROJECT_DIR"/* ]]; then
    printf '%s\n' "${path_physical#"$PROJECT_DIR"/}"
    return
  fi

  printf '%s\n' "$path"
}

state_is_true() {
  local expr="$1"
  jq -e "$expr == true" "$STATE_FILE" >/dev/null 2>&1
}

is_spec_or_plan_entry_path() {
  local path="$1"
  [[ "$path" =~ ^docs/superpowers/specs/.*\.md$ || "$path" =~ ^docs/superpowers/plans/.*\.md$ ]]
}

is_plan_path() {
  local path="$1"
  [[ "$path" =~ ^docs/superpowers/plans/.*\.md$ ]]
}

is_exception_path() {
  local path="$1"
  case "$path" in
    docs/superpowers/specs/*|*.md|docs/*|*.json|*.yaml|*.yml|*.config.*|.env*|*.d.ts|types/*.ts|*.types.ts|dist/*|build/*)
      return 0
      ;;
  esac
  return 1
}

is_test_like_path() {
  local path="$1"
  [[ "$path" =~ (^|/)(test|tests|spec|__tests__)/|\.test\.|\.spec\.|_test\.|_spec\. ]]
}

infer_candidate_tests() {
  local path="$1"
  local file_name stem ext dir prefix

  file_name="${path##*/}"
  if [[ "$path" == */* ]]; then
    dir="${path%/*}"
    prefix="$dir/"
  else
    prefix=""
  fi

  if [[ "$file_name" == *.* && "$file_name" != .* ]]; then
    stem="${file_name%.*}"
    ext=".${file_name##*.}"
  else
    stem="$file_name"
    ext=""
  fi

  printf '%s\n' "${prefix}${stem}.test${ext}"
  printf '%s\n' "${prefix}${stem}.spec${ext}"
}

has_verified_failing_candidate() {
  local path="$1"
  local candidate failed normalized_failed
  local -a candidates failed_tests

  mapfile -t candidates < <(infer_candidate_tests "$path")
  mapfile -t failed_tests < <(jq -r '.tdd.tests_verified_fail[]? | select(type == "string")' "$STATE_FILE")

  for failed in "${failed_tests[@]}"; do
    normalized_failed="$(normalize_path "$failed")"
    for candidate in "${candidates[@]}"; do
      if [ "$normalized_failed" = "$candidate" ]; then
        return 0
      fi
    done
  done

  return 1
}

PROJECT_DIR="$(resolve_project_dir)"
PROJECT_DIR_LOGICAL_ROOT="$(resolve_logical_state_root_from_candidate "${CLAUDE_PROJECT_DIR:-}")"
if [ -z "$PROJECT_DIR_LOGICAL_ROOT" ]; then
  PROJECT_DIR_LOGICAL_ROOT="$(resolve_logical_state_root_from_candidate "$(hook_cwd_from_input)")"
fi
STATE_FILE="$PROJECT_DIR/.claude/flow_state.json"

bootstrap_missing_state() {
  if [ -f "$STATE_FILE" ]; then
    return
  fi

  if [ -x "$INIT_STATE_SCRIPT" ] || [ -f "$INIT_STATE_SCRIPT" ]; then
    printf '%s' "$INPUT" | CLAUDE_PROJECT_DIR="$PROJECT_DIR" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$INIT_STATE_SCRIPT" >/dev/null 2>&1 || true
  fi
}

state_is_readable() {
  [ -f "$STATE_FILE" ] && jq empty "$STATE_FILE" >/dev/null 2>&1
}

if [ -z "$PROJECT_DIR" ]; then
  deny_pretool "PreToolUse gate 状态不可用：无法确定项目目录。"
  exit 0
fi

bootstrap_missing_state

if ! state_is_readable; then
  deny_pretool "PreToolUse gate 状态不可用：尝试自愈后仍无法读取 .claude/flow_state.json。"
  exit 0
fi

TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')"

if [ "$TOOL_NAME" = "AskUserQuestion" ]; then
  if ! state_is_true '.workflow.active'; then
    exit 0
  fi

  CURRENT_PHASE="$(jq -r '.current_phase // ""' "$STATE_FILE")"
  if [ "$CURRENT_PHASE" = "brainstorming" ] \
    && state_is_true '.brainstorming.question_asked' \
    && ! state_is_true '.brainstorming.findings_updated_after_question'; then
    deny_pretool "Brainstorming 阶段每次提问后必须更新 findings.md。"
    exit 0
  fi

  exit 0
fi

if [ "$TOOL_NAME" != "Write" ] && [ "$TOOL_NAME" != "Edit" ]; then
  exit 0
fi

FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')"
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

NORMALIZED_PATH="$(normalize_path "$FILE_PATH")"

if [ "$NORMALIZED_PATH" = ".claude/flow_state.json" ]; then
  deny_pretool "禁止直接手改 flow_state.json，请通过 hooks 自动推进状态。"
  exit 0
fi

if ! state_is_true '.workflow.active'; then
  if is_spec_or_plan_entry_path "$NORMALIZED_PATH"; then
    exit 0
  fi
  exit 0
fi

if is_plan_path "$NORMALIZED_PATH"; then
  if ! (state_is_true '.exceptions.skip_planning' && state_is_true '.exceptions.user_confirmed'); then
    if ! state_is_true '.brainstorming.spec_reviewed' || ! state_is_true '.brainstorming.user_approved_spec'; then
      deny_pretool "写入计划前必须先完成 spec review 并获得用户批准；only skip_planning may bypass this gate."
      exit 0
    fi
  fi
fi

if is_exception_path "$NORMALIZED_PATH"; then
  exit 0
fi

if ! state_is_true '.brainstorming.spec_written'; then
  if ! (state_is_true '.exceptions.skip_brainstorming' && state_is_true '.exceptions.user_confirmed'); then
    deny_pretool "需要先完成 brainstorming/SPEC。"
    exit 0
  fi
fi

if state_is_true '.exceptions.skip_tdd' && state_is_true '.exceptions.user_confirmed'; then
  exit 0
fi

if ! state_is_true '.worktree.created' || ! state_is_true '.worktree.baseline_verified'; then
  deny_pretool "TDD 之前必须先用 record-worktree-state.sh 记录 worktree.created 和 worktree.baseline_verified。"
  exit 0
fi

if is_test_like_path "$NORMALIZED_PATH"; then
  exit 0
fi

if state_is_true '.tdd.pending_failure_record'; then
  deny_pretool "检测到待记录的失败测试目标。先运行 record-tdd-state.sh fail <target>，再继续修改生产代码。"
  exit 0
fi

if ! has_verified_failing_candidate "$NORMALIZED_PATH"; then
  deny_pretool "NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST. 先写测试并运行到失败。"
  exit 0
fi

exit 0
