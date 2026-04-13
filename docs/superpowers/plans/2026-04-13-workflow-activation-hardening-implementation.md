# Workflow Activation Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make workflow activation reliable and controllable: keep root canonical `docs/superpowers/...` auto-activation, add subtree canonical auto-activation, add explicit `激活/关闭 superpowers enforcer` control phrases, and preserve `workflow.active == false` as the no-op boundary for workflow-only enforcement.

**Architecture:** Keep this round narrow and deterministic. First extend workflow state so manual activation and manual shutdown are explicit, normalized fields. Then teach `UserPromptSubmit` to handle the new control phrases while preserving existing skip-style explicit workflow intent. Finally, generalize canonical path recognition in the state-sync and pretool gate scripts so activation and workflow-artifact exceptions follow the same project-relative suffix rule for both root and subtree layouts.

**Tech Stack:** Claude Code plugin hooks, Bash, `jq`, shell regression tests, Markdown docs

---

## Scope Check

This spec covers one subsystem: workflow activation semantics. It should stay one plan.

Do not widen this implementation into:

1. Bash file-write equivalence with `Write/Edit`
2. parser-backed Bash redesign
3. full workflow state-machine redesign
4. skill/frontmatter hook migration

## AGENTS Task-Splitting Rules

This plan follows `AGENTS.md`:

1. each task owns one primary activation surface
2. each task has one main verification path
3. tasks run serially because they share workflow state semantics
4. each task must complete one TDD loop and one review loop before the next starts
5. no task may widen into unrelated enforcement redesign

## File Structure

### Files to modify

- `templates/flow_state.json.tmpl`
- `scripts/init-state.sh`
- `scripts/lib/workflow_paths.sh`
- `scripts/sync-user-prompt-state.sh`
- `scripts/sync-post-tool-state.sh`
- `scripts/check-pretool-gates.sh`
- `tests/helpers/state-fixtures.sh`
- `tests/test_init_state.sh`
- `tests/test_bypass_state.sh`
- `tests/test_workflow_activation.sh`
- `tests/test_pretool_command_gates.sh`
- `README.md`
- `README_cn.md`
- `CLAUDE.md`

### Files to verify but not necessarily modify

- `tests/test_interrupt_state.sh`
- `tests/test_posttool_command_gates.sh`
- `tests/test_bash_command_gate.sh`
- `tests/test_stop_gates.sh`
- `tests/test_hooks_official_events.sh`

### Responsibility map

- `templates/flow_state.json.tmpl`: default workflow schema, including new manual override/deactivation fields
- `scripts/init-state.sh`: state normalization and recovery for older state files
- `scripts/lib/workflow_paths.sh`: shared current-project root resolution, project-relative path normalization, canonical workflow path matching, and excluded-prefix checks
- `scripts/sync-user-prompt-state.sh`: explicit user prompt activation/deactivation and skip-style prompt activation semantics
- `scripts/sync-post-tool-state.sh`: canonical artifact auto-activation based on normalized project-relative suffix matching
- `scripts/check-pretool-gates.sh`: workflow-artifact recognition while inactive and active, including subtree canonical paths
- `tests/helpers/state-fixtures.sh`: reusable test fixtures for v2 state shapes
- `tests/test_init_state.sh`: state schema and normalization regression
- `tests/test_bypass_state.sh`: `UserPromptSubmit` activation/deactivation prompt behavior
- `tests/test_workflow_activation.sh`: canonical path auto-activation behavior
- `tests/test_pretool_command_gates.sh`: `Write/Edit` gate alignment with the new canonical path semantics
- `README.md`, `README_cn.md`, `CLAUDE.md`: user-facing activation behavior and control phrase documentation

## Task 1: Extend Workflow State Schema And Normalization

**User-facing goal:** Fresh and recovered state files can represent explicit manual activation and manual shutdown without ambiguity.

**Files:**
- Modify: `templates/flow_state.json.tmpl`
- Modify: `scripts/init-state.sh`
- Modify: `tests/helpers/state-fixtures.sh`
- Modify: `tests/test_init_state.sh`

- [ ] **Step 1: Write the failing tests**

In `tests/test_init_state.sh`, add assertions that fail unless a fresh or normalized v2 state contains:

