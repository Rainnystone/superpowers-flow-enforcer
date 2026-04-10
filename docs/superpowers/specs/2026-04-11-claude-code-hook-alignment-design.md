# Claude Code Hook Alignment Design

> Scope: redesign `superpowers-flow-enforcer` so it reliably enforces the workflow it claims in `README.md` and `CLAUDE.md`, using official Claude Code hook semantics and a minimal, observable state model.

## Goal

Make the plugin reliably enforce the intended Claude Code workflow subset:

1. `brainstorming -> spec -> planning -> worktree -> tdd -> review -> verification -> finishing`
2. explicit bypass with confirmation
3. explicit pause/interrupt handling for text-based user requests
4. compatibility with official Claude Code hook events and output contracts

This design does **not** aim to fully encode every detail of every superpowers skill. It only enforces the subset the plugin already claims to enforce.

## Non-Goals

1. Do not attempt to prove that a named skill was literally invoked.
2. Do not attempt to fully model all branching behavior from `using-superpowers`.
3. Do not enforce that brainstorming must always ask clarifying questions.
4. Do not make `planning-with-files-zh` a hidden hard dependency of the main workflow unless explicitly enabled.

## Context

The current plugin already shows the intended direction:

1. It uses a project-local state file.
2. It tries to gate production code behind spec, plan, and failing tests.
3. It tries to require review and verification before completion.

However, the implementation is not yet reliable enough because:

1. Some hooks rely on state fields that are never updated.
2. Some gate conditions are attached to the wrong bypass flags.
3. At least one lifecycle event name is not aligned with official Claude Code hooks.
4. Some behavior that should be driven by observable facts is instead tied to abstract state like `skill_invoked`.

## Design Principles

### 1. Enforce observable facts, not imagined intent

Prefer state transitions that come from actual events:

1. a spec file was written
2. a plan file was written
3. a findings file was written after a brainstorming question
4. a test command failed
5. a review result was explicitly recorded

Avoid gates that depend on undocumented or unmaintained abstractions such as “this skill must have been invoked”.

### 2. Keep phase boundaries explicit

Each major phase must have:

1. its own gate condition
2. its own bypass flag
3. its own completion criteria

No phase should silently inherit another phase’s bypass.

### 3. Claude Code compatibility first

The plugin is specifically for Claude Code, so official hook event names, JSON outputs, and lifecycle semantics are the source of truth.

### 4. Prefer narrow, deterministic hooks

Use `type: "prompt"` only where judgment is genuinely needed. Use scripts for state mutation and deterministic parsing.

## Official Claude Code Constraints This Design Must Respect

Based on Anthropic Claude Code docs:

