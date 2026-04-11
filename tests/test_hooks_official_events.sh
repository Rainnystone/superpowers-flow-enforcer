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

jq -e '
  .hooks.Stop
  | length == 2
  and all(.[]; .hooks[0].prompt | contains("stop_hook_active"))
' hooks/hooks.json >/dev/null || {
  echo 'Expected both Stop prompts to include stop_hook_active' >&2
  exit 1
}

task_completed_prompt="$(jq -r '.hooks.PostToolUse[] | select(.matcher == "TaskCompleted") | .hooks[0].prompt' hooks/hooks.json)"
stop_prompts="$(jq -r '.hooks.Stop[].hooks[0].prompt' hooks/hooks.json)"

TASK_COMPLETED_PROMPT="$task_completed_prompt" STOP_PROMPTS="$stop_prompts" python3 - <<'PY'
import os
import sys

task_prompt = os.environ['TASK_COMPLETED_PROMPT']
stop_prompts = os.environ['STOP_PROMPTS'].splitlines()
first_stop_prompt, second_stop_prompt = stop_prompts

required_task_checks = [
    'review.tasks[task_id].spec_review_passed',
    'review.tasks[task_id].code_review_passed',
]

missing = [needle for needle in required_task_checks if needle not in task_prompt]
if missing:
    sys.stderr.write('Expected TaskCompleted to check recorded review fields: ' + ', '.join(missing) + '\n')
    raise SystemExit(1)

if 'review.tasks[task_id] is missing or not fully passed' in task_prompt:
    sys.stderr.write('Expected TaskCompleted to stop using the generic review.tasks[task_id] gate\n')
    raise SystemExit(1)

if 'If workflow.active is not true, return {"continue": true}' not in task_prompt:
    sys.stderr.write('Expected TaskCompleted to allow completion when workflow.active is not true\n')
    raise SystemExit(1)

if not any('interrupt.allowed' in prompt for prompt in stop_prompts):
    sys.stderr.write('Expected Stop to check interrupt.allowed\n')
    raise SystemExit(1)

if 'completion keywords appear' not in first_stop_prompt or 'fresh passing verification evidence' not in first_stop_prompt:
    sys.stderr.write('Expected first Stop prompt to require transcript-based fresh passing verification evidence\n')
    raise SystemExit(1)

if not any('finishing.invoked' in prompt for prompt in stop_prompts):
    sys.stderr.write('Expected Stop to check finishing.invoked\n')
    raise SystemExit(1)

if any('finishing.skill_invoked' in prompt for prompt in stop_prompts):
    sys.stderr.write('Expected Stop to stop referencing finishing.skill_invoked\n')
    raise SystemExit(1)

required_second_stop_checks = [
    'If state file is missing or unreadable, return {"decision": "approve"}',
    'If workflow.active is not true, return {"decision": "approve"}',
]

missing_second_stop = [needle for needle in required_second_stop_checks if needle not in second_stop_prompt]
if missing_second_stop:
    sys.stderr.write('Expected second Stop prompt to safely approve when workflow state is unavailable or inactive: ' + ', '.join(missing_second_stop) + '\n')
    raise SystemExit(1)
PY

planning_prompt="$(jq -r '.hooks.PreToolUse[] | select(.matcher == "Edit|Write") | .hooks[0].prompt' hooks/hooks.json)"
ask_user_question_prompt="$(jq -r '.hooks.PreToolUse[] | select(.matcher == "AskUserQuestion") | .hooks[0].prompt' hooks/hooks.json)"

PLANNING_PROMPT="$planning_prompt" ASK_USER_QUESTION_PROMPT="$ask_user_question_prompt" python3 - <<'PY'
import os
import sys

prompt = os.environ['PLANNING_PROMPT']
ask_prompt = os.environ['ASK_USER_QUESTION_PROMPT']

try:
    plan_branch_index = prompt.index('If path matches docs/superpowers/plans/*.md')
    docs_allow_index = prompt.index('If path matches docs/config/type/generated exceptions ')
except IndexError:
    sys.stderr.write('Expected the planning prompt to contain both plan-file and broad docs branches\n')
    raise SystemExit(1)

if plan_branch_index > docs_allow_index:
    sys.stderr.write('Expected docs/superpowers/plans/*.md to be checked before the broad docs allow-list\n')
    raise SystemExit(1)

plan_branch = prompt[plan_branch_index:docs_allow_index]