```bash
assert_json_equals "$file" '.workflow.override' 'null'
assert_json_equals "$file" '.workflow.deactivated_by' 'null'
assert_json_equals "$file" '.workflow.deactivated_at' 'null'
```

Add fixture-driven cases for:

1. old v2 workflow object missing the new fields
2. partial workflow object that should normalize in place
3. invalid new field types that should trigger backup-and-reset

In `tests/helpers/state-fixtures.sh`, add helper writers for:

```bash
write_v2_state_with_partial_workflow_override() { ... }
write_v2_state_with_invalid_workflow_override_types() { ... }
```

- [ ] **Step 2: Run the test to verify RED**

Run:

```bash
bash tests/test_init_state.sh
```

Expected: FAIL because the template and normalization logic do not yet define the new workflow fields.

- [ ] **Step 3: Write the minimal implementation**

Update `templates/flow_state.json.tmpl` to add:

```json
"workflow": {
  "active": false,
  "activated_by": null,
  "activated_at": null,
  "override": null,
  "deactivated_by": null,
  "deactivated_at": null
}
```

Update `scripts/init-state.sh` so workflow normalization:

1. treats the new fields as part of the normal v2 workflow object
2. fills missing fields in place for safe partial objects
3. backs up and resets only when field types are unsafe
4. preserves the current source-of-truth project root behavior

Do not change any non-workflow state semantics in this task.

- [ ] **Step 4: Run the test to verify GREEN**

Run:

```bash
bash tests/test_init_state.sh
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
git add templates/flow_state.json.tmpl scripts/init-state.sh tests/helpers/state-fixtures.sh tests/test_init_state.sh
git commit -m "fix: extend workflow activation state schema"
```

## Task 2: Add Explicit Prompt Activation And Deactivation

**User-facing goal:** The user can explicitly turn enforcement on with `激活 superpowers enforcer` and off with `关闭 superpowers enforcer`, while existing skip-style prompts remain explicit workflow intent.

**Files:**
- Modify: `scripts/sync-user-prompt-state.sh`
- Modify: `tests/test_bypass_state.sh`

- [ ] **Step 1: Write the failing tests**

Extend `tests/test_bypass_state.sh` with `UserPromptSubmit` cases for:

1. normalized substring match for `激活 superpowers enforcer`
2. normalized substring match for `关闭 superpowers enforcer`
3. manual activation setting:

```bash
assert_json_equals "$STATE_FILE" '.workflow.active' 'true'
assert_json_equals "$STATE_FILE" '.workflow.override' '"manual_on"'
assert_json_equals "$STATE_FILE" '.workflow.activated_by' '"manual_prompt"'
```

4. manual shutdown setting:

```bash
assert_json_equals "$STATE_FILE" '.workflow.active' 'false'
assert_json_equals "$STATE_FILE" '.workflow.override' '"manual_off"'
assert_json_equals "$STATE_FILE" '.workflow.deactivated_by' '"manual_prompt"'
```

5. skip-style prompt after manual shutdown reactivates workflow and clears `manual_off`
6. explicit `激活 superpowers enforcer` after a prior `manual_off` reactivates workflow and replaces the manual shutdown state
7. malformed or missing prompt string stays silent/no-op

- [ ] **Step 2: Run the test to verify RED**

Run:

```bash
bash tests/test_bypass_state.sh
```

Expected: FAIL because the current script only handles skip-style prompts and interrupt keywords.

- [ ] **Step 3: Write the minimal implementation**

Update `scripts/sync-user-prompt-state.sh` to:

1. normalize prompt text by trimming and collapsing repeated whitespace
2. detect `激活 superpowers enforcer` as a normalized substring
3. detect `关闭 superpowers enforcer` as a normalized substring
4. on manual activate:
   - set `.workflow.active = true`
   - set `.workflow.override = "manual_on"`
   - set `.workflow.activated_by = "manual_prompt"`
   - set `.workflow.activated_at = now`
5. on manual deactivate:
   - set `.workflow.active = false`
   - set `.workflow.override = "manual_off"`
   - set `.workflow.deactivated_by = "manual_prompt"`
   - set `.workflow.deactivated_at = now`
6. preserve existing skip-specific exception bookkeeping
7. when a skip-style prompt is processed:
   - set `.workflow.override = null` unconditionally
   - set `.workflow.active = true`
   - keep `activated_by = "user_prompt_skip"`
   - keep the existing skip-specific exception bookkeeping

