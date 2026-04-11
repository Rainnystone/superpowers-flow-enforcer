# Agent Hook Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove all active Claude Code `agent` hooks from this plugin to fix the current `Messages are required for agent hooks` runtime failure, while preserving the existing workflow rules.

**Architecture:** Keep the existing state-sync scripts, but move all deterministic stateful gates to `command` hooks using the official command-hook output contract for each event. Avoid same-event sibling ordering assumptions by folding `PostToolUse` gating into `sync-post-tool-state.sh` itself, instead of adding a second command hook that reads the same state file. In this refactor, the `PostToolUse` gate checks run after state mutation inside that script, and that ordering is acceptable because every current `PostToolUse` gate is defined against the post-mutation state. Leave only input-only semantic checks as `prompt` hooks, with a single remaining `Stop` prompt that evaluates `last_assistant_message`.

**Tech Stack:** Claude Code plugin hooks JSON, Bash, `jq`, shell regression tests

---

## Event Output Contracts

This plan uses the official Claude Code command-hook contract for each event. These schemas are event-specific and must not be mixed:

1. `UserPromptSubmit`
   - block with top-level `{"decision":"block","reason":"..."}`
   - allow by exiting 0 without blocking JSON
2. `PreToolUse`
   - deny with `hookSpecificOutput.permissionDecision = "deny"`
   - allow by exiting 0 without deny JSON
3. `PostToolUse`
   - block with top-level `{"decision":"block","reason":"..."}`
   - allow by exiting 0 without blocking JSON
4. `TaskCompleted`
   - for this fix, use `exit 2` plus stderr to block completion
   - do not use top-level `decision:"block"` here
5. `Stop`
   - block with top-level `{"decision":"block","reason":"..."}`
   - allow by exiting 0 without blocking JSON

## AGENTS Task-Splitting Rules

This plan follows `AGENTS.md`:

1. each task owns one primary hook surface
2. each task has one main verification path
3. tasks run serially because they all modify `hooks/hooks.json`
4. every task uses a TDD loop before implementation
5. every task ends with a focused commit

## File Structure

### Files to modify

- `hooks/hooks.json`
- `scripts/sync-user-prompt-state.sh`
- `tests/test_hooks_official_events.sh`
- `tests/test_bypass_state.sh`
- `tests/test_interrupt_state.sh`

### Files to create

- `scripts/check-pretool-gates.sh`
- `scripts/check-task-completed.sh`
- `scripts/check-stop-review-gate.sh`
- `tests/test_pretool_command_gates.sh`
- `tests/test_posttool_command_gates.sh`
- `tests/test_stop_gates.sh`

### Responsibility map

- `hooks/hooks.json`: final hook inventory, hook type changes, command/prompt wiring
- `scripts/sync-user-prompt-state.sh`: `UserPromptSubmit` state sync plus direct block/allow for skip confirmation
- `scripts/check-pretool-gates.sh`: deterministic `PreToolUse` stateful gates
- `scripts/sync-post-tool-state.sh`: `PostToolUse` / `PostToolUseFailure` state mutation plus deterministic `PostToolUse` gating
- `scripts/check-task-completed.sh`: deterministic `TaskCompleted` completion gate
- `scripts/check-stop-review-gate.sh`: deterministic `Stop` review/finishing state gate
- `tests/test_hooks_official_events.sh`: static hook inventory and prompt-contract assertions
- focused new tests: command-hook behavior for each migrated gate family

## Task 1: Remove Agent From UserPromptSubmit

**User-facing goal:** skip requests still require confirmation, malformed or unreadable state still fails open, and `UserPromptSubmit` no longer depends on `agent`.

**Files:**
- Modify: `hooks/hooks.json`
- Modify: `scripts/sync-user-prompt-state.sh`
- Modify: `tests/test_hooks_official_events.sh`
- Modify: `tests/test_bypass_state.sh`
- Modify: `tests/test_interrupt_state.sh`

- [ ] **Step 1: Write the failing tests**

Update `tests/test_hooks_official_events.sh` to fail unless:

```python
assert ('UserPromptSubmit', '*', 'agent') not in inventory
assert ('UserPromptSubmit', '*', 'command') in inventory
```

Extend `tests/test_bypass_state.sh` with command-hook behavior checks:

```bash
OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"skip planning"}' "$CLAUDE_PROJECT_DIR" \
    | bash scripts/sync-user-prompt-state.sh
)"
assert_json_equals <(printf '%s' "$OUTPUT") '.decision' '"block"'
assert_json_equals <(printf '%s' "$OUTPUT") '.reason | contains("确认跳过")' 'true'
```

And keep the malformed-state case as fail-open:

```bash
[ "$BROKEN_STATUS" -eq 0 ]
[ -z "$BROKEN_OUTPUT" ] || printf '%s' "$BROKEN_OUTPUT" | jq empty >/dev/null 2>&1
```

- [ ] **Step 2: Run the tests to verify RED**

Run:
```bash
bash tests/test_hooks_official_events.sh
bash tests/test_bypass_state.sh
```

Expected:
- hook inventory test fails because `UserPromptSubmit` still uses `agent`
- bypass test fails because the command script does not yet return block JSON

- [ ] **Step 3: Implement the minimal fix**

In `hooks/hooks.json`:

```json
{
  "matcher": "*",
  "hooks": [
    {
      "type": "command",
      "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/sync-user-prompt-state.sh",
      "timeout": 10
    }
  ]
}
```

In `scripts/sync-user-prompt-state.sh`, after state sync:

```bash
if [ -n "$phase" ] && [ "${confirmation_phase:-}" = "" ]; then
  jq -n '{
    decision: "block",
    reason: "检测到跳过流程请求。请先明确确认：确认跳过 <phase>，并给出原因。"
  }'
  exit 0
fi
```

The block branch must `exit 0` immediately after printing the block JSON. It must not fall through to the script's trailing allow output such as `echo '{"continue":true}'`, because a command-hook path must emit only the single JSON object for that branch.

Keep these behaviors:

1. malformed JSON input => allow / no-op
2. unreadable state => allow / no-op
3. interrupt keyword recording still happens
4. confirmed skip still allows
5. `UserPromptSubmit` command output uses the official event contract for this event only:
   - block with top-level `{"decision":"block","reason":"..."}`
   - allow by exiting 0 with no blocking JSON

- [ ] **Step 4: Run the tests to verify GREEN**

Run:
```bash
bash tests/test_hooks_official_events.sh
bash tests/test_bypass_state.sh
bash tests/test_interrupt_state.sh
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add hooks/hooks.json scripts/sync-user-prompt-state.sh tests/test_hooks_official_events.sh tests/test_bypass_state.sh tests/test_interrupt_state.sh
git commit -m "fix: remove agent hook from user prompt submit"
```

## Task 2: Move Stateful PreToolUse Gates To Command

**User-facing goal:** write gates and brainstorming-question gate still enforce the same workflow rules, but no longer rely on `agent`.

**Files:**
- Modify: `hooks/hooks.json`
- Create: `scripts/check-pretool-gates.sh`
- Modify: `tests/test_hooks_official_events.sh`
- Create: `tests/test_pretool_command_gates.sh`

- [ ] **Step 1: Write the failing tests**

Add static assertions in `tests/test_hooks_official_events.sh`:

```python
assert ('PreToolUse', 'Edit|Write', 'command') in inventory
assert ('PreToolUse', 'AskUserQuestion', 'command') in inventory
assert ('PreToolUse', 'Edit|Write', 'agent') not in inventory
assert ('PreToolUse', 'AskUserQuestion', 'agent') not in inventory
assert ('PreToolUse', 'Bash', 'prompt') in inventory
```

Create `tests/test_pretool_command_gates.sh` with cases like:

```bash
OUTPUT="$(
  jq -n --arg path "src/app.ts" '{hook_event_name:"PreToolUse",tool_name:"Write",tool_input:{file_path:$path}}' \
    | bash scripts/check-pretool-gates.sh
)"
assert_json_equals <(printf '%s' "$OUTPUT") '.hookSpecificOutput.permissionDecision' '"deny"'
```

Cover:

1. deny direct `.claude/flow_state.json` edits
2. allow workflow entry artifacts before activation
3. deny plan writes before spec review/user approval
4. deny production writes before `spec_written`
5. deny production writes when `worktree.created` / `baseline_verified` missing
6. deny production writes when `tdd.pending_failure_record == true`
7. allow test-like paths
8. deny brainstorming `AskUserQuestion` when findings update is missing

- [ ] **Step 2: Run the tests to verify RED**

