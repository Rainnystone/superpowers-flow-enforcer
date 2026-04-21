# SPEC: Fix P0 Naming Mismatch, P1 Shell Profile Pollution, P2 Stop Hook Phase Guard, P3 State File Corruption, and P4 Planning Review Gate

## Context

`superpowers-flow-enforcer` is a Claude Code plugin that enforces workflow-aware hooks for the superpowers skill ecosystem. Five issues were identified during code review and active usage:

1. **P0 (Blocking)**: The plugin's packet role validator rejects `code-quality-reviewer`, but `superpowers:subagent-driven-development` uses this exact role name in its prompt templates.
2. **P1 (Stability)**: Hook scripts spawn bash without `--norc`, making them vulnerable to shell profile pollution (unconditional `echo` in `~/.bashrc`/`~/.zshrc` corrupts JSON stdout parsing).
3. **P2 (Correctness)**: The `Stop` hook enforces review/finishing checks regardless of `current_phase`, causing a deadlock when the session stops during `brainstorming`/`planning` stages where no review records exist yet.
4. **P4 (Design Gap)**: The PostToolUse hook treats the first canonical plan write as "planning complete" and immediately blocks for worktree creation. There is no intermediate state for "plan written but still under review/fix/re-review", making the plan review cycle incompatible with the enforced state machine.

## Goals

### Goal 4: Harden state file against corruption and invalid writes

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

### Goal 1: Accept `code-quality-reviewer` as a valid packet role

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

### Goal 2: Prevent shell profile pollution in hook scripts

Official Claude Code documentation warns that hooks run in non-interactive shells but still source the user's profile. Unconditional `echo` statements in `~/.bashrc` or `~/.zshrc` prepend noise to stdout, breaking JSON parsing.

**Acceptance criteria**:
- All plugin hook scripts invoked via `hooks.json` use `bash --norc` (or equivalent profile-suppressing invocation)
- Windows Git Bash compatibility is maintained (`bash --norc` is supported in Git Bash)
- Hook JSON output remains clean regardless of user shell configuration
- No functional behavior changes other than the execution environment isolation

### Goal 3: Add phase guard to Stop hook

The `Stop` hook (`check-stop-review-gate.sh`) currently blocks any stop when `review.tasks` is empty, even during `brainstorming` or `planning` phases where review records are not expected. It also forces `finishing-a-development-branch` when all reviews pass, even if the session hasn't reached implementation yet.

**Acceptance criteria**:
- Stop hook skips `has_review_records` check when `current_phase` is `init`, `brainstorming`, or `planning`
- Stop hook skips `all_reviews_passed && !finishing.invoked` check when `current_phase` is not `review` or `finishing`
- Stop hook still enforces review/finishing checks in `tdd`, `review`, and `finishing` phases
- Completion claim verification (`fresh_passing_evidence_detected`) continues to run in all phases

### Goal 5: Add plan review gate to planning phase

The `brainstorming` phase has a two-step gate (`spec_written` → `spec_reviewed` + `user_approved_spec`) enforced by `sync-post-tool-state.sh` and `check-pretool-gates.sh`. The `planning` phase has no equivalent gate: `sync-post-tool-state.sh` sets `.planning.plan_written = true` on the first canonical plan write, then immediately blocks all subsequent PostToolUse with "Plan 已写完，先执行 using-git-worktrees...". This makes the plan review → fix → re-review cycle impossible because any plan edit re-triggers the worktree block.

**Acceptance criteria**:
- Canonical plan write sets `.planning.plan_written = true` and `.planning.plan_file`, but does **not** immediately advance to worktree gate
- A new `.planning.plan_reviewed` state field tracks whether the plan has passed review
- PostToolUse blocks with a plan-review message when `plan_written == true && plan_reviewed == false`
- After `plan_reviewed` is set to `true`, the worktree gate becomes active (existing worktree block behavior resumes)
- Re-editing the same canonical plan file while `plan_reviewed == false` does not produce a different or confusing block message
- The `planning` state schema change is reflected in template, init, and migration logic
- `plan_reviewed` defaults to `false` for fresh states, migrated v1 states, and existing v2 states that predate this field (safe via `// false` fallback in gate checks)

## Non-Goals

- No changes to the TDD enforcement logic or subagent internal behavior (as discussed, subagents self-enforce TDD)
- No automation of `record-review-state.sh` (manual marking is acceptable complexity)
- No `if` field optimization on Bash matcher (out of scope for this fix)
- No changes to `sha256sum || shasum` fallback logic (already verified safe)
- No changes to plugin dev mode or hook lifecycle (platform limitation, not fixable in this repo)
- No midstream activation phase recovery rules (e.g., inferring current phase from existing canonical files when `enable enforcer` is issued mid-workstream). The current behavior trusts the existing `.claude/flow_state.json` as-is. Phase recovery semantics can be defined in a future workstream.

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

**`plan_reviewed` write semantics** — The field is initialized to `false` by the canonical plan write hook. Setting it to `true` follows the same manual-marking pattern as `brainstorming.spec_reviewed` (which is set via `record-review-state.sh` or equivalent manual state update). No new automation script is introduced in this fix; the model or user marks plan review completion explicitly, just as they do for spec review. This preserves consistency with the existing `spec_reviewed` pattern without expanding scope.

This preserves the existing worktree gate behavior while inserting a plan review intermediate state. The plan review → fix → re-review cycle is now possible because re-editing the plan while `plan_reviewed == false` continues to block with the same plan-review message rather than jumping ahead to worktree.

**`init-state.sh` / `migrate-state.sh`** — ensure the new field is bootstrapped with default `false`.

### Windows Compatibility Note

Git Bash for Windows (based on MSYS2) supports `bash --norc`. The `--norc` flag is a standard bash option present in all major distributions. No Windows-specific fallback is needed.

## Test Plan

### P0 Tests

1. **Unit test**: Pipe a mock PreToolUse JSON with `SPFE_PACKET_ROLE=code-quality-reviewer` into `check-pretool-gates.sh` and verify exit 0 (not blocked)
2. **Unit test**: Verify `task_flow_packets.sh` extracts `code-quality-reviewer` correctly
3. **Integration test**: Simulate full workflow — implementer → spec-reviewer → code-quality-reviewer → next implementer, verifying each gate allows the dispatch
4. **Regression test**: Confirm `code-reviewer` still works exactly as before

### P1 Tests

1. **Environment test**: Create a fake `~/.bashrc` with `echo "pollution"`, run any hook script via the `hooks.json` command pattern, verify stdout contains only valid JSON
2. **Cross-platform check**: Verify `bash --norc` is available on the target platform (macOS done, Windows Git Bash assumed available)

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
