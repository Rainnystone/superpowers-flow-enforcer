#!/bin/bash
set -euo pipefail

TASK_FLOW_PACKETS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_FLOW_PACKETS_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$TASK_FLOW_PACKETS_SCRIPT_DIR/../.." && pwd)}"
# shellcheck source=lib/platform_compat.sh
source "$TASK_FLOW_PACKETS_PLUGIN_ROOT/scripts/lib/platform_compat.sh"

task_flow_packets_extract_packet_metadata() {
  platform_compat_run_python -c "$(cat <<'PY'
import json
import sys

try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit(1)

hook_event_name = data.get("hook_event_name")
if hook_event_name not in {"PreToolUse", "PostToolUse"}:
    raise SystemExit(1)

tool_name = data.get("tool_name")
if tool_name != "Agent":
    raise SystemExit(1)

tool_input = data.get("tool_input")
if not isinstance(tool_input, dict):
    raise SystemExit(1)

description = tool_input.get("description")
prompt = tool_input.get("prompt")
subagent_type = tool_input.get("subagent_type")
if not isinstance(description, str) or not isinstance(prompt, str) or not isinstance(subagent_type, str):
    raise SystemExit(1)

if not prompt:
    raise SystemExit(1)

lines = prompt.splitlines()
if len(lines) < 3:
    raise SystemExit(1)

task_line, role_line, blank_line = lines[0], lines[1], lines[2]
if blank_line != "":
    raise SystemExit(1)

task_prefix = "SPFE_TASK_ID="
role_prefix = "SPFE_PACKET_ROLE="
if not task_line.startswith(task_prefix) or not role_line.startswith(role_prefix):
    raise SystemExit(1)

task_id = task_line[len(task_prefix):]
role = role_line[len(role_prefix):]
if not task_id or not role:
    raise SystemExit(1)

if role not in {"implementer", "spec-reviewer", "code-reviewer", "code-quality-reviewer"}:
    raise SystemExit(1)

print(json.dumps({"task_id": task_id, "role": role}, separators=(",", ":")))
PY
)"
}

task_flow_packets_extract_packet_metadata_raw() {
  platform_compat_run_python -c "$(cat <<'PY'
import json
import sys

try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit(1)

hook_event_name = data.get("hook_event_name")
if hook_event_name not in {"PreToolUse", "PostToolUse"}:
    raise SystemExit(1)

tool_name = data.get("tool_name")
if tool_name != "Agent":
    raise SystemExit(1)

tool_input = data.get("tool_input")
if not isinstance(tool_input, dict):
    raise SystemExit(1)

description = tool_input.get("description")
prompt = tool_input.get("prompt")
subagent_type = tool_input.get("subagent_type")
if not isinstance(description, str) or not isinstance(prompt, str) or not isinstance(subagent_type, str):
    raise SystemExit(1)

if not prompt:
    raise SystemExit(1)

lines = prompt.splitlines()
if len(lines) < 3:
    raise SystemExit(1)

task_line, role_line, blank_line = lines[0], lines[1], lines[2]
if blank_line != "":
    raise SystemExit(1)

task_prefix = "SPFE_TASK_ID="
role_prefix = "SPFE_PACKET_ROLE="
if not task_line.startswith(task_prefix) or not role_line.startswith(role_prefix):
    raise SystemExit(1)

task_id = task_line[len(task_prefix):]
role = role_line[len(role_prefix):]
if not task_id or not role:
    raise SystemExit(1)

print(json.dumps({"task_id": task_id, "role": role}, separators=(",", ":")))
PY
)"
}

task_flow_packets_taskcreated_matches_official_contract() {
  platform_compat_run_python -c "$(cat <<'PY'
import json
import sys

try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit(1)

if data.get("hook_event_name") != "TaskCreated":
    raise SystemExit(1)

task_id = data.get("task_id")
task_subject = data.get("task_subject")
task_description = data.get("task_description")
teammate_name = data.get("teammate_name")
team_name = data.get("team_name")

if not isinstance(task_id, str) or not task_id:
    raise SystemExit(1)

if not isinstance(task_subject, str) or not task_subject:
    raise SystemExit(1)

for optional_value in [task_description, teammate_name, team_name]:
    if optional_value is not None and not isinstance(optional_value, str):
        raise SystemExit(1)

if "tool_input" in data:
    raise SystemExit(1)

print("ok")
PY
)"
}

