# SPEC: Fix P0 Naming Mismatch, P1 Shell Profile Pollution, P2 Stop Hook Phase Guard, P3 State File Corruption, P4 Planning Review Gate, and P5 Midstream Activation Recovery

## Context

`superpowers-flow-enforcer` is a Claude Code plugin that enforces workflow-aware hooks for the superpowers skill ecosystem. Six issues were identified during code review and active usage:

1. **P0 (Blocking)**: The plugin's packet role validator rejects `code-quality-reviewer`, but `superpowers:subagent-driven-development` uses this exact role name in its prompt templates.
2. **P1 (Stability)**: Hook scripts spawn bash without `--norc`, making them vulnerable to shell profile pollution (unconditional `echo` in `~/.bashrc`/`~/.zshrc` corrupts JSON stdout parsing).
3. **P2 (Correctness)**: The `Stop` hook enforces review/finishing checks regardless of `current_phase`, causing a deadlock when the session stops during `brainstorming`/`planning` stages where no review records exist yet.
4. **P3 (Robustness)**: `init-state.sh` and `update-state.sh` do not validate that state file writes produce JSON objects, allowing bare scalars (e.g., `false`) to corrupt the state file.
5. **P4 (Design Gap)**: The PostToolUse hook treats the first canonical plan write as "planning complete" and immediately blocks for worktree creation. There is no intermediate state for "plan written but still under review/fix/re-review", making the plan review cycle incompatible with the enforced state machine.
6. **P5 (Recovery)**: When `enable enforcer` is issued mid-workstream, the enforcer sets `workflow.active = true` but does not adjust `current_phase`, leaving it at `init` even when structured state or canonical artifacts indicate the session has progressed further.

## Goals

### Goal 1 (P0): Accept `code-quality-reviewer` as a valid packet role

`superpowers:subagent-driven-development` defines two reviewer roles:
- `spec-reviewer`
- `code-quality-reviewer`

The plugin currently only accepts `code-reviewer`, causing a hard block when users follow the official superpowers prompt templates.

**Acceptance criteria**:
- `SPFE_PACKET_ROLE=code-quality-reviewer` in an Agent dispatch prompt is accepted by the PreToolUse/Agent gate
- The role is treated identically to `code-reviewer` in all state transitions and review ordering logic
- `check-pretool-gates.sh` allows `code-quality-reviewer` to proceed when spec review has passed
- `sync-post-tool-state.sh` records `code-quality-reviewer` dispatch correctly
- Existing `code-reviewer` support is preserved for backward compatibility

### Goal 2 (P1): Prevent shell profile pollution in hook scripts

Official Claude Code documentation warns that hooks run in non-interactive shells but still source the user's profile. Unconditional `echo` statements in `~/.bashrc` or `~/.zshrc` prepend noise to stdout, breaking JSON parsing.

**Acceptance criteria**:
- All plugin hook scripts invoked via `hooks.json` use `bash --norc` (or equivalent profile-suppressing invocation)
- Windows Git Bash compatibility is maintained (`bash --norc` is supported in Git Bash)
- Hook JSON output remains clean regardless of user shell configuration
- No functional behavior changes other than the execution environment isolation

### Goal 3 (P2): Add phase guard to Stop hook

The `Stop` hook (`check-stop-review-gate.sh`) currently blocks any stop when `review.tasks` is empty, even during `brainstorming` or `planning` phases where review records are not expected. It also forces `finishing-a-development-branch` when all reviews pass, even if the session hasn't reached implementation yet.

**Acceptance criteria**:
- Stop hook skips `has_review_records` check when `current_phase` is `init`, `brainstorming`, or `planning`
- Stop hook skips `all_reviews_passed && !finishing.invoked` check when `current_phase` is not `review` or `finishing`
- Stop hook still enforces review/finishing checks in `tdd`, `review`, and `finishing` phases
- Completion claim verification (`fresh_passing_evidence_detected`) continues to run in all phases

### Goal 4 (P3): Harden state file against corruption and invalid writes

