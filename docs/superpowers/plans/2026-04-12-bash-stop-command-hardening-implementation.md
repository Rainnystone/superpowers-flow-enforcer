# Bash And Stop Command Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the remaining flaky `PreToolUse:Bash` and `Stop` model-driven hooks with deterministic command hooks. For `PreToolUse:Bash`, adopt the narrower product rule that `.claude/flow_state.json` is private plugin state, so non-helper Bash commands must not mention it directly, but only after the superpower workflow has actually been activated. Across this round, `workflow.active == false` must mean no user-visible enforcement from these gates.

**Architecture:** Keep this round narrow. First migrate `PreToolUse:Bash` to a dedicated command-gate script that enforces state privacy with a simple deterministic rule, but only when `workflow.active == true`: only straightforward approved helper invocation is allowed to coexist with state management, and any other Bash mention of `.claude/flow_state.json` is denied. When the workflow is inactive, the Bash gate must no-op. Then collapse `Stop` into a single conservative command gate by extending the existing stop command script, preserving all current deterministic review/finishing behavior and replacing the prompt-only completion check with a narrow command heuristic over `last_assistant_message`, while keeping the same inactive-workflow no-op boundary.

**Tech Stack:** Claude Code plugin hooks JSON, Bash, `jq`, shell regression tests

---

## AGENTS Task-Splitting Rules

This plan follows `AGENTS.md`:

1. each task owns one primary hook surface
2. each task has one main verification path
3. tasks run serially because they all modify `hooks/hooks.json`
4. each task must finish one TDD loop and one review loop before the next starts
5. no task may widen into unrelated workflow redesign

## File Structure

### Files to modify

- `hooks/hooks.json`
- `scripts/check-stop-review-gate.sh`
- `tests/test_hooks_official_events.sh`
- `tests/test_stop_gates.sh`

### Files to create

- `scripts/check-bash-command-gate.sh`
- `tests/test_bash_command_gate.sh`

### Responsibility map

- `hooks/hooks.json`: final hook inventory and event wiring
- `scripts/check-bash-command-gate.sh`: deterministic `PreToolUse:Bash` command validation
- `scripts/check-stop-review-gate.sh`: final command-only `Stop` gate, including conservative completion-claim checks
- `tests/test_hooks_official_events.sh`: static hook inventory and contract assertions
- `tests/test_bash_command_gate.sh`: focused regression for Bash command gating
- `tests/test_stop_gates.sh`: focused regression for final `Stop` command behavior

## Task 1: Move `PreToolUse:Bash` To Command

**User-facing goal:** `.claude/flow_state.json` is treated as private plugin state only after superpower workflow activation. The Bash hook becomes deterministic and conservative during active workflow: straightforward approved helper invocation is allowed, and any other Bash command that mentions `.claude/flow_state.json` is blocked. Outside active workflow, this gate stays silent.

**Files:**
- Modify: `hooks/hooks.json`
- Create: `scripts/check-bash-command-gate.sh`
- Modify: `tests/test_hooks_official_events.sh`
- Create: `tests/test_bash_command_gate.sh`

- [ ] **Step 1: Write the failing tests**

In `tests/test_hooks_official_events.sh`, add static assertions that fail unless:

```python
assert ('PreToolUse', 'Bash', 'command') in inventory
assert ('PreToolUse', 'Bash', 'prompt') not in inventory
```

Create `tests/test_bash_command_gate.sh` with cases covering:

1. when `workflow.active == false`, Bash mention of `.claude/flow_state.json` is allowed/no-op
2. when `workflow.active == true`, any non-helper Bash mention of `.claude/flow_state.json` is denied
3. straightforward approved helper invocation is allowed
4. unrelated Bash commands that do not mention `.claude/flow_state.json` are allowed
5. helper chaining or helper plus redirection mentioning `.claude/flow_state.json` is denied

Example denial driver:

```bash
OUTPUT="$(
  jq -n --arg cmd 'cat .claude/flow_state.json' '{
    hook_event_name:"PreToolUse",
    tool_name:"Bash",
    tool_input:{command:$cmd}
  }' | bash scripts/check-bash-command-gate.sh
)"
assert_json_equals <(printf '%s' "$OUTPUT") '.hookSpecificOutput.permissionDecision' '"deny"'
```

- [ ] **Step 2: Run the tests to verify RED**

Run:

```bash
bash tests/test_hooks_official_events.sh
bash tests/test_bash_command_gate.sh
```

Expected:

1. static hook inventory fails because `PreToolUse:Bash` is still `prompt`
2. Bash gate test fails because the command script does not exist yet

- [ ] **Step 3: Write the minimal implementation**

Create `scripts/check-bash-command-gate.sh`:

1. read stdin JSON
2. resolve project dir / state file in the same robust way used by adjacent command hooks
3. read `workflow.active`
4. return silent allow when `workflow.active != true`
5. extract `.tool_input.command`
6. deny any non-helper command that mentions `.claude/flow_state.json` once workflow is active
7. allow only straightforward approved helper invocation
8. return the official `PreToolUse` command decision JSON on deny

Minimal deny shape:

```bash
jq -n --arg reason "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'
```

Update `hooks/hooks.json` so `PreToolUse/Bash` calls:

```json
{
  "type": "command",
  "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-bash-command-gate.sh"
}
```

