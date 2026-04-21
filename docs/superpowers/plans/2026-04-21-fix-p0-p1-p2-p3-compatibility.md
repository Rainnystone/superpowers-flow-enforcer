# Fix P0 Naming Mismatch, P1 Shell Profile Pollution, P2 Stop Hook Phase Guard, P3 State File Corruption, P4 Planning Review Gate

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix five blocking/stability/design-gap issues in the superpowers-flow-enforcer plugin: accept `code-quality-reviewer` as a role alias, isolate hooks from shell profile pollution via `--norc`, add phase-aware guards to the Stop hook, harden state file writes against corruption, and add a plan review intermediate state to the planning phase so plan review/fix/re-review cycles are compatible with the enforced state machine.

**Architecture:** Minimal delta changes across nine source files plus four test files. P0 adds a normalization layer at validation boundaries. P1 injects `--norc` into the existing `hooks.json` command pattern. P2 gates two restrictive checks in `check-stop-review-gate.sh` behind `current_phase` conditions. P3 adds JSON object type guards in `init-state.sh` and `update-state.sh`. P4 inserts a `plan_reviewed` state field and a two-step planning gate (plan review → worktree) into `sync-post-tool-state.sh`, `templates/flow_state.json.tmpl`, and `migrate-state.sh`.

**Tech Stack:** Bash 4.0+, jq, python3 (for inline JSON parsing in task_flow_packets.sh)

---

## Packet 1: P0 — `code-quality-reviewer` alias support

**User-facing goal:** Users following the official superpowers prompt templates can dispatch `SPFE_PACKET_ROLE=code-quality-reviewer` without being blocked by the PreToolUse/Agent gate.

**Owned files:**
- Modify: `scripts/lib/task_flow_packets.sh` (3 Python inline scripts)
- Modify: `scripts/check-pretool-gates.sh` (`is_supported_packet_role` + runtime normalization)
- Modify: `scripts/sync-post-tool-state.sh` (`record_successful_agent_dispatch` normalization)
- Modify: `tests/test_agent_task_boundary_gate.sh` (new code-quality-reviewer alias tests)

**Parallel safety:** Safe to run in parallel with Packet 3 and Packet 4. Must run before Packet 2 only if Packet 2 also touches `test_agent_task_boundary_gate.sh`; in this plan Packet 2 does not.

**Default verification:** `bash tests/test_agent_task_boundary_gate.sh`

- [ ] **Step 1: Write failing tests (RED)**

Append to `tests/test_agent_task_boundary_gate.sh` after the existing code-reviewer allow test (after line 368):

```bash
# P0: code-quality-reviewer alias tests

write_v2_state "$STATE_FILE"
jq '
  .workflow.active = true
  | .worktree.created = true
  | .worktree.baseline_verified = true
  | .task_flow.active_task_id = "task-alias-1"
  | .review.tasks["task-alias-1"] = {spec_review_passed:true, code_review_passed:false}
' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"

# Test 1a: code-quality-reviewer should be allowed when spec review passed
allow_output="$(run_agent_gate $'SPFE_TASK_ID=task-alias-1\nSPFE_PACKET_ROLE=code-quality-reviewer\n\nCode quality review after spec pass.')"
assert_pretool_allow "$allow_output"

# Test 1b: code-reviewer should still work (regression)
allow_output="$(run_agent_gate $'SPFE_TASK_ID=task-alias-1\nSPFE_PACKET_ROLE=code-reviewer\n\nCode review after spec pass.')"
assert_pretool_allow "$allow_output"

# Test 1c: sync-post-tool-state.sh should normalize code-quality-reviewer to code-reviewer
# run_posttool_agent_dispatch simulates a PostToolUse/Agent success event,
# which triggers sync-post-tool-state.sh to record the dispatched role.
write_v2_state "$STATE_FILE"
posttool_output="$(run_posttool_agent_dispatch 'task-alias-2' 'code-quality-reviewer')"
assert_posttool_allow "$posttool_output"
assert_json_equals "$STATE_FILE" '.task_flow.active_packet_role' '"code-reviewer"'
```

