# Fix P0 Role Alias, Correct P1 Scope, P2 Stop Hook Phase Guard, P3 State File Corruption, P4 Local Planning Hold, and P5 Midstream Activation Recovery

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix six spec/contract issues in the superpowers-flow-enforcer plugin: accept `code-quality-reviewer` as a compatibility alias, correct the repo's P1 scope around Claude Code hook profile pollution, add phase-aware guards to the Stop hook, harden state file writes against corruption, add a repo-local plan-review hold before the existing worktree gate, and recover the correct `current_phase` when `enable enforcer` is issued mid-workstream without breaking resume recovery.

**Architecture:** Minimal delta changes across hook/state scripts, tests, and active docs. P0 adds a normalization layer at validation boundaries. P1 becomes docs/troubleshooting sync because the real pollution path is outside the plugin's inner bash invocation boundary. P2 gates two restrictive checks in `check-stop-review-gate.sh` behind `current_phase` conditions. P3 adds JSON object type guards in `init-state.sh` and `update-state.sh`. P4 inserts a repo-local `plan_reviewed` state field and a two-step local planning hold (plan review → existing worktree gate) into `sync-post-tool-state.sh`, `templates/flow_state.json.tmpl`, `migrate-state.sh`, and `record-plan-state.sh`. P5 adds resume-safe phase recovery to `sync-user-prompt-state.sh` and reuses existing canonical path semantics for artifact fallback.

**Tech Stack:** Bash 4.0+, jq, python3 (for inline JSON parsing in task_flow_packets.sh)

---

## Packet 1: P0 — `code-quality-reviewer` compatibility alias support

**User-facing goal:** Sessions that use `SPFE_PACKET_ROLE=code-quality-reviewer` as a compatibility spelling are not blocked by the PreToolUse/Agent gate, while `code-reviewer` remains the primary internal role.

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

## Packet 2: P1 — Correct the documented scope of hook profile pollution

**User-facing goal:** The repo stops claiming an unsupported `--norc` fix for Claude Code hook profile pollution, and instead tells users the official mitigation.

**Owned files:**
- Modify: `README.md`
- Modify: `README_cn.md`
- Modify: `CLAUDE.md`
- Verify: `tests/test_hooks_official_events.sh` (no hook command-string regression; `hooks/hooks.json` should stay unchanged)

**Parallel safety:** Safe to run in parallel with Packets 1, 3, and 4. It must not edit `hooks/hooks.json`.

**Default verification:** `bash tests/test_hooks_official_events.sh && rg -n 'interactive|交互|~/.zshrc|~/.bashrc|JSON validation failed|profile' README.md README_cn.md CLAUDE.md`

- [ ] **Step 1: Update active docs**

Add/adjust wording in `README.md`, `README_cn.md`, and `CLAUDE.md` so they all say:

- Claude Code sources the user's shell profile before the configured hook command runs.
- Unconditional `echo` in `~/.zshrc` / `~/.bashrc` can prepend noise before hook JSON.
- The supported mitigation is to guard that output so it only runs in interactive shells, for example:

```bash
if [[ $- == *i* ]]; then
  echo "Shell ready"
fi
```

- This repo does **not** claim that changing `hooks/hooks.json` to `bash --norc ...` fixes that outer-shell behavior.

- [ ] **Step 2: Keep hook wiring unchanged**

Do **not** edit `hooks/hooks.json` in this packet. The purpose of this packet is to remove an incorrect remediation, not to ship an unverified hook-runtime change.

- [ ] **Step 3: Verify docs and hook wiring (GREEN)**

Run: `bash tests/test_hooks_official_events.sh`
Expected: PASS (no hook command strings changed).

Run:
```bash
rg -n 'interactive|交互|~/.zshrc|~/.bashrc|JSON validation failed|profile' README.md README_cn.md CLAUDE.md
```
Expected: The three active docs contain the official mitigation guidance.

- [ ] **Step 4: Commit**