Do not introduce fuzzy synonym matching in this task.

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
git commit -m "fix: add explicit workflow activation prompts"
```

## Task 3: Generalize Canonical Path Auto-Activation

**User-facing goal:** Writing canonical spec/plan documents activates workflow whether they live at repository root or inside a current-project subtree, while manual shutdown still blocks passive auto-reactivation.

**Files:**
- Create: `scripts/lib/workflow_paths.sh`
- Modify: `scripts/sync-post-tool-state.sh`
- Modify: `tests/test_workflow_activation.sh`

- [ ] **Step 1: Write the failing tests**

Extend `tests/test_workflow_activation.sh` with cases for:

1. subtree spec write:

```bash
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"simulation-toolset/docs/superpowers/specs/demo.md"}}'
```

2. subtree plan write
3. dotted-relative subtree path
4. absolute subtree path
5. alias-mixed subtree path
6. cwd-derived subtree path
7. excluded prefix such as `.simulation/foo/docs/superpowers/specs/demo.md` not activating
8. excluded prefix such as `.git/docs/superpowers/specs/demo.md` not activating
9. excluded fixture/testdata path such as `testdata/docs/superpowers/specs/demo.md` not activating
10. canonical-looking path outside the current project root not activating
11. manual-off state preventing canonical path auto-reactivation
12. `manual_on` state surviving a later canonical auto-activation instead of being cleared

For positive cases, assert:

```bash
assert_json_equals "$STATE_FILE" '.workflow.active' 'true'
assert_json_equals "$STATE_FILE" '.workflow.activated_by' '"spec_write"'
```

For canonical plan-write cases, assert:

```bash
assert_json_equals "$STATE_FILE" '.workflow.active' 'true'
assert_json_equals "$STATE_FILE" '.workflow.activated_by' '"plan_write"'
```

For the `manual_on` preservation case, assert:

```bash
assert_json_equals "$STATE_FILE" '.workflow.active' 'true'
assert_json_equals "$STATE_FILE" '.workflow.override' '"manual_on"'
```

For the manual-off case, assert `.workflow.active` stays `false`.

- [ ] **Step 2: Run the test to verify RED**

Run:

```bash
bash tests/test_workflow_activation.sh
```

Expected: FAIL because current matching only recognizes root-level canonical paths and does not honor `manual_off`.

- [ ] **Step 3: Write the minimal implementation**

Create `scripts/lib/workflow_paths.sh` and update `scripts/sync-post-tool-state.sh` to use it.

The helper must be the single source of truth for:

1. resolving the current project root from `CLAUDE_PROJECT_DIR` or hook `cwd`
2. converting candidate paths into the same physical path space as that root
3. deriving a normalized project-relative path
4. testing canonical workflow suffix matches
5. testing excluded prefixes such as `.git/`, `.worktrees/`, `node_modules/`, `vendor/`, `.simulation/`, and fixture/testdata trees

Update `scripts/sync-post-tool-state.sh` to:

1. source the shared helper instead of re-implementing path semantics inline
2. keep the existing root-resolution behavior already used for state lookup
3. normalize candidate file paths into the same physical path space as the resolved project root
4. compute a normalized project-relative path only after the root is physically resolved
5. treat a file as canonical when the normalized project-relative path ends with:

```text
docs/superpowers/specs/<filename>.md
docs/superpowers/plans/<filename>.md
```

6. reject activation when the normalized project-relative path starts under excluded prefixes such as `.git/`, `.worktrees/`, `node_modules/`, `vendor/`, `.simulation/`, or fixture/testdata trees
7. preserve root-level canonical activation as the zero-prefix case
8. if `.workflow.override == "manual_off"`, skip passive auto-activation
9. if `.workflow.override == "manual_on"`, keep it instead of clearing it on later canonical writes

Do not add special handling for one concrete directory name such as `simulation-toolset`.

- [ ] **Step 4: Run the test to verify GREEN**

Run:

```bash
bash tests/test_workflow_activation.sh
```

Expected: PASS

- [ ] **Step 5: Run adjacent non-regression**

Run:

```bash
bash tests/test_posttool_command_gates.sh
```

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add scripts/sync-post-tool-state.sh tests/test_workflow_activation.sh
git commit -m "fix: broaden canonical workflow activation paths"
```