Do not change any other `PreToolUse` matcher in this task.

Implementation note:

1. Do not try to preserve the earlier “allow benign textual mentions” semantics once workflow is active.
2. This task intentionally chooses the simpler product rule because active superpower workflows do not need arbitrary Bash access to hook-managed state.
3. This task must not introduce user-visible enforcement before workflow activation.

- [ ] **Step 4: Run the tests to verify GREEN**

Run:

```bash
bash tests/test_hooks_official_events.sh
bash tests/test_bash_command_gate.sh
```

Expected: PASS

- [ ] **Step 5: Run adjacent non-regression**

Run:

```bash
bash tests/test_pretool_command_gates.sh
```

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add hooks/hooks.json scripts/check-bash-command-gate.sh tests/test_hooks_official_events.sh tests/test_bash_command_gate.sh
git commit -m "fix: move bash pretool gate to command hook"
```

## Task 2: Collapse `Stop` To Conservative Command-Only

**User-facing goal:** `Stop` no longer depends on prompt output stability, while preserving current deterministic stop policy, replacing the freshness check with a conservative command heuristic, and staying silent outside active workflow.

**Files:**
- Modify: `hooks/hooks.json`
- Modify: `scripts/check-stop-review-gate.sh`
- Modify: `tests/test_hooks_official_events.sh`
- Modify: `tests/test_stop_gates.sh`

- [ ] **Step 1: Write the failing tests**

In `tests/test_hooks_official_events.sh`, add static assertions that fail unless:

```python
assert ('Stop', '*', 'command') in inventory
assert ('Stop', '*', 'prompt') not in inventory
```

Extend `tests/test_stop_gates.sh` with command-driven cases for:

1. `stop_hook_active == true` allows
2. `interrupt.allowed == true` allows
3. `workflow.active != true` allows and does not block non-superpower usage
4. missing review records blocks
5. finishing required blocks
6. skip-review confirmed allows
7. skip-finishing confirmed allows
8. non-completion message allows
9. completion-style message without obvious passing verification evidence blocks
10. completion-style message with obvious passing verification evidence allows

Drive the hook with official `Stop` stdin JSON, including `last_assistant_message`.

- [ ] **Step 2: Run the tests to verify RED**

Run:

```bash
bash tests/test_hooks_official_events.sh
bash tests/test_stop_gates.sh
```

Expected:

1. static inventory fails because `Stop` still contains a prompt hook
2. stop behavior tests fail because the current script does not yet cover the final command-only heuristic

- [ ] **Step 3: Write the minimal implementation**

Update `hooks/hooks.json` so `Stop` contains only:

```json
{
  "matcher": "*",
  "hooks": [
    {
      "type": "command",
      "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-stop-review-gate.sh",
      "timeout": 10
    }
  ]
}
```

Extend `scripts/check-stop-review-gate.sh` so it:

1. preserves current deterministic state-driven allow/block logic
2. reads `last_assistant_message` from stdin
3. uses a conservative keyword heuristic for completion claims
4. blocks only when completion-style claims appear without obvious passing verification evidence in the same message
5. allows when obvious passing verification evidence appears
6. keeps `workflow.active != true` as an early allow boundary

Keep the `Stop` event command output contract:

```json
{"decision":"block","reason":"..."}
```

Allow path remains silent `exit 0`.

- [ ] **Step 4: Run the tests to verify GREEN**

Run:

```bash
bash tests/test_hooks_official_events.sh
bash tests/test_stop_gates.sh
```

Expected: PASS

- [ ] **Step 5: Run adjacent non-regression**

Run:

```bash
bash tests/test_interrupt_state.sh
```

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add hooks/hooks.json scripts/check-stop-review-gate.sh tests/test_hooks_official_events.sh tests/test_stop_gates.sh
git commit -m "fix: make stop hook command-only"
```

## Task 3: Final Verification

**User-facing goal:** the plugin no longer relies on prompt stability for `PreToolUse:Bash` or `Stop`, and the current workflow behavior still holds.

**Files:**
- Modify: none unless verification exposes a real defect

- [ ] **Step 1: Run targeted regression pack**

Run:

```bash
bash tests/test_hooks_official_events.sh
bash tests/test_bash_command_gate.sh
bash tests/test_stop_gates.sh
```

Expected: PASS

- [ ] **Step 2: Run adjacent safety coverage**

Run:

```bash
bash tests/test_bypass_state.sh
bash tests/test_interrupt_state.sh
bash tests/test_pretool_command_gates.sh
bash tests/test_posttool_command_gates.sh
bash tests/test_workflow_activation.sh
```

Expected: PASS

- [ ] **Step 3: Confirm hook inventory**

Run:

```bash
if rg -n '"type"\\s*:\\s*"agent"' hooks/hooks.json; then exit 1; fi
```

Expected: no output, exit 0

- [ ] **Step 4: If all green, do not create an extra commit**

Only create a follow-up commit if verification exposes a real defect that needs a fix.

## Review Handoff Notes

Reviewers should evaluate against:

1. `docs/superpowers/specs/2026-04-12-bash-stop-command-hardening-design.md`
2. the explicit out-of-scope rule that this round does not widen workflow policy
3. the requirement that `PreToolUse:Bash` becomes deterministic `command`
4. the requirement that `Stop` becomes conservative `command` rather than reverting to `agent`