Run: `bash tests/test_agent_task_boundary_gate.sh`
Expected: FAIL at Test 1a (code-quality-reviewer not yet accepted).

- [ ] **Step 2: Expand accepted roles in `task_flow_packets.sh`**

Change all three Python inline scripts (lines 53, 200, 256):

```python
# Before
if role not in {"implementer", "spec-reviewer", "code-reviewer"}:
    raise SystemExit(1)

# After
if role not in {"implementer", "spec-reviewer", "code-reviewer", "code-quality-reviewer"}:
    raise SystemExit(1)
```

- [ ] **Step 3: Expand `is_supported_packet_role` in `check-pretool-gates.sh`**

Change lines 169-178:

```bash
is_supported_packet_role() {
  local packet_role="$1"
  case "$packet_role" in
    implementer|spec-reviewer|code-reviewer|code-quality-reviewer)
      return 0
      ;;
  esac
  return 1
}
```

After `packet_role` extraction (after line 342), add normalization:

```bash
# Normalize code-quality-reviewer to code-reviewer for internal state consistency
if [ "$packet_role" = "code-quality-reviewer" ]; then
  packet_role="code-reviewer"
fi
```

- [ ] **Step 4: Normalize role in `sync-post-tool-state.sh`**

After `packet_role` extraction in `record_successful_agent_dispatch` (after line 91), add:

```bash
# Normalize code-quality-reviewer to code-reviewer for state storage
if [ "$packet_role" = "code-quality-reviewer" ]; then
  packet_role="code-reviewer"
fi
```

- [ ] **Step 5: Verify tests pass (GREEN)**

Run: `bash tests/test_agent_task_boundary_gate.sh`
Expected: PASS.

Run: `bash tests/test_pretool_command_gates.sh`
Expected: PASS (regression check).

- [ ] **Step 6: Commit**

```bash
git add scripts/lib/task_flow_packets.sh scripts/check-pretool-gates.sh scripts/sync-post-tool-state.sh tests/test_agent_task_boundary_gate.sh
git commit -m "feat(p0): accept code-quality-reviewer as code-reviewer alias"
```

---

## Packet 2: P1 — `--norc` shell profile isolation

**User-facing goal:** Hook scripts remain resilient to users whose shell profiles contain unconditional `echo` statements.

**Owned files:**
- Modify: `hooks/hooks.json`
- Modify: `tests/test_pretool_command_gates.sh` (behavioral anti-pollution test)

**Parallel safety:** Safe to run in parallel with Packet 1 (no shared test file). Can run in parallel with Packet 3 and Packet 4.

**Default verification:** `bash tests/test_pretool_command_gates.sh && jq empty hooks/hooks.json`

- [ ] **Step 1: Write failing test (RED)**

Append to `tests/test_pretool_command_gates.sh`:

```bash
# P1: --norc behavioral isolation test
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Create a fake HOME with a polluted ~/.bashrc
FAKE_HOME="$TMP_DIR/fake_home"
mkdir -p "$FAKE_HOME"
echo 'echo "PROFILE_POLLUTION"' > "$FAKE_HOME/.bashrc"

# Verify that without --norc, profile pollution contaminates stdout
polluted_output="$(HOME="$FAKE_HOME" bash "${CLAUDE_PLUGIN_ROOT}/scripts/init-state.sh" < /dev/null)"
if ! echo "$polluted_output" | grep -q "PROFILE_POLLUTION"; then
  echo "SKIP: Could not reproduce profile pollution on this environment" >&2
else
  # Verify --norc suppresses ~/.bashrc pollution
  clean_output="$(HOME="$FAKE_HOME" bash --norc "${CLAUDE_PLUGIN_ROOT}/scripts/init-state.sh" < /dev/null)"
  if echo "$clean_output" | grep -q "PROFILE_POLLUTION"; then
    echo "FAIL: bash --norc failed to suppress ~/.bashrc pollution" >&2
    exit 1
  fi
  if ! echo "$clean_output" | jq empty >/dev/null 2>&1; then
    echo "FAIL: Clean hook output is not valid JSON" >&2
    exit 1
  fi
fi

# Verify hooks.json contains --norc in all commands
if ! grep -q 'bash --norc' hooks/hooks.json; then
  echo "FAIL: hooks.json commands must use bash --norc" >&2
  exit 1
fi
```

