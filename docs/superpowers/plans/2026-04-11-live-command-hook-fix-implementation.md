# Live Command Hook Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the live Claude Code hook issues so installed plugin sessions parse official hook input correctly, bootstrap state reliably, and only enforce workflow gates after the session has actually entered the superpowers workflow.

**Architecture:** Keep the current plugin architecture and patch only the live failure path. Add a small activation latch in state, fix command-hook stdin parsing and directory fallback in Bash scripts, and update hook prompts so workflow-specific enforcement fails open when the workflow is not active.

**Tech Stack:** Claude Code plugin hooks JSON, Bash, `jq`, shell regression tests

---

## AGENTS Task-Splitting Rules

This plan follows `AGENTS.md` task discipline:

1. each task has one primary objective
2. each task owns one main code surface
3. each task has one default verification path
4. tasks are serial unless proven safe to parallelize
5. no task widens into unrelated workflow redesign

## File Structure

### Existing files to modify

- `templates/flow_state.json.tmpl`
- `scripts/init-state.sh`
- `scripts/sync-user-prompt-state.sh`
- `scripts/sync-post-tool-state.sh`
- `hooks/hooks.json`
- `tests/helpers/state-fixtures.sh`
- `tests/test_init_state.sh`
- `tests/test_bypass_state.sh`
- `tests/test_interrupt_state.sh`
- `tests/test_hooks_official_events.sh`

### New files to create

- `tests/test_workflow_activation.sh`

### Responsibility map

- `templates/flow_state.json.tmpl`: default state including workflow activation latch
- `scripts/init-state.sh`: resolve project directory, initialize state from official command-hook inputs, and normalize readable existing state that lacks `.workflow`
- `scripts/sync-user-prompt-state.sh`: parse official `UserPromptSubmit` input, bootstrap missing state, and update bypass / interrupt state
- `scripts/sync-post-tool-state.sh`: activate workflow on explicit superpower entry artifacts
- `hooks/hooks.json`: ensure gates only apply when workflow enforcement is active
- `tests/*`: regression coverage for official stdin shape, activation, and fail-open behavior

## Task 1: Add Workflow Activation State and SessionStart Fallback

**User-facing goal:** The plugin should initialize or normalize a valid state file in real Claude Code sessions even when `$CLAUDE_PROJECT_DIR` is missing, and the resulting state should start inactive until the user actually enters the superpowers workflow.

**Owned files:** `templates/flow_state.json.tmpl`, `scripts/init-state.sh`, `tests/helpers/state-fixtures.sh`, `tests/test_init_state.sh`

**Default verification:** `bash tests/test_init_state.sh`

**Parallel-safe:** No. This task establishes the state shape used by every later packet.

**Files:**
- Modify: `templates/flow_state.json.tmpl`
- Modify: `scripts/init-state.sh`
- Modify: `tests/helpers/state-fixtures.sh`
- Modify: `tests/test_init_state.sh`

- [ ] **Step 1: Write the failing tests for official `SessionStart` input and readable v2 backfill**

```bash
unset CLAUDE_PROJECT_DIR
export CLAUDE_PLUGIN_ROOT="$(pwd)"

SESSION_CWD="$TMP_DIR/project"
mkdir -p "$SESSION_CWD"

printf '{"hook_event_name":"SessionStart","cwd":"%s"}' "$SESSION_CWD" \
  | bash scripts/init-state.sh >/dev/null

assert_file_exists "$SESSION_CWD/.claude/flow_state.json"
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.workflow.active' 'false'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.project_dir' "\"$SESSION_CWD\""
```

Also add a readable existing-state case:

```bash
write_v2_state_without_workflow "$SESSION_CWD/.claude/flow_state.json"

printf '{"hook_event_name":"SessionStart","cwd":"%s"}' "$SESSION_CWD" \
  | bash scripts/init-state.sh >/dev/null

assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.state_version' '2'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.workflow.active' 'false'
assert_json_equals "$SESSION_CWD/.claude/flow_state.json" '.workflow.activated_by' 'null'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_init_state.sh`  
Expected: FAIL because `init-state.sh` only reads `$CLAUDE_PROJECT_DIR`, the template lacks `workflow.active`, and readable existing v2 state is not backfilled

- [ ] **Step 3: Implement minimal state and fallback changes**

```json
"workflow": {
  "active": false,
  "activated_by": null,
  "activated_at": null
}
```

```bash
INPUT="$(cat || true)"
CWD_FROM_INPUT="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJECT_DIR" ]; then
  PROJECT_DIR="$CWD_FROM_INPUT"
fi
if [ -z "$PROJECT_DIR" ]; then
  PROJECT_DIR="${PWD:-$(pwd)}"
fi
```