if 'planning.plan_written is not true' in plan_branch:
    sys.stderr.write('Expected plan-file gate to stop using planning.plan_written as a bypass condition\n')
    raise SystemExit(1)

required = [
    'docs/superpowers/plans/*.md',
    'brainstorming.spec_reviewed is true',
    'brainstorming.user_approved_spec is true',
    'exceptions.skip_planning and exceptions.user_confirmed',
    'only skip_planning may bypass this gate',
]

missing = [needle for needle in required if needle not in plan_branch]
if missing:
    sys.stderr.write('Expected planning gate to cover plan-file writes: ' + ', '.join(missing) + '\n')
    raise SystemExit(1)

if 'skip_brainstorming' in plan_branch:
    sys.stderr.write('Expected plan-file gate to avoid skip_brainstorming in the plan branch\n')
    raise SystemExit(1)

required_workflow_entry_allows = [
    'docs/superpowers/specs/*.md',
    'docs/superpowers/plans/*.md',
]

missing_entry_allows = [needle for needle in required_workflow_entry_allows if needle not in prompt]
if missing_entry_allows:
    sys.stderr.write('Expected production-write prompt to explicitly allow canonical workflow-entry artifacts: ' + ', '.join(missing_entry_allows) + '\n')
    raise SystemExit(1)

try:
    artifact_entry_branch = 'If path matches canonical workflow-entry artifacts docs/superpowers/specs/*.md or docs/superpowers/plans/*.md and workflow.active is not true, return allow'
    artifact_entry_index = prompt.index(artifact_entry_branch)
    workflow_active_index = prompt.index('If workflow.active is not true, return allow')
except ValueError:
    sys.stderr.write('Expected production-write prompt to define a pre-activation workflow-entry artifact allow branch before the generic workflow.active allow\n')
    raise SystemExit(1)

if artifact_entry_index > workflow_active_index:
    sys.stderr.write('Expected generic workflow.active allow to run after the pre-activation workflow-entry artifact branch\n')
    raise SystemExit(1)

if 'If workflow.active is not true, return allow' not in prompt:
    sys.stderr.write('Expected production-write prompt to allow writes when workflow.active is not true\n')
    raise SystemExit(1)

artifact_entry_segment = prompt[artifact_entry_index:workflow_active_index]

required_entry_branch_content = [
    'docs/superpowers/specs/*.md',
    'docs/superpowers/plans/*.md',
    'workflow.active is not true',
    'return allow',
]

missing_entry_branch_content = [needle for needle in required_entry_branch_content if needle not in artifact_entry_segment]
if missing_entry_branch_content:
    sys.stderr.write('Expected pre-activation workflow-entry branch to include: ' + ', '.join(missing_entry_branch_content) + '\n')
    raise SystemExit(1)

if workflow_active_index > plan_branch_index:
    sys.stderr.write('Expected docs/superpowers/plans/*.md planning gate to remain separate after the generic workflow.active allow\n')
    raise SystemExit(1)

if 'If workflow.active is not true, return {"continue": true}' not in ask_prompt:
    sys.stderr.write('Expected AskUserQuestion gate to allow when workflow.active is not true\n')
    raise SystemExit(1)

try:
    test_allow_index = prompt.index('If path is test-like')
    pending_failure_index = prompt.index('If tdd.pending_failure_record is true')
    candidate_test_gate_index = prompt.index('Otherwise treat as production file')
except ValueError:
    sys.stderr.write('Expected production-write prompt to include test allow, pending failure record gate, and candidate-test gate\n')
    raise SystemExit(1)

if not (test_allow_index < pending_failure_index < candidate_test_gate_index):
    sys.stderr.write('Expected pending failure record gate to be after test-file allow and before candidate-test production gate\n')
    raise SystemExit(1)

test_allow_gate = prompt[test_allow_index:pending_failure_index]
pending_gate = prompt[pending_failure_index:candidate_test_gate_index]

if 'return allow' not in test_allow_gate:
    sys.stderr.write('Expected test-like branch to explicitly return allow\n')
    raise SystemExit(1)

required_pending_gate_content = [
    'tdd.pending_failure_record is true',
    'record-tdd-state.sh fail <target>',
]

missing_pending = [needle for needle in required_pending_gate_content if needle not in pending_gate]
if missing_pending:
    sys.stderr.write('Expected pending failure gate to instruct explicit failure recording: ' + ', '.join(missing_pending) + '\n')
    raise SystemExit(1)

