# Claude Code Hook Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `superpowers-flow-enforcer` reliably enforce the workflow it claims in `README.md` and `CLAUDE.md`, using official Claude Code hook events and a minimal, maintainable state model.

**Architecture:** Keep the plugin centered on `hooks/hooks.json` and a small set of Bash helpers that mutate `flow_state.json`. Implement the redesign as small vertical slices: each slice introduces one behavior change, one test proving it, and the minimal code needed to make it work.

**Tech Stack:** Claude Code plugin hooks JSON, Bash, `jq`, Markdown docs, shell regression tests

---

## AGENTS Task-Splitting Rules

This plan follows the task decomposition style required by `AGENTS.md`:

1. tasks are small, direct, and behavior-oriented
2. each task fixes one real gap instead of bundling unrelated cleanup
3. each task has a concrete verification command
4. implementation should prefer the simplest path that fully solves the problem
5. optional enhancement work stays out of scope unless explicitly requested

## File Structure

### Existing files to modify

- `hooks/hooks.json`
- `scripts/init-state.sh`
- `scripts/sync-user-prompt-state.sh`
- `scripts/sync-post-tool-state.sh`
- `scripts/update-state.sh`
- `templates/flow_state.json.tmpl`
- `README.md`
- `README_cn.md`
- `CLAUDE.md`

### New files to create

- `scripts/migrate-state.sh`
- `scripts/record-spec-state.sh`
- `scripts/record-review-state.sh`
- `scripts/record-finishing-state.sh`
- `scripts/record-worktree-state.sh`
- `tests/helpers/assert.sh`
- `tests/helpers/state-fixtures.sh`
- `tests/test_init_state.sh`
- `tests/test_bypass_state.sh`
- `tests/test_interrupt_state.sh`
- `tests/test_hooks_official_events.sh`
- `tests/test_brainstorming_findings_flow.sh`
- `tests/test_recorded_review_flow.sh`
- `tests/test_worktree_baseline_flow.sh`
- `tests/test_post_tool_use_failure.sh`

### Responsibility map

- `hooks/hooks.json`: official event wiring and gate prompts
- `scripts/init-state.sh`: initialize or recover state at session start
- `scripts/migrate-state.sh`: upgrade older state safely
- `scripts/sync-user-prompt-state.sh`: bypass and text-interrupt parsing
- `scripts/sync-post-tool-state.sh`: successful-tool state sync
- `scripts/record-spec-state.sh`: explicit spec-review and user-approval recording
- `scripts/record-review-state.sh`: explicit per-task review recording
- `scripts/record-finishing-state.sh`: finishing stage recording
- `scripts/record-worktree-state.sh`: explicit worktree and baseline verification recording
- `tests/*`: shell regression tests proving each behavior slice

## Task 1: Create a Minimal Shell Test Harness

**Files:**
- Create: `tests/helpers/assert.sh`
- Create: `tests/helpers/state-fixtures.sh`

- [ ] **Step 1: Write the helper shells**

```bash
# tests/helpers/assert.sh
#!/bin/bash
set -euo pipefail

assert_json_equals() {
  local file="$1" jq_expr="$2" expected="$3"
  local actual
  actual="$(jq -c "$jq_expr" "$file")"
  [ "$actual" = "$expected" ] || {
    echo "Expected $jq_expr = $expected, got $actual" >&2
    exit 1
  }
}

assert_json_missing() {
  local file="$1" jq_expr="$2"
  jq -e "$jq_expr" "$file" >/dev/null 2>&1 && {
    echo "Expected $jq_expr to be missing" >&2
    exit 1
  }
}

assert_file_contains() {
  local file="$1" pattern="$2"
  grep -q "$pattern" "$file" || {
    echo "Expected $file to contain $pattern" >&2
    exit 1
  }
}

assert_file_exists() {
  [ -f "$1" ] || {
    echo "Expected file $1 to exist" >&2
    exit 1
  }
}
```

