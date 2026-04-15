#!/bin/bash
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

INPUT="$(cat)"

if ! printf '%s' "$INPUT" | jq empty >/dev/null 2>&1; then
  exit 0
fi

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
  hook_cwd="$(printf '%s' "$INPUT" | jq -r '
    if (.cwd | type) == "string" and .cwd != "" then
      .cwd
    else
      empty
    end
  ' 2>/dev/null || true)"
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

PROJECT_DIR="$(resolve_project_dir)"
STATE_FILE="$PROJECT_DIR/.claude/flow_state.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_STATE_SCRIPT="$SCRIPT_DIR/init-state.sh"

bootstrap_state_if_missing() {
  if [ -f "$STATE_FILE" ]; then
    return
  fi

  printf '%s' "$INPUT" | CLAUDE_PROJECT_DIR="$PROJECT_DIR" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$INIT_STATE_SCRIPT" >/dev/null
}

state_is_readable() {
  [ -f "$STATE_FILE" ] && jq empty "$STATE_FILE" >/dev/null 2>&1
}

bootstrap_state_if_missing

if ! state_is_readable; then
  exit 0
fi

USER_PROMPT="$(printf '%s' "$INPUT" | jq -r '.prompt // ""' 2>/dev/null || true)"
if [ "$(printf '%s' "$INPUT" | jq -r '(.prompt | type) == "string"' 2>/dev/null || echo "false")" != "true" ]; then
  USER_PROMPT=""
fi

normalize_prompt_text() {
  printf '%s' "$1" | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//'
}

split_manual_control_clauses() {
  local text="$1"
  text="${text//，/$'\n'}"
  text="${text//,/$'\n'}"
  text="${text//。/$'\n'}"
  text="${text//！/$'\n'}"
  text="${text//!/$'\n'}"
  text="${text//？/$'\n'}"
  text="${text//\?/$'\n'}"
  text="${text//；/$'\n'}"
  text="${text//;/$'\n'}"
  text="${text//：/$'\n'}"
  text="${text//:/$'\n'}"
  printf '%s\n' "$text"
}

is_manual_control_clause_start() {
  case "$1" in
    ""|请|请先|先|然后|再|接着|随后|请再|麻烦|麻烦请|请帮我|请直接|please|please\ just|just|then|and\ then|now)
      return 0
      ;;
  esac

  return 1
}

is_manual_control_clause_continuation() {
  case "$1" in
    ""|然后*|再*|接着*|随后*|继续*|谢谢*|多谢*|谢啦*|thanks*|thx*|thank\ you*|and\ continue*|and\ return*|and\ then*|and\ stop*|stop*|please*)
      return 0
      ;;
  esac

  return 1
}

is_manual_control_clause_explanatory() {
  case "$1" in
    *不要*|*别*|*不是*|*如果*|*假如*|*说明*|*解释*|*含义*|*意思*|*例子*|*举例*|*比如*|*例如*|*会做什么*|*什么意思*|*do\ not*|*don\'t*|*not*|*if*|*suppose*|*explain*|*meaning*|*example*|*for\ example*|*what\ will*|*what\ does*|*what\ happens*|*what\ would*)
      return 0
      ;;
  esac

  return 1
}