## Task 4: Align `PreToolUse` Workflow Artifact Recognition

**User-facing goal:** Once canonical subtree paths are valid workflow artifacts, `Write/Edit` gates must treat them the same way as root-level spec/plan artifacts.

**Files:**
- Modify: `scripts/check-pretool-gates.sh`
- Modify: `tests/test_pretool_command_gates.sh`

- [ ] **Step 1: Write the failing tests**

Extend `tests/test_pretool_command_gates.sh` with cases for:

1. inactive workflow + subtree canonical spec path allows
2. inactive workflow + subtree canonical plan path allows
3. active workflow + subtree canonical plan path still counts as a plan artifact for the spec-review/user-approval gate
4. subtree canonical workflow artifacts are not treated as generic production files for TDD/worktree gating
5. excluded fixture/testdata canonical-looking path is not treated as a workflow artifact
6. excluded `.git/.../docs/superpowers/...` path is not treated as a workflow artifact

Representative assertion:

```bash
allow_output="$(run_write_gate 'simulation-toolset/docs/superpowers/specs/spec.md')"
test -z "$allow_output"
```

Representative plan gate assertion:

```bash
deny_output="$(run_write_gate 'packages/tooling/docs/superpowers/plans/plan.md')"
assert_json_equals <(printf '%s' "$deny_output") '.hookSpecificOutput.permissionDecision' '"deny"'
```

- [ ] **Step 2: Run the test to verify RED**

Run:

```bash
bash tests/test_pretool_command_gates.sh
```

Expected: FAIL because canonical artifact recognition is still root-only in `check-pretool-gates.sh`.

- [ ] **Step 3: Write the minimal implementation**

Update `scripts/check-pretool-gates.sh` so the canonical artifact helpers:

1. source and reuse `scripts/lib/workflow_paths.sh` instead of duplicating path semantics
2. continue to recognize root-level canonical paths
3. recognize subtree canonical paths
4. exclude `.git/`, `.worktrees/`, `node_modules/`, `vendor/`, `.simulation/`, and fixture/testdata trees from workflow-artifact recognition
5. keep non-canonical `docs/*.md` behavior unchanged
6. preserve `workflow.active != true` as the no-op boundary for workflow-only enforcement

Do not refactor unrelated gate logic in this task.

- [ ] **Step 4: Run the test to verify GREEN**

Run:

```bash
bash tests/test_pretool_command_gates.sh
```

Expected: PASS

- [ ] **Step 5: Run adjacent non-regression**

Run:

```bash
bash tests/test_bash_command_gate.sh
```

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add scripts/check-pretool-gates.sh tests/test_pretool_command_gates.sh
git commit -m "fix: align pretool gates with canonical subtree activation"
```

## Task 5: Document The New Activation Contract And Run Final Verification

**User-facing goal:** The documented installation and usage behavior matches the implemented activation contract.

**Files:**
- Modify: `README.md`
- Modify: `README_cn.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Write the doc deltas**

Update docs to say:

1. workflow can be activated explicitly with `激活 superpowers enforcer`
2. workflow can be deactivated explicitly with `关闭 superpowers enforcer`
3. canonical spec/plan files may live at repository root or inside a current-project subtree
4. while workflow is inactive, workflow-only gates remain silent/no-op

Do not restate parser or Bash redesign details in this task.

- [ ] **Step 2: Run focused verification**

Run:

```bash
bash tests/test_init_state.sh
bash tests/test_bypass_state.sh
bash tests/test_interrupt_state.sh
bash tests/test_workflow_activation.sh
bash tests/test_pretool_command_gates.sh
bash tests/test_posttool_command_gates.sh
```

Expected: PASS

- [ ] **Step 3: Run adjacent activation regressions**

Run:

```bash
bash tests/test_bash_command_gate.sh
bash tests/test_stop_gates.sh
bash tests/test_hooks_official_events.sh
```

Expected: PASS

- [ ] **Step 4: Run final hygiene**

Run:

```bash
git diff --check
```

Expected: no output

- [ ] **Step 5: Commit**

```bash
git add README.md README_cn.md CLAUDE.md
git commit -m "docs: describe hardened workflow activation"
```