```bash
# tests/helpers/state-fixtures.sh
#!/bin/bash
set -euo pipefail

write_v1_state() {
  cat > "$1" <<'EOF'
{"current_phase":"brainstorming","brainstorming":{"spec_written":true,"findings_updated":false,"skill_invoked":true},"planning":{"plan_written":false},"tdd":{"tests_verified_fail":[]},"exceptions":{"skip_brainstorming":false,"skip_tdd":false,"skip_review":false,"skip_finishing":false,"user_confirmed":false},"interrupt":{"allowed":false}}
EOF
}

write_v2_state() {
  cat > "$1" <<'EOF'
{"state_version":2,"current_phase":"init","brainstorming":{"question_asked":false,"findings_updated_after_question":false,"spec_written":false,"spec_file":null,"spec_reviewed":false,"user_approved_spec":false},"planning":{"plan_written":false,"plan_file":null},"worktree":{"created":false,"path":null,"baseline_verified":false},"tdd":{"tests_verified_fail":[],"tests_verified_pass":[]},"review":{"tasks":{}},"finishing":{"invoked":false},"exceptions":{"skip_brainstorming":false,"skip_planning":false,"skip_tdd":false,"skip_review":false,"skip_finishing":false,"pending_confirmation_for":null,"reason":null,"user_confirmed":false},"interrupt":{"allowed":false,"reason":null}}
EOF
}

write_unsafe_v1_state() {
  cat > "$1" <<'EOF'
{"current_phase":"planning","brainstorming":"broken","planning":{"plan_written":true},"tdd":{"tests_verified_fail":"bad"}}
EOF
}
```

- [ ] **Step 2: Run the helpers once to verify they are sourceable**

Run: `bash -lc 'source tests/helpers/assert.sh && source tests/helpers/state-fixtures.sh'`
Expected: exit 0

- [ ] **Step 3: Commit**

```bash
git add tests/helpers/assert.sh tests/helpers/state-fixtures.sh
git commit -m "test: add shell test helpers for hook state"
```

## Task 2: Version `flow_state.json` and Migrate Safe v1 State

**Files:**
- Modify: `templates/flow_state.json.tmpl`
- Modify: `scripts/init-state.sh`
- Create: `scripts/migrate-state.sh`
- Create: `tests/test_init_state.sh`
- Test: `tests/test_init_state.sh`

- [ ] **Step 1: Write the failing test for fresh init and safe migration**

```bash
#!/bin/bash
set -euo pipefail

source tests/helpers/assert.sh
source tests/helpers/state-fixtures.sh

TMP_DIR="$(mktemp -d)"
export CLAUDE_PROJECT_DIR="$TMP_DIR/project"
export CLAUDE_PLUGIN_ROOT="$(pwd)"
mkdir -p "$CLAUDE_PROJECT_DIR/.claude"

write_v1_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
bash scripts/init-state.sh >/dev/null

assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.state_version' '2'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.brainstorming.spec_written' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.brainstorming.findings_updated_after_question' 'false'
assert_json_missing "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.brainstorming.skill_invoked'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_init_state.sh`
Expected: FAIL because the template is not versioned and migration does not exist

- [ ] **Step 3: Implement versioned template and safe migration**

```json
{
  "state_version": 2,
  "current_phase": "init",
  "brainstorming": {
    "question_asked": false,
    "findings_updated_after_question": false,
    "spec_written": false,
    "spec_file": null,
    "spec_reviewed": false,
    "user_approved_spec": false
  }
}
```