For readable existing state files missing `.workflow`, normalize in place instead of resetting:

```bash
jq '
  if (.workflow // null) == null then
    .workflow = {
      "active": false,
      "activated_by": null,
      "activated_at": null
    }
  else
    .
  end
' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
```

- [ ] **Step 4: Re-run the test**

Run: `bash tests/test_init_state.sh`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add templates/flow_state.json.tmpl scripts/init-state.sh tests/helpers/state-fixtures.sh tests/test_init_state.sh
git commit -m "fix: initialize and normalize workflow state"
```

## Task 2: Fix `UserPromptSubmit` Parsing and Self-Heal Missing State

**User-facing goal:** Real Claude Code prompts should correctly trigger bypass and interrupt detection, and the plugin should recover if `SessionStart` did not create the state file first.

**Owned files:** `scripts/sync-user-prompt-state.sh`, `tests/test_bypass_state.sh`, `tests/test_interrupt_state.sh`

**Default verification:** `bash tests/test_bypass_state.sh && bash tests/test_interrupt_state.sh`

**Parallel-safe:** No. This task depends on the Task 1 state shape and bootstrap behavior.

**Files:**
- Modify: `scripts/sync-user-prompt-state.sh`
- Modify: `tests/test_bypass_state.sh`
- Modify: `tests/test_interrupt_state.sh`

- [ ] **Step 1: Write the failing tests using official `UserPromptSubmit` input**

```bash
unset CLAUDE_PROJECT_DIR
export CLAUDE_PLUGIN_ROOT="$(pwd)"

printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"skip planning - spec approved"}' "$TMP_DIR/project" \
  | bash scripts/sync-user-prompt-state.sh >/dev/null

assert_json_equals "$TMP_DIR/project/.claude/flow_state.json" '.exceptions.skip_planning' 'true'
assert_json_equals "$TMP_DIR/project/.claude/flow_state.json" '.workflow.active' 'true'
```

```bash
printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"暂停，明天继续"}' "$TMP_DIR/project" \
  | bash scripts/sync-user-prompt-state.sh >/dev/null

assert_json_equals "$TMP_DIR/project/.claude/flow_state.json" '.interrupt.allowed' 'true'
assert_json_equals "$TMP_DIR/project/.claude/flow_state.json" '.interrupt.reason' '"暂停，明天继续"'
assert_json_equals "$TMP_DIR/project/.claude/flow_state.json" '.workflow.active' 'false'
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test_bypass_state.sh && bash tests/test_interrupt_state.sh`  
Expected: FAIL because the script reads `.user_prompt`, requires an existing state file, and cannot resolve the project dir from `cwd`

- [ ] **Step 3: Implement official parsing and state bootstrap**

```bash
INPUT="$(cat || true)"
USER_PROMPT="$(printf '%s' "$INPUT" | jq -r '.prompt // ""' 2>/dev/null || true)"
CWD_FROM_INPUT="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJECT_DIR" ]; then
  PROJECT_DIR="$CWD_FROM_INPUT"
fi
if [ -z "$PROJECT_DIR" ]; then
  PROJECT_DIR="${PWD:-$(pwd)}"
fi

STATE_FILE="$PROJECT_DIR/.claude/flow_state.json"
if [ ! -f "$STATE_FILE" ]; then
  CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "${CLAUDE_PLUGIN_ROOT}/scripts/init-state.sh" >/dev/null
fi
```

When a skip request is recorded, also set:

```bash
.workflow.active = true
| .workflow.activated_by = "user_prompt_skip"
| .workflow.activated_at = $now
```

- [ ] **Step 4: Re-run the tests**

Run: `bash tests/test_bypass_state.sh && bash tests/test_interrupt_state.sh`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/sync-user-prompt-state.sh tests/test_bypass_state.sh tests/test_interrupt_state.sh
git commit -m "fix: parse official user prompt hook input"
```

## Task 3: Activate Workflow Only on Explicit Superpower Entry Signals

**User-facing goal:** Ordinary Claude Code sessions should remain untouched; workflow enforcement should start only after explicit superpower-aligned entry signals.

**Owned files:** `scripts/sync-post-tool-state.sh`, `tests/test_workflow_activation.sh`

**Default verification:** `bash tests/test_workflow_activation.sh`

**Parallel-safe:** No. This task depends on the new state fields from Task 1 and the prompt-side behavior from Task 2.

**Files:**
- Modify: `scripts/sync-post-tool-state.sh`
- Create: `tests/test_workflow_activation.sh`

- [ ] **Step 1: Write the failing activation tests**

```bash
write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"docs/superpowers/specs/2026-04-11-demo.md"}}' \
  | bash scripts/sync-post-tool-state.sh >/dev/null

assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.workflow.active' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.workflow.activated_by' '"spec_write"'
```