task_flow_packets_extract_taskcreated_packet_metadata() {
  platform_compat_run_python -c "$(cat <<'PY'
import json
import sys

try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit(1)

if data.get("hook_event_name") != "TaskCreated":
    raise SystemExit(1)

task_id = data.get("task_id")
task_subject = data.get("task_subject")
task_description = data.get("task_description")

if not isinstance(task_id, str) or not task_id:
    raise SystemExit(1)
if not isinstance(task_subject, str) or not task_subject:
    raise SystemExit(1)
if not isinstance(task_description, str) or not task_description:
    raise SystemExit(1)

if "tool_input" in data:
    raise SystemExit(1)

lines = task_description.splitlines()
if len(lines) < 3:
    raise SystemExit(1)

task_line, role_line, blank_line = lines[0], lines[1], lines[2]
if blank_line != "":
    raise SystemExit(1)

task_prefix = "SPFE_TASK_ID="
role_prefix = "SPFE_PACKET_ROLE="
if not task_line.startswith(task_prefix) or not role_line.startswith(role_prefix):
    raise SystemExit(1)

task_id_from_description = task_line[len(task_prefix):]
role = role_line[len(role_prefix):]
if not task_id_from_description or not role:
    raise SystemExit(1)

if task_id_from_description != task_id:
    raise SystemExit(1)

if role not in {"implementer", "spec-reviewer", "code-reviewer", "code-quality-reviewer"}:
    raise SystemExit(1)

print(json.dumps({"task_id": task_id_from_description, "role": role}, separators=(",", ":")))
PY
)"
}

task_flow_packets_extract_posttool_packet_metadata() {
  platform_compat_run_python -c "$(cat <<'PY'
import json
import sys

try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit(1)

if data.get("hook_event_name") != "PostToolUse":
    raise SystemExit(1)

tool_name = data.get("tool_name")
if tool_name != "Agent":
    raise SystemExit(1)

tool_input = data.get("tool_input")
if not isinstance(tool_input, dict):
    raise SystemExit(1)

description = tool_input.get("description")
prompt = tool_input.get("prompt")
subagent_type = tool_input.get("subagent_type")
if not isinstance(description, str) or not isinstance(prompt, str) or not isinstance(subagent_type, str):
    raise SystemExit(1)

if not prompt:
    raise SystemExit(1)

lines = prompt.splitlines()
if len(lines) < 3:
    raise SystemExit(1)

task_line, role_line, blank_line = lines[0], lines[1], lines[2]
if blank_line != "":
    raise SystemExit(1)

task_prefix = "SPFE_TASK_ID="
role_prefix = "SPFE_PACKET_ROLE="
if not task_line.startswith(task_prefix) or not role_line.startswith(role_prefix):
    raise SystemExit(1)

task_id = task_line[len(task_prefix):]
role = role_line[len(role_prefix):]
if not task_id or not role:
    raise SystemExit(1)

if role not in {"implementer", "spec-reviewer", "code-reviewer", "code-quality-reviewer"}:
    raise SystemExit(1)

print(json.dumps({"task_id": task_id, "role": role}, separators=(",", ":")))
PY
)"
}

task_flow_packets_select_success_event() {
  local taskcreated_file="$1"
  local posttool_file="$2"

  if task_flow_packets_extract_taskcreated_packet_metadata < "$taskcreated_file" >/dev/null 2>&1; then
    printf 'TaskCreated\n'
    return 0
  fi

  if task_flow_packets_extract_posttool_packet_metadata < "$posttool_file" >/dev/null 2>&1; then
    printf 'PostToolUse\n'
    return 0
  fi

  return 1
}
