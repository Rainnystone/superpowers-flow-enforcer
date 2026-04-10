#!/bin/bash
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo '{"continue":true,"systemMessage":"jq missing, skip user prompt state sync"}'
  exit 0
fi

if [ -z "${CLAUDE_PROJECT_DIR:-}" ]; then
  echo '{"continue":true}'
  exit 0
fi

STATE_FILE="$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
if [ ! -f "$STATE_FILE" ]; then
  echo '{"continue":true}'
  exit 0
fi

INPUT="$(cat)"
USER_PROMPT="$(echo "$INPUT" | jq -r '.user_prompt // ""')"
PROMPT_LC="$(echo "$USER_PROMPT" | tr '[:upper:]' '[:lower:]')"
NOW_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
tmp_file="${STATE_FILE}.tmp"

phase=""
if echo "$PROMPT_LC" | grep -qE 'skip[[:space:]]+brainstorming|跳过[[:space:]]*brainstorming|不需要[[:space:]]*brainstorming'; then
  phase="brainstorming"
elif echo "$PROMPT_LC" | grep -qE 'skip[[:space:]]+tdd|skip[[:space:]]+test|跳过[[:space:]]*测试|不需要[[:space:]]*测试'; then
  phase="tdd"
elif echo "$PROMPT_LC" | grep -qE 'skip[[:space:]]+review|跳过[[:space:]]*review|不需要[[:space:]]*review'; then
  phase="review"
elif echo "$PROMPT_LC" | grep -qE 'skip[[:space:]]+finishing|跳过[[:space:]]*finishing|不需要[[:space:]]*finishing'; then
  phase="finishing"
fi

if [ -n "$phase" ]; then
  jq --arg phase "$phase" --arg reason "$USER_PROMPT" '.exceptions["skip_" + $phase] = true | .exceptions.reason = $reason | .exceptions.user_confirmed = false | .exceptions.confirmed_at = null' "$STATE_FILE" > "$tmp_file"
  mv "$tmp_file" "$STATE_FILE"
fi

if echo "$PROMPT_LC" | grep -qE '确认|同意|yes|confirm|确定|继续'; then
  has_skip="$(jq -r '.exceptions.skip_brainstorming or .exceptions.skip_tdd or .exceptions.skip_review or .exceptions.skip_finishing' "$STATE_FILE")"
  if [ "$has_skip" = "true" ]; then
    jq --arg now "$NOW_UTC" '.exceptions.user_confirmed = true | .exceptions.confirmed_at = $now' "$STATE_FILE" > "$tmp_file"
    mv "$tmp_file" "$STATE_FILE"
  fi
fi

interrupt_keyword=""
if echo "$PROMPT_LC" | grep -qE '停止|stop|pause|暂停|明天继续|稍后继续|休息一下|break'; then
  interrupt_keyword="detected"
fi

if [ -n "$interrupt_keyword" ]; then
  jq --arg reason "$USER_PROMPT" '.interrupt.allowed = true | .interrupt.reason = $reason | .interrupt.keywords_detected = ((.interrupt.keywords_detected // []) + [$reason] | unique)' "$STATE_FILE" > "$tmp_file"
  mv "$tmp_file" "$STATE_FILE"
fi

echo '{"continue":true}'
