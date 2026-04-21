# SPEC: Fix P0 Naming Mismatch, P1 Shell Profile Pollution, P2 Stop Hook Phase Guard, P3 State File Corruption, P4 Planning Review Gate, and P5 Midstream Activation Recovery

## Context

`superpowers-flow-enforcer` is a Claude Code plugin that enforces workflow-aware hooks for the superpowers skill ecosystem. Six issues were identified during code review and active usage:

1. **P0 (Compatibility)**: The plugin's packet role validator rejects `code-quality-reviewer`. Some adjacent review prompts and local workflows use that wording, but the repo should treat it as an optional compatibility alias rather than claiming upstream superpowers has already standardized the exact `SPFE_PACKET_ROLE=code-quality-reviewer` string.
2. **P1 (Runtime Boundary)**: Claude Code's hook launcher sources the user's shell profile before executing the configured hook command. The current `bash --norc` proposal only changes the inner bash invocation, so the active docs/spec must stop claiming that it fixes outer-shell profile pollution.
3. **P2 (Correctness)**: The `Stop` hook enforces review/finishing checks regardless of `current_phase`, causing a deadlock when the session stops during `brainstorming`/`planning` stages where no review records exist yet.
4. **P3 (Robustness)**: `init-state.sh` and `update-state.sh` do not validate that state file writes produce JSON objects, allowing bare scalars (e.g., `false`) to corrupt the state file.
5. **P4 (Local Workflow Gap)**: The current plugin's local post-plan flow treats the first canonical plan write as an immediate handoff to worktree creation. That leaves no stable state for a local plan review / fix / re-review loop inside this repo's enforced workflow.
6. **P5 (Recovery Contract)**: When `enable enforcer` is issued mid-workstream, the enforcer sets `workflow.active = true` but does not adjust `current_phase`, leaving it at `init` even when structured state or canonical artifacts indicate the session has progressed further. Any recovery logic must preserve the existing `resume-enforcer` contract and current canonical-path semantics.

## Goals

### Goal 1 (P0): Accept `code-quality-reviewer` as an optional compatibility alias

`code-reviewer` remains this plugin's primary public packet role. However, some local review prompts and adjacent superpowers terminology use `code-quality-reviewer`. The plugin should optionally accept that spelling as a compatibility alias and normalize it internally, without claiming that upstream superpowers already requires the exact alias in its official packet contract.

**Acceptance criteria**:
- `SPFE_PACKET_ROLE=code-quality-reviewer` in an Agent dispatch prompt is accepted by the PreToolUse/Agent gate
- The role is treated identically to `code-reviewer` in all state transitions and review ordering logic
- `check-pretool-gates.sh` allows `code-quality-reviewer` to proceed when spec review has passed
- `sync-post-tool-state.sh` records `code-quality-reviewer` dispatch correctly
- Existing `code-reviewer` support is preserved for backward compatibility

### Goal 2 (P1): Correct the P1 scope and stop claiming an unsupported repo-side fix

Official Claude Code documentation says the shell spawned for hooks sources the user's profile before the configured hook command runs. That means unconditional `echo` statements in `~/.bashrc` / `~/.zshrc` can corrupt hook JSON before any inner `bash --norc ...` command ever starts. This repo should not claim that changing `hooks.json` command strings fixes that outer-shell behavior.

**Acceptance criteria**:
- Active spec/plan and user-facing docs no longer claim that `bash --norc` in `hooks.json` solves Claude Code's documented outer-shell profile pollution path
- README / CLAUDE guidance points users to the official mitigation: guard profile output so it only runs in interactive shells
- No hook command-string rewrite is proposed unless it is independently proven against the real Claude Code hook runtime
- Existing hook wiring and official hook-event tests remain unchanged in this batch

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

### Goal 5 (P4): Add a repo-local plan-review hold before the existing worktree gate

The plugin's current local workflow already treats a canonical plan write as entry into planning and then immediately blocks for worktree creation. That local contract leaves no stable state for plan review / fix / re-review inside this repo. If the repo keeps that local order, the additional hold must be documented as a repo-local enforcer extension rather than as an upstream superpowers rule.

**Acceptance criteria**:
- Canonical plan write sets `.planning.plan_written = true` and `.planning.plan_file`, but PostToolUse blocks with a stable local plan-review message instead of immediately escalating to the worktree gate
- A new `.planning.plan_reviewed` field tracks whether this repo-local planning hold has been cleared
- After `plan_reviewed` is set to `true`, the existing local worktree gate becomes active again
- Re-editing the same canonical plan file while `plan_reviewed == false` does not produce a different or confusing block message
- The `planning` state schema change is reflected in template, init, and migration logic
- Docs/spec/plan describe `plan_reviewed` as a repo-local enforcer state, not as an upstream superpowers requirement

