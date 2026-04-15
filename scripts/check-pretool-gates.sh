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
WORKFLOW_PATHS_LIB="$SCRIPT_DIR/lib/workflow_paths.sh"
TASK_FLOW_PACKETS_LIB="$SCRIPT_DIR/lib/task_flow_packets.sh"

# shellcheck source=/dev/null
source "$WORKFLOW_PATHS_LIB"
# shellcheck source=/dev/null
source "$TASK_FLOW_PACKETS_LIB"

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
  workflow_paths_resolve_state_root_from_candidate "${1:-}"
}

resolve_logical_state_root_from_candidate() {
  workflow_paths_resolve_state_root_alias_from_candidate "${1:-}"
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

normalize_recorded_path() {
  local path="$1"

  while [[ "$path" == ./* ]]; do
    path="${path#./}"
  done

  if [[ "$path" = /* ]]; then
    local absolute
    absolute="$(workflow_paths__normalize_absolute_path "$path" || true)"
    if [ -n "$absolute" ]; then
      printf '%s\n' "$absolute"
      return
    fi
  fi

  printf '%s\n' "$(workflow_paths__normalize_relative_path "$path")"
}

normalize_hook_path() {
  local path="$1"
  local hook_cwd="${2:-}"
  local project_relative=""
  local absolute=""

  while [[ "$path" == ./* ]]; do
    path="${path#./}"
  done

  project_relative="$(workflow_paths_normalize_project_relative_path "$path" "$PROJECT_DIR" "$hook_cwd")"
  if [ -n "$project_relative" ]; then
    printf '%s\n' "$project_relative"
    return
  fi

  if [[ "$path" = /* ]]; then
    absolute="$(workflow_paths__normalize_absolute_path "$path" || true)"
    if [ -n "$absolute" ]; then
      printf '%s\n' "$absolute"
      return
    fi
  fi

  printf '%s\n' "$(workflow_paths__normalize_relative_path "$path")"
}

state_is_true() {
  local expr="$1"
  jq -e "$expr == true" "$STATE_FILE" >/dev/null 2>&1
}

state_active_task_id() {
  jq -r '
    if (.task_flow.active_task_id | type) == "string" then
      .task_flow.active_task_id
    else
      ""
    end
  ' "$STATE_FILE" 2>/dev/null || true
}

state_task_review_passed() {
  local task_id="$1"
  local review_key="$2"

  jq -e --arg task_id "$task_id" --arg review_key "$review_key" '
    .review.tasks[$task_id][$review_key] == true
  ' "$STATE_FILE" >/dev/null 2>&1
}

task_boundary_agent_gate_active() {
  local active_task_id
  active_task_id="$(state_active_task_id)"
  if [ -n "$active_task_id" ]; then
    return 0
  fi

  if state_is_true '.workflow.active' \
    && state_is_true '.worktree.created' \
    && state_is_true '.worktree.baseline_verified'; then
    return 0
  fi

  return 1
}

is_supported_packet_role() {
  local packet_role="$1"
  case "$packet_role" in
    implementer|spec-reviewer|code-reviewer)
      return 0
      ;;
  esac

  return 1
}

canonical_workflow_artifact_type() {
  local path="$1"
  local hook_cwd="${2:-}"
  local project_relative=""

  project_relative="$(workflow_paths_normalize_project_relative_path "$path" "$PROJECT_DIR" "$hook_cwd")"
  if [ -z "$project_relative" ]; then
    printf 'none\n'
    return
  fi

  workflow_paths_classify_canonical_write "$project_relative"
}

is_spec_or_plan_entry_path() {
  local path="$1"
  [ "$(canonical_workflow_artifact_type "$path")" != "none" ]
}

is_plan_path() {
  local path="$1"
  [ "$(canonical_workflow_artifact_type "$path")" = "plan" ]
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
    normalized_failed="$(normalize_recorded_path "$failed")"
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

if state_is_true '.resume.recovery_required'; then
  if [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Agent" ]; then
    deny_pretool "检测到 resumed 的未完成 superpowers workflow。先执行 /superpowers-flow-enforcer:resume-enforcer 完成恢复摘要，再继续 Edit/Write/Agent。"
    exit 0
  fi
fi

if [ "$TOOL_NAME" = "Agent" ]; then
  if ! task_boundary_agent_gate_active; then
    exit 0
  fi

  packet_metadata=""
  if ! packet_metadata="$(printf '%s' "$INPUT" | task_flow_packets_extract_packet_metadata_raw 2>/dev/null)"; then
    deny_pretool "Agent dispatch 缺少任务包元数据。请在 prompt 开头添加 SPFE_TASK_ID 和 SPFE_PACKET_ROLE。"
    exit 0
  fi

  packet_task_id="$(printf '%s' "$packet_metadata" | jq -r '.task_id // ""')"
  packet_role="$(printf '%s' "$packet_metadata" | jq -r '.role // ""')"
  active_task_id="$(state_active_task_id)"

  if [ -z "$active_task_id" ]; then
    if ! is_supported_packet_role "$packet_role"; then
      deny_pretool "SPFE_PACKET_ROLE=$packet_role 不受支持。仅允许 implementer、spec-reviewer、code-reviewer。"
      exit 0
    fi

    if [ "$packet_role" = "implementer" ]; then
      exit 0
    fi

    deny_pretool "Agent review dispatch requires an active task; no active task is open. Dispatch implementer first with SPFE_PACKET_ROLE=implementer."
    exit 0
  fi

  if ! is_supported_packet_role "$packet_role"; then
    deny_pretool "Current open task $active_task_id only accepts reviewer roles spec-reviewer and code-reviewer. Claude must finish current review loop first for $active_task_id before dispatching SPFE_PACKET_ROLE=$packet_role."
    exit 0
  fi

  if [ "$packet_role" = "implementer" ]; then
    if [ "$packet_task_id" = "$active_task_id" ]; then
      exit 0
    fi

    if state_task_review_passed "$active_task_id" "spec_review_passed" \
      && state_task_review_passed "$active_task_id" "code_review_passed"; then
      exit 0
    fi

    deny_pretool "Current open task $active_task_id is missing review pass(es). Claude must finish current review loop first for $active_task_id before dispatching implementer for $packet_task_id."
    exit 0
  fi

  if [ "$packet_task_id" != "$active_task_id" ]; then
    deny_pretool "Current open task $active_task_id is still in review. Claude must finish current review loop first for $active_task_id before dispatching $packet_role for $packet_task_id."
    exit 0
  fi

  if [ "$packet_role" = "spec-reviewer" ]; then
    exit 0
  fi

  if state_task_review_passed "$active_task_id" "spec_review_passed"; then
    exit 0
  fi

  deny_pretool "Current open task $active_task_id requires spec-reviewer pass before code-reviewer. Claude must finish current review loop first for $active_task_id before dispatching code-reviewer."
  exit 0
fi

if [ "$TOOL_NAME" != "Write" ] && [ "$TOOL_NAME" != "Edit" ]; then
  exit 0
fi

FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')"
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

HOOK_CWD="$(hook_cwd_from_input)"
NORMALIZED_PATH="$(normalize_hook_path "$FILE_PATH" "$HOOK_CWD")"
CANONICAL_WORKFLOW_KIND="$(canonical_workflow_artifact_type "$FILE_PATH" "$HOOK_CWD")"

if [ "$NORMALIZED_PATH" = ".claude/flow_state.json" ]; then
  deny_pretool "禁止直接手改 flow_state.json，请通过 hooks 自动推进状态。"
  exit 0
fi

if ! state_is_true '.workflow.active'; then
  if [ "$CANONICAL_WORKFLOW_KIND" != "none" ]; then
    exit 0
  fi
  exit 0
fi

if [ "$CANONICAL_WORKFLOW_KIND" = "plan" ]; then
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