`init-state.sh` and `update-state.sh` both write to `.claude/flow_state.json`, but neither validates that the output is a JSON object before persisting it. A malformed or extraction-style jq expression (e.g. `--jq '.workflow.active'`) can write a bare boolean `false` back to the file. On the next session start, `init-state.sh` runs `jq empty` which accepts any valid JSON — including bare scalars — then attempts to index `.state_version` on a boolean, producing:

```
jq: error: Cannot index boolean with string "state_version"
```

**Acceptance criteria**:
- `init-state.sh` rejects any state file whose top-level type is not `object`
- `update-state.sh` refuses to persist a non-object jq result
- When corruption is detected, the state file is backed up and reset from the template
- The backup mechanism preserves the corrupted file for manual inspection
- Existing valid state files are unaffected

### Goal 5 (P4): Add plan review gate to planning phase

The `brainstorming` phase has a two-step gate (`spec_written` → `spec_reviewed` + `user_approved_spec`) enforced by `sync-post-tool-state.sh` and `check-pretool-gates.sh`. The `planning` phase has no equivalent gate: `sync-post-tool-state.sh` sets `.planning.plan_written = true` on the first canonical plan write, then immediately blocks all subsequent PostToolUse with "Plan 已写完，先执行 using-git-worktrees...". This makes the plan review → fix → re-review cycle impossible because any plan edit re-triggers the worktree block.

**Acceptance criteria**:
- Canonical plan write sets `.planning.plan_written = true` and `.planning.plan_file`, but does **not** immediately advance to worktree gate
- A new `.planning.plan_reviewed` state field tracks whether the plan has passed review
- PostToolUse blocks with a plan-review message when `plan_written == true && plan_reviewed == false`
- After `plan_reviewed` is set to `true`, the worktree gate becomes active (existing worktree block behavior resumes)
- Re-editing the same canonical plan file while `plan_reviewed == false` does not produce a different or confusing block message
- The `planning` state schema change is reflected in template, init, and migration logic
- `plan_reviewed` defaults to `false` for fresh states, migrated v1 states, and existing v2 states that predate this field (safe via `// false` fallback in gate checks)

### Goal 6 (P5): Midstream activation phase recovery

When `enable enforcer` is issued mid-workstream, the enforcer currently only sets `workflow.active = true` without adjusting `current_phase`. This leaves `current_phase` at `init` even when structured state fields or canonical artifacts indicate the session has already progressed through brainstorming, planning, or implementation phases. The enforcer must recover the correct phase so that subsequent hooks enforce the right gates.

**Recovery rules** (evaluated in order; first match wins):
1. If `.finishing.invoked == true` → `current_phase = "finishing"`
2. If `.review.tasks` is non-empty → `current_phase = "review"`
3. If `.tdd.current_task` is non-null or `.worktree.created == true` → `current_phase = "tdd"`
4. If `.planning.plan_written == true` → `current_phase = "planning"`
5. If `.brainstorming.spec_written == true` → `current_phase = "brainstorming"`
6. Otherwise → keep `current_phase = "init"`

**Fallback rules** (used only when state file lacks the relevant field):
- If `docs/superpowers/plans/*.md` exists in the project → `current_phase = "planning"`
- If `docs/superpowers/specs/*.md` exists in the project → `current_phase = "brainstorming"`

**Acceptance criteria**:
- `enable enforcer` sets `workflow.active = true` AND adjusts `current_phase` based on the recovery rules above
- Recovery is based solely on structured state fields first, then deterministic artifacts as fallback
- Recovery does not infer phase from natural language, user prompts, or assistant prose
- When no state fields or artifacts indicate progress, `current_phase` stays at `init`
- The recovery logic runs inside `sync-user-prompt-state.sh` during the `is_manual_activate_exact_command` handler
- Existing `disable enforcer` behavior is unaffected

## Non-Goals