Run: `bash tests/test_pretool_command_gates.sh`
Expected: FAIL at `--norc` suppression check (hooks.json not yet updated).

- [ ] **Step 2: Implement `--norc` in `hooks.json`**

Replace every `bash ${CLAUDE_PLUGIN_ROOT}` with `bash --norc ${CLAUDE_PLUGIN_ROOT}` in all 10 command entries.

- [ ] **Step 3: Verify tests pass (GREEN)**

Run: `bash tests/test_pretool_command_gates.sh && jq empty hooks/hooks.json`
Expected: Both PASS.

- [ ] **Step 4: Commit**

```bash
git add hooks/hooks.json tests/test_pretool_command_gates.sh
git commit -m "feat(p1): isolate hooks from shell profile pollution with --norc"
```

---

## Packet 3: P2 — Stop hook phase guard

**User-facing goal:** Stopping a session during `brainstorming` or `planning` no longer deadlocks with "还没有 review 记录".

**Owned files:**
- Modify: `scripts/check-stop-review-gate.sh`
- Modify: `tests/test_stop_gates.sh`

**Parallel safety:** Safe to run in parallel with Packet 1 and Packet 4. Shares no files with Packet 1/2/4.

**Default verification:** `bash tests/test_stop_gates.sh`

- [ ] **Step 1: Write failing tests (RED)**

Append to `tests/test_stop_gates.sh` after line 213:

```bash
# P2: Stop hook phase guard tests

# brainstorming phase with empty review.tasks should allow stop
write_v2_state "$STATE_FILE"
jq '.workflow.active = true | .current_phase = "brainstorming"' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"
allow_output="$(run_stop_gate "$PRIMARY_PROJECT")"
assert_stop_allow_silent "$allow_output"

# planning phase with empty review.tasks should allow stop
write_v2_state "$STATE_FILE"
jq '.workflow.active = true | .current_phase = "planning"' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"
allow_output="$(run_stop_gate "$PRIMARY_PROJECT")"
assert_stop_allow_silent "$allow_output"

# tdd phase with empty review.tasks should still block
write_v2_state "$STATE_FILE"
jq '.workflow.active = true | .current_phase = "tdd"' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"
deny_output="$(run_stop_gate "$PRIMARY_PROJECT")"
assert_stop_block "$deny_output" 'review'

# review phase with all reviews passed but finishing not invoked should block
write_v2_state "$STATE_FILE"
jq '.workflow.active = true | .current_phase = "review" | .review.tasks = {"task-001": {"spec_review_passed": true, "code_review_passed": true}}' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"
deny_output="$(run_stop_gate "$PRIMARY_PROJECT")"
assert_stop_block "$deny_output" 'finishing'

# finishing phase with all reviews passed but finishing not invoked should block
write_v2_state "$STATE_FILE"
jq '.workflow.active = true | .current_phase = "finishing" | .review.tasks = {"task-001": {"spec_review_passed": true, "code_review_passed": true}}' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"
deny_output="$(run_stop_gate "$PRIMARY_PROJECT")"
assert_stop_block "$deny_output" 'finishing'

# Regression: completion claim check still works in brainstorming phase
write_v2_state "$STATE_FILE"
jq '.workflow.active = true | .current_phase = "brainstorming"' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"
deny_output="$(run_stop_gate "$PRIMARY_PROJECT" false 'Done. I fixed it and everything is working now.')"
assert_stop_block "$deny_output" 'verification'
```

Run: `bash tests/test_stop_gates.sh`
Expected: FAIL at brainstorming/planning allow tests.

