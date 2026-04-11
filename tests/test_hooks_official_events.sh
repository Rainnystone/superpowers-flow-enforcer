#!/bin/bash
set -euo pipefail

source tests/helpers/assert.sh

post_tool_use_matchers="$(jq -r '.hooks.PostToolUse[].matcher' hooks/hooks.json)"

printf '%s\n' "$post_tool_use_matchers" | grep -Fxq 'TaskCompleted' || {
  echo 'Expected PostToolUse to include TaskCompleted' >&2
  exit 1
}

if printf '%s\n' "$post_tool_use_matchers" | grep -Fxq 'TaskUpdate'; then
  echo 'Expected PostToolUse to stop using TaskUpdate' >&2
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

if not model_hooks:
    sys.stderr.write('Expected at least one model-driven hook\n')
    raise SystemExit(1)

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

expected_types = {
    ('UserPromptSubmit', '*'): 'agent',
    ('PreToolUse', 'Edit|Write'): 'agent',
    ('PreToolUse', 'AskUserQuestion'): 'agent',
    ('PreToolUse', 'Bash'): 'prompt',
    ('PostToolUse', 'Write|Edit'): 'agent',
    ('PostToolUse', 'Write'): 'agent',
    ('PostToolUse', 'Bash'): 'agent',
    ('PostToolUse', 'TaskCompleted'): 'agent',
}

for key, expected_type in expected_types.items():
    event_name, matcher = key
    found = [
        hook for hook in model_hooks
        if hook['event'] == event_name and hook['matcher'] == matcher
    ]
    if not found:
        sys.stderr.write(f'Expected model-driven hook for {event_name}/{matcher}\n')
        raise SystemExit(1)
    if any(hook['type'] != expected_type for hook in found):
        actual = ', '.join(sorted({hook['type'] for hook in found}))
        sys.stderr.write(f'Expected {event_name}/{matcher} to use type:{expected_type}, got {actual}\n')
        raise SystemExit(1)

user_prompt_submit_prompt = next(
    hook['prompt'] for hook in model_hooks
    if hook['event'] == 'UserPromptSubmit' and hook['matcher'] == '*'
)
required_user_prompt_fail_open_checks = [
    'If state file is missing or unreadable',
    'do not block on that basis',
    '{"ok": true}',
]
missing_user_prompt_fail_open = [
    needle for needle in required_user_prompt_fail_open_checks
    if needle not in user_prompt_submit_prompt
]
if missing_user_prompt_fail_open:
    sys.stderr.write(
        'Expected UserPromptSubmit prompt to include explicit state-read fail-open branch: '
        + ', '.join(missing_user_prompt_fail_open)
        + '\n'
    )
    raise SystemExit(1)

task_completed_prompt = next(
    hook['prompt'] for hook in model_hooks
    if hook['event'] == 'PostToolUse' and hook['matcher'] == 'TaskCompleted'
)
for required in [
    'review.tasks[task_id].spec_review_passed',
    'review.tasks[task_id].code_review_passed',
]:
    if required not in task_completed_prompt:
        sys.stderr.write(f'Expected TaskCompleted prompt to check {required}\n')
        raise SystemExit(1)

edit_write_prompt = next(
    hook['prompt'] for hook in model_hooks
    if hook['event'] == 'PreToolUse' and hook['matcher'] == 'Edit|Write'
)
try:
    branch4_start = edit_write_prompt.index('(4)')
    branch5_start = edit_write_prompt.index('(5)')
except ValueError:
    sys.stderr.write('Expected PreToolUse/Edit|Write prompt to include explicit numbered branch (4) and (5)\n')
    raise SystemExit(1)

branch4 = edit_write_prompt[branch4_start:branch5_start]
if 'block unless' in branch4:
    sys.stderr.write('Expected PreToolUse/Edit|Write branch (4) to avoid natural-language "block unless"\n')
    raise SystemExit(1)
if '{"ok": false, "reason":' not in branch4:
    sys.stderr.write('Expected PreToolUse/Edit|Write branch (4) to return explicit deny schema {"ok": false, "reason": "..."}\n')
    raise SystemExit(1)

stop_model_hooks = [hook for hook in model_hooks if hook['event'] == 'Stop']
if len(stop_model_hooks) != 2:
    sys.stderr.write('Expected exactly two model-driven Stop hooks\n')
    raise SystemExit(1)