```bash
git add README.md README_cn.md CLAUDE.md
git commit -m "docs(p1): document Claude Code hook profile pollution as runtime limitation"
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

## Packet 5: P4 — Repo-local plan-review hold before worktree

**User-facing goal:** After a canonical plan write, the session can stay in a local plan review / fix / re-review loop before the existing worktree gate resumes. This is a repo-local enforcer extension, not a claim about upstream superpowers ordering.

**Owned files:**
- Modify: `templates/flow_state.json.tmpl` (add `plan_reviewed` field)
- Modify: `scripts/sync-post-tool-state.sh` (set `plan_reviewed = false` on write; split single worktree gate into local plan-review hold + existing worktree gate)
- Modify: `scripts/migrate-state.sh` (bootstrap `plan_reviewed` default for v1→v2 migration)
- Create: `scripts/record-plan-state.sh` (write entry for `plan_reviewed`, mirrors `record-spec-state.sh`)
- Modify: `tests/test_posttool_command_gates.sh` (update plan-write assertions to expect plan-review block, add worktree gate test after plan_reviewed=true)
- Verify: `scripts/init-state.sh` fresh-state path produces `plan_reviewed: false` (no code change expected; template already contains the field)

**Parallel safety:** Safe to run in parallel with Packet 1, Packet 2, and Packet 3. Must run after Packet 4 only if Packet 4 touches `sync-post-tool-state.sh`; in this plan Packet 4 does not.

**Default verification:** `bash tests/test_posttool_command_gates.sh && bash tests/test_init_state.sh`

- [ ] **Step 1: Write failing tests (RED)**

In `tests/test_posttool_command_gates.sh`, update the existing plan-write assertions (around lines 113–128):

```bash
# P4: canonical plan write after spec_reviewed should block with local plan-review message
write_v2_state "$STATE_FILE"
jq '.brainstorming.spec_reviewed = true' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"
plan_block_output="$(run_posttool_write 'docs/superpowers/plans/demo.md')"
assert_posttool_block "$plan_block_output" 'plan review'
assert_json_equals "$STATE_FILE" '.planning.plan_written' 'true'
assert_json_equals "$STATE_FILE" '.planning.plan_file' '"docs/superpowers/plans/demo.md"'
assert_json_equals "$STATE_FILE" '.planning.plan_reviewed' 'false'

# P4: after plan_reviewed=true, non-plan write hits existing worktree gate (not plan-review gate)
write_v2_state "$STATE_FILE"
jq '
  .brainstorming.spec_reviewed = true
  | .planning.plan_written = true
  | .planning.plan_file = "docs/superpowers/plans/demo.md"
  | .planning.plan_reviewed = true
' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"
worktree_block_output="$(run_posttool_write 'docs/superpowers/other.md')"
assert_posttool_block "$worktree_block_output" 'worktree'
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
    block_posttool "Plan 已写入，请先完成 plan review，再进入 worktree 阶段。"
  fi

  if state_is_true '.planning.plan_reviewed' && ! state_is_true '.worktree.created'; then
    block_posttool "Plan 已通过 review，先执行 using-git-worktrees 创建隔离工作区并跑 baseline tests。"
  fi
```

- [ ] **Step 5: Verify `plan_reviewed` in fresh state (init-state.sh)**

`scripts/init-state.sh` does not need new logic for this packet. Fresh states will get `plan_reviewed: false` **because Step 2 updates the template** that `init-state.sh` already copies. For existing v2 states that predate this field, all gate scripts use `state_is_true '.planning.plan_reviewed'`, so the missing field safely behaves as `false` until migration or rewrite fills it in.

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

- [ ] **Step 7: Create `record-plan-state.sh`**

Create `scripts/record-plan-state.sh` as an explicit repo-local write entry for `planning.plan_reviewed`, mirroring the existing `record-spec-state.sh` pattern:

```bash
#!/bin/bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo 'Usage: record-plan-state.sh plan-reviewed pass|fail' >&2
  exit 1
