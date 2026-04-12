#!/bin/bash
set -euo pipefail

source tests/helpers/assert.sh

post_tool_use_matchers="$(jq -r '.hooks.PostToolUse[].matcher' hooks/hooks.json)"

if printf '%s\n' "$post_tool_use_matchers" | grep -Fxq 'TaskUpdate'; then
  echo 'Expected PostToolUse to stop using TaskUpdate' >&2
  exit 1
fi

user_prompt_hook_count="$(jq '.hooks.UserPromptSubmit[0].hooks | length' hooks/hooks.json)"
if [ "$user_prompt_hook_count" -ne 1 ]; then
  echo "Expected UserPromptSubmit to have exactly one hook, got $user_prompt_hook_count" >&2
  exit 1
fi

user_prompt_hook_type="$(jq -r '.hooks.UserPromptSubmit[0].hooks[0].type // ""' hooks/hooks.json)"
if [ "$user_prompt_hook_type" != "command" ]; then
  echo "Expected UserPromptSubmit to use command hook, got $user_prompt_hook_type" >&2
  exit 1
fi

user_prompt_hook_command="$(jq -r '.hooks.UserPromptSubmit[0].hooks[0].command // ""' hooks/hooks.json)"
if [ "$user_prompt_hook_command" != 'bash ${CLAUDE_PLUGIN_ROOT}/scripts/sync-user-prompt-state.sh' ]; then
  echo "Expected UserPromptSubmit command hook to call scripts/sync-user-prompt-state.sh" >&2
  exit 1
fi

python3 - <<'PY'
import json
import sys
from pathlib import Path

hooks = json.loads(Path('hooks/hooks.json').read_text(encoding='utf-8'))['hooks']

forbidden_placeholders = {
    '$USER_PROMPT',
    '$TOOL_INPUT.file_path',
    '$TOOL_INPUT.command',
    '$TRANSCRIPT_PATH',
}

forbidden_response_keys = {
    '"continue"',
    '"decision"',
    '"systemMessage"',
    '"hookSpecificOutput"',
}

model_hooks = []
for event_name, groups in hooks.items():
    for group in groups:
        matcher = group.get('matcher', '*')
        for index, hook in enumerate(group.get('hooks', [])):
            hook_type = hook.get('type')
            if hook_type in {'prompt', 'agent'}:
                model_hooks.append({
                    'event': event_name,
                    'matcher': matcher,
                    'index': index,
                    'type': hook_type,
                    'prompt': hook.get('prompt', ''),
                })

for hook in model_hooks:
    prompt = hook['prompt']
    if '{"ok": true}' not in prompt:
        sys.stderr.write(f"Expected {hook['event']}/{hook['matcher']} to include allow schema {{\"ok\": true}}\n")
        raise SystemExit(1)
    if '{"ok": false, "reason":' not in prompt:
        sys.stderr.write(f"Expected {hook['event']}/{hook['matcher']} to include block schema {{\"ok\": false, \"reason\": ...}}\n")
        raise SystemExit(1)

    bad_placeholders = [token for token in forbidden_placeholders if token in prompt]
    if bad_placeholders:
        sys.stderr.write(
            f"Expected {hook['event']}/{hook['matcher']} to stop using pseudo-placeholders: {', '.join(bad_placeholders)}\n"
        )
        raise SystemExit(1)

    bad_keys = [token for token in forbidden_response_keys if token in prompt]
    if bad_keys:
        sys.stderr.write(
            f"Expected {hook['event']}/{hook['matcher']} to stop using command-hook output keys: {', '.join(bad_keys)}\n"
        )
        raise SystemExit(1)

    if hook['type'] == 'prompt' and '$ARGUMENTS' not in prompt:
        sys.stderr.write(f"Expected prompt hook {hook['event']}/{hook['matcher']} to rely on $ARGUMENTS\n")
        raise SystemExit(1)

stop_model_hooks = [
    hook for hook in model_hooks
    if hook['event'] == 'Stop'
]
if stop_model_hooks:
    actual = ', '.join(sorted({hook['type'] for hook in stop_model_hooks}))
    sys.stderr.write(f'Expected Stop to stop using model-driven hooks, got {actual}\n')
    raise SystemExit(1)

inventory = {
    (event_name, group.get('matcher', '*'), hook.get('type', ''))
    for event_name, groups in hooks.items()
    for group in groups
    for hook in group.get('hooks', [])
}

if ('PreToolUse', 'Edit|Write', 'command') not in inventory:
    sys.stderr.write('Expected PreToolUse/Edit|Write to use command hook\n')
    raise SystemExit(1)
if ('PreToolUse', 'AskUserQuestion', 'command') not in inventory:
    sys.stderr.write('Expected PreToolUse/AskUserQuestion to use command hook\n')
    raise SystemExit(1)
if ('PreToolUse', 'Bash', 'command') not in inventory:
    sys.stderr.write('Expected PreToolUse/Bash to use command hook\n')
    raise SystemExit(1)
if ('PreToolUse', 'Bash', 'prompt') in inventory:
    sys.stderr.write('Expected PreToolUse/Bash to stop using prompt hook\n')
    raise SystemExit(1)
if ('PreToolUse', 'Edit|Write', 'agent') in inventory:
    sys.stderr.write('Expected PreToolUse/Edit|Write to stop using agent hook\n')
    raise SystemExit(1)
if ('PreToolUse', 'AskUserQuestion', 'agent') in inventory:
    sys.stderr.write('Expected PreToolUse/AskUserQuestion to stop using agent hook\n')
    raise SystemExit(1)
for matcher in ('Write|Edit', 'Write', 'Bash'):
    if ('PostToolUse', matcher, 'agent') in inventory:
        sys.stderr.write(f'Expected PostToolUse/{matcher} to stop using agent hook\n')
        raise SystemExit(1)