- [ ] **Step 2: Implement phase guard in `check-stop-review-gate.sh`**

After line 165 (`workflow.active` check), add:

```bash
CURRENT_PHASE="$(jq -r '.current_phase // "init"' "$STATE_FILE")"
```

Replace lines 167-175 (review records check):

```bash
SKIP_REVIEW_CONFIRMED=false
if state_expr_is_true '.exceptions.skip_review' && state_expr_is_true '.exceptions.user_confirmed'; then
  SKIP_REVIEW_CONFIRMED=true
fi

if [ "$CURRENT_PHASE" = "tdd" ] || [ "$CURRENT_PHASE" = "review" ] || [ "$CURRENT_PHASE" = "finishing" ]; then
  if [ "$SKIP_REVIEW_CONFIRMED" != true ] && ! has_review_records; then
    block_stop '还没有 review 记录，先执行 requesting-code-review 的两阶段评审。'
    exit 0
  fi
fi
```

Replace lines 177-185 (finishing check):

```bash
SKIP_FINISHING_CONFIRMED=false
if state_expr_is_true '.exceptions.skip_finishing' && state_expr_is_true '.exceptions.user_confirmed'; then
  SKIP_FINISHING_CONFIRMED=true
fi

if [ "$CURRENT_PHASE" = "review" ] || [ "$CURRENT_PHASE" = "finishing" ]; then
  if [ "$SKIP_FINISHING_CONFIRMED" != true ] && all_reviews_passed && ! state_expr_is_true '.finishing.invoked'; then
    block_stop '所有任务都已 review，通过后还需执行 finishing-a-development-branch。'
    exit 0
  fi
fi
```

- [ ] **Step 3: Verify tests pass (GREEN)**

Run: `bash tests/test_stop_gates.sh`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add scripts/check-stop-review-gate.sh tests/test_stop_gates.sh
git commit -m "feat(p2): add phase guard to Stop hook to prevent deadlock"
```

---

## Packet 4: P3 — State file corruption guard

**User-facing goal:** A malformed state file or accidental scalar write is automatically detected, backed up, and reset instead of causing a cryptic jq error on the next session start.

**Owned files:**
- Modify: `scripts/init-state.sh`
- Modify: `scripts/update-state.sh`
- Modify: `tests/test_init_state.sh`

**Parallel safety:** Safe to run in parallel with Packet 1, Packet 2, and Packet 3. Shares no files.

**Default verification:** `bash tests/test_init_state.sh`

- [ ] **Step 1: Write failing tests (RED)**

Append to `tests/test_init_state.sh` (or add a new focused test block):

```bash
# P3: State file corruption guard tests

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

STATE_FILE="$TMP_DIR/.claude/flow_state.json"
mkdir -p "$TMP_DIR/.claude"
TEMPLATE="${CLAUDE_PLUGIN_ROOT}/templates/flow_state.json.tmpl"

# Test: bare boolean false should trigger backup + reset
printf 'false' > "$STATE_FILE"
output="$(echo '{}' | CLAUDE_PROJECT_DIR="$TMP_DIR" CLAUDE_PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT" bash "$CLAUDE_PLUGIN_ROOT/scripts/init-state.sh")"
if [ ! -f "$STATE_FILE.bak" ]; then
  echo "FAIL: Expected .bak file to be created for corrupted state" >&2
  exit 1
fi
if ! jq -e 'type == "object"' "$STATE_FILE" >/dev/null 2>&1; then
  echo "FAIL: Expected state file to be reset to valid object" >&2
  exit 1
fi

# Test: bare string should trigger backup + reset
printf '"corrupted"' > "$STATE_FILE"
rm -f "$STATE_FILE.bak"
output="$(echo '{}' | CLAUDE_PROJECT_DIR="$TMP_DIR" CLAUDE_PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT" bash "$CLAUDE_PLUGIN_ROOT/scripts/init-state.sh")"
if [ ! -f "$STATE_FILE.bak" ]; then
  echo "FAIL: Expected .bak file for string-corrupted state" >&2
  exit 1