fi

ACTION="$1"
RESULT="$2"

case "$ACTION" in
  plan-reviewed) FIELD="plan_reviewed" ;;
  *) echo "Unsupported plan action: $ACTION" >&2; exit 1 ;;
esac

case "$RESULT" in
  pass) VALUE=true ;;
  fail) VALUE=false ;;
  *) echo "Unsupported result: $RESULT" >&2; exit 1 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

jq -n --argjson value "$VALUE" --arg field "$FIELD" '{planning:{($field):$value}}' \
  | bash "$PLUGIN_ROOT/scripts/update-state.sh" --merge >/dev/null
```

Make executable: `chmod +x scripts/record-plan-state.sh`

Verify: `CLAUDE_PROJECT_DIR=/tmp bash scripts/record-plan-state.sh plan-reviewed pass && echo "ok"`

- [ ] **Step 8: Verify tests pass (GREEN)**

Run: `bash tests/test_posttool_command_gates.sh`
Expected: PASS.

Run: `bash tests/test_init_state.sh`
Expected: PASS (regression check; fresh state and migrated state must both contain `planning.plan_reviewed`).

- [ ] **Step 9: Commit**

```bash
git add templates/flow_state.json.tmpl scripts/sync-post-tool-state.sh scripts/migrate-state.sh scripts/record-plan-state.sh tests/test_posttool_command_gates.sh
git commit -m "feat(p4): add plan review gate with record-plan-state.sh"
```

---

## Packet 6: P5 — Midstream activation phase recovery

**User-facing goal:** When `enable enforcer` is issued mid-workstream, the enforcer recovers the correct `current_phase` conservatively, without clearing the existing resume gate or drifting away from the repo's canonical path semantics.

**Owned files:**
- Modify: `scripts/sync-user-prompt-state.sh` (add conservative phase recovery and integrate into activation handler)
- Modify: `scripts/lib/workflow_paths.sh` only if a helper is needed to reuse canonical artifact semantics without duplicating subtree / exclusion logic
- Modify: `tests/test_bypass_state.sh` (state-based recovery + resume-gate preservation tests)
- Modify: `tests/test_workflow_activation.sh` (artifact fallback tests using existing subtree / alias path surface)
- Verify: `tests/test_resume_recovery_flow.sh` (resume contract remains intact)

**Parallel safety:** Safe to run in parallel with Packet 1, Packet 2, and Packet 3. Shares no files with other packets.

**Default verification:** `bash tests/test_bypass_state.sh && bash tests/test_workflow_activation.sh && bash tests/test_resume_recovery_flow.sh`

- [ ] **Step 1: Write failing tests (RED)**

Append to `tests/test_bypass_state.sh` after the existing enable/disable enforcer test block. The test uses the same `MANUAL_PROMPT_PROJECT` and `STATE_FILE` variables already defined in that file:

```bash
# P5: Midstream activation phase recovery tests

# Test: existing non-init phase is preserved
write_v2_state "$STATE_FILE"
jq '.current_phase = "review"' "$STATE_FILE" > "$STATE_FILE.tmp"
mv "$STATE_FILE.tmp" "$STATE_FILE"
P5_REVIEW_PHASE_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"enable enforcer"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$P5_REVIEW_PHASE_OUTPUT" ]; then
  echo "P5: Expected enable enforcer preserve-phase path to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.current_phase' '"review"'
assert_json_equals "$STATE_FILE" '.workflow.active' 'true'

# Test: debugging.active=true recovers to "debugging"
write_v2_state "$STATE_FILE"
jq '.debugging.active = true' "$STATE_FILE" > "$STATE_FILE.tmp"
mv "$STATE_FILE.tmp" "$STATE_FILE"
P5_DEBUG_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"enable enforcer"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$P5_DEBUG_OUTPUT" ]; then
  echo "P5: Expected enable enforcer debugging recovery to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.current_phase' '"debugging"'