matches_manual_control_phrase() {
  local phrase="$1"
  local clauses=()
  local clause

  while IFS= read -r clause; do
    clause="$(normalize_prompt_text "$clause")"
    if [ -n "$clause" ]; then
      clauses+=("$clause")
    fi
  done < <(split_manual_control_clauses "$PROMPT_LC")

  local clause_index
  for clause_index in "${!clauses[@]}"; do
    clause="${clauses[$clause_index]}"
    case "$clause" in
      *"$phrase"*) ;;
      *)
        continue
        ;;
    esac

    local prefix
    local suffix
    prefix="$(normalize_prompt_text "${clause%%"$phrase"*}")"
    suffix="$(normalize_prompt_text "${clause#*"$phrase"}")"

    if is_manual_control_clause_explanatory "$prefix" || is_manual_control_clause_explanatory "$suffix"; then
      continue
    fi

    if [ -n "$prefix" ]; then
      if ! is_manual_control_clause_start "$prefix"; then
        continue
      fi
    elif [ "$clause_index" -gt 0 ]; then
      local prev_clause
      prev_clause="${clauses[$((clause_index - 1))]}"
      prev_clause="$(normalize_prompt_text "$prev_clause")"

      if is_manual_control_clause_explanatory "$prev_clause"; then
        continue
      fi

      if ! is_manual_control_clause_start "$prev_clause" && ! is_manual_control_clause_continuation "$prev_clause"; then
        continue
      fi
    fi

    if [ -n "$suffix" ]; then
      if is_manual_control_clause_continuation "$suffix"; then
        return 0
      fi
      continue
    fi

    if [ "$clause_index" -lt $((${#clauses[@]} - 1)) ]; then
      local next_clause
      next_clause="${clauses[$((clause_index + 1))]}"
      next_clause="$(normalize_prompt_text "$next_clause")"
      if is_manual_control_clause_continuation "$next_clause"; then
        return 0
      fi
      continue
    fi

    return 0
  done

  return 1
}

PROMPT_NORMALIZED="$(normalize_prompt_text "$USER_PROMPT")"
PROMPT_LC="$(printf '%s' "$PROMPT_NORMALIZED" | tr '[:upper:]' '[:lower:]')"
NOW_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
tmp_file="${STATE_FILE}.tmp"

record_interrupt_if_requested() {
  if echo "$PROMPT_LC" | grep -qE '停止|stop|pause|暂停|明天继续|稍后继续|休息一下|break'; then
    jq --arg reason "$USER_PROMPT" '.interrupt.allowed = true | .interrupt.reason = $reason | del(.interrupt.keywords_detected)' "$STATE_FILE" > "$tmp_file"
    mv "$tmp_file" "$STATE_FILE"
  fi
}

normalize_confirmation_phase() {
  case "$1" in
    tdd|test|测试)
      echo "tdd"
      ;;
    *)
      echo "$1"
      ;;
  esac
}

emit_skip_block_json() {
  local guidance_phase="$1"
  if [ "$guidance_phase" = "tdd" ]; then
    guidance_phase="tdd（或 test/测试）"
  fi

  jq -n --arg phase "$guidance_phase" '{
    decision: "block",
    reason: ("检测到跳过流程请求。请先明确确认：确认跳过 " + $phase + "。确认后可选补充原因。")
  }'
}

is_manual_deactivate_prompt() {
  matches_manual_control_phrase "关闭 superpowers enforcer" || matches_manual_control_phrase "deactivate superpowers enforcer" || matches_manual_control_phrase "关闭 enforcer" || matches_manual_control_phrase "disable enforcer"
}

is_manual_activate_prompt() {
  matches_manual_control_phrase "激活 superpowers enforcer" || matches_manual_control_phrase "activate superpowers enforcer" || matches_manual_control_phrase "开启 enforcer" || matches_manual_control_phrase "enable enforcer"
}

confirmation_phase=""
if [[ "$PROMPT_LC" =~ ^confirm[[:space:]]+skip[[:space:]]+(brainstorming|planning|tdd|test|review|finishing)([[:space:]].*)?$ ]]; then
  confirmation_phase="$(normalize_confirmation_phase "${BASH_REMATCH[1]}")"
elif [[ "$PROMPT_LC" =~ ^确认跳过[[:space:]]*(brainstorming|planning|tdd|test|测试|review|finishing)([[:space:]].*)?$ ]]; then
  confirmation_phase="$(normalize_confirmation_phase "${BASH_REMATCH[1]}")"
fi

pending_phase="$(jq -r '.exceptions.pending_confirmation_for // ""' "$STATE_FILE")"
if [ -n "$confirmation_phase" ]; then
  if [ -n "$pending_phase" ] && [ "$confirmation_phase" = "$pending_phase" ]; then
    jq --arg now "$NOW_UTC" '.exceptions.user_confirmed = true | .exceptions.confirmed_at = $now' "$STATE_FILE" > "$tmp_file"
    mv "$tmp_file" "$STATE_FILE"
  fi

  record_interrupt_if_requested

  exit 0
fi

phase=""
if echo "$PROMPT_LC" | grep -qE 'skip[[:space:]]+brainstorming|跳过[[:space:]]*brainstorming|不需要[[:space:]]*brainstorming'; then
  phase="brainstorming"
elif echo "$PROMPT_LC" | grep -qE 'skip[[:space:]]+planning|跳过[[:space:]]*planning|不需要[[:space:]]*planning'; then
  phase="planning"
elif echo "$PROMPT_LC" | grep -qE 'skip[[:space:]]+tdd|skip[[:space:]]+test|跳过[[:space:]]*测试|不需要[[:space:]]*测试'; then
  phase="tdd"
elif echo "$PROMPT_LC" | grep -qE 'skip[[:space:]]+review|跳过[[:space:]]*review|不需要[[:space:]]*review'; then
  phase="review"
elif echo "$PROMPT_LC" | grep -qE 'skip[[:space:]]+finishing|跳过[[:space:]]*finishing|不需要[[:space:]]*finishing'; then
  phase="finishing"
fi

if is_manual_deactivate_prompt; then
  jq --arg now "$NOW_UTC" '
    .workflow.active = false
    | .workflow.override = "manual_off"
    | .workflow.deactivated_by = "manual_prompt"
    | .workflow.deactivated_at = $now
    | .interrupt.allowed = false
    | .interrupt.reason = null
    | .interrupt.keywords_detected = []
  ' "$STATE_FILE" > "$tmp_file"
  mv "$tmp_file" "$STATE_FILE"
  exit 0
fi

if is_manual_activate_prompt; then
  jq --arg now "$NOW_UTC" '
    .workflow.active = true
    | .workflow.override = "manual_on"
    | .workflow.activated_by = "manual_prompt"
    | .workflow.activated_at = $now
    | .workflow.deactivated_by = null
    | .workflow.deactivated_at = null
    | .interrupt.allowed = false
    | .interrupt.reason = null
    | .interrupt.keywords_detected = []
  ' "$STATE_FILE" > "$tmp_file"
  mv "$tmp_file" "$STATE_FILE"
  exit 0
fi

if [ -n "$phase" ]; then
  jq --arg phase "$phase" --arg reason "$USER_PROMPT" --arg now "$NOW_UTC" '
    .exceptions.skip_brainstorming = false
    | .exceptions.skip_planning = false
    | .exceptions.skip_tdd = false
    | .exceptions.skip_review = false
    | .exceptions.skip_finishing = false
    | .exceptions["skip_" + $phase] = true
    | .exceptions.pending_confirmation_for = $phase
    | .exceptions.reason = $reason
    | .exceptions.user_confirmed = false
    | .exceptions.confirmed_at = null
    | .workflow.override = null
    | .workflow.active = true
    | .workflow.activated_by = "user_prompt_skip"
    | .workflow.activated_at = $now
    | .workflow.deactivated_by = null
    | .workflow.deactivated_at = null
  ' "$STATE_FILE" > "$tmp_file"
  mv "$tmp_file" "$STATE_FILE"

  record_interrupt_if_requested

  pending_after_skip="$(jq -r '.exceptions.pending_confirmation_for // ""' "$STATE_FILE" 2>/dev/null || true)"
  user_confirmed_after_skip="$(jq -r '.exceptions.user_confirmed // false' "$STATE_FILE" 2>/dev/null || true)"
  if [ "$pending_after_skip" != "$phase" ] || [ "$user_confirmed_after_skip" != "true" ]; then
    emit_skip_block_json "$phase"
    exit 0
  fi
fi

record_interrupt_if_requested

exit 0