```bash
# scripts/migrate-state.sh
#!/bin/bash
set -euo pipefail

MODE="${1:-}"
STATE_FILE="${2:-$1}"

if [ "$MODE" = "--check-safe" ]; then
  jq -e '
    (.brainstorming | type) == "object"
    and (.planning | type) == "object"
    and ((.tdd.tests_verified_fail // []) | type) == "array"
  ' "$STATE_FILE" >/dev/null
  exit $?
fi

TMP_FILE="${STATE_FILE}.tmp"
jq '
  .state_version = 2
  | .brainstorming.question_asked = false
  | .brainstorming.findings_updated_after_question = (.brainstorming.findings_updated // false)
  | .brainstorming.spec_reviewed = false
  | .brainstorming.user_approved_spec = false
  | .planning.plan_file = (.planning.plan_file // null)
  | .worktree = (.worktree // {"created":false,"path":null,"baseline_verified":false})
  | .tdd.tests_verified_pass = (.tdd.tests_verified_pass // [])
  | .review = (.review // {"tasks":{}})
  | .finishing = {"invoked":false}
  | .exceptions.skip_planning = (.exceptions.skip_planning // false)
  | .exceptions.pending_confirmation_for = null
  | .interrupt.reason = (.interrupt.reason // null)
  | .migrated_at = (now | todate)
  | del(.brainstorming.skill_invoked, .planning.skill_invoked, .worktree.skill_invoked, .finishing.skill_invoked, .brainstorming.findings_updated)
' "$STATE_FILE" > "$TMP_FILE"

mv "$TMP_FILE" "$STATE_FILE"
```

- [ ] **Step 4: Update `init-state.sh` to initialize or migrate**

Run logic:

```bash
if [ -f "$STATE_FILE" ]; then
  VERSION="$(jq -r '.state_version // 1' "$STATE_FILE" 2>/dev/null || echo invalid)"
  if [ "$VERSION" = "invalid" ]; then
    cp "$STATE_FILE" "${STATE_FILE}.bak"
    # initialize fresh v2 state
  elif [ "$VERSION" -lt 2 ]; then
    if bash "${CLAUDE_PLUGIN_ROOT}/scripts/migrate-state.sh" --check-safe "$STATE_FILE"; then
      bash "${CLAUDE_PLUGIN_ROOT}/scripts/migrate-state.sh" "$STATE_FILE"
    fi
  fi
else
  # initialize fresh v2 state
fi
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash tests/test_init_state.sh`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add templates/flow_state.json.tmpl scripts/init-state.sh scripts/migrate-state.sh tests/test_init_state.sh
git commit -m "fix: version workflow state and migrate safe v1 sessions"
```

## Task 3: Reset Corrupt or Unsafe State Instead of Guessing

**Files:**
- Modify: `scripts/init-state.sh`
- Modify: `scripts/migrate-state.sh`
- Modify: `tests/test_init_state.sh`
- Test: `tests/test_init_state.sh`

- [ ] **Step 1: Extend the failing test for corrupt and unsafe state**

```bash
printf '{invalid json' > "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
bash scripts/init-state.sh >/dev/null
assert_file_exists "$CLAUDE_PROJECT_DIR/.claude/flow_state.json.bak"
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.state_version' '2'

write_unsafe_v1_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
bash scripts/init-state.sh >/dev/null
assert_file_exists "$CLAUDE_PROJECT_DIR/.claude/flow_state.json.bak"
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.current_phase' '"init"'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_init_state.sh`
Expected: FAIL because corrupt or contradictory state is not backed up and reinitialized

- [ ] **Step 3: Implement backup-and-reset behavior**

Unsafe migration cases to treat as reset:

1. parse failure
2. required objects replaced with scalars
3. arrays replaced with non-arrays
4. contradictory phase state that cannot be trusted

Minimal implementation:

```bash
backup_and_reset() {
  cp "$STATE_FILE" "${STATE_FILE}.bak"
  # write fresh template with dynamic fields
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_init_state.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/init-state.sh scripts/migrate-state.sh tests/test_init_state.sh
git commit -m "fix: recover from corrupt or unsafe workflow state"
```

## Task 4: Add `skip_planning` and Narrow Bypass Confirmation

**Files:**
- Modify: `templates/flow_state.json.tmpl`
- Modify: `scripts/sync-user-prompt-state.sh`
- Create: `tests/test_bypass_state.sh`
- Test: `tests/test_bypass_state.sh`

- [ ] **Step 1: Write the failing bypass test**