### Goal 6 (P5): Midstream activation phase recovery

When `enable enforcer` is issued mid-workstream, the enforcer currently only sets `workflow.active = true` without adjusting `current_phase`. This leaves `current_phase` at `init` even when structured state fields or canonical artifacts indicate the session has already progressed through brainstorming, planning, worktree setup, debugging, or implementation phases. The enforcer must recover phase conservatively, without breaking the existing resume-enforcer protocol or misclassifying historical review state as an active review phase.

**Recovery rules** (evaluated in order; first match wins):
1. If `.current_phase` is already one of `brainstorming`, `planning`, `worktree`, `tdd`, `review`, `debugging`, or `finishing` → keep it as-is
2. If `.finishing.invoked == true` → `current_phase = "finishing"`
3. If `.debugging.active == true` → `current_phase = "debugging"`
4. If `.worktree.created == true` and `.worktree.baseline_verified != true` → `current_phase = "worktree"`
5. If `.tdd.current_task` is non-null or `.worktree.baseline_verified == true` → `current_phase = "tdd"`
6. If `.planning.plan_written == true` → `current_phase = "planning"`
7. If `.brainstorming.spec_written == true` → `current_phase = "brainstorming"`
8. Otherwise → keep `current_phase = "init"`

**Fallback rules** (used only when state file lacks the relevant field):
- Use the already-resolved project root from `sync-user-prompt-state.sh`; do not fall back to raw `CLAUDE_PROJECT_DIR:-.`
- Reuse the repo's existing canonical path semantics, including subtree canonical paths, alias/cwd-derived paths, and excluded trees such as `.git`, `.worktrees`, `vendor`, `.simulation`, and fixture/testdata directories
- If a supported canonical plan artifact exists anywhere in the project scope → `current_phase = "planning"`
- Else if a supported canonical spec artifact exists anywhere in the project scope → `current_phase = "brainstorming"`

**Acceptance criteria**:
- `enable enforcer` sets `workflow.active = true` AND adjusts `current_phase` based on the recovery rules above
- Recovery is based solely on structured state fields first, then deterministic artifacts as fallback
- Recovery does not infer phase from natural language, user prompts, or assistant prose
- When no state fields or artifacts indicate progress, `current_phase` stays at `init`
- The recovery logic runs inside `sync-user-prompt-state.sh` during the `is_manual_activate_exact_command` handler
- `enable enforcer` does **not** clear `resume.recovery_required`; if resume recovery is pending, `/superpowers-flow-enforcer:resume-enforcer` remains mandatory before new Edit/Write/Agent operations
- Recovery does **not** use `.review.tasks` by itself to infer an active `review` phase
- Existing `disable enforcer` behavior is unaffected

## Non-Goals

- No changes to the TDD enforcement logic or subagent internal behavior (as discussed, subagents self-enforce TDD)
- No automation of `record-review-state.sh` (manual marking is acceptable complexity)
- No `if` field optimization on Bash matcher (out of scope for this fix)
- No changes to `sha256sum || shasum` fallback logic (already verified safe)
- No repo-side attempt to suppress Claude Code's outer-shell startup output from inside `hooks.json`; that runtime behavior is treated as a platform boundary in this batch
- No changes to plugin dev mode or hook lifecycle (platform limitation, not fixable in this repo)
- No midstream activation natural-language inference. Phase recovery after `enable enforcer` must never infer phase from free-form user prompts, assistant prose, or keyword matching. This prevents an unbounded keyword-enumeration problem and keeps recovery logic finite, auditable, and testable.

## Design

### P0: Role alias mapping

`code-quality-reviewer` should be treated as a compatibility alias for the existing `code-reviewer` role. The cleanest fix is to accept both role names at validation boundaries and normalize `code-quality-reviewer` to `code-reviewer` internally for state storage, while keeping `code-reviewer` as the repo's primary documented contract.

Files to modify:
- `scripts/lib/task_flow_packets.sh` — expand accepted role set in Python validation
- `scripts/check-pretool-gates.sh` — expand `is_supported_packet_role` and `case` logic
- `scripts/sync-post-tool-state.sh` — normalize role before writing to `task_flow.active_packet_role`

### P1: Treat shell profile pollution as a documented hook-runtime limitation

Claude Code's official hook documentation places this failure mode outside the plugin's inner bash invocation boundary: the hook launcher sources the user's shell profile before it evaluates the configured command string. As a result, changing `hooks.json` from `bash ...` to `bash --norc ...` does not prove that the real pollution path is fixed.

**Decision**: Do not change `hooks/hooks.json` in this batch. Instead:

1. Remove the incorrect `--norc` remediation from the active spec/plan.
2. Update README / README_cn / CLAUDE to explain the official mitigation: wrap profile output in an interactive-shell guard (`if [[ $- == *i* ]]; then ... fi`).
3. Keep the existing hook wiring unchanged unless a future change is validated against the real Claude Code hook runtime rather than a nested-shell approximation.