Run:
```bash
bash tests/test_hooks_official_events.sh
bash tests/test_pretool_command_gates.sh
```

Expected: FAIL because the command script and hook wiring do not exist yet

- [ ] **Step 3: Implement the minimal fix**

Create `scripts/check-pretool-gates.sh` with:

```bash
INPUT="$(cat)"
TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')"

deny_pretool() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
}
```

Implement deterministic branches using current state fields only. Keep `PreToolUse/Bash` as the existing `prompt` hook.

Use the official `PreToolUse` command contract only:

```bash
deny_pretool "reason"
# =>
# {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"reason"}}
```

Wire `hooks/hooks.json` to:

```json
{
  "matcher": "Edit|Write",
  "hooks": [
    {
      "type": "command",
      "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-pretool-gates.sh",
      "timeout": 10
    }
  ]
}
```

and similarly for `AskUserQuestion`.

- [ ] **Step 4: Run the tests to verify GREEN**

Run:
```bash
bash tests/test_hooks_official_events.sh
bash tests/test_pretool_command_gates.sh
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add hooks/hooks.json scripts/check-pretool-gates.sh tests/test_hooks_official_events.sh tests/test_pretool_command_gates.sh
git commit -m "fix: move pre tool state gates to command hooks"
```

## Task 3: Move Stateful PostToolUse And TaskCompleted Gates To Command

**User-facing goal:** post-write, post-plan, post-worktree, and task-completion review gates keep their current behavior without `agent` and without relying on same-event hook ordering.

**Files:**
- Modify: `hooks/hooks.json`
- Modify: `scripts/sync-post-tool-state.sh`
- Create: `scripts/check-task-completed.sh`
- Modify: `tests/test_hooks_official_events.sh`
- Create: `tests/test_posttool_command_gates.sh`

- [ ] **Step 1: Write the failing tests**

Add static assertions:

```python
for matcher in ('Write|Edit', 'Write', 'Bash'):
    assert ('PostToolUse', matcher, 'agent') not in inventory
assert ('TaskCompleted', '*', 'command') in inventory
assert ('TaskCompleted', '*', 'agent') not in inventory
```

Create `tests/test_posttool_command_gates.sh` with cases for:

1. deny after spec write when `brainstorming.spec_reviewed != true`
2. deny after plan write when `worktree.created != true`
3. deny after `git worktree add` when `worktree.baseline_verified != true`
4. deny `TaskCompleted` when either review stage is missing using the official `TaskCompleted` payload fields:
   - `task_id`
   - `task_subject`
   - optional `task_description`, `teammate_name`, `team_name`
   - no completion-status field is expected
5. allow these cases when state is satisfied

Use top-level block JSON for `PostToolUse`:

```bash
assert_json_equals <(printf '%s' "$OUTPUT") '.decision' '"block"'
```

For `TaskCompleted`, pin the official payload and control mode:

```bash
STATUS=0
OUTPUT_FILE="$TMP_DIR/task-completed.out"
ERROR_FILE="$TMP_DIR/task-completed.err"

set +e
jq -n --arg task_id "task-001" '{
  hook_event_name:"TaskCompleted",
  task_id:$task_id,
  task_subject:"demo"
}' | bash scripts/check-task-completed.sh >"$OUTPUT_FILE" 2>"$ERROR_FILE"
STATUS=$?
set -e

[ "$STATUS" -eq 2 ]
grep -q '必须完成两阶段 review' "$ERROR_FILE"
```

And assert the script does not depend on a fictitious completion-status field.

- [ ] **Step 2: Run the tests to verify RED**

Run:
```bash
bash tests/test_hooks_official_events.sh
bash tests/test_posttool_command_gates.sh
```

Expected: FAIL

- [ ] **Step 3: Implement the minimal fix**

Keep a single `PostToolUse` command hook and extend `scripts/sync-post-tool-state.sh` so it:

1. mutates state as it already does
2. computes any required normalized path or worktree information itself
3. executes `PostToolUse` gate checks after mutation, using the just-updated state
4. emits top-level `{"decision":"block","reason":"..."}` only for the matched `PostToolUse` gating cases
5. does not rely on a sibling hook reading the just-mutated state

This ordering is intentional and must be preserved because every current `PostToolUse` gate is a post-action gate:

1. `Write|Edit` spec gate is evaluated after `brainstorming.spec_written/spec_file` are recorded
2. `Write` plan gate is evaluated after `planning.plan_written/plan_file` are recorded
3. `Bash` worktree gate is evaluated after `worktree.created/path/baseline_verified` are updated

If implementation uncovers any `PostToolUse` gate that truly depends on pre-mutation state, stop and revise the plan instead of silently mixing pre- and post-mutation semantics in the same script.

Create `scripts/check-task-completed.sh` with the official `TaskCompleted` control mode:

```bash
INPUT="$(cat)"
TASK_ID="$(printf '%s' "$INPUT" | jq -r '.task_id // ""')"

resolve_project_dir() {
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    printf '%s\n' "$CLAUDE_PROJECT_DIR"
    return
  fi
  printf '%s' "$INPUT" | jq -r '.cwd // ""'
}

PROJECT_DIR="$(resolve_project_dir)"
STATE_FILE="$PROJECT_DIR/.claude/flow_state.json"

if [ -z "$TASK_ID" ]; then
  echo "TaskCompleted missing task_id" >&2
  exit 2
fi

if [ -z "$PROJECT_DIR" ] || ! jq empty "$STATE_FILE" >/dev/null 2>&1; then
  exit 0
fi

if ! jq -e --arg task_id "$TASK_ID" '
  .review.tasks[$task_id].spec_review_passed == true
  and .review.tasks[$task_id].code_review_passed == true
' "$STATE_FILE" >/dev/null 2>&1; then
  echo "Task 标记完成前，必须完成两阶段 review。" >&2
  exit 2
fi
```

This task explicitly uses the official `TaskCompleted` command control for “block completion but keep teammate running”:

1. block with `exit 2` and stderr
2. do not use top-level `decision:"block"`
3. do not require any completion-status field that is absent from the official payload
4. resolve project/state via `CLAUDE_PROJECT_DIR` first, then `cwd` from hook input
5. unreadable or missing state stays fail-open, matching current state-dependent gate behavior

Wire `hooks/hooks.json` so:

1. `PostToolUse` keeps one command hook for `sync-post-tool-state.sh`
2. `TaskCompleted` becomes its own top-level `type:"command"` hook entry

- [ ] **Step 4: Run the tests to verify GREEN**

Run:
```bash
bash tests/test_hooks_official_events.sh
bash tests/test_posttool_command_gates.sh
```

Expected: PASS

- [ ] **Step 5: Re-run adjacent state-sync coverage**

Run:
```bash
bash tests/test_workflow_activation.sh
bash tests/test_worktree_baseline_flow.sh
bash tests/test_recorded_review_flow.sh
```

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add hooks/hooks.json scripts/sync-post-tool-state.sh scripts/check-task-completed.sh tests/test_hooks_official_events.sh tests/test_posttool_command_gates.sh
git commit -m "fix: move post tool state gates to command hooks"
```

## Task 4: Remove Agent From Stop While Preserving Both Gates

**User-facing goal:** `Stop` still blocks unsafe completion and still enforces review/finishing state, but no longer depends on `agent`.

**Files:**
- Modify: `hooks/hooks.json`
- Create: `scripts/check-stop-review-gate.sh`
- Modify: `tests/test_hooks_official_events.sh`
- Create: `tests/test_stop_gates.sh`

- [ ] **Step 1: Write the failing tests**

Update static assertions so:

```python
assert ('Stop', '*', 'agent') not in inventory
assert stop_prompt_count == 1
assert ('Stop', '*', 'command') in inventory
```

Require the remaining `Stop` prompt to reference `last_assistant_message` and not reference transcript-file reads:

```python
require(text, 'last_assistant_message', label)
forbid(text, 'read the referenced transcript file', label)
forbid(text, 'derive the transcript path', label)
```

Create `tests/test_stop_gates.sh` with:

1. command gate allows when `stop_hook_active == true`
2. command gate allows when `interrupt.allowed == true`
3. command gate allows when `workflow.active != true`
4. command gate allows when `exceptions.skip_review` and `exceptions.user_confirmed` are both true
5. command gate allows when `exceptions.skip_finishing` and `exceptions.user_confirmed` are both true
6. command gate blocks when review records are missing
7. command gate blocks when finishing is still required
8. prompt gate text is input-only and keyed to `last_assistant_message`
9. unreadable state follows the current allow/no-op behavior for the stateful `Stop` gate
10. prompt-contract coverage for the freshness rule includes both:
   - a negative branch: completion claim without fresh passing verification evidence => block
   - a positive branch: completion claim with fresh passing verification evidence in `last_assistant_message` => allow

- [ ] **Step 2: Run the tests to verify RED**

Run:
```bash
bash tests/test_hooks_official_events.sh
bash tests/test_stop_gates.sh
```

Expected: FAIL

- [ ] **Step 3: Implement the minimal fix**

Create `scripts/check-stop-review-gate.sh`:

```bash
INPUT="$(cat)"