```bash
#!/bin/bash
set -euo pipefail

source tests/helpers/assert.sh
source tests/helpers/state-fixtures.sh

TMP_DIR="$(mktemp -d)"
export CLAUDE_PROJECT_DIR="$TMP_DIR/project"
mkdir -p "$CLAUDE_PROJECT_DIR/.claude"
write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

printf '{"user_prompt":"skip planning - spec approved"}' | bash scripts/sync-user-prompt-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.skip_planning' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.pending_confirmation_for' '"planning"'

printf '{"user_prompt":"继续"}' | bash scripts/sync-user-prompt-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.user_confirmed' 'false'

printf '{"user_prompt":"confirm skip planning"}' | bash scripts/sync-user-prompt-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.exceptions.user_confirmed' 'true'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_bypass_state.sh`
Expected: FAIL because `skip_planning` and exact pending-phase confirmation do not exist

- [ ] **Step 3: Implement phase-scoped bypass**

Required state shape:

```json
"exceptions": {
  "skip_brainstorming": false,
  "skip_planning": false,
  "skip_tdd": false,
  "skip_review": false,
  "skip_finishing": false,
  "pending_confirmation_for": null,
  "reason": null,
  "user_confirmed": false
}
```

Required behavior:

1. detect the exact phase being skipped
2. set only that phase’s flag
3. require exact confirmation for the pending phase
4. do not let generic “继续” confirm everything

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_bypass_state.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add templates/flow_state.json.tmpl scripts/sync-user-prompt-state.sh tests/test_bypass_state.sh
git commit -m "fix: scope bypass confirmation to a single workflow phase"
```

## Task 5: Keep Text Pause Requests but Stop Overclaiming Interrupt Support

**Files:**
- Modify: `scripts/sync-user-prompt-state.sh`
- Create: `tests/test_interrupt_state.sh`
- Test: `tests/test_interrupt_state.sh`

- [ ] **Step 1: Write the failing interrupt test**

```bash
#!/bin/bash
set -euo pipefail

source tests/helpers/assert.sh
source tests/helpers/state-fixtures.sh

TMP_DIR="$(mktemp -d)"
export CLAUDE_PROJECT_DIR="$TMP_DIR/project"
mkdir -p "$CLAUDE_PROJECT_DIR/.claude"
write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

printf '{"user_prompt":"暂停，明天继续"}' | bash scripts/sync-user-prompt-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.interrupt.allowed' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.interrupt.reason' '"暂停，明天继续"'
```

- [ ] **Step 2: Run test to verify it fails or is incomplete**

Run: `bash tests/test_interrupt_state.sh`
Expected: FAIL if reason/state shape is outdated, or reveal that interrupt fields are not aligned with v2 template

- [ ] **Step 3: Implement the minimal supported interrupt behavior**

Behavior:

1. support text-based pause requests from `UserPromptSubmit`
2. record only conversation-level pause intent
3. do not add code that pretends to intercept true CLI interrupts

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_interrupt_state.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/sync-user-prompt-state.sh tests/test_interrupt_state.sh
git commit -m "fix: keep text pause requests as explicit workflow state"
```

## Task 6: Replace `TaskUpdate` with Official `TaskCompleted` and Handle `stop_hook_active`

**Files:**
- Modify: `hooks/hooks.json`
- Create: `tests/test_hooks_official_events.sh`
- Test: `tests/test_hooks_official_events.sh`

- [ ] **Step 1: Write the failing official-events test**

```bash
#!/bin/bash
set -euo pipefail

source tests/helpers/assert.sh

assert_file_contains hooks/hooks.json '"TaskCompleted"'
assert_file_contains hooks/hooks.json 'stop_hook_active'
assert_file_contains hooks/hooks.json 'skip_planning'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_hooks_official_events.sh`
Expected: FAIL because the config still uses `TaskUpdate`, lacks `stop_hook_active`, and wires planning to the wrong bypass

- [ ] **Step 3: Implement the smallest official-events fix**

Required changes:

1. rename `TaskUpdate` hook to `TaskCompleted`
2. add `stop_hook_active` handling to `Stop`
3. make planning gate depend on `skip_planning`

Representative fragments:

```json
{
  "matcher": "TaskCompleted",
  "hooks": [{ "type": "prompt", "prompt": "Read $TOOL_INPUT and state..." }]
}
```

