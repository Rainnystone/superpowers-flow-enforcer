# Claude Code Live Command Hook Fix Design

> Scope: fix only the recently confirmed live Claude Code hook issues around `SessionStart`, `UserPromptSubmit`, and `Stop`. Do not redesign other workflow gates, state fields, or the broader superpowers enforcement model in this pass.

## Goal

Make the installed Claude Code plugin behave reliably in real sessions by fixing the command-hook input path and state bootstrap path:

1. `SessionStart` must reliably create or migrate `flow_state.json`
2. `UserPromptSubmit` must reliably parse real Claude Code input and update bypass / interrupt state
3. `Stop` must not trap non-workflow sessions just because state initialization failed
4. workflow enforcement must only activate once the session has actually entered the superpowers workflow
5. trigger behavior must continue to follow superpower-aligned workflow phases, not become a generic global blocker

## Product Boundary

This plugin is still intended to follow the superpowers workflow. In this patch, that means:

1. the plugin continues to enforce only superpower-aligned phase transitions
2. if the user never entered the superpowers workflow, the plugin should not start enforcing workflow gates
3. it must not turn missing state into a blanket "review/finishing required" block for arbitrary Claude Code sessions
4. it must not attempt a fresh redesign of how brainstorming / planning / TDD / review are modeled

For this plugin, "entered the superpowers workflow" has a concrete operational meaning. Because plugin hooks cannot observe literal skill activation, the plugin treats the following as explicit workflow entry:

1. an explicit skip request for a superpower phase
2. creation or modification of canonical superpowers artifacts under `docs/superpowers/specs/` or `docs/superpowers/plans/`
3. explicit use of plugin-owned recorder scripts for later workflow phases

Sessions that do none of the above are treated as non-workflow sessions and must not be forced into workflow-only gates.

## Non-Goals

1. do not redesign the overall `flow_state.json` schema beyond what is required for the live bug
2. do not revisit `planning-with-files` integration
3. do not rework the review / finishing model beyond safe handling when state is missing
4. do not migrate the plugin to skill-frontmatter hooks in this patch
5. do not broaden the patch into a new workflow architecture

## Confirmed Facts

From the live Claude Code installation and official hooks docs:

1. `command` hooks receive event input JSON on `stdin`
2. `UserPromptSubmit` uses `prompt`, not `user_prompt`
3. `SessionStart` and `UserPromptSubmit` include `cwd`
4. the current `sync-user-prompt-state.sh` reads `.user_prompt`, so bypass and interrupt detection silently fail in live use
5. the current `init-state.sh` depends directly on `$CLAUDE_PROJECT_DIR`, so missing environment propagation can prevent state initialization
6. plugin hooks are global; they do not naturally track skill activation the way skill-frontmatter hooks do

## Design Principles

### 1. Fix the real live path first

Prefer the smallest change that makes the installed plugin work in real Claude Code sessions:

1. parse the official stdin format
2. resolve the project directory robustly
3. avoid silent no-op behavior

### 2. Keep superpower semantics, not generic global blocking

The plugin is meant to follow superpower phases. Therefore:

1. if the session has not actually entered the superpowers workflow, workflow-only gates should approve
2. if no usable workflow state exists, workflow-only gates should not invent a fake "review required" state
3. stateful enforcement should happen only once the session has enough information to know it is in the enforced workflow

### 3. Prefer self-healing over brittle ordering assumptions

Even if `SessionStart` misses once, `UserPromptSubmit` should be able to bootstrap state and continue.

### 4. Use an explicit activation latch

Because plugin hooks are global, this patch needs an explicit state bit that says whether workflow enforcement is active for the current session.

The single source of truth for workflow entry is `workflow.active`, and it may only be changed by the explicit entry signals defined in this spec.

## Alternatives Considered

### Option A: Minimal live fix in existing scripts