fi

# Test: valid v2 object should NOT be reset
cp "$TEMPLATE" "$STATE_FILE"
output="$(echo '{}' | CLAUDE_PROJECT_DIR="$TMP_DIR" CLAUDE_PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT" bash "$CLAUDE_PLUGIN_ROOT/scripts/init-state.sh")"
if [ -f "$STATE_FILE.bak" ]; then
  echo "FAIL: Valid state should not trigger backup" >&2
  exit 1
fi

# Test: update-state.sh should reject non-object jq results
cp "$TEMPLATE" "$STATE_FILE"
if CLAUDE_PROJECT_DIR="$TMP_DIR" bash "$CLAUDE_PLUGIN_ROOT/scripts/update-state.sh" --jq '.workflow.active' >/dev/null 2>&1; then
  echo "FAIL: update-state.sh should abort when jq produces non-object" >&2
  exit 1
fi
if ! jq -e '.workflow.active == false' "$STATE_FILE" >/dev/null 2>&1; then
  echo "FAIL: Original state should be untouched after aborted update" >&2
  exit 1
fi

# Test: update-state.sh normal object mutation should succeed
if ! CLAUDE_PROJECT_DIR="$TMP_DIR" bash "$CLAUDE_PLUGIN_ROOT/scripts/update-state.sh" --jq '.workflow.active = true' >/dev/null 2>&1; then
  echo "FAIL: update-state.sh should succeed for object mutation" >&2
  exit 1
fi
if ! jq -e '.workflow.active == true' "$STATE_FILE" >/dev/null 2>&1; then
  echo "FAIL: Object mutation should persist" >&2
  exit 1
fi
```

Run: `bash tests/test_init_state.sh`
Expected: FAIL at P3 tests (init-state.sh and update-state.sh not yet hardened).

- [ ] **Step 2: Harden `init-state.sh`**

Replace line 189:

```bash
# Before
if ! jq empty "$STATE_FILE" >/dev/null 2>&1; then
    backup_and_reset_state

# After
if ! jq -e 'type == "object"' "$STATE_FILE" >/dev/null 2>&1; then
    backup_and_reset_state
```

- [ ] **Step 3: Harden `update-state.sh`**

Replace the `write_tmp_and_swap` function:

```bash
write_tmp_and_swap() {
  local expr="$1"
  local tmp_file
  tmp_file="${STATE_FILE}.tmp"
  jq "$expr" "$STATE_FILE" > "$tmp_file"

  if ! jq -e 'type == "object"' "$tmp_file" >/dev/null 2>&1; then
    echo '{"error":"State mutation produced non-object JSON; aborting to prevent corruption"}'
    rm -f "$tmp_file"
    exit 1
  fi

  mv "$tmp_file" "$STATE_FILE"
}
```

- [ ] **Step 4: Verify tests pass (GREEN)**

Run: `bash tests/test_init_state.sh`
Expected: PASS

Run: `bash -n scripts/init-state.sh && bash -n scripts/update-state.sh`
Expected: No syntax errors.

- [ ] **Step 5: Commit**

```bash
git add scripts/init-state.sh scripts/update-state.sh tests/test_init_state.sh
git commit -m "feat(p3): guard state file against corruption with object type checks"
```

---

## Packet 5: P4 — Planning review gate

**User-facing goal:** After a canonical plan write, the session can enter a plan review / fix / re-review cycle before being forced to create a git worktree. The planning phase now has the same two-step gate pattern as brainstorming (written → reviewed → next phase).

**Owned files:**
- Modify: `templates/flow_state.json.tmpl` (add `plan_reviewed` field)
- Modify: `scripts/sync-post-tool-state.sh` (set `plan_reviewed = false` on write; split single worktree gate into two-step gate)
- Modify: `scripts/migrate-state.sh` (bootstrap `plan_reviewed` default for v1→v2 migration)
- Modify: `tests/test_posttool_command_gates.sh` (update plan-write assertions to expect plan-review block, add plan-reviewed allow test)
- Verify: `scripts/init-state.sh` fresh-state path produces `plan_reviewed: false` (no code change expected; template already contains the field)

**Parallel safety:** Safe to run in parallel with Packet 1, Packet 2, and Packet 3. Must run after Packet 4 only if Packet 4 touches `sync-post-tool-state.sh`; in this plan Packet 4 does not.

**Default verification:** `bash tests/test_posttool_command_gates.sh && bash tests/test_init_state.sh`

- [ ] **Step 1: Write failing tests (RED)**

In `tests/test_posttool_command_gates.sh`, update the existing plan-write assertions (around lines 113–128):

```bash
# P4: plan write after spec_reviewed should block with plan-review message
write_v2_state "$STATE_FILE"
jq '.brainstorming.spec_reviewed = true' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"
plan_block_output="$(run_posttool_write 'docs/superpowers/plans/demo.md')"
assert_posttool_block "$plan_block_output" 'plan review'
assert_json_equals "$STATE_FILE" '.planning.plan_written' 'true'
assert_json_equals "$STATE_FILE" '.planning.plan_file' '"docs/superpowers/plans/demo.md"'
assert_json_equals "$STATE_FILE" '.planning.plan_reviewed' 'false'