# Test: worktree.created=true with baseline false recovers to "worktree"
write_v2_state "$STATE_FILE"
jq '.worktree.created = true' "$STATE_FILE" > "$STATE_FILE.tmp"
mv "$STATE_FILE.tmp" "$STATE_FILE"
P5_WORKTREE_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"enable enforcer"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$P5_WORKTREE_OUTPUT" ]; then
  echo "P5: Expected enable enforcer worktree recovery to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.current_phase' '"worktree"'

# Test: baseline verified recovers to "tdd"
write_v2_state "$STATE_FILE"
jq '.worktree.created = true | .worktree.baseline_verified = true' "$STATE_FILE" > "$STATE_FILE.tmp"
mv "$STATE_FILE.tmp" "$STATE_FILE"
P5_TDD_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"enable enforcer"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$P5_TDD_OUTPUT" ]; then
  echo "P5: Expected enable enforcer tdd recovery to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.current_phase' '"tdd"'

# Test: planning.plan_written=true recovers to "planning"
write_v2_state "$STATE_FILE"
jq '.planning.plan_written = true' "$STATE_FILE" > "$STATE_FILE.tmp"
mv "$STATE_FILE.tmp" "$STATE_FILE"
P5_PLANNING_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"enable enforcer"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$P5_PLANNING_OUTPUT" ]; then
  echo "P5: Expected enable enforcer planning recovery to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.current_phase' '"planning"'

# Test: brainstorming.spec_written=true recovers to "brainstorming"
write_v2_state "$STATE_FILE"
jq '.brainstorming.spec_written = true' "$STATE_FILE" > "$STATE_FILE.tmp"
mv "$STATE_FILE.tmp" "$STATE_FILE"
P5_BRAINSTORM_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"enable enforcer"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$P5_BRAINSTORM_OUTPUT" ]; then
  echo "P5: Expected enable enforcer brainstorming recovery to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.current_phase' '"brainstorming"'

# Test: finishing.invoked=true recovers to "finishing"
write_v2_state "$STATE_FILE"
jq '.finishing.invoked = true' "$STATE_FILE" > "$STATE_FILE.tmp"
mv "$STATE_FILE.tmp" "$STATE_FILE"
P5_FINISHING_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"enable enforcer"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$P5_FINISHING_OUTPUT" ]; then
  echo "P5: Expected enable enforcer finishing recovery to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.current_phase' '"finishing"'

# Test: empty state stays at "init"
write_v2_state "$STATE_FILE"
P5_INIT_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"enable enforcer"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$P5_INIT_OUTPUT" ]; then
  echo "P5: Expected enable enforcer empty state to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.current_phase' '"init"'

# Test: enable enforcer must NOT clear resume.recovery_required
write_v2_state "$STATE_FILE"
jq '.planning.plan_written = true | .resume.recovery_required = true' "$STATE_FILE" > "$STATE_FILE.tmp"
mv "$STATE_FILE.tmp" "$STATE_FILE"
P5_RESUME_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"enable enforcer"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$P5_RESUME_OUTPUT" ]; then
  echo "P5: Expected enable enforcer with resume to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.current_phase' '"planning"'
assert_json_equals "$STATE_FILE" '.resume.recovery_required' 'true'

# Regression: disable enforcer does not change current_phase
write_v2_state "$STATE_FILE"
jq '.current_phase = "planning" | .planning.plan_written = true' "$STATE_FILE" > "$STATE_FILE.tmp"
mv "$STATE_FILE.tmp" "$STATE_FILE"
P5_DISABLE_OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"disable enforcer"}' "$MANUAL_PROMPT_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
if [ -n "$P5_DISABLE_OUTPUT" ]; then
  echo "P5: Expected disable enforcer to be silent allow" >&2
  exit 1