```json
{
  "type": "prompt",
  "prompt": "If stop_hook_active is true, return {\"decision\":\"approve\"}..."
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_hooks_official_events.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add hooks/hooks.json tests/test_hooks_official_events.sh
git commit -m "fix: align task completion and stop hooks with claude code"
```

## Task 7: Make Brainstorming Findings Enforcement Depend on Real Events

**Files:**
- Modify: `scripts/sync-post-tool-state.sh`
- Modify: `hooks/hooks.json`
- Create: `tests/test_brainstorming_findings_flow.sh`
- Test: `tests/test_brainstorming_findings_flow.sh`

- [ ] **Step 1: Write the failing findings-flow test**

```bash
#!/bin/bash
set -euo pipefail

source tests/helpers/assert.sh
source tests/helpers/state-fixtures.sh

TMP_DIR="$(mktemp -d)"
export CLAUDE_PROJECT_DIR="$TMP_DIR/project"
mkdir -p "$CLAUDE_PROJECT_DIR/.claude"
write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

printf '{"tool_name":"AskUserQuestion"}' | bash scripts/sync-post-tool-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.brainstorming.question_asked' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.brainstorming.findings_updated_after_question' 'false'

printf '{"tool_name":"Write","tool_input":{"file_path":"findings.md"}}' | bash scripts/sync-post-tool-state.sh >/dev/null
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.brainstorming.findings_updated_after_question' 'true'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_brainstorming_findings_flow.sh`
Expected: FAIL because current logic still uses old `findings_updated` state and hook-level `skill_invoked`

- [ ] **Step 3: Implement event-based findings tracking**

Required behavior:

1. `AskUserQuestion` sets `question_asked = true`
2. `AskUserQuestion` clears `findings_updated_after_question`
3. writing `findings.md` sets `findings_updated_after_question = true`
4. hook gate no longer depends on `brainstorming.skill_invoked`

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_brainstorming_findings_flow.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/sync-post-tool-state.sh hooks/hooks.json tests/test_brainstorming_findings_flow.sh
git commit -m "fix: enforce brainstorming findings updates from real events"
```

## Task 8: Add Explicit Spec, Review, and Finishing Recorders

**Files:**
- Create: `scripts/record-spec-state.sh`
- Create: `scripts/record-review-state.sh`
- Create: `scripts/record-finishing-state.sh`
- Modify: `scripts/update-state.sh`
- Create: `tests/test_recorded_review_flow.sh`
- Test: `tests/test_recorded_review_flow.sh`

- [ ] **Step 1: Write the failing recorder-flow test**

```bash
#!/bin/bash
set -euo pipefail

source tests/helpers/assert.sh
source tests/helpers/state-fixtures.sh

TMP_DIR="$(mktemp -d)"
export CLAUDE_PROJECT_DIR="$TMP_DIR/project"
export CLAUDE_PLUGIN_ROOT="$(pwd)"
mkdir -p "$CLAUDE_PROJECT_DIR/.claude"
write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

bash scripts/record-spec-state.sh self-review pass
bash scripts/record-spec-state.sh user-approval pass
bash scripts/record-review-state.sh task-001 spec pass
bash scripts/record-review-state.sh task-001 code pass
bash scripts/record-finishing-state.sh invoked

assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.brainstorming.spec_reviewed' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.brainstorming.user_approved_spec' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.review.tasks["task-001"].spec_review_passed' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.review.tasks["task-001"].code_review_passed' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.finishing.invoked' 'true'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_recorded_review_flow.sh`
Expected: FAIL because explicit recorder scripts do not exist

- [ ] **Step 3: Implement the three recorder scripts**

Representative review recorder:

```bash
#!/bin/bash
set -euo pipefail

TASK_ID="$1"
STAGE="$2"   # spec | code
RESULT="$3"  # pass | fail

FIELD="spec_review_passed"
[ "$STAGE" = "code" ] && FIELD="code_review_passed"

bash "${CLAUDE_PLUGIN_ROOT}/scripts/update-state.sh" --jq \
  ".review.tasks[\"$TASK_ID\"].$FIELD = ($RESULT == \"pass\")"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_recorded_review_flow.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/record-spec-state.sh scripts/record-review-state.sh scripts/record-finishing-state.sh scripts/update-state.sh tests/test_recorded_review_flow.sh
git commit -m "feat: add explicit workflow state recorders"
```