# P4: plan write with plan_reviewed=true should allow (worktree gate comes next)
write_v2_state "$STATE_FILE"
jq '
  .brainstorming.spec_reviewed = true
  | .planning.plan_reviewed = true
' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"
plan_allow_output="$(run_posttool_write 'docs/superpowers/plans/demo.md')"
assert_posttool_allow "$plan_allow_output"
```

Also add a re-edit consistency test after the above:

```bash
# P4: re-editing plan while plan_reviewed=false stays on plan-review block
write_v2_state "$STATE_FILE"
jq '.brainstorming.spec_reviewed = true' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"
plan_block_output_1="$(run_posttool_write 'docs/superpowers/plans/demo.md')"
assert_posttool_block "$plan_block_output_1" 'plan review'
plan_block_output_2="$(run_posttool_write 'docs/superpowers/plans/demo.md')"
assert_posttool_block "$plan_block_output_2" 'plan review'

# Verify both block messages are identical (no confusing drift on re-edit)
msg_1="$(printf '%s' "$plan_block_output_1" | jq -r '.reason')"
msg_2="$(printf '%s' "$plan_block_output_2" | jq -r '.reason')"
if [ "$msg_1" != "$msg_2" ]; then
  echo "FAIL: Re-edit block message drifted: '$msg_1' vs '$msg_2'" >&2
  exit 1
fi
```

Run: `bash tests/test_posttool_command_gates.sh`
Expected: FAIL at plan-review block assertions.

- [ ] **Step 2: Add `plan_reviewed` to state template**

Change `templates/flow_state.json.tmpl` line 17–21:

```json
  "planning": {
    "plan_written": false,
    "plan_file": null,
    "plan_reviewed": false,
    "execution_mode": null
  },
```

- [ ] **Step 3: Set `plan_reviewed = false` on canonical plan write**

In `scripts/sync-post-tool-state.sh`, line 1265, change:

```bash
        .planning.plan_written = true
        | .planning.plan_file = $path
```

To:

```bash
        .planning.plan_written = true
        | .planning.plan_file = $path
        | .planning.plan_reviewed = false
```

- [ ] **Step 4: Split single worktree gate into two-step gate**

In `scripts/sync-post-tool-state.sh`, replace lines 1347–1349:

```bash
  if [ "$PLAN_WRITE_RECORDED" = "true" ] && ! state_is_true '.worktree.created'; then
    block_posttool "Plan 已写完，先执行 using-git-worktrees 创建隔离工作区并跑 baseline tests。"
  fi