Files to modify for P1:
- `README.md`
- `README_cn.md`
- `CLAUDE.md`

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

This is a repo-local enforcer extension, not an upstream superpowers contract. The current plugin already treats canonical plan writes as the point where the local workflow enters planning and then advances toward worktree creation. The missing piece is a stable hold state for plan review / fix / re-review before the existing local worktree gate resumes.

**State schema change** — add `.planning.plan_reviewed` (bool, default `false`) to `templates/flow_state.json.tmpl`.

**`sync-post-tool-state.sh` change** — on canonical plan write:
1. Set `.planning.plan_written = true` and `.planning.plan_file` (existing behavior)
2. Also set `.planning.plan_reviewed = false` (new)
3. Replace the current one-shot plan-write block with a persistent state-based hold:
   ```bash
   if state_is_true '.planning.plan_written' && ! state_is_true '.planning.plan_reviewed'; then
       block_posttool "Plan 已写入，请先完成 plan review，再进入 worktree 阶段。"
   fi
   ```
4. Keep the worktree gate behind the review hold:
   ```bash
   if state_is_true '.planning.plan_reviewed' && ! state_is_true '.worktree.created'; then
       block_posttool "Plan 已通过 review，先执行 using-git-worktrees 创建隔离工作区并跑 baseline tests。"
   fi
   ```

This hold must be driven by persisted state, not only by whether the *current* PostToolUse event happened to write the plan file. Otherwise a later unrelated write would bypass the local plan-review stage.

**`plan_reviewed` write semantics** — The field is initialized to `false` by the canonical plan write hook. Setting it to `true` uses a dedicated script `scripts/record-plan-state.sh` that mirrors the existing `scripts/record-spec-state.sh` pattern. Usage:

```bash
# Mark plan review as passed
record-plan-state.sh plan-reviewed pass

# Mark plan review as failed (resets to false)
record-plan-state.sh plan-reviewed fail
```

The script writes `{planning:{plan_reviewed:<value>}}` via `update-state.sh --merge`, keeping the local review-clear signal explicit and auditable.

This preserves the existing local worktree gate behavior while inserting a repo-local plan-review hold. The plan review → fix → re-review cycle is now possible because any later PostToolUse event while `plan_reviewed == false` continues to block with the same plan-review message rather than jumping ahead to worktree or silently bypassing the hold.

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
- `scripts/sync-post-tool-state.sh` — set `plan_reviewed = false` on write; replace one-shot gate with persistent hold + worktree gate
- `scripts/migrate-state.sh` — bootstrap default
- Create: `scripts/record-plan-state.sh` — write entry for `plan_reviewed`

### P5: Midstream activation phase recovery

The activation handler in `sync-user-prompt-state.sh` (lines 228-242) currently sets `workflow.active = true` without adjusting `current_phase`. When `enable enforcer` is issued after work has already begun (e.g., spec written, plan written, worktree created), the enforcer stays at `current_phase = "init"`, causing all subsequent phase-aware hooks to enforce the wrong gates.

**`sync-user-prompt-state.sh` change** — after setting `workflow.active = true`, add conservative phase recovery logic:

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

The activation handler must **not** clear `resume.recovery_required`. Manual enable should refresh phase-aware hook state, but a pending resumed-workflow recovery still has to go through `/superpowers-flow-enforcer:resume-enforcer`.

Where `recover_phase_from_state` is a new function:

```bash
recover_phase_from_state() {
  local state_file="$1"
  local project_dir="$2"
  local current_phase

  current_phase="$(jq -r '.current_phase // "init"' "$state_file" 2>/dev/null || echo init)"
  case "$current_phase" in
    brainstorming|planning|worktree|tdd|review|debugging|finishing)
      echo "$current_phase"; return 0 ;;
  esac

  # State-first recovery: check structured fields in priority order
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

  # Artifact fallback: reuse existing canonical-path semantics
  if project_contains_canonical_artifact "$project_dir" "plan"; then
    echo "planning"; return 0
  fi
  if project_contains_canonical_artifact "$project_dir" "spec"; then
    echo "brainstorming"; return 0
  fi

  echo "init"
}
```

`project_contains_canonical_artifact` should reuse the repo's existing canonical path classifier semantics from `scripts/lib/workflow_paths.sh` rather than hard-coding only `project_root/docs/superpowers/...`.

Files to modify for P5:
- `scripts/sync-user-prompt-state.sh` — add `recover_phase_from_state` function and integrate into activation handler
- `scripts/lib/workflow_paths.sh` — optional helper if needed to reuse canonical artifact semantics without duplicating subtree / exclusion rules

### Platform Note