- No changes to the TDD enforcement logic or subagent internal behavior (as discussed, subagents self-enforce TDD)
- No automation of `record-review-state.sh` (manual marking is acceptable complexity)
- No `if` field optimization on Bash matcher (out of scope for this fix)
- No changes to `sha256sum || shasum` fallback logic (already verified safe)
- No changes to plugin dev mode or hook lifecycle (platform limitation, not fixable in this repo)
- No midstream activation natural-language inference. Phase recovery after `enable enforcer` must never infer phase from free-form user prompts, assistant prose, or keyword matching. This prevents an unbounded keyword-enumeration problem and keeps recovery logic finite, auditable, and testable.

## Design

### P0: Role alias mapping

`code-quality-reviewer` is semantically identical to `code-reviewer` in the superpowers workflow. The cleanest fix is to accept both role names at validation boundaries and normalize `code-quality-reviewer` to `code-reviewer` internally for state storage.

Files to modify:
- `scripts/lib/task_flow_packets.sh` — expand accepted role set in Python validation
- `scripts/check-pretool-gates.sh` — expand `is_supported_packet_role` and `case` logic
- `scripts/sync-post-tool-state.sh` — normalize role before writing to `task_flow.active_packet_role`

### P1: `--norc` isolation

Two possible approaches:

**Option A**: Change shebang in every script to `#!/bin/bash --norc`
- Pros: self-documenting, no hooks.json changes
- Cons: shebang flags are ignored when scripts are invoked as `bash script.sh` rather than `./script.sh`

**Option B**: Change `hooks.json` command strings from `bash ${CLAUDE_PLUGIN_ROOT}/scripts/xxx.sh` to `bash --norc ${CLAUDE_PLUGIN_ROOT}/scripts/xxx.sh`
- Pros: guaranteed to take effect regardless of invocation style
- Cons: slightly longer command strings

**Decision**: Option B. The plugin's `hooks.json` already uses explicit `bash ${CLAUDE_PLUGIN_ROOT}/...` invocations, so `--norc` can be injected there without touching every script file. This also avoids any risk of shebang-flag stripping on Windows.

### P2: Stop hook phase guard

Add a `current_phase` read early in `check-stop-review-gate.sh`, then gate the two restrictive checks behind phase conditions:

```bash
CURRENT_PHASE="$(jq -r '.current_phase // "init"' "$STATE_FILE")"

# Review check only in phases where review is expected
if [ "$CURRENT_PHASE" = "tdd" ] || [ "$CURRENT_PHASE" = "review" ] || [ "$CURRENT_PHASE" = "finishing" ]; then
  if [ "$SKIP_REVIEW_CONFIRMED" != true ] && ! has_review_records; then
    block_stop '还没有 review 记录，先执行 requesting-code-review 的两阶段评审。'
    exit 0
  fi
fi

# Finishing check only when actually in finishing or review phase
if [ "$CURRENT_PHASE" = "review" ] || [ "$CURRENT_PHASE" = "finishing" ]; then
  if [ "$SKIP_FINISHING_CONFIRMED" != true ] && all_reviews_passed && ! state_expr_is_true '.finishing.invoked'; then
    block_stop '所有任务都已 review，通过后还需执行 finishing-a-development-branch。'
    exit 0
  fi
fi
```

This preserves the completion claim check (`completion_claim_detected` + `fresh_passing_evidence_detected`) for all phases, which is correct — you should never claim completion without evidence regardless of phase.

### P3: State file corruption guard

Two scripts need hardening:

**`init-state.sh`** — Replace the weak `jq empty` check at line 189 with a type assertion:

```bash
# Before
if ! jq empty "$STATE_FILE" >/dev/null 2>&1; then
    backup_and_reset_state
# After
if ! jq -e 'type == "object"' "$STATE_FILE" >/dev/null 2>&1; then
    backup_and_reset_state
```

`jq -e 'type == "object"'` returns exit 0 only when the top-level JSON value is an object. Bare scalars (`false`, `"string"`, `42`, `null`) and arrays all return exit 1, triggering the existing `backup_and_reset_state` path which preserves the corrupted file as `.bak` and reinitializes from the template.