```

With:

```bash
  if [ "$PLAN_WRITE_RECORDED" = "true" ] && ! state_is_true '.planning.plan_reviewed'; then
    block_posttool "Plan 已写入，请先完成 plan review 并让用户批准后再进入 worktree 阶段。"
  fi

  if state_is_true '.planning.plan_reviewed' && ! state_is_true '.worktree.created'; then
    block_posttool "Plan 已通过 review，先执行 using-git-worktrees 创建隔离工作区并跑 baseline tests。"
  fi
```

- [ ] **Step 5: Verify `plan_reviewed` in fresh state (init-state.sh)**

`scripts/init-state.sh` has no `normalize_planning_state()` healing path for v2 states. Fresh states get `plan_reviewed: false` from the template (Step 2). For existing v2 states that predate this field, all gate scripts use `state_is_true '.planning.plan_reviewed'` which evaluates `null == true` as false, so the missing field safely defaults to `false`. No code change in `init-state.sh` is required.

Run a quick verification:
```bash
rm -f "$TMP_DIR/.claude/flow_state.json"
mkdir -p "$TMP_DIR/.claude"
echo '{}' | CLAUDE_PROJECT_DIR="$TMP_DIR" bash "${CLAUDE_PLUGIN_ROOT}/scripts/init-state.sh" >/dev/null
jq -e '.planning.plan_reviewed == false' "$TMP_DIR/.claude/flow_state.json" >/dev/null 2>&1 || {
  echo "FAIL: Fresh state missing planning.plan_reviewed = false" >&2
  exit 1
}
```

- [ ] **Step 6: Bootstrap `plan_reviewed` in migrate-state.sh**

In `scripts/migrate-state.sh`, line 161–165, change:

```json
    "planning": {
      "plan_written": (.planning.plan_written // false),
      "plan_file": (.planning.plan_file // null),
      "execution_mode": (.planning.execution_mode // null)
    },
```

To:

```json
    "planning": {
      "plan_written": (.planning.plan_written // false),
      "plan_file": (.planning.plan_file // null),
      "plan_reviewed": false,
      "execution_mode": (.planning.execution_mode // null)
    },
```

- [ ] **Step 7: Verify tests pass (GREEN)**

Run: `bash tests/test_posttool_command_gates.sh`
Expected: PASS.

Run: `bash tests/test_init_state.sh`
Expected: PASS (regression check; fresh state and migrated state must both contain `planning.plan_reviewed`).

- [ ] **Step 8: Commit**

```bash
git add templates/flow_state.json.tmpl scripts/sync-post-tool-state.sh scripts/init-state.sh scripts/migrate-state.sh tests/test_posttool_command_gates.sh
git commit -m "feat(p4): add plan review gate before worktree creation"
```

---

## Packet 6: Full regression and active docs sync

**User-facing goal:** All five fixes work together without regressions, and active planning files reflect completion.

**Owned files:**
- Modify: `task_plan.md`, `progress.md`

**Parallel safety:** Must run after all prior packets.

**Default verification:** `for t in tests/test_*.sh; do bash "$t"; done`

- [ ] **Step 1: Run the entire test suite**

```bash
for t in tests/test_*.sh; do
  echo "=== $t ==="
  bash "$t" || { echo "FAIL: $t"; exit 1; }
done
echo "All tests passed"
```

Expected: All PASS.

- [ ] **Step 2: Validate JSON and shell syntax**

```bash
jq empty hooks/hooks.json
bash -n scripts/init-state.sh
bash -n scripts/update-state.sh
bash -n scripts/check-pretool-gates.sh
bash -n scripts/check-stop-review-gate.sh
bash -n scripts/sync-post-tool-state.sh
bash -n scripts/lib/task_flow_packets.sh
```

Expected: All PASS.

- [ ] **Step 3: Sync user-facing docs**

Update `CLAUDE.md` and `README.md` / `README_cn.md` to mention `code-quality-reviewer` as an accepted packet role alias (alongside `code-reviewer`).

Search for existing `code-reviewer` mentions in user-facing docs and add the alias:
```bash
grep -n 'code-reviewer' CLAUDE.md README.md README_cn.md 2>/dev/null || true
```

For example, in `CLAUDE.md` line 57 (Packetized Subagent Execution section), change:
```markdown
- Code quality review packets must use `SPFE_PACKET_ROLE=code-reviewer`.
```
To:
```markdown
- Code quality review packets must use `SPFE_PACKET_ROLE=code-reviewer` or `SPFE_PACKET_ROLE=code-quality-reviewer` (both are accepted; the latter is normalized to the former internally).
```

- [ ] **Step 4: Update active tracking files**

Update `task_plan.md` phase 8 checklist to include P0–P4:

```markdown
### 阶段 8：TDD 实施
- [x] RED: 编写测试用例
  - [x] P0: code-quality-reviewer 角色测试
  - [x] P1: --norc 隔离测试
  - [x] P2: Stop hook phase guard 测试
  - [x] P3: State file corruption guard 测试
  - [x] P4: Planning review gate 测试
- [x] GREEN: 实施最小代码改动
  - [x] P0: 修改 task_flow_packets.sh、check-pretool-gates.sh、sync-post-tool-state.sh
  - [x] P1: 修改 hooks.json
  - [x] P2: 修改 check-stop-review-gate.sh
  - [x] P3: 修改 init-state.sh、update-state.sh
  - [x] P4: 修改 flow_state.json.tmpl、sync-post-tool-state.sh、init-state.sh、migrate-state.sh
- [x] REFACTOR: 清理代码
- [x] 验证所有测试通过
```

Append to `progress.md`:

```markdown
## 2026-04-21 Session 2 (续)

### 已完成
- [x] SPEC 更新加入 P0-P4
- [x] Implementation plan 更新 (6 packets, AGENTS.md 合规)
- [x] TDD 实施 P0-P4
- [x] 全量回归测试通过

### 关键变更
1. P0: `scripts/lib/task_flow_packets.sh`, `check-pretool-gates.sh`, `sync-post-tool-state.sh` — code-quality-reviewer 别名
2. P1: `hooks/hooks.json` — 全部 10 个 command 注入 `bash --norc`
3. P2: `scripts/check-stop-review-gate.sh` — current_phase 读取 + 双检查 phase guard
4. P3: `scripts/init-state.sh`, `scripts/update-state.sh` — `jq -e 'type == "object"'` 硬校验
5. P4: `templates/flow_state.json.tmpl`, `scripts/sync-post-tool-state.sh`, `scripts/migrate-state.sh` — planning 阶段两阶段门控 (plan review → worktree)
```

- [ ] **Step 5: Final commit**

```bash
git add task_plan.md progress.md CLAUDE.md README.md README_cn.md
git commit -m "docs: mark P0-P4 implementation complete"
```

---

## Self-Review

**1. Spec coverage:**
- Goal 1 (code-quality-reviewer): Packet 1 covers validation, pretool gate, and state normalization. ✅
- Goal 2 (--norc): Packet 2 covers test and hooks.json injection. ✅
- Goal 3 (phase guard): Packet 3 covers tests and implementation. ✅
- Goal 4 (corruption guard): Packet 4 covers init-state.sh and update-state.sh hardening. ✅
- Goal 5 (planning review gate): Packet 5 covers state schema, posttool gate split, template, init, migration, and tests. ✅
- Completion claim verification untouched (runs in all phases) — verified in P2 regression test. ✅

**2. Placeholder scan:**
- No "TBD", "TODO", or "implement later". ✅
- All code blocks contain actual code. ✅
- All commands are exact with expected output. ✅

**3. Type consistency:**
- `packet_role` normalization uses consistent string comparison. ✅
- Phase names match state schema. ✅
- `jq -e 'type == "object"'` used consistently in P3. ✅
- `planning.plan_reviewed` is boolean, defaults `false`, and follows the same naming pattern as `brainstorming.spec_reviewed`. ✅

**4. AGENTS.md packet discipline:**
- Each packet has one primary objective, one main surface area, one verification path. ✅
- Serial/parallel relationships declared. ✅
- No two packets share a primary production file (except Packet 1→2 test file dependency). ✅