Change `init-state.sh` and `sync-user-prompt-state.sh` to use official stdin fields and add missing-state self-healing. Add a safe `Stop` fallback.

Pros:

1. smallest patch
2. directly addresses the observed bug
3. does not reopen broader architecture questions

Cons:

1. keeps the current plugin-level architecture
2. does not solve older design debt outside this live bug

### Option B: Introduce a shared hook input parser layer

Create a reusable Bash helper for stdin/env resolution and refactor all hook scripts around it.

Pros:

1. more uniform long-term
2. reduces repeated parsing logic

Cons:

1. larger patch surface
2. expands beyond the user's requested boundary

### Option C: Move phase-sensitive logic into skill-frontmatter hooks

Use skill-local hooks so lifecycle tracking follows active superpowers skills more directly.

Pros:

1. closer to literal skill activation
2. less guessing inside plugin hooks

Cons:

1. bigger product change
2. requires rethinking the current plugin packaging model
3. explicitly out of scope for this fix

## Chosen Approach

Choose Option A, with one addition: explicit workflow activation state.

This patch should fix the live command-hook path without reopening the broader plugin architecture.

## Proposed Behavior Changes

### 1. `SessionStart` project directory resolution

`init-state.sh` should resolve the project directory in this order:

1. `$CLAUDE_PROJECT_DIR` if present
2. `stdin.cwd` if present
3. `PWD` as final fallback

If no usable directory can be resolved, the script should emit a diagnostic message and exit cleanly instead of failing silently or crashing under `set -u`.

### 2. `UserPromptSubmit` official stdin parsing

`sync-user-prompt-state.sh` should:

1. read stdin once
2. parse `.prompt`
3. resolve the project directory using the same fallback order as above
4. stop treating missing input as silent success without explanation

This change must restore:

1. bypass request detection
2. bypass confirmation detection
3. interrupt / pause detection

### 3. `UserPromptSubmit` state bootstrap

If `sync-user-prompt-state.sh` receives a valid project directory but the state file is missing, it should bootstrap state before applying prompt-derived updates.

Preferred behavior:

1. create `.claude/` if needed
2. initialize state through the existing init path
3. then continue with bypass / interrupt parsing

This makes `UserPromptSubmit` robust even when `SessionStart` did not initialize state first.

### 4. Explicit workflow activation

Add a state bit:

```json
"workflow": {
  "active": false,
  "activated_by": null,
  "activated_at": null
}
```

Rules:

1. `workflow.active` starts as `false`
2. workflow enforcement hooks must fail open while `workflow.active` is `false`
3. `workflow.active` becomes `true` only on explicit superpower-aligned entry signals

Activation signals in scope for this patch:

1. explicit phase skip request in `UserPromptSubmit`
2. writing `docs/superpowers/specs/*.md`
3. writing `docs/superpowers/plans/*.md`
4. explicit record-script usage for later phases, if those scripts are touched in implementation

The spec/plan file paths above are treated as explicit opt-in to the superpowers workflow because they are canonical workflow artifacts owned by this plugin. A session that never touches those artifact paths and never issues a phase skip request remains non-workflow.

This satisfies the product rule that if the user never used superpowers, the plugin should not trigger workflow enforcement.

### 5. Existing state compatibility

This patch must define behavior for already-installed state files.

Rule:

1. do not require a fresh state reset for existing installs
2. do not require a `state_version` bump for this patch
3. if an existing readable v2 state file is missing `.workflow`, treat it as inactive and backfill:

```json
"workflow": {
  "active": false,
  "activated_by": null,
  "activated_at": null
}
```

4. if the state file is unreadable or structurally unsafe, keep the existing backup-and-reset behavior

This keeps rollout minimal while making the new field deterministic for old installs.

### 6. Safe `Stop` behavior without state

`Stop` currently assumes readable workflow state. That is too brittle for a global plugin.

New rule:

1. transcript-based completion-evidence checks may still run
2. workflow-state-based review / finishing checks must fail open when the state file is missing or unreadable