1. supported lifecycle events include `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `TaskCompleted`, `SubagentStop`, and `Stop`
2. `TaskUpdate` is not an official hook event name; `TaskCompleted` is the correct event for task completion gating
3. `SubagentStop` is available for subagent-level completion logic, but it should only be used where the plugin truly wants to react to subagent termination rather than generic task completion
4. `Stop` does not run on a true user interrupt
5. `stop_hook_active` must be handled to avoid repeated continuation loops
6. plugins can provide `hooks/hooks.json`
7. command hooks run with full user permissions, so scripts should be minimal and defensive

## Proposed Workflow Model

### Brainstorming

This plugin will enforce the following subset only:

1. implementation work cannot proceed before a spec exists, unless `skip_brainstorming` is explicitly confirmed
2. if the session enters a brainstorming-question flow and a question is asked, a `findings.md` update is required before the next meaningful progression step
3. a written spec must be explicitly marked as reviewed before the workflow may advance to planning

It will **not** enforce that brainstorming must always ask questions.

### Planning

1. implementation work cannot proceed before a plan exists, unless `skip_planning` is explicitly confirmed
2. a plan must live at `docs/superpowers/plans/...`
3. a plan cannot silently be skipped via `skip_brainstorming`

### Worktree

1. after planning, worktree setup is required before TDD implementation begins
2. “baseline tests complete” must be recorded by a dedicated path, not inferred from any passing test command

### TDD

1. production code requires a known failing test first, unless `skip_tdd` is explicitly confirmed
2. test failure/pass tracking should accept explicit state recording, not rely only on regex extraction from command strings

### Review

1. each task must record:
   - spec review status
   - code quality review status
2. task completion depends on recorded review state

### Verification

1. completion claims require fresh evidence from the current turn
2. this remains primarily transcript-driven, because it maps well to official `Stop` semantics

### Finishing

1. after all required review records are complete, the plugin requires an explicit finishing step unless `skip_finishing` is confirmed

## Proposed State Model

Keep `flow_state.json`, but reduce it to fields that can actually be maintained.

### Required fields

```json
{
  "current_phase": "init",
  "brainstorming": {
    "question_asked": false,
    "findings_updated_after_question": false,
    "spec_written": false,
    "spec_file": null,
    "spec_reviewed": false,
    "user_approved_spec": false
  },
  "planning": {
    "plan_written": false,
    "plan_file": null
  },
  "worktree": {
    "created": false,
    "path": null,
    "baseline_verified": false
  },
  "tdd": {
    "tests_verified_fail": [],
    "tests_verified_pass": []
  },
  "review": {
    "tasks": {}
  },
  "finishing": {
    "invoked": false
  },
  "exceptions": {
    "skip_brainstorming": false,
    "skip_planning": false,
    "skip_tdd": false,
    "skip_review": false,
    "skip_finishing": false,
    "pending_confirmation_for": null,
    "reason": null,
    "user_confirmed": false
  },
  "interrupt": {
    "allowed": false,
    "reason": null
  }
}
```

### Fields to remove or stop using

Remove or deprecate fields that are currently not reliably maintained:

1. `brainstorming.skill_invoked`
2. `planning.skill_invoked`
3. `worktree.skill_invoked`
4. `finishing.skill_invoked`
5. any field that cannot be updated by a deterministic script or explicit recording command

## Hook Responsibilities

### SessionStart

Responsibilities:

1. initialize state if missing
2. inject minimal context
3. do not perform heavy analysis

Additional recommendation:

1. if root `task_plan.md`, `findings.md`, and `progress.md` exist, mention that they should be read before continuing

### UserPromptSubmit

Responsibilities:

1. detect bypass requests
2. detect text-based pause/interrupt requests
3. record pending confirmation target precisely
4. block until bypass confirmation is explicit

Design change:

Instead of broadly interpreting any “confirm/continue”, require confirmation of the specific pending phase, for example:

1. `confirm skip brainstorming`
2. `确认跳过 planning`

This reduces accidental confirmation.

### PreToolUse

Responsibilities:

1. protect state file from direct editing
2. gate code writing by phase order
3. enforce TDD on production writes

Required changes:

1. planning gate must use `skip_planning`, not `skip_brainstorming`
2. file exceptions should be computed by script or made consistent with docs

### PostToolUse

Responsibilities:

1. update state after successful writes
2. mark findings updates
3. mark spec/plan creation
4. record worktree creation
5. record passing tests

Required change for brainstorming:

1. if `AskUserQuestion` occurs, set `question_asked = true` and `findings_updated_after_question = false`
2. if `findings.md` is written afterwards, set `findings_updated_after_question = true`
3. gate on these direct facts, not on `skill_invoked`

### PostToolUseFailure

Responsibilities:

1. detect failed test commands
2. move state into debugging mode
3. add direct feedback that systematic debugging is now required

This is more aligned with official hook semantics than using only `PostToolUse`.

### TaskCompleted

Responsibilities:

1. replace the current non-official `TaskUpdate` hook
2. block task completion if required review records are missing

Rationale:

1. this aligns with the official Claude Code task lifecycle
2. it keeps the plugin centered on task closure semantics rather than every subagent stop
3. `SubagentStop` can be added later as a narrower companion hook if subagent-specific guardrails are needed

### Stop

Responsibilities:

1. first check `stop_hook_active`; if true, immediately allow stop
2. if `interrupt.allowed` is true, allow stop
3. otherwise enforce fresh verification evidence
4. then enforce finishing requirements

Important limitation:

This only applies to normal turn completion, not true user interrupts.

## State Migration Policy

The current repository already ships a `flow_state.json` template, so this redesign must define how older state files are handled.

### Versioning

Add a top-level integer field:

```json
{
  "state_version": 2
}
```

The current unversioned schema should be treated as version 1.

### Upgrade behavior

On `SessionStart`:

1. if no state file exists, initialize a fresh version 2 state
2. if the state file exists and has no `state_version`, treat it as version 1 and migrate it
3. if `state_version` is lower than current, run a deterministic migration
4. if the file is invalid or cannot be migrated safely, back it up and reinitialize

### Migration rules from version 1 to version 2

1. preserve stable facts that still exist in the new model:
   - `current_phase`
   - `brainstorming.spec_written`
   - `brainstorming.spec_file`
   - `planning.plan_written`
   - `planning.plan_file`
   - `worktree.created`
   - `worktree.path`
   - `tdd.tests_verified_fail`
   - `tdd.tests_verified_pass`
   - `review.tasks`
   - `exceptions.*`
   - `interrupt.*`
2. drop deprecated `skill_invoked` fields entirely
3. map `brainstorming.findings_updated` into `brainstorming.findings_updated_after_question` when possible
4. initialize newly required fields with safe defaults
5. record migration time in state for debugging

### Safety rule

If migration sees contradictory state, prefer reset over guessing. This plugin is an enforcement layer; stale or ambiguous state is more dangerous than starting fresh.

## Bypass Design

### Current problem

Bypass is too sticky and too broad.

### Proposed design

1. user states a bypass request
2. `exceptions.pending_confirmation_for` is set to the exact phase
3. hook blocks and asks for explicit confirmation
4. only a matching confirmation phrase confirms that exact phase
5. after the phase is skipped or the next phase transition occurs, clear the pending confirmation

This keeps bypass scoped and auditable.

## Interrupt Design

### Supported behavior

This plugin should support only text-based pause requests inside the conversation, such as:

1. `停止`
2. `pause`
3. `明天继续`

### Unsupported behavior

It should not claim to control true CLI interrupts, because official Claude Code `Stop` hooks do not run in that path.

Documentation should explicitly say this.

## Optional Planning-With-Files Mode

This should be a separate optional feature, not a hidden dependency of the main workflow.

If enabled, enforce:

1. root `task_plan.md`, `findings.md`, `progress.md` exist
2. brainstorming-question flow requires `findings.md` updates
3. major phase transitions require `progress.md` updates

This mode can be activated later without blocking the main plugin redesign.

## Implementation Outline

### Phase 1: Official compatibility and broken gates

1. rename `TaskUpdate` hook to `TaskCompleted`
2. add `stop_hook_active` handling to `Stop`
3. split planning bypass from brainstorming bypass
4. remove dependency on `brainstorming.skill_invoked`

### Phase 2: State model cleanup

1. simplify template fields
2. remove dead fields or stop reading them in hooks
3. add deterministic state recording for spec review, task review, finishing

### Phase 3: Test/debug lifecycle cleanup

1. move failure-driven debugging logic to `PostToolUseFailure`
2. keep successful test/result syncing in `PostToolUse`
3. tighten baseline verification semantics

### Phase 4: Optional planning-files enforcement

1. decide config shape
2. add root file checks
3. document this as optional mode

## Acceptance Criteria

The redesign is complete when:

1. all hook event names match official Claude Code documentation
2. every hook gate depends only on maintained state or direct observable events
3. skipping brainstorming does not skip planning
4. asking a brainstorming-style question reliably requires a later `findings.md` update
5. task completion review gates actually fire via official lifecycle events
6. Stop-based verification no longer risks looping because `stop_hook_active` is handled
7. documentation accurately matches the implemented behavior

## Open Questions

1. Should `planning-with-files-zh` enforcement be enabled by default, or shipped as an optional mode?
2. Should review recording be fully automatic, or require explicit helper-script calls from the review workflow?

## Recommended Next Step

After spec review, write an implementation plan that starts with official compatibility fixes and state model cleanup before any optional enhancements.