## Task 9: Gate Planning on Spec Review and User Approval

**Files:**
- Modify: `hooks/hooks.json`
- Modify: `tests/test_hooks_official_events.sh`
- Test: `bash tests/test_hooks_official_events.sh && bash tests/test_recorded_review_flow.sh`

- [ ] **Step 1: Extend the failing hook test for planning prerequisites**

Add expectations:

1. the planning gate references `brainstorming.spec_reviewed`
2. the planning gate references `brainstorming.user_approved_spec`

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_hooks_official_events.sh`
Expected: FAIL because planning can still advance without explicit spec review and user approval

- [ ] **Step 3: Update the planning gate**

Required behavior:

1. writing a plan must require both `brainstorming.spec_reviewed == true`
2. writing a plan must require both `brainstorming.user_approved_spec == true`
3. only `skip_planning` can bypass this gate

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test_hooks_official_events.sh && bash tests/test_recorded_review_flow.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add hooks/hooks.json tests/test_hooks_official_events.sh
git commit -m "fix: require spec review before planning"
```

## Task 10: Enforce Worktree Creation and Baseline Verification Before TDD

**Files:**
- Create: `scripts/record-worktree-state.sh`
- Modify: `hooks/hooks.json`
- Modify: `templates/flow_state.json.tmpl`
- Create: `tests/test_worktree_baseline_flow.sh`
- Test: `tests/test_worktree_baseline_flow.sh`

- [ ] **Step 1: Write the failing worktree/baseline test**

```bash
#!/bin/bash
set -euo pipefail

source tests/helpers/assert.sh
source tests/helpers/state-fixtures.sh

TMP_DIR="$(mktemp -d)"
export CLAUDE_PROJECT_DIR="$TMP_DIR/project"
export CLAUDE_PLUGIN_ROOT="$(pwd)"
mkdir -p "$CLAUDE_PROJECT_DIR/.claude"
write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

bash scripts/record-worktree-state.sh created /tmp/wt-1
bash scripts/record-worktree-state.sh baseline pass

assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.created' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.path' '"/tmp/wt-1"'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.baseline_verified' 'true'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_worktree_baseline_flow.sh`
Expected: FAIL because there is no dedicated worktree/baseline recorder and the gate is still tied to loose Bash-result parsing

- [ ] **Step 3: Implement the explicit worktree recorder and gate**

Representative script:

```bash
#!/bin/bash
set -euo pipefail

MODE="$1"   # created | baseline
VALUE="${2:-}"

if [ "$MODE" = "created" ]; then
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/update-state.sh" worktree created true
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/update-state.sh" worktree path "$VALUE"
else
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/update-state.sh" worktree baseline_verified true
fi
```

Required behavior:

1. plan completion no longer implies worktree readiness
2. TDD-facing gates require `worktree.created == true`
3. TDD-facing gates require `worktree.baseline_verified == true`

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_worktree_baseline_flow.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/record-worktree-state.sh hooks/hooks.json templates/flow_state.json.tmpl tests/test_worktree_baseline_flow.sh
git commit -m "feat: add explicit worktree and baseline verification flow"
```

## Task 11: Make `TaskCompleted` and `Stop` Consume the Recorded State

**Files:**
- Modify: `hooks/hooks.json`
- Modify: `templates/flow_state.json.tmpl`
- Test: `bash tests/test_hooks_official_events.sh && bash tests/test_recorded_review_flow.sh`

- [ ] **Step 1: Extend the hook expectations**

Add expectations to `tests/test_hooks_official_events.sh`:

1. `TaskCompleted` references `review.tasks`
2. `Stop` references `finishing.invoked`
3. `Stop` references `interrupt.allowed`
4. `Stop` references fresh verification evidence
5. no gate still depends on `finishing.skill_invoked`

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_hooks_official_events.sh`
Expected: FAIL because hook prompts still reference dead state fields