This batch does not change hook command strings for profile-pollution handling, so there is no Windows-specific shell-flag work here. Platform-specific guidance stays in the user docs and follows Claude Code's documented hook behavior.

## Test Plan

### P0 Tests

1. **Unit test**: Pipe a mock PreToolUse JSON with `SPFE_PACKET_ROLE=code-quality-reviewer` into `check-pretool-gates.sh` and verify exit 0 (not blocked)
2. **Unit test**: Verify `task_flow_packets.sh` extracts `code-quality-reviewer` correctly
3. **Integration test**: Simulate full workflow — implementer → spec-reviewer → code-quality-reviewer → next implementer, verifying each gate allows the dispatch
4. **Regression test**: Confirm `code-reviewer` still works exactly as before

### P1 Tests

1. **Docs check**: Verify README / README_cn / CLAUDE explain the official interactive-shell guard mitigation for profile `echo` output
2. **Contract check**: Verify the active spec/plan no longer claim that `bash --norc` in `hooks.json` fixes Claude Code's outer-shell hook pollution path
3. **Regression test**: Run `tests/test_hooks_official_events.sh` to confirm no unintended hook command-string change is introduced by this batch

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

1. **Unit test**: Simulate `spec_reviewed = true` then write canonical plan, verify PostToolUse blocks with a stable plan-review message (not "using-git-worktrees")
2. **Unit test**: Same state, set `planning.plan_reviewed = true`, verify a subsequent non-plan write hits the existing local worktree gate
3. **Unit test**: Write canonical plan, modify it again while `plan_reviewed = false`, verify block message stays consistent (plan review, not worktree)
4. **Schema test**: Verify `templates/flow_state.json.tmpl` contains `planning.plan_reviewed` with default `false`
5. **Migration test**: Verify existing state without `planning.plan_reviewed` behaves as `false` (jq `// false` fallback)

### P5 Tests

1. **Unit test**: State with `current_phase = "review"` (or `debugging` / `worktree`), issue `enable enforcer`, verify the existing non-`init` phase is preserved
2. **Unit test**: State with `finishing.invoked = true`, verify recovery sets `current_phase = "finishing"`
3. **Unit test**: State with `debugging.active = true`, verify recovery sets `current_phase = "debugging"`
4. **Unit test**: State with `worktree.created = true` and `baseline_verified = false`, verify recovery sets `current_phase = "worktree"`
5. **Unit test**: State with `tdd.current_task != null` or `worktree.baseline_verified = true`, verify recovery sets `current_phase = "tdd"`
6. **Unit test**: State with `planning.plan_written = true`, verify recovery sets `current_phase = "planning"`
7. **Unit test**: State with `brainstorming.spec_written = true` only, verify recovery sets `current_phase = "brainstorming"`
8. **Unit test**: Empty state (all defaults), verify recovery keeps `current_phase = "init"`
9. **Artifact fallback test**: With no structured phase fields, create supported subtree / alias canonical spec/plan artifacts and verify recovery uses the same semantics as existing workflow activation
10. **Resume gate test**: State with `resume.recovery_required = true`, issue `enable enforcer`, verify `resume.recovery_required` remains `true`
11. **Regression test**: `disable enforcer` still works without changing `current_phase`

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| `code-quality-reviewer` normalization misses an edge case | Low | Medium | Comprehensive grep for all role checks; add tests |
| P1 remains unresolved at runtime because the root cause is outside plugin control | Medium | Medium | Make the limitation explicit in docs and stop claiming an ineffective repo-side fix |
| Phase guard is too permissive and skips review check in wrong phase | Low | High | Test with explicit `current_phase` values; keep check in `tdd/review/finishing` |
| `jq -e 'type == "object"'` has unexpected edge case | Very Low | Low | `type` is a core jq primitive; thoroughly tested in jq itself |
| `update-state.sh` abort breaks legitimate scalar extraction use case | Very Low | Low | No legitimate use case exists for writing scalars back to state file |
| `planning.plan_reviewed` field breaks existing state without migration | Low | Medium | Use jq `// false` fallback in gate checks; migration script sets default |
| Repo-local plan-review hold is mistaken for an upstream superpowers rule | Medium | Medium | State explicitly in docs/spec that `plan_reviewed` is a local enforcer extension |
| Midstream recovery picks wrong phase | Low | Medium | Preserve existing non-`init` phase first; avoid using historical `review.tasks` as an active review signal |
| Artifact fallback drifts from existing canonical path semantics | Medium | Medium | Reuse `workflow_paths.sh` semantics instead of a root-only `compgen -G` check |
| Resume gate still blocks after phase recovery and surprises users | Low | Medium | Keep contract explicit: phase recovery refreshes state, but `/superpowers-flow-enforcer:resume-enforcer` still clears the gate |