fi
assert_json_equals "$STATE_FILE" '.workflow.active' 'false'
assert_json_equals "$STATE_FILE" '.current_phase' '"planning"'
```

Append artifact fallback tests to `tests/test_workflow_activation.sh`, because that file already exercises supported root / subtree / alias / cwd-derived canonical write semantics. Add a block that:

1. Seeds a state file with `current_phase = "init"` and no structured phase fields.
2. Creates a supported subtree or alias canonical plan artifact.
3. Sends `enable enforcer` through `scripts/sync-user-prompt-state.sh`.
4. Verifies recovery lands in `planning`.
5. Repeats the pattern for a canonical spec artifact and verifies `brainstorming`.

Do not use a root-only `project_dir/docs/superpowers/...` check as the only test surface.

Run: `bash tests/test_bypass_state.sh`
Expected: FAIL at P5 recovery assertions (sync-user-prompt-state.sh not yet updated).

- [ ] **Step 2: Add `recover_phase_from_state` and canonical-artifact helper**

In `scripts/sync-user-prompt-state.sh`, before `is_manual_activate_exact_command()`, add:

```bash
project_contains_canonical_artifact() {
  local project_dir="$1"
  local want_kind="$2"
  local file rel kind

  while IFS= read -r -d '' file; do
    rel="$(workflow_paths_normalize_project_relative_path "$file" "$project_dir" "$project_dir")"
    kind="$(workflow_paths_classify_canonical_write "$rel")"
    if [ "$kind" = "$want_kind" ]; then
      return 0
    fi
  done < <(find "$project_dir" -type f \( -path '*/docs/superpowers/specs/*.md' -o -path '*/docs/superpowers/plans/*.md' \) -print0)

  return 1
}

recover_phase_from_state() {
  local state_file="$1"
  local project_dir="$2"
  local current_phase

  current_phase="$(jq -r '.current_phase // "init"' "$state_file" 2>/dev/null || echo init)"
  case "$current_phase" in
    brainstorming|planning|worktree|tdd|review|debugging|finishing)
      echo "$current_phase"; return 0 ;;
  esac

  if jq -e '.finishing.invoked == true' "$state_file" >/dev/null 2>&1; then
    echo "finishing"; return 0
  fi
  if jq -e '.debugging.active == true' "$state_file" >/dev/null 2>&1; then
    echo "debugging"; return 0
  fi
  if jq -e '.worktree.created == true and (.worktree.baseline_verified // false) != true' "$state_file" >/dev/null 2>&1; then
    echo "worktree"; return 0
  fi
  if jq -e '.tdd.current_task != null or (.worktree.baseline_verified // false) == true' "$state_file" >/dev/null 2>&1; then
    echo "tdd"; return 0
  fi
  if jq -e '.planning.plan_written == true' "$state_file" >/dev/null 2>&1; then
    echo "planning"; return 0
  fi
  if jq -e '.brainstorming.spec_written == true' "$state_file" >/dev/null 2>&1; then
    echo "brainstorming"; return 0
  fi

  if project_contains_canonical_artifact "$project_dir" "plan"; then
    echo "planning"; return 0
  fi
  if project_contains_canonical_artifact "$project_dir" "spec"; then
    echo "brainstorming"; return 0
  fi

  echo "init"
}
```

Source `scripts/lib/workflow_paths.sh` if needed so the fallback uses the same subtree / alias / exclusion semantics as the rest of the plugin.

- [ ] **Step 3: Integrate recovery into activation handler without clearing resume gate**

Replace the activation handler block (lines 228-242):

```bash
if is_manual_activate_exact_command "$PROMPT_LC"; then
  RECOVERED_PHASE="$(recover_phase_from_state "$STATE_FILE" "$PROJECT_DIR")"
  jq --arg now "$NOW_UTC" --arg phase "$RECOVERED_PHASE" '
    .workflow.active = true
    | .workflow.override = "manual_on"
    | .workflow.activated_by = "manual_prompt"
    | .workflow.activated_at = $now
    | .workflow.deactivated_by = null
    | .workflow.deactivated_at = null
    | .interrupt.allowed = false
    | .interrupt.reason = null
    | .interrupt.keywords_detected = []
    | .current_phase = $phase
  ' "$STATE_FILE" > "$tmp_file"
  mv "$tmp_file" "$STATE_FILE"
  exit 0