**`update-state.sh`** — Add a guard in `write_tmp_and_swap` before the atomic `mv`:

```bash
write_tmp_and_swap() {
  local expr="$1"
  local tmp_file
  tmp_file="${STATE_FILE}.tmp"
  jq "$expr" "$STATE_FILE" > "$tmp_file"

  # Guard: refuse to persist non-object jq results
  if ! jq -e 'type == "object"' "$tmp_file" >/dev/null 2>&1; then
    echo '{"error":"State mutation produced non-object JSON; aborting to prevent corruption"}'
    rm -f "$tmp_file"
    exit 1
  fi

  mv "$tmp_file" "$STATE_FILE"
}
```

This prevents any jq expression that extracts a scalar or array from corrupting the state file. The caller receives a JSON error and the original state file is untouched.

### P4: Planning review gate

The `brainstorming` phase already models a review gate with `.brainstorming.spec_written` → `.brainstorming.spec_reviewed` → `.brainstorming.user_approved_spec`. The `planning` phase should follow the same pattern.

**State schema change** — add `.planning.plan_reviewed` (bool, default `false`) to `templates/flow_state.json.tmpl`.

**`sync-post-tool-state.sh` change** — on canonical plan write:
1. Set `.planning.plan_written = true` and `.planning.plan_file` (existing behavior)
2. Also set `.planning.plan_reviewed = false` (new)
3. Change the PostToolUse block condition from:
   ```bash
   if [ "$PLAN_WRITE_RECORDED" = "true" ] && ! state_is_true '.worktree.created'; then
   ```
   to:
   ```bash
   if [ "$PLAN_WRITE_RECORDED" = "true" ] && ! state_is_true '.planning.plan_reviewed'; then
       block_posttool "Plan 已写入，请先完成 plan review 并让用户批准后再进入 worktree 阶段。"
   fi
   ```
4. Add a second gate for the worktree phase after plan review passes:
   ```bash
   if state_is_true '.planning.plan_reviewed' && ! state_is_true '.worktree.created'; then
       block_posttool "Plan 已通过 review，先执行 using-git-worktrees 创建隔离工作区并跑 baseline tests。"
   fi
   ```

**`plan_reviewed` write semantics** — The field is initialized to `false` by the canonical plan write hook. Setting it to `true` uses a dedicated script `scripts/record-plan-state.sh` that mirrors the existing `scripts/record-spec-state.sh` pattern. Usage:

```bash
# Mark plan review as passed
record-plan-state.sh plan-reviewed pass

# Mark plan review as failed (resets to false)
record-plan-state.sh plan-reviewed fail
```

The script writes `{planning:{plan_reviewed:<value>}}` via `update-state.sh --merge`, identical to how `record-spec-state.sh` writes `{brainstorming:{spec_reviewed:<value>}}`. This keeps the write entry explicit, auditable, and consistent with the brainstorming gate pattern.

This preserves the existing worktree gate behavior while inserting a plan review intermediate state. The plan review → fix → re-review cycle is now possible because re-editing the plan while `plan_reviewed == false` continues to block with the same plan-review message rather than jumping ahead to worktree.

**`init-state.sh` / `migrate-state.sh`** — ensure the new field is bootstrapped with default `false`.

**New script: `scripts/record-plan-state.sh`** — mirrors `scripts/record-spec-state.sh`:

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

Files to modify for P4:
- `templates/flow_state.json.tmpl` — add `plan_reviewed` field
- `scripts/sync-post-tool-state.sh` — set `plan_reviewed = false` on write; split gate
- `scripts/migrate-state.sh` — bootstrap default
- Create: `scripts/record-plan-state.sh` — write entry for `plan_reviewed`

### P5: Midstream activation phase recovery

The activation handler in `sync-user-prompt-state.sh` (lines 228-242) currently sets `workflow.active = true` without adjusting `current_phase`. When `enable enforcer` is issued after work has already begun (e.g., spec written, plan written, worktree created), the enforcer stays at `current_phase = "init"`, causing all subsequent phase-aware hooks to enforce the wrong gates.