if ('PostToolUse', 'TaskCompleted', 'agent') in inventory:
    sys.stderr.write('Expected PostToolUse/TaskCompleted to stop using agent hook\n')
    raise SystemExit(1)
if ('TaskCompleted', '*', 'command') not in inventory:
    sys.stderr.write('Expected TaskCompleted/* to use command hook\n')
    raise SystemExit(1)
if ('TaskCompleted', '*', 'agent') in inventory:
    sys.stderr.write('Expected TaskCompleted/* to stop using agent hook\n')
    raise SystemExit(1)
if ('Stop', '*', 'agent') in inventory:
    sys.stderr.write('Expected Stop/* to stop using agent hook\n')
    raise SystemExit(1)
if ('Stop', '*', 'command') not in inventory:
    sys.stderr.write('Expected Stop/* to include a command hook\n')
    raise SystemExit(1)

pretool_entries = {
    group.get('matcher', '*'): group.get('hooks', [])
    for group in hooks.get('PreToolUse', [])
}
bash_pretool_hooks = pretool_entries.get('Bash', [])
if len(bash_pretool_hooks) != 1:
    sys.stderr.write('Expected PreToolUse/Bash to have exactly one hook\n')
    raise SystemExit(1)
bash_pretool_hook = bash_pretool_hooks[0]
if bash_pretool_hook.get('type') != 'command':
    sys.stderr.write('Expected PreToolUse/Bash hook type to be command\n')
    raise SystemExit(1)
if bash_pretool_hook.get('command') != 'bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-bash-command-gate.sh':
    sys.stderr.write('Expected PreToolUse/Bash command hook to call scripts/check-bash-command-gate.sh\n')
    raise SystemExit(1)
if 'prompt' in bash_pretool_hook:
    sys.stderr.write('Expected PreToolUse/Bash to stop using prompt hook wiring\n')
    raise SystemExit(1)
for matcher in ('Edit|Write', 'AskUserQuestion'):
    group_hooks = pretool_entries.get(matcher, [])
    if len(group_hooks) != 1:
        sys.stderr.write(f'Expected PreToolUse/{matcher} to have exactly one hook\n')
        raise SystemExit(1)
    hook = group_hooks[0]
    if hook.get('type') != 'command':
        sys.stderr.write(f'Expected PreToolUse/{matcher} hook type to be command\n')
        raise SystemExit(1)
    if hook.get('command') != 'bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-pretool-gates.sh':
        sys.stderr.write(f'Expected PreToolUse/{matcher} command hook to call scripts/check-pretool-gates.sh\n')
        raise SystemExit(1)

posttool_entries = {
    group.get('matcher', '*'): group.get('hooks', [])
    for group in hooks.get('PostToolUse', [])
}
posttool_all_hooks = posttool_entries.get('*', [])
if len(posttool_all_hooks) != 1:
    sys.stderr.write('Expected PostToolUse/* to have exactly one hook\n')
    raise SystemExit(1)
posttool_hook = posttool_all_hooks[0]
if posttool_hook.get('type') != 'command':
    sys.stderr.write('Expected PostToolUse/* hook type to be command\n')
    raise SystemExit(1)
if posttool_hook.get('command') != 'bash ${CLAUDE_PLUGIN_ROOT}/scripts/sync-post-tool-state.sh':
    sys.stderr.write('Expected PostToolUse/* command hook to call scripts/sync-post-tool-state.sh\n')
    raise SystemExit(1)
for matcher in ('Write|Edit', 'Write', 'Bash'):
    group_hooks = posttool_entries.get(matcher, [])
    if group_hooks:
        sys.stderr.write(f'Expected PostToolUse/{matcher} to be removed and handled inside sync-post-tool-state.sh\n')
        raise SystemExit(1)
if posttool_entries.get('TaskCompleted', []):
    sys.stderr.write('Expected PostToolUse/TaskCompleted to be removed after top-level TaskCompleted migration\n')
    raise SystemExit(1)

task_completed_entries = hooks.get('TaskCompleted', [])
if len(task_completed_entries) != 1:
    sys.stderr.write('Expected exactly one TaskCompleted hook group\n')
    raise SystemExit(1)
task_completed_hooks = task_completed_entries[0].get('hooks', [])
if len(task_completed_hooks) != 1:
    sys.stderr.write('Expected TaskCompleted/* to have exactly one hook\n')
    raise SystemExit(1)
task_completed_hook = task_completed_hooks[0]
if task_completed_hook.get('type') != 'command':
    sys.stderr.write('Expected TaskCompleted/* hook type to be command\n')
    raise SystemExit(1)
if task_completed_hook.get('command') != 'bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-task-completed.sh':
    sys.stderr.write('Expected TaskCompleted/* command hook to call scripts/check-task-completed.sh\n')
    raise SystemExit(1)

stop_entries = hooks.get('Stop', [])
if len(stop_entries) != 1:
    sys.stderr.write('Expected exactly one Stop hook group\n')
    raise SystemExit(1)

stop_hooks = stop_entries[0].get('hooks', [])
if len(stop_hooks) != 1:
    sys.stderr.write('Expected Stop/* to have exactly one hook\n')
    raise SystemExit(1)

stop_command = stop_hooks[0]
if stop_command.get('type') != 'command':
    sys.stderr.write('Expected Stop/* hook type to be command\n')
    raise SystemExit(1)
if stop_command.get('command') != 'bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-stop-review-gate.sh':
    sys.stderr.write('Expected Stop command hook to call scripts/check-stop-review-gate.sh\n')
    raise SystemExit(1)
PY