if '"permissionDecision":"deny"' not in pending_gate:
    sys.stderr.write('Expected pending failure gate to explicitly deny production writes\n')
    raise SystemExit(1)
PY

python3 - <<'PY'
from pathlib import Path
import sys

readme_en = Path('README.md').read_text(encoding='utf-8')
readme_cn = Path('README_cn.md').read_text(encoding='utf-8')
claude_md = Path('CLAUDE.md').read_text(encoding='utf-8')

def require(text: str, needle: str, label: str) -> None:
    if needle not in text:
        sys.stderr.write(f'Expected {label} to contain: {needle}\n')
        raise SystemExit(1)

def forbid(text: str, needle: str, label: str) -> None:
    if needle in text:
        sys.stderr.write(f'Expected {label} to stop containing: {needle}\n')
        raise SystemExit(1)

for label, text in [('README.md', readme_en), ('README_cn.md', readme_cn)]:
    require(text, 'TaskCompleted', label)
    require(text, 'PostToolUseFailure', label)
    forbid(text, 'TaskUpdate', label)
    forbid(text, 'Checked automatically via `check-exception.sh`', label)
    forbid(text, '通过 `check-exception.sh` 自动检查', label)
    forbid(text, 'skill invoked', label)
    forbid(text, 'baseline tests passed', label)
    forbid(text, 'tests verified, choice made', label)
    forbid(text, '测试已验证，已做出选择', label)

for label, text in [('README.md', readme_en), ('README_cn.md', readme_cn), ('CLAUDE.md', claude_md)]:
    require(text, 'text keyword', label)
    forbid(text, 'true user interrupt', label)
PY

python3 - <<'PY'
from pathlib import Path
import sys

readme_en = Path('README.md').read_text(encoding='utf-8')
readme_cn = Path('README_cn.md').read_text(encoding='utf-8')

def require_any(text: str, needles: list[str]) -> None:
    if not any(needle in text for needle in needles):
        raise AssertionError('none matched: ' + ', '.join(needles))

def require_order(text: str, needles: list[str], label: str) -> None:
    indices = []
    for needle in needles:
        idx = text.find(needle)
        if idx < 0:
            sys.stderr.write(f'Expected {label} to contain: {needle}\n')
            raise SystemExit(1)
        indices.append(idx)
    if indices != sorted(indices):
        sys.stderr.write(f'Expected {label} to mention concepts in order: ' + ' -> '.join(needles) + '\n')
        raise SystemExit(1)

readme_en_required = [
    'supplement to',
    'obra/superpowers',
    'planning-with-files',
    'task_plan.md',
    'findings.md',
    'progress.md',
    'Claude Code',
    'GLM-5',
    '128K context window',
]
for needle in readme_en_required:
    if needle not in readme_en:
        sys.stderr.write(f'Expected README.md to contain: {needle}\n')
        raise SystemExit(1)

require_any(readme_en, [
    'designed to be used together with',
    'pairs with',
    'works together with',
    'used together with',
])

require_order(readme_en, ['obra/superpowers', 'planning-with-files', '## Installation'], 'README.md')
for needle in ['brainstorming', 'spec', 'planning', 'execution']:
    if needle not in readme_en:
        sys.stderr.write(f'Expected README.md to mention workflow concept: {needle}\n')
        raise SystemExit(1)

if 'external memory' not in readme_en:
    sys.stderr.write('Expected README.md to describe planning-with-files as external memory\n')
    raise SystemExit(1)

readme_cn_required = [
    '补充',
    'obra/superpowers',
    'planning-with-files',
    'task_plan.md',
    'findings.md',
    'progress.md',
    'Claude Code',
    'GLM-5',
    '128K 上下文窗口',
]
for needle in readme_cn_required:
    if needle not in readme_cn:
        sys.stderr.write(f'Expected README_cn.md to contain: {needle}\n')
        raise SystemExit(1)

require_any(readme_cn, ['配合使用', '一起使用', '共同使用', '搭配使用'])
require_order(readme_cn, ['obra/superpowers', 'planning-with-files', '## 安装'], 'README_cn.md')
for needle in ['brainstorming', 'spec', 'planning', 'execution']:
    if needle not in readme_cn:
        sys.stderr.write(f'Expected README_cn.md to mention workflow concept: {needle}\n')
        raise SystemExit(1)

if '外部记忆' not in readme_cn:
    sys.stderr.write('Expected README_cn.md to describe planning-with-files as external memory\n')
    raise SystemExit(1)
PY
