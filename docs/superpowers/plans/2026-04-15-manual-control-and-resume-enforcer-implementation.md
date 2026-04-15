# Manual Control And Resume Enforcer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement shorter recommended enforcer control phrases, a small explicit interrupt-command surface, and a deterministic `/superpowers-flow-enforcer:resume-enforcer` recovery handshake for resumed unfinished workflows without widening the broader workflow state machine.

**Architecture:** Keep the runtime deterministic. First extend `flow_state.json` with explicit resume metadata and safe normalization/migration rules. Then update `UserPromptSubmit`, `SessionStart`, and `PreToolUse` so manual control, explicit interrupt commands, and resume recovery are driven by observable state only. Finally, add one plugin-bundled recovery skill plus a helper record script, clear `task_flow` on the normal finishing path, and sync the user-facing docs to the new control surface.

**Tech Stack:** Claude Code plugin hooks, Bash, `jq`, shell regression tests, Markdown docs/skills

---

## Scope Check

This spec still describes one subsystem: workflow control and workflow recovery. The shorter control phrases and the resume handshake share the same state file, the same hook surfaces, and the same docs. Keep them in one implementation plan.

Do not widen this implementation into:

1. full workflow state-machine redesign
2. automatic phase advancement during recovery
3. Bash write-equivalence with `Edit|Write`
4. heuristic parsing of free-form recovery intent
5. heuristic parsing of broad natural-language interrupt intent
6. adding any new planning-file directory requirement that conflicts with upstream `planning-with-files` conventions

## AGENTS Task-Splitting Rules

This plan follows `AGENTS.md` and should be executed with `@superpowers:test-driven-development` inside each packet:

1. each task owns one primary runtime surface
2. each task has one main verification command and only a small adjacent non-regression check
3. tasks run serially because they share `flow_state.json` semantics and overlapping shell tests
4. no implementer packet should edit files outside the task’s declared ownership
5. the default execution mode for this plan is serial `@superpowers:subagent-driven-development`

## File Structure

### Files to create

- `skills/resume-enforcer/SKILL.md`
- `scripts/record-resume-state.sh`
- `tests/test_resume_recovery_flow.sh`

### Files to modify

- `templates/flow_state.json.tmpl`
- `scripts/init-state.sh`
- `scripts/migrate-state.sh`
- `scripts/sync-user-prompt-state.sh`
- `scripts/check-pretool-gates.sh`
- `scripts/record-finishing-state.sh`
- `tests/helpers/state-fixtures.sh`
- `tests/test_init_state.sh`
- `tests/test_bypass_state.sh`
- `tests/test_pretool_command_gates.sh`
- `tests/test_agent_task_boundary_gate.sh`
- `tests/test_recorded_review_flow.sh`
- `README.md`
- `README_cn.md`
- `CLAUDE.md`

### Files to verify but not necessarily modify

- `hooks/hooks.json`
- `.claude-plugin/plugin.json`
- `manifest.json`
- `scripts/update-state.sh`
- `tests/test_interrupt_state.sh`
- `tests/test_hooks_official_events.sh`

### Responsibility map

- `templates/flow_state.json.tmpl`: default v2 state schema, now including `resume.*`
- `scripts/init-state.sh`: SessionStart bootstrap, normalization, migration handoff, resume trigger, deterministic clear rules
- `scripts/migrate-state.sh`: v1 -> v2 migration safety for the new `resume` object
- `scripts/sync-user-prompt-state.sh`: manual enforcer control detection and interrupt-priority ordering
- `scripts/check-pretool-gates.sh`: temporary recovery gate for `Edit|Write|Agent`
- `scripts/record-resume-state.sh`: explicit recovery-complete state recorder used by the recovery skill
- `skills/resume-enforcer/SKILL.md`: manual recovery workflow for resumed unfinished sessions
- `scripts/record-finishing-state.sh`: deterministic task-flow closure on the normal finishing path
- `tests/helpers/state-fixtures.sh`: reusable v2 state fixtures, including `resume` variants
- `tests/test_init_state.sh`: state schema, migration, and `SessionStart(source=resume)` regression coverage
- `tests/test_bypass_state.sh`: manual control phrase detection and interrupt-priority regression
- `tests/test_pretool_command_gates.sh`: `Edit|Write` recovery gate regression
- `tests/test_agent_task_boundary_gate.sh`: `Agent` recovery gate regression
- `tests/test_resume_recovery_flow.sh`: record-script contract for successful recovery completion
- `tests/test_recorded_review_flow.sh`: finishing-path task-flow cleanup regression
- `README.md`, `README_cn.md`, `CLAUDE.md`: recommended commands, resume handshake, and state/documentation alignment