**`sync-user-prompt-state.sh` change** — after setting `workflow.active = true`, add phase recovery logic:

```bash
if is_manual_activate_exact_command "$PROMPT_LC"; then
  RECOVERED_PHASE="$(recover_phase_from_state "$STATE_FILE")"
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

Where `recover_phase_from_state` is a new function:

```bash
recover_phase_from_state() {
  local state_file="$1"

  # State-first recovery: check structured fields in priority order
  if jq -e '.finishing.invoked == true' "$state_file" >/dev/null 2>&1; then
    echo "finishing"; return 0
  fi
  if jq -e '.review.tasks | length > 0' "$state_file" >/dev/null 2>&1; then
    echo "review"; return 0
  fi
  if jq -e '.tdd.current_task != null or .worktree.created == true' "$state_file" >/dev/null 2>&1; then
    echo "tdd"; return 0
  fi
  if jq -e '.planning.plan_written == true' "$state_file" >/dev/null 2>&1; then
    echo "planning"; return 0
  fi
  if jq -e '.brainstorming.spec_written == true' "$state_file" >/dev/null 2>&1; then
    echo "brainstorming"; return 0
  fi

  # Artifact fallback: check canonical file existence
  local project_dir="${CLAUDE_PROJECT_DIR:-.}"
  if compgen -G "$project_dir/docs/superpowers/plans/*.md" >/dev/null 2>&1; then
    echo "planning"; return 0
  fi
  if compgen -G "$project_dir/docs/superpowers/specs/*.md" >/dev/null 2>&1; then
    echo "brainstorming"; return 0
  fi

  echo "init"
}
```

Files to modify for P5:
- `scripts/sync-user-prompt-state.sh` — add `recover_phase_from_state` function and integrate into activation handler

### Windows Compatibility Note

Git Bash for Windows (based on MSYS2) supports `bash --norc`. The `--norc` flag is a standard bash option present in all major distributions. No Windows-specific fallback is needed.

## Test Plan

### P0 Tests

1. **Unit test**: Pipe a mock PreToolUse JSON with `SPFE_PACKET_ROLE=code-quality-reviewer` into `check-pretool-gates.sh` and verify exit 0 (not blocked)
2. **Unit test**: Verify `task_flow_packets.sh` extracts `code-quality-reviewer` correctly
3. **Integration test**: Simulate full workflow — implementer → spec-reviewer → code-quality-reviewer → next implementer, verifying each gate allows the dispatch
4. **Regression test**: Confirm `code-reviewer` still works exactly as before

### P1 Tests

1. **Behavioral test**: Create a fake rcfile with `echo "PROFILE_POLLUTION"`, use `bash --rcfile <fake-rcfile> -i -c 'echo ...'` to prove pollution reaches stdout, then use `bash --norc --rcfile <fake-rcfile> -i -c 'echo ...'` to prove `--norc` suppresses it and output is valid JSON
2. **Config test**: Verify `hooks.json` contains `bash --norc` in all command entries
3. **Cross-platform check**: Verify `bash --norc` is available on the target platform (macOS done, Windows Git Bash assumed available)

### P2 Tests

1. **Unit test**: Simulate `current_phase=brainstorming`, empty `review.tasks`, verify Stop hook exits 0 (not blocked)
2. **Unit test**: Simulate `current_phase=planning`, empty `review.tasks`, verify Stop hook exits 0
3. **Unit test**: Simulate `current_phase=tdd`, empty `review.tasks`, verify Stop hook blocks with "还没有 review 记录"
4. **Unit test**: Simulate `current_phase=review`, all reviews passed, `finishing.invoked=false`, verify Stop hook blocks with "finishing-a-development-branch"
5. **Regression test**: Verify completion claim check still works in all phases

### P3 Tests

1. **Unit test**: Write `false` to `.claude/flow_state.json`, run `init-state.sh`, verify it triggers `backup_and_reset_state` and produces valid object state
2. **Unit test**: Write `42` to `.claude/flow_state.json`, run `init-state.sh`, verify backup + reset
3. **Unit test**: Write `"string"` to `.claude/flow_state.json`, run `init-state.sh`, verify backup + reset
4. **Unit test**: Valid v2 object state, run `init-state.sh`, verify no reset and state preserved
5. **Unit test**: Run `update-state.sh --jq '.workflow.active'` on valid state, verify it aborts with error JSON and leaves original state untouched
6. **Unit test**: Run `update-state.sh --jq '.workflow.active = true'` on valid state, verify it succeeds and state remains object
7. **Regression test**: Run `update-state.sh brainstorming spec_written true`, verify normal merge path unaffected

### P4 Tests

1. **Unit test**: Simulate `spec_reviewed = true` then write canonical plan, verify PostToolUse blocks with "plan review" message (not "using-git-worktrees")
2. **Unit test**: Same state, set `planning.plan_reviewed = true`, verify PostToolUse allows (or blocks with worktree message on subsequent non-plan writes)
3. **Unit test**: Write canonical plan, modify it again while `plan_reviewed = false`, verify block message stays consistent (plan review, not worktree)
4. **Schema test**: Verify `templates/flow_state.json.tmpl` contains `planning.plan_reviewed` with default `false`
5. **Migration test**: Verify existing state without `planning.plan_reviewed` behaves as `false` (jq `// false` fallback)