This preserves the useful "show fresh verification evidence" gate while preventing the plugin from trapping ordinary Claude Code sessions that never successfully entered the workflow state machine.

### 7. Preserve superpower-aligned trigger semantics

This patch does not change the core trigger model:

1. workflow enforcement continues to follow superpower-aligned phase facts
2. enforcement only starts after `workflow.active` becomes true
3. no new generic global review gate is introduced
4. no attempt is made to infer skill activation directly from plugin hooks

## Files In Scope

### Must modify

1. `scripts/init-state.sh`
2. `scripts/sync-user-prompt-state.sh`
3. `hooks/hooks.json`
4. `tests/test_init_state.sh`
5. `tests/test_bypass_state.sh`
6. `tests/test_interrupt_state.sh`
7. `tests/test_hooks_official_events.sh`
8. `templates/flow_state.json.tmpl`
9. `scripts/migrate-state.sh` or equivalent init-time backfill path, if needed to normalize existing readable v2 state

### May modify if needed

1. `tests/helpers/state-fixtures.sh`
2. `scripts/sync-post-tool-state.sh`

### Out of scope

1. TDD parser redesign
2. review state model redesign
3. planning-with-files enforcement redesign
4. marketplace / install changes
5. README or CLAUDE wording unrelated to this bug

## Acceptance Criteria

The fix is complete only if all of the following are true:

1. `init-state.sh` can initialize state when only `stdin.cwd` is available
2. `sync-user-prompt-state.sh` correctly detects bypass / interrupt when given official `UserPromptSubmit` JSON with `prompt` and `cwd`
3. `sync-user-prompt-state.sh` can bootstrap state if the state file is missing
4. workflow gates do not apply while `workflow.active` is `false`
5. `workflow.active` becomes `true` only on explicit superpower-aligned entry signals in scope
6. an existing readable v2 state file without `.workflow` is normalized to inactive workflow state
7. `Stop` no longer blocks a session solely because workflow state is missing or unreadable
8. transcript-based completion evidence gating still exists
9. no unrelated workflow logic is redesigned in this patch

## Verification Strategy

Verification should include:

1. shell tests using official `UserPromptSubmit` stdin shape
2. shell tests proving `SessionStart` fallback from `cwd`
3. shell tests proving an existing readable v2 state without `.workflow` is backfilled to inactive workflow state
4. shell tests proving workflow gates stay dormant while `workflow.active` is `false`
5. shell or static hook assertions proving `Stop` contains explicit missing-state approval logic
6. rerun of existing hook regression tests to ensure no unrelated regression

## Risks

### Risk 1: wrong directory fallback

If `cwd` is not the project root in some sessions, state could be created in the wrong directory.

Mitigation:

1. prefer `$CLAUDE_PROJECT_DIR` when present
2. use `cwd` only as fallback
3. keep `PWD` as last resort only

### Risk 2: state bootstrap during `UserPromptSubmit` masks deeper issues

Self-healing can make the system more robust, but it can also hide a broken `SessionStart`.

Mitigation:

1. keep bootstrap minimal
2. emit a diagnostic system message or stderr trace when bootstrap happens
3. do not broaden the fix beyond bootstrap + prompt sync

### Risk 3: activation never turns on early enough

If activation signals are too narrow, some intended workflow sessions may not get enforced early enough.

Mitigation:

1. activate on explicit superpower artifacts and skip requests
2. keep activation logic small and observable
3. leave broader early-brainstorming redesign out of scope for this patch

### Risk 4: `Stop` becomes too permissive

If missing-state handling is too broad, the plugin could stop enforcing review / finishing even in sessions that should be enforced.

Mitigation:

1. only fail open when state is missing, unreadable, or `workflow.active` is `false`
2. keep transcript-based verification checks active
3. leave normal review / finishing gating unchanged when state exists and workflow is active