if any(hook['type'] != 'agent' for hook in stop_model_hooks):
    sys.stderr.write('Expected both Stop hooks to use type:agent\n')
    raise SystemExit(1)

for hook in [h for h in model_hooks if h['type'] == 'agent']:
    prompt = hook['prompt']
    if 'Parse $ARGUMENTS' not in prompt:
        sys.stderr.write(f"Expected agent hook {hook['event']}/{hook['matcher']} to explicitly parse $ARGUMENTS\n")
        raise SystemExit(1)

state_agent_keys = {
    ('UserPromptSubmit', '*'),
    ('PreToolUse', 'Edit|Write'),
    ('PreToolUse', 'AskUserQuestion'),
    ('PostToolUse', 'Write|Edit'),
    ('PostToolUse', 'Write'),
    ('PostToolUse', 'Bash'),
    ('PostToolUse', 'TaskCompleted'),
}

for key in state_agent_keys:
    event_name, matcher = key
    agent_hooks = [
        hook for hook in model_hooks
        if hook['event'] == event_name and hook['matcher'] == matcher and hook['type'] == 'agent'
    ]
    for hook in agent_hooks:
        prompt = hook['prompt']
        if 'derive the state path' not in prompt:
            sys.stderr.write(f"Expected {event_name}/{matcher} to derive the state path from $ARGUMENTS\n")
            raise SystemExit(1)
        if 'read the referenced state file' not in prompt:
            sys.stderr.write(f"Expected {event_name}/{matcher} to read the referenced state file\n")
            raise SystemExit(1)

transcript_stop_hooks = [
    hook for hook in stop_model_hooks
    if 'completion keywords appear' in hook['prompt']
]
if len(transcript_stop_hooks) != 1:
    sys.stderr.write('Expected exactly one Stop hook to perform transcript-based completion-evidence checks\n')
    raise SystemExit(1)

for hook in transcript_stop_hooks:
    prompt = hook['prompt']
    if 'derive the state path' not in prompt or 'read the referenced state file' not in prompt:
        sys.stderr.write('Expected transcript-based Stop hook to derive/read state path from $ARGUMENTS\n')
        raise SystemExit(1)
    if 'derive the transcript path' not in prompt or 'read the referenced transcript file' not in prompt:
        sys.stderr.write('Expected transcript-based Stop hook to derive/read transcript path from $ARGUMENTS\n')
        raise SystemExit(1)
    if 'fresh passing verification evidence' not in prompt:
        sys.stderr.write('Expected transcript-based Stop hook to check fresh passing verification evidence\n')
        raise SystemExit(1)
    if 'interrupt.allowed' not in prompt:
        sys.stderr.write('Expected transcript-based Stop hook to check interrupt.allowed\n')
        raise SystemExit(1)

state_only_stop_hooks = [hook for hook in stop_model_hooks if hook not in transcript_stop_hooks]
if len(state_only_stop_hooks) != 1:
    sys.stderr.write('Expected exactly one state-only Stop hook\n')
    raise SystemExit(1)

for hook in state_only_stop_hooks:
    prompt = hook['prompt']
    if 'derive the state path' not in prompt or 'read the referenced state file' not in prompt:
        sys.stderr.write('Expected state-only Stop hook to derive/read state path from $ARGUMENTS\n')
        raise SystemExit(1)
    if 'derive the transcript path' in prompt or 'read the referenced transcript file' in prompt:
        sys.stderr.write('Expected state-only Stop hook to avoid unnecessary transcript coupling\n')
        raise SystemExit(1)
    if 'finishing.invoked' not in prompt:
        sys.stderr.write('Expected state-only Stop hook to check finishing.invoked\n')
        raise SystemExit(1)
    if 'interrupt.allowed' not in prompt:
        sys.stderr.write('Expected state-only Stop hook to check interrupt.allowed\n')
        raise SystemExit(1)

bash_prompt = next(
    hook['prompt'] for hook in model_hooks
    if hook['event'] == 'PreToolUse' and hook['matcher'] == 'Bash'
)
if '$ARGUMENTS' not in bash_prompt:
    sys.stderr.write('Expected PreToolUse/Bash prompt hook to use $ARGUMENTS\n')
    raise SystemExit(1)
if 'derive the state path' in bash_prompt or 'read the referenced state file' in bash_prompt:
    sys.stderr.write('Expected PreToolUse/Bash prompt hook to avoid file inspection behavior\n')
    raise SystemExit(1)
PY