### P5 Tests

1. **Unit test**: State with `planning.plan_written = true`, `current_phase = "init"`, issue `enable enforcer`, verify `current_phase` becomes `"planning"`
2. **Unit test**: State with `brainstorming.spec_written = true` only, verify recovery sets `current_phase = "brainstorming"`
3. **Unit test**: State with `worktree.created = true`, verify recovery sets `current_phase = "tdd"`
4. **Unit test**: State with `review.tasks` non-empty, verify recovery sets `current_phase = "review"`
5. **Unit test**: State with `finishing.invoked = true`, verify recovery sets `current_phase = "finishing"`
6. **Unit test**: Empty state (all defaults), verify recovery keeps `current_phase = "init"`
7. **Artifact fallback test**: State with no structured fields but `docs/superpowers/specs/*.md` exists, verify recovery sets `current_phase = "brainstorming"`
8. **Regression test**: `disable enforcer` still works without phase recovery side effects

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| `code-quality-reviewer` normalization misses an edge case | Low | Medium | Comprehensive grep for all role checks; add tests |
| `--norc` breaks some hook that relied on profile env vars | Very Low | Low | Hooks are self-contained scripts; they do not depend on user shell env |
| Windows Git Bash lacks `--norc` | Very Low | Medium | `--norc` is standard bash; Git Bash uses real bash |
| Phase guard is too permissive and skips review check in wrong phase | Low | High | Test with explicit `current_phase` values; keep check in `tdd/review/finishing` |
| `jq -e 'type == "object"'` has unexpected edge case | Very Low | Low | `type` is a core jq primitive; thoroughly tested in jq itself |
| `update-state.sh` abort breaks legitimate scalar extraction use case | Very Low | Low | No legitimate use case exists for writing scalars back to state file |
| `planning.plan_reviewed` field breaks existing state without migration | Low | Medium | Use jq `// false` fallback in gate checks; migration script sets default |
| Plan review gate delays worktree creation for existing workflows | Low | Low | The gate only adds one explicit approval step; existing spec-review gate already does this |
| Two-step planning gate (plan review → worktree) confuses users | Low | Low | Block messages are explicit about which step is missing |
| Midstream recovery picks wrong phase | Low | Medium | Recovery rules are ordered by most-advanced-first; test each state field independently |
| `compgen -G` not available on all platforms | Very Low | Medium | Git Bash and macOS bash both support `compgen -G`; fallback can use `ls` if needed |
| Recovery overwrites manually-set `current_phase` | Low | Medium | Recovery only runs on `enable enforcer`; once active, normal phase transitions take over |