fi
```

Do **not** clear `.resume.recovery_required` here. Manual enable should recover phase-aware state, but the dedicated `/superpowers-flow-enforcer:resume-enforcer` flow remains the only supported way to clear the resume gate.

- [ ] **Step 4: Verify tests pass (GREEN)**

Run: `bash tests/test_bypass_state.sh`
Expected: PASS.

Run: `bash tests/test_workflow_activation.sh`
Expected: PASS, including new subtree / alias artifact fallback cases.

Run: `bash tests/test_resume_recovery_flow.sh`
Expected: PASS (resume contract unchanged).

- [ ] **Step 5: Commit**

```bash
git add scripts/sync-user-prompt-state.sh scripts/lib/workflow_paths.sh tests/test_bypass_state.sh tests/test_workflow_activation.sh
git commit -m "feat(p5): midstream activation phase recovery on enable enforcer"
```

---

## Packet 7: Full regression and active docs sync

**User-facing goal:** All six fixes work together without regressions, and active planning files and user-facing docs reflect completion.

**Owned files:**
- Modify: `README.md`
- Modify: `README_cn.md`
- Modify: `CLAUDE.md`
- Modify: `task_plan.md`, `progress.md`, `findings.md`

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
bash -n scripts/sync-user-prompt-state.sh
bash -n scripts/record-plan-state.sh
bash -n scripts/lib/task_flow_packets.sh
```

Expected: All PASS.

- [ ] **Step 3: Sync user-facing docs**

Update `CLAUDE.md` and `README.md` / `README_cn.md`:

1. Add `code-quality-reviewer` compatibility alias. In `CLAUDE.md` Packetized Subagent Execution section, change:
```markdown
- Code quality review packets must use `SPFE_PACKET_ROLE=code-reviewer`.
```
To:
```markdown
- Code quality review packets must use `SPFE_PACKET_ROLE=code-reviewer` or `SPFE_PACKET_ROLE=code-quality-reviewer` (both are accepted; the latter is normalized to the former internally).
```

2. Replace the old P1 `--norc` claim with the official hook-runtime guidance. Add wording that:
```markdown
- Claude Code sources the user's shell profile before running the hook command.
- Unconditional `echo` in `~/.zshrc` / `~/.bashrc` can break hook JSON.
- Guard that output so it only runs in interactive shells.
```

3. Add `planning.plan_reviewed` as a repo-local planning hold. In `CLAUDE.md` Brainstorming / Planning section, add:
```markdown
- **Planning Phase**: In this repo's local enforcer flow, plan writing sets `plan_reviewed = false`. The plan must pass local plan review before the existing worktree gate resumes. Use `record-plan-state.sh plan-reviewed pass` to mark review completion.
```

4. Add midstream activation behavior without changing the resume contract. In `CLAUDE.md` Workflow Entry / Resume section, add:
```markdown
- **Midstream Activation**: When `enable enforcer` is issued mid-workstream, the enforcer recovers `current_phase` from structured state fields and canonical artifacts. Phase is not inferred from natural language.
- **Resume Gate**: Manual enable does not clear `resume.recovery_required`; resumed unfinished workflows still require `/superpowers-flow-enforcer:resume-enforcer`.
```

Search for existing mentions to avoid duplicates:
```bash
grep -n 'code-reviewer\|plan_reviewed\|midstream\|plan-reviewed\|interactive\|profile\|~/.zshrc\|~/.bashrc\|resume.recovery_required' CLAUDE.md README.md README_cn.md 2>/dev/null || true
```

- [ ] **Step 4: Update active tracking files**

Update `task_plan.md` phase 8 checklist to include P0–P5:

```markdown
### 阶段 8：TDD 实施
- [x] RED: 编写测试用例
  - [x] P0: code-quality-reviewer 角色测试
  - [x] P1: shell profile pollution 文档 / 契约修正
  - [x] P2: Stop hook phase guard 测试
  - [x] P3: State file corruption guard 测试
  - [x] P4: Planning review gate 测试
  - [x] P5: Midstream activation phase recovery 测试
- [x] GREEN: 实施最小代码改动
  - [x] P0: 修改 task_flow_packets.sh、check-pretool-gates.sh、sync-post-tool-state.sh
  - [x] P1: 修改 README.md、README_cn.md、CLAUDE.md（不改 hooks.json）
  - [x] P2: 修改 check-stop-review-gate.sh
  - [x] P3: 修改 init-state.sh、update-state.sh
  - [x] P4: 修改 flow_state.json.tmpl、sync-post-tool-state.sh、migrate-state.sh、record-plan-state.sh
  - [x] P5: 修改 sync-user-prompt-state.sh、tests/test_workflow_activation.sh（必要时加 workflow_paths helper）
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
2. P1: `README.md`, `README_cn.md`, `CLAUDE.md` — 明确 shell profile pollution 是 Claude Code hook runtime 限制，并同步官方 mitigation
3. P2: `scripts/check-stop-review-gate.sh` — current_phase 读取 + 双检查 phase guard
4. P3: `scripts/init-state.sh`, `scripts/update-state.sh` — `jq -e 'type == "object"'` 硬校验
5. P4: `templates/flow_state.json.tmpl`, `scripts/sync-post-tool-state.sh`, `scripts/migrate-state.sh` — repo-local planning hold (`plan_reviewed`) → existing worktree gate
6. P5: `scripts/sync-user-prompt-state.sh`（以及必要时 `scripts/lib/workflow_paths.sh`）— 恢复 `current_phase`，但不清除 resume gate
```

Append a `Codex`-labeled summary to `findings.md` describing the final contract decisions for:
- P1 as a documented Claude Code runtime limitation
- P4 as a repo-local planning hold
- P5 as resume-safe phase recovery that does not clear `resume.recovery_required`

- [ ] **Step 5: Final commit**

```bash
git add task_plan.md progress.md findings.md CLAUDE.md README.md README_cn.md
git commit -m "docs: mark P0-P5 implementation complete"
```

---

## Self-Review

**1. Spec coverage:**
- Goal 1 (code-quality-reviewer alias): Packet 1 covers validation, pretool gate, and state normalization. ✅
- Goal 2 (P1 scope correction): Packet 2 removes the unsupported `--norc` remediation and syncs active docs to the official mitigation. ✅
- Goal 3 (phase guard): Packet 3 covers tests and implementation. ✅
- Goal 4 (corruption guard): Packet 4 covers init-state.sh and update-state.sh hardening. ✅
- Goal 5 (repo-local planning hold): Packet 5 covers state schema, posttool gate split, template, init, migration, `record-plan-state.sh`, and tests. ✅
- Goal 6 (midstream activation): Packet 6 covers resume-safe `recover_phase_from_state`, activation handler integration, and state/artifact fallback tests. ✅
- Completion claim verification untouched (runs in all phases) — verified in P2 regression test. ✅

**2. Placeholder scan:**
- No "TBD", "TODO", or "implement later". ✅
- All code blocks contain actual code. ✅
- All commands are exact with expected output. ✅

**3. Type consistency:**
- `packet_role` normalization uses consistent string comparison. ✅
- Phase names match state schema. ✅
- `jq -e 'type == "object"'` used consistently in P3. ✅
- `planning.plan_reviewed` is boolean, defaults `false`, and is explicitly described as a repo-local enforcer field. ✅

**4. AGENTS.md packet discipline:**
- Each packet has one primary objective, one main surface area, one verification path. ✅
- Serial/parallel relationships declared. ✅
- No two packets share a primary production file; Packet 7 is the only intentional docs/tracking consolidation packet. ✅