## Task 1: Add Resume State Schema, Fixtures, And Migration Safety

**User-facing goal:** Fresh and migrated state files can represent resume-recovery status deterministically, and unsafe old states reset instead of partially guessing.

**Files:**
- Modify: `templates/flow_state.json.tmpl`
- Modify: `scripts/init-state.sh`
- Modify: `scripts/migrate-state.sh`
- Modify: `tests/helpers/state-fixtures.sh`
- Modify: `tests/test_init_state.sh`

- [ ] **Step 1: Write the failing tests**

Extend `tests/test_init_state.sh` so it fails unless a fresh or normalized v2 state includes:

```bash
assert_json_equals "$file" '.resume.recovery_required' 'false'
assert_json_equals "$file" '.resume.recovery_completed_at' 'null'
assert_json_equals "$file" '.resume.last_resume_source' 'null'
```

Add fixture coverage in `tests/helpers/state-fixtures.sh` for:

```bash
write_v2_state_without_resume() { ... }
write_v2_state_with_partial_resume() { ... }
write_v2_state_with_invalid_resume_types() { ... }
```

Keep these helpers layered on top of the existing `write_v2_state` fixture so the new `resume` cases inherit the same canonical v2 baseline as the rest of the test suite.

Also add migration assertions that `bash scripts/migrate-state.sh --check-safe "$file"` accepts only:

1. boolean `resume.recovery_required`
2. string-or-null `resume.recovery_completed_at`
3. string-or-null `resume.last_resume_source`

- [ ] **Step 2: Run the test to verify RED**

Run:

```bash
bash tests/test_init_state.sh
```

Expected: FAIL because the current template, migration safety check, and normalization logic do not define `resume.*`.

- [ ] **Step 3: Write the minimal implementation**

Update `templates/flow_state.json.tmpl` to add:

```json
"resume": {
  "recovery_required": false,
  "recovery_completed_at": null,
  "last_resume_source": null
}
```

Update `scripts/migrate-state.sh` and `scripts/init-state.sh` so:

1. v1 -> v2 migration emits the default `resume` object
2. readable v2 states missing `resume` normalize in place
3. partial `resume` objects normalize in place
4. unsafe `resume` field types trigger backup-and-reset
5. existing workflow and task-flow normalization behavior stays intact

- [ ] **Step 4: Run the test to verify GREEN**

Run:

```bash
bash tests/test_init_state.sh
```

Expected: PASS

- [ ] **Step 5: Run adjacent non-regression**

Run:

```bash
bash tests/test_recorded_review_flow.sh
```

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add templates/flow_state.json.tmpl scripts/init-state.sh scripts/migrate-state.sh tests/helpers/state-fixtures.sh tests/test_init_state.sh
git commit -m "fix: add resume recovery state schema"
```

## Task 2: Add Short Manual Control Phrases And Interrupt Priority

**User-facing goal:** Users can control enforcement with a small exact-command whitelist (`开启/关闭 enforcer`, `enable/disable enforcer`, plus the existing long-form commands), and interrupt intent is reduced to a small exact-command whitelist instead of broad natural-language guessing.

**Files:**
- Modify: `scripts/sync-user-prompt-state.sh`
- Modify: `tests/test_bypass_state.sh`
- Verify: `tests/test_interrupt_state.sh`

- [ ] **Step 1: Write the failing tests**

Extend `tests/test_bypass_state.sh` with accepted prompt cases for:

1. `开启 enforcer`
2. `关闭 enforcer`
3. `enable enforcer`
4. `disable enforcer`

Keep the existing long-form command cases so backward compatibility remains covered.

Extend the interrupt coverage so only these exact prompts are positive:

1. `停止任务`
2. `暂停任务`
3. `stop task`
4. `pause task`

And make representative former broad prompts explicit negatives, such as:

1. `请开启 enforcer`
2. `先整理上下文，然后关闭 enforcer 再继续`
3. `Please enable enforcer, thanks`
4. `disable enforcer and stop for now`
5. `暂停，明天继续`
6. `Please stop for now`
7. `Please stop after this step`

For the control prompts, assert:

```bash
assert_json_equals "$STATE_FILE" '.workflow.override' '"manual_on"'
assert_json_equals "$STATE_FILE" '.workflow.activated_by' '"manual_prompt"'
assert_json_equals "$STATE_FILE" '.interrupt.allowed' 'false'
```

and:

```bash
assert_json_equals "$STATE_FILE" '.workflow.override' '"manual_off"'
assert_json_equals "$STATE_FILE" '.workflow.deactivated_by' '"manual_prompt"'
assert_json_equals "$STATE_FILE" '.interrupt.allowed' 'false'
```

- [ ] **Step 2: Run the test to verify RED**

Run:

```bash
bash tests/test_bypass_state.sh
```

Expected: FAIL because the script still accepts broader clause-style enforcer prompts and still uses broader interrupt detection than the new exact-command contract allows.

- [ ] **Step 3: Write the minimal implementation**

Update `scripts/sync-user-prompt-state.sh` so:

1. `is_manual_activate_prompt` recognizes:

```bash
"激活 superpowers enforcer"
"activate superpowers enforcer"
"开启 enforcer"
"enable enforcer"
```

2. `is_manual_deactivate_prompt` recognizes:

```bash
"关闭 superpowers enforcer"
"deactivate superpowers enforcer"
"关闭 enforcer"
"disable enforcer"
```

3. after normalization, the prompt must equal one of the supported commands; do not keep clause parsing, explanatory heuristics, or partial phrase matching
4. recognized enforcer-control commands are processed before `record_interrupt_if_requested`
5. once a control command matches, the script exits without writing `interrupt.allowed` from the same prompt
6. interrupt recording is reduced to the exact normalized prompts:

```bash
"停止任务"
"暂停任务"
"stop task"
"pause task"
```

7. broader natural-language stop/pause prompts no longer set `interrupt.allowed`
8. former clause-style manual-control prompts such as `Please enable enforcer, thanks` or `disable enforcer and stop for now` no longer mutate state

- [ ] **Step 4: Run the test to verify GREEN**

Run:

```bash
bash tests/test_bypass_state.sh
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
git add scripts/sync-user-prompt-state.sh tests/test_bypass_state.sh
git commit -m "fix: add short enforcer control phrases"
```

## Task 3: Add Resume-Aware SessionStart Trigger And Clear Rules

**User-facing goal:** Resumed unfinished workflow sessions are flagged for recovery immediately, while ordinary startup, inactive workflow sessions, and already-clean closures stay quiet.

**Files:**
- Modify: `scripts/init-state.sh`
- Modify: `tests/test_init_state.sh`
- Verify: `hooks/hooks.json`
- Verify: `tests/test_hooks_official_events.sh`

- [ ] **Step 1: Write the failing tests**

Add `SessionStart` cases in `tests/test_init_state.sh` for JSON input shaped like:

```json
{"hook_event_name":"SessionStart","cwd":"/tmp/project","source":"resume"}
```

Cover these scenarios:

1. progressed active workflow, unfinished review/task state:

```bash
assert_json_equals "$STATE_FILE" '.resume.recovery_required' 'true'
assert_json_equals "$STATE_FILE" '.resume.last_resume_source' '"resume"'
```

2. inactive workflow clears recovery:

```bash
assert_json_equals "$STATE_FILE" '.resume.recovery_required' 'false'
```

3. `workflow.override == "manual_off"` clears recovery
4. cleanly finished workflow (`finishing.invoked == true`, `task_flow.active_task_id == null`, all recorded reviews passed) clears recovery
5. non-resume `SessionStart` does not force recovery merely because old progress exists
6. `SessionStart(source=resume)` emits a short recovery hint that exactly names `/superpowers-flow-enforcer:resume-enforcer` when recovery is required

- [ ] **Step 2: Run the test to verify RED**

Run:

```bash
bash tests/test_init_state.sh
```

Expected: FAIL because `SessionStart` does not yet distinguish `source == "resume"` or compute deterministic recovery-required conditions.

- [ ] **Step 3: Write the minimal implementation**

Update `scripts/init-state.sh` to:

1. read the official `SessionStart.source` field from hook stdin
2. treat these as workflow-progressed signals:

```jq
.current_phase != "init"
or .brainstorming.question_asked == true
or .brainstorming.spec_written == true
or .planning.plan_written == true
or .worktree.created == true
or .task_flow.active_task_id != null
or ((.review.tasks // {}) | length > 0)
or ((.tdd.test_files_created // []) | length > 0)
or ((.tdd.production_files_written // []) | length > 0)
or ((.tdd.tests_verified_fail // []) | length > 0)
or ((.tdd.tests_verified_pass // []) | length > 0)
```

3. treat these as deterministic clear conditions:
   - `.workflow.active != true`
   - `.workflow.override == "manual_off"`
   - clean-finish predicate from the spec
4. persist `resume.recovery_required` across later non-resume starts until a clear condition happens
5. set `resume.last_resume_source = "resume"` only on resume-triggered starts
6. keep the hook fast and keep the existing `hooks/hooks.json` SessionStart wiring unchanged

- [ ] **Step 4: Run the test to verify GREEN**

Run:

```bash
bash tests/test_init_state.sh
```

Expected: PASS

- [ ] **Step 5: Run adjacent non-regression**

Run:

```bash
bash tests/test_hooks_official_events.sh
```

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add scripts/init-state.sh tests/test_init_state.sh
git commit -m "fix: require recovery on resumed unfinished workflows"
```

## Task 4: Add The PreTool Recovery Gate For Edit, Write, And Agent

**User-facing goal:** Once a resumed unfinished workflow has been marked as needing recovery, Claude cannot continue editing files or dispatching new agents until `/superpowers-flow-enforcer:resume-enforcer` succeeds.

**Files:**
- Modify: `scripts/check-pretool-gates.sh`
- Modify: `tests/test_pretool_command_gates.sh`
- Modify: `tests/test_agent_task_boundary_gate.sh`

- [ ] **Step 1: Write the failing tests**

Add gate coverage for:

1. `Write` denied when:

```bash
.workflow.active = true
.resume.recovery_required = true
```

2. `Edit` denied under the same state
3. `Agent` denied under the same state, before same-task/new-task packet logic runs
4. the deny reason contains `/superpowers-flow-enforcer:resume-enforcer`
5. `AskUserQuestion` remains allowed
6. `Bash` remains outside this recovery gate

Reuse explicit state setup instead of transcript inference.

- [ ] **Step 2: Run the test to verify RED**

Run:

```bash
bash tests/test_pretool_command_gates.sh
```

Expected: FAIL because the script does not yet deny `Edit|Write` on `resume.recovery_required`.

- [ ] **Step 3: Write the minimal implementation**

Update `scripts/check-pretool-gates.sh` so the new early gate:

1. reads `resume.recovery_required == true`
2. applies only to the existing `Edit|Write|Agent` command-hook surface
3. runs before TDD or packet-boundary enforcement
4. points users to `/superpowers-flow-enforcer:resume-enforcer`
5. does not expand into `PreToolUse/Bash` in this round

- [ ] **Step 4: Run the test to verify GREEN**

Run:

```bash
bash tests/test_pretool_command_gates.sh
```

Expected: PASS

- [ ] **Step 5: Run adjacent non-regression**

Run:

```bash
bash tests/test_agent_task_boundary_gate.sh
```

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add scripts/check-pretool-gates.sh tests/test_pretool_command_gates.sh tests/test_agent_task_boundary_gate.sh
git commit -m "fix: gate edits until resume recovery completes"
```

## Task 5: Add The Resume Recovery Skill And Completion Recorder

**User-facing goal:** The plugin ships a dedicated manual recovery command that rebuilds the execution picture from persisted state and then clears the recovery gate only after that summary is explicitly recorded.

**Files:**
- Create: `skills/resume-enforcer/SKILL.md`
- Create: `scripts/record-resume-state.sh`
- Create: `tests/test_resume_recovery_flow.sh`
- Verify: `scripts/update-state.sh`
- Verify: `.claude-plugin/plugin.json`
- Verify: `manifest.json`

- [ ] **Step 1: Write the failing tests**

Create `tests/test_resume_recovery_flow.sh` with:

1. usage rejection for unsupported action or missing source:

```bash
bash scripts/record-resume-state.sh >/dev/null 2>&1
```

Expected: exit non-zero

2. success case for:

```bash
bash scripts/record-resume-state.sh completed resume
```

Assert:

```bash
assert_json_equals "$STATE_FILE" '.resume.recovery_required' 'false'
assert_json_equals "$STATE_FILE" '.resume.last_resume_source' '"resume"'
```

and assert `.resume.recovery_completed_at` is a non-null string timestamp.

- [ ] **Step 2: Run the test to verify RED**

Run:

```bash
bash tests/test_resume_recovery_flow.sh
```

Expected: FAIL because neither the record script nor the skill file exists.

- [ ] **Step 3: Write the minimal implementation**

Create `scripts/record-resume-state.sh` with the contract:

```bash
record-resume-state.sh completed <source>
```

On success it must merge:

```json
{
  "resume": {
    "recovery_required": false,
    "recovery_completed_at": "<now>",
    "last_resume_source": "<source>"
  }
}
```

Create `skills/resume-enforcer/SKILL.md` so the manual workflow:

1. reads `.claude/flow_state.json`
2. reads root-level `task_plan.md`, `progress.md`, and `findings.md` first when those files exist
3. falls back to `.planning-with-files/task_plan.md`, `.planning-with-files/progress.md`, and `.planning-with-files/findings.md` only when the root-level files do not exist
4. continues recovery from state plus git context when neither planning location exists
5. runs `git status --short`
6. optionally runs `git diff --stat`
7. emits a structured recovery summary with:
   - current phase
   - open task / review state
   - last confirmed progress point
   - next required action
8. calls `bash ${CLAUDE_PLUGIN_ROOT}/scripts/record-resume-state.sh completed resume`

Do not modify `.claude-plugin/plugin.json` or `manifest.json`; verify the new skill is discoverable purely by shipping it under `skills/`.

- [ ] **Step 4: Run the test to verify GREEN**

Run:

```bash
bash tests/test_resume_recovery_flow.sh
```

Expected: PASS

- [ ] **Step 5: Run adjacent non-regression**

Run:

```bash
bash tests/test_init_state.sh
```

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add skills/resume-enforcer/SKILL.md scripts/record-resume-state.sh tests/test_resume_recovery_flow.sh
git commit -m "feat: add resume recovery skill"
```

## Task 6: Clear Task Flow On The Normal Finishing Path

**User-facing goal:** When the workflow reaches the normal finishing path, stale task-boundary state is cleared deterministically so future resume checks do not keep treating a closed implementation loop as still open.

**Files:**
- Modify: `scripts/record-finishing-state.sh`
- Modify: `tests/test_recorded_review_flow.sh`

- [ ] **Step 1: Write the failing test**

Extend `tests/test_recorded_review_flow.sh` to seed:

```bash
jq '.task_flow.active_task_id = "task-001" | .task_flow.active_packet_role = "implementer" | .task_flow.last_dispatch_at = "2026-04-15T00:00:00Z"' "$STATE_FILE" > "$TMP_DIR/state.json"
```

After:

```bash
bash scripts/record-finishing-state.sh invoked
```

assert:

```bash
assert_json_equals "$STATE_FILE" '.finishing.invoked' 'true'
assert_json_equals "$STATE_FILE" '.task_flow.active_task_id' 'null'
assert_json_equals "$STATE_FILE" '.task_flow.active_packet_role' 'null'
```

and keep `.task_flow.last_dispatch_at` unchanged.

- [ ] **Step 2: Run the test to verify RED**

Run:

```bash
bash tests/test_recorded_review_flow.sh
```

Expected: FAIL because the current finishing recorder does not clear `task_flow`.

- [ ] **Step 3: Write the minimal implementation**

Update `scripts/record-finishing-state.sh` so its merge payload becomes:

```json
{
  "finishing": {"invoked": true},
  "task_flow": {
    "active_task_id": null,
    "active_packet_role": null
  }
}
```

Do not clear `task_flow.last_dispatch_at` in this round.

- [ ] **Step 4: Run the test to verify GREEN**

Run:

```bash
bash tests/test_recorded_review_flow.sh
```

Expected: PASS

- [ ] **Step 5: Run adjacent non-regression**

Run:

```bash
bash tests/test_agent_task_boundary_gate.sh
```

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add scripts/record-finishing-state.sh tests/test_recorded_review_flow.sh
git commit -m "fix: clear task flow on finishing"
```

## Task 7: Sync Runtime Docs And Command Guidance

**User-facing goal:** The README, Chinese README, and runtime guidance all recommend the short commands, explain the recovery handshake clearly, and do not imply that `stop` disables enforcement.

**Files:**
- Modify: `README.md`
- Modify: `README_cn.md`
- Modify: `CLAUDE.md`
- Verify: `skills/resume-enforcer/SKILL.md`

- [ ] **Step 1: Update the docs**

In all three docs, update the command guidance so:

1. default recommended manual control is:
   - `开启 enforcer`
   - `关闭 enforcer`
   - `enable enforcer`
   - `disable enforcer`
2. all manual-control commands are described as exact commands after whitespace normalization
3. long-form compatibility is still documented
4. `启动/停止 enforcer` and `start/stop enforcer` are explicitly not supported this round
5. `stop` / `暂停` remain interrupt vocabulary, not enforcer shutdown vocabulary
6. resumed unfinished workflows must run `/superpowers-flow-enforcer:resume-enforcer` before new edits or agent dispatch
7. state tracking now includes `resume.recovery_required`, `resume.recovery_completed_at`, and `resume.last_resume_source`
8. recovery planning records read root-level `task_plan.md` / `progress.md` / `findings.md` first and use `.planning-with-files/` only as a compatibility fallback

- [ ] **Step 2: Verify the docs mention the new runtime surface**

Run:

```bash
rg -n '开启 enforcer|关闭 enforcer|enable enforcer|disable enforcer|/superpowers-flow-enforcer:resume-enforcer|resume\\.recovery_required|task_plan\\.md|\\.planning-with-files/' README.md README_cn.md CLAUDE.md skills/resume-enforcer/SKILL.md
```

Expected: each concept is present in the correct file.

- [ ] **Step 3: Run the focused final regression bundle**

Run:

```bash
bash tests/test_init_state.sh
bash tests/test_bypass_state.sh
bash tests/test_interrupt_state.sh
bash tests/test_pretool_command_gates.sh
bash tests/test_agent_task_boundary_gate.sh
bash tests/test_resume_recovery_flow.sh
bash tests/test_recorded_review_flow.sh
bash tests/test_hooks_official_events.sh
```

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add README.md README_cn.md CLAUDE.md
git commit -m "docs: document resume recovery workflow"
```