Add the plan-write path too:

```bash
write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"docs/superpowers/plans/2026-04-11-demo.md"}}' \
  | bash scripts/sync-post-tool-state.sh >/dev/null

assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.workflow.active' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.workflow.activated_by' '"plan_write"'
```

Also include a negative check for unrelated writes:

```bash
write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"README.md"}}' \
  | bash scripts/sync-post-tool-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.workflow.active' 'false'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_workflow_activation.sh`  
Expected: FAIL because `workflow.active` is never updated

- [ ] **Step 3: Implement activation on explicit artifacts**

For spec writes:

```bash
.current_phase = "brainstorming"
| .workflow.active = true
| .workflow.activated_by = "spec_write"
| .workflow.activated_at = $now
```

For plan writes:

```bash
.current_phase = "planning"
| .workflow.active = true
| .workflow.activated_by = "plan_write"
| .workflow.activated_at = $now
```

Do not activate on unrelated prompts or generic tool usage.

- [ ] **Step 4: Re-run the test**

Run: `bash tests/test_workflow_activation.sh`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/sync-post-tool-state.sh tests/test_workflow_activation.sh
git commit -m "fix: activate enforcement only on workflow entry"
```

## Task 4: Gate Hooks on `workflow.active` and Add Safe `Stop` Fallback

**User-facing goal:** If the user never entered the superpowers workflow, the plugin should not block ordinary work. If state is missing, `Stop` should not invent a fake review requirement.

**Owned files:** `hooks/hooks.json`, `tests/test_hooks_official_events.sh`

**Default verification:** `bash tests/test_hooks_official_events.sh`

**Parallel-safe:** No. This task consumes the activation behavior introduced by Tasks 1-3.

**Files:**
- Modify: `hooks/hooks.json`
- Modify: `tests/test_hooks_official_events.sh`

- [ ] **Step 1: Write the failing hook assertions**

Add static assertions that:

1. the main `PreToolUse Edit|Write` prompt explicitly allows canonical `docs/superpowers/specs/*.md` and `docs/superpowers/plans/*.md` writes before workflow activation
2. the main `PreToolUse Edit|Write` prompt checks `workflow.active` only after those explicit workflow-entry artifact paths are exempted
3. the `AskUserQuestion` gate checks `workflow.active`
4. the `TaskCompleted` gate checks `workflow.active`
5. the second `Stop` prompt approves when state is missing/unreadable or `workflow.active` is false
6. the first `Stop` prompt still requires fresh verification evidence from transcript-based completion claims

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_hooks_official_events.sh`  
Expected: FAIL because the current prompts enforce review/finishing regardless of workflow activation and can still block plan-file entry before activation

- [ ] **Step 3: Implement minimal prompt changes**

For `PreToolUse Edit|Write`:

```text
... after flow_state protection, explicitly allow canonical docs/superpowers/specs/*.md and docs/superpowers/plans/*.md writes, then if workflow.active is not true, return allow ...
```

For `AskUserQuestion`:

```text
If workflow.active is not true, return continue true.
```

For `TaskCompleted`:

```text
If workflow.active is not true, return continue true.
```

For the first `Stop` prompt:

```text
If state file is missing or unreadable, ignore state-based checks here and only evaluate transcript-based completion evidence.
```

For the second `Stop` prompt:

```text
If state file is missing or unreadable, return approve.
If workflow.active is not true, return approve.
```

- [ ] **Step 4: Re-run the test**

Run: `bash tests/test_hooks_official_events.sh`  
Expected: PASS

- [ ] **Step 5: Run the full regression suite**

Run:

```bash
bash tests/test_init_state.sh && \
bash tests/test_bypass_state.sh && \
bash tests/test_interrupt_state.sh && \
bash tests/test_workflow_activation.sh && \
bash tests/test_hooks_official_events.sh && \
bash tests/test_brainstorming_findings_flow.sh && \
bash tests/test_recorded_review_flow.sh && \
bash tests/test_worktree_baseline_flow.sh && \
bash tests/test_post_tool_use_failure.sh
```

Expected: all tests PASS

- [ ] **Step 6: Commit**

```bash
git add hooks/hooks.json tests/test_hooks_official_events.sh
git commit -m "fix: gate enforcement on active workflow state"
```

## Final Verification

- [ ] Run the full regression suite again from a clean tree
- [ ] Verify the install target still loads the same `hooks/hooks.json` and scripts after reload
- [ ] Confirm no changes were made outside the scoped live-hook fix surface

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-11-live-command-hook-fix-implementation.md`. Two execution options:

1. Subagent-Driven (recommended) - I dispatch a fresh subagent per task, review between tasks, fast iteration
2. Inline Execution - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