- [ ] **Step 3: Update hook prompts to consume recorded state**

Required changes:

1. `TaskCompleted` checks `review.tasks[task_id].spec_review_passed`
2. `TaskCompleted` checks `review.tasks[task_id].code_review_passed`
3. `Stop` checks `interrupt.allowed`
4. `Stop` checks for fresh passing verification evidence before allowing completion claims
5. `Stop` checks `finishing.invoked`

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test_hooks_official_events.sh && bash tests/test_recorded_review_flow.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add hooks/hooks.json templates/flow_state.json.tmpl tests/test_hooks_official_events.sh
git commit -m "fix: consume explicit review and finishing state in hooks"
```

## Task 12: Move Failed-Test Debugging to `PostToolUseFailure`

**Files:**
- Modify: `hooks/hooks.json`
- Modify: `scripts/sync-post-tool-state.sh`
- Create: `tests/test_post_tool_use_failure.sh`
- Test: `tests/test_post_tool_use_failure.sh`

- [ ] **Step 1: Write the failing failure-hook test**

```bash
#!/bin/bash
set -euo pipefail

source tests/helpers/assert.sh

assert_file_contains hooks/hooks.json '"PostToolUseFailure"'
assert_file_contains hooks/hooks.json 'systematic-debugging'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_post_tool_use_failure.sh`
Expected: FAIL because failed-test/debug enforcement is not modeled as its own failure hook

- [ ] **Step 3: Implement the official failure-path hook**

Required behavior:

1. keep successful state sync in `PostToolUse`
2. use `PostToolUseFailure` for failed Bash/test commands that should trigger debugging guidance
3. do not rely only on success-path `Bash` result parsing for failure enforcement

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_post_tool_use_failure.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add hooks/hooks.json scripts/sync-post-tool-state.sh tests/test_post_tool_use_failure.sh
git commit -m "fix: route failed-test debugging through post tool use failure"
```

## Task 13: Align README, README_cn, and CLAUDE with Shipped Behavior

**Files:**
- Modify: `README.md`
- Modify: `README_cn.md`
- Modify: `CLAUDE.md`
- Modify: `hooks/hooks.json`
- Test: `bash tests/test_init_state.sh && bash tests/test_bypass_state.sh && bash tests/test_interrupt_state.sh && bash tests/test_hooks_official_events.sh && bash tests/test_brainstorming_findings_flow.sh && bash tests/test_recorded_review_flow.sh && bash tests/test_post_tool_use_failure.sh`

- [ ] **Step 1: Add the failing doc assertions**

Extend `tests/test_hooks_official_events.sh` to assert:

1. docs mention `TaskCompleted`, not `TaskUpdate`
2. docs describe text-based pause support but do not claim to catch true user interrupts
3. docs only mention `check-exception.sh` if the hook actually calls it

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_hooks_official_events.sh`
Expected: FAIL because docs still overstate or mismatch current behavior

- [ ] **Step 3: Update docs with the smallest truthful wording**

Required documentation corrections:

1. use official Claude Code hook names
2. state that text pause requests are supported
3. state that true user interrupts do not trigger `Stop`
4. either wire `check-exception.sh` or remove the claim that it is active

- [ ] **Step 4: Run the full regression suite**

Run: `bash tests/test_init_state.sh && bash tests/test_bypass_state.sh && bash tests/test_interrupt_state.sh && bash tests/test_hooks_official_events.sh && bash tests/test_brainstorming_findings_flow.sh && bash tests/test_recorded_review_flow.sh && bash tests/test_worktree_baseline_flow.sh && bash tests/test_post_tool_use_failure.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add README.md README_cn.md CLAUDE.md hooks/hooks.json tests/test_hooks_official_events.sh
git commit -m "docs: align plugin behavior with official claude code semantics"
```

## Notes for Implementers

1. Use `@superpowers:test-driven-development` on every task.
2. If a step turns into broad refactoring, stop and split again; do not bundle extra cleanup.
3. `planning-with-files-zh` enforcement remains out of scope for this implementation plan unless the human explicitly expands scope.