if [ "$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false')" = "true" ]; then
  exit 0
fi

resolve_project_dir() {
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    printf '%s\n' "$CLAUDE_PROJECT_DIR"
    return
  fi
  printf '%s' "$INPUT" | jq -r '.cwd // ""'
}

PROJECT_DIR="$(resolve_project_dir)"
STATE_FILE="$PROJECT_DIR/.claude/flow_state.json"

if [ -z "$PROJECT_DIR" ] || ! jq empty "$STATE_FILE" >/dev/null 2>&1; then
  exit 0
fi

block_stop() {
  jq -n --arg reason "$1" '{decision:"block", reason:$reason}'
}
```

Implement the deterministic review/finishing gate in command form, preserving:

1. `workflow.active`
2. `interrupt.allowed`
3. `exceptions.skip_review` + `exceptions.user_confirmed`
4. `exceptions.skip_finishing` + `exceptions.user_confirmed`
5. `review.tasks`
6. `finishing.invoked`
7. unreadable-state allow/no-op behavior
8. state resolution via `CLAUDE_PROJECT_DIR` first, then `cwd` from hook input

Replace the remaining `Stop` prompt text with an input-only prompt that uses `$ARGUMENTS`, `stop_hook_active`, and `last_assistant_message` only:

```text
Parse $ARGUMENTS as JSON. If stop_hook_active is true, return {"ok": true}. Read last_assistant_message from the hook input. If it claims completion but does not include fresh passing verification evidence, return {"ok": false, "reason": "..."}; else return {"ok": true}.
```

Because prompt hooks are not directly executable in local shell tests, verify the freshness rule at the prompt-contract level by asserting that the prompt text encodes both the negative and positive `last_assistant_message` scenarios above.

- [ ] **Step 4: Run the tests to verify GREEN**

Run:
```bash
bash tests/test_hooks_official_events.sh
bash tests/test_stop_gates.sh
bash tests/test_interrupt_state.sh
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add hooks/hooks.json scripts/check-stop-review-gate.sh tests/test_hooks_official_events.sh tests/test_stop_gates.sh
git commit -m "fix: remove agent hooks from stop gates"
```

## Task 5: Final Verification

**User-facing goal:** the plugin no longer depends on `agent` hooks and current workflow behavior still holds.

**Files:**
- Modify: none unless verification exposes a real bug

- [ ] **Step 1: Run the targeted regression pack**

Run:
```bash
bash tests/test_hooks_official_events.sh
bash tests/test_bypass_state.sh
bash tests/test_interrupt_state.sh
bash tests/test_pretool_command_gates.sh
bash tests/test_posttool_command_gates.sh
bash tests/test_stop_gates.sh
```

Expected: PASS

- [ ] **Step 2: Run broader workflow smoke coverage**

Run:
```bash
bash tests/test_init_state.sh
bash tests/test_workflow_activation.sh
bash tests/test_post_tool_use_failure.sh
bash tests/test_recorded_review_flow.sh
bash tests/test_recorded_tdd_flow.sh
bash tests/test_worktree_baseline_flow.sh
```

Expected: PASS

- [ ] **Step 3: Confirm final inventory**

Run:
```bash
jq '[.. | objects | select(.type? == "agent")] | length' hooks/hooks.json
```

Expected:
```text
0
```

- [ ] **Step 4: Commit only if verification forced additional fixes**

If verification required no further code changes, do not create an extra commit.

## Plan Review Handoff Notes

Review against:

1. `docs/superpowers/specs/2026-04-11-agent-hook-removal-design.md`
2. the locked boundary that product rules must not change
3. the explicit inventory requirement that active `agent` hooks go to zero
4. the requirement that `Stop` preserves `stop_hook_active`, interrupt handling, review/finishing blocking, and prompt-based verification from `last_assistant_message`
