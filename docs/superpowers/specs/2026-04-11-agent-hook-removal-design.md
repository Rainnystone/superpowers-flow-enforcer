# Agent Hook Removal Design

> Scope: remove the plugin's dependence on Claude Code `type: "agent"` hooks to fix the current runtime error `Failed to run: Messages are required for agent hooks. This is a bug`, without changing the product rules the plugin enforces.

## Goal

Make the plugin stable in current Claude Code by eliminating all `type: "agent"` hooks from `hooks/hooks.json`, while preserving the existing workflow policy as closely as possible.

## Why This Change

The current urgent failure is not a workflow-policy bug. It is a runtime stability bug:

1. the plugin currently depends on `type: "agent"` hooks for several workflow gates
2. real Claude Code sessions can fail with:
   - `Failed to run: Messages are required for agent hooks. This is a bug`
3. when this happens, hook execution fails even if the workflow policy itself is otherwise correct

The best-practice response is to remove dependence on the unstable runtime surface first, then reconsider richer hook types only after the platform is stable again.

## Non-Goals

1. Do not redesign the workflow state model.
2. Do not add new gates.
3. Do not remove existing gates just because they are harder to express without `agent`.
4. Do not change bypass semantics unless required to preserve existing behavior under the new hook types.
5. Do not revisit unrelated README or product-design questions.

## Design Principles

### 1. Prefer deterministic hooks over model-driven hooks

If a gate can be evaluated with state fields or raw hook input, implement it in `type: "command"` rather than via LLM judgment.

### 2. Keep `prompt` hooks only for input-only semantic checks

`type: "prompt"` remains acceptable only when the hook can decide from hook input JSON alone, using `$ARGUMENTS`, without reading repository files, state files, or transcripts.

### 3. Remove all `agent` hooks from the active configuration

This fix is explicitly a de-agentization pass. Current Claude Code runtime stability is more important than preserving richer multi-turn verification behavior.

### 4. Preserve product policy, not implementation shape

The product contract is the workflow gating behavior. The exact hook type is an implementation detail and may change if the runtime requires it.

### 5. Preserve exact gate semantics per hook

This fix must preserve the current allow/block semantics of each active `agent` hook as closely as possible. The implementation may change hook type, but it must not quietly weaken or drop an existing gate. Where a hook is split across `command` and `prompt`, the combined behavior must remain equivalent to the current policy.

## Target Architecture

After this change:

1. `hooks/hooks.json` contains no `type: "agent"` hooks
2. deterministic workflow gates are enforced through `type: "command"` hooks
3. remaining model-driven checks, if any, use only `type: "prompt"` with official Claude Code `{"ok": true}` / `{"ok": false, "reason": "..."}` output
4. no hook relies on same-event `additionalContext` handoff between sibling hooks

## Current Agent-Hook Inventory And Required Replacement

The current active `agent` hooks are:

1. `UserPromptSubmit/*`
2. `PreToolUse/Edit|Write`
3. `PreToolUse/AskUserQuestion`
4. `PostToolUse/Write|Edit`
5. `PostToolUse/Write`
6. `PostToolUse/Bash`
7. `PostToolUse/TaskCompleted`
8. `Stop/*` verification-evidence gate
9. `Stop/*` review/finishing gate

They must be replaced as follows:

1. `UserPromptSubmit/*`
   - move fully to `command`
   - preserve current behavior: missing/unreadable state must fail open; skip requests without confirmation must still block
2. `PreToolUse/Edit|Write`
   - move fully to `command`
   - preserve current path normalization, workflow activation behavior, planning gate, TDD gate, and pending-failure gate
3. `PreToolUse/AskUserQuestion`
   - move fully to `command`
   - preserve current brainstorming findings-update gate
4. `PostToolUse/Write|Edit`
   - move fully to `command`
   - preserve current spec-review gate
5. `PostToolUse/Write`
   - move fully to `command`
   - preserve current plan-to-worktree gate
6. `PostToolUse/Bash`
   - move fully to `command`
   - preserve current worktree-baseline gate
7. `PostToolUse/TaskCompleted`
   - move fully to `command`
   - preserve current task review completion gate using `review.tasks`
8. `Stop/*` verification-evidence gate
   - may remain `prompt`, but only if it relies on hook input JSON alone
   - must preserve `stop_hook_active` handling exactly
   - must use `Stop` hook input fields that Claude Code officially provides, especially `last_assistant_message`, rather than asking a prompt hook to read transcript files
   - must continue blocking completion claims without fresh verification evidence according to current policy
9. `Stop/*` review/finishing gate
   - move fully to `command`
   - preserve `workflow.active`, `interrupt.allowed`, `review.tasks`, `finishing.invoked`, `skip_review`, and `skip_finishing` behavior exactly

`PreToolUse/Bash` is not part of the de-agentization target. It already qualifies as an input-only semantic check and should remain `type: "prompt"` unless implementation constraints force a narrower `command` equivalent.

## Required Functional Changes

### A. Remove `agent` hooks from `hooks/hooks.json`

Every current `type: "agent"` hook must be replaced with either:

1. `type: "command"` if the gate is deterministic, or
2. `type: "prompt"` if the gate only needs the event input JSON

No `type: "agent"` entries should remain in the active hook configuration after this fix.

### B. Deterministic gates move to command hooks

The following categories must be treated as deterministic and implemented via `command` hooks:

1. workflow-active checks
2. spec/planning/worktree/TDD/review/finishing state-field checks
3. path allow/deny logic derived from tool input
4. interrupt and bypass state checks
5. task review completion checks driven by `review.tasks`

These checks should read:

1. hook input JSON from stdin
2. state from `flow_state.json` when needed
3. only the minimum fields required to preserve current gate behavior

For this fix, the deterministic-command requirement explicitly includes:

1. `UserPromptSubmit/*`
2. `PreToolUse/Edit|Write`
3. `PreToolUse/AskUserQuestion`
4. `PostToolUse/Write|Edit`
5. `PostToolUse/Write`
6. `PostToolUse/Bash`
7. `PostToolUse/TaskCompleted`
8. `Stop/*` review/finishing gate

### C. Remaining prompt hooks must be input-only

Any hook left as `type: "prompt"` must satisfy all of the following:

1. it can decide from `$ARGUMENTS` alone
2. it does not ask the model to read state files, transcripts, or repository files
3. it returns the official prompt-hook schema:
   - allow: `{"ok": true}`
   - block: `{"ok": false, "reason": "..."}`

### D. Stop-hook behavior must be preserved exactly within the new hook types

`Stop` currently serves two policy goals:

1. require fresh verification evidence before completion claims
2. allow intentional stop when interrupt state permits it

This fix must preserve those goals with explicit parity:

1. every `Stop` replacement must preserve `stop_hook_active` handling so the hook does not loop or self-block
2. state-driven `Stop` checks belong in `command`
3. any remaining completion-language check may stay in `prompt` only if it uses hook input alone
4. if prompt-based completion evidence is retained, it must not ask the model to read transcript files
5. if prompt-based completion evidence is retained, it must evaluate the official `Stop` input payload, especially `last_assistant_message`, rather than relying on transcript-file reads
6. do not keep a broken `agent` Stop hook just to preserve transcript-file reading
7. do not weaken the current interrupt, review, finishing, or verification gate semantics as part of this migration

### E. Do not rely on same-event hook chaining

The design must not assume:

1. a `command` hook runs before a sibling `prompt` hook
2. `additionalContext` from one hook becomes structured input for another hook in the same event

If a gate needs derived data, the hook that enforces the gate must compute or read that data itself.

## Testing Requirements

### Static configuration coverage

Update regression tests so they assert:

1. `hooks/hooks.json` contains zero `type: "agent"` hooks
2. every remaining `type: "prompt"` hook uses `ok/reason`
3. no remaining `prompt` hook prompt text instructs the model to read state files or transcript files

### Behavioral non-regression

Keep or update tests proving that:

1. bypass detection still works
2. interrupt state handling still works
3. workflow activation behavior still works
4. `UserPromptSubmit` preserves current allow/block behavior under valid state, missing state, and unreadable state
5. `TaskCompleted` preserves current review-completion behavior
6. `Stop` preserves:
   - `stop_hook_active` allow behavior
   - interrupt allow behavior
   - review/finishing block behavior
   - use of official `Stop` input fields, especially `last_assistant_message`, for any remaining prompt-based verification check
   - completion-without-fresh-verification block behavior
7. core workflow gates still hold

### Runtime safety coverage

Add or keep coverage showing that:

1. no hook path depends on `agent` runtime
2. command-hook state reads still fail open where current behavior requires fail-open
3. `PreToolUse/Bash` remains input-only and does not regress into state-file or transcript-file reads

### Post-change inventory coverage

Tests must assert the final hook inventory explicitly:

1. zero `type: "agent"` hooks remain
2. `PreToolUse/Bash` remains `type: "prompt"`
3. all other formerly stateful `agent` gates listed in the inventory above have moved to `type: "command"`
4. any remaining `prompt` hooks are input-only and use `ok/reason`

## Acceptance Criteria

This fix is complete only if all of the following are true:

1. the active hook configuration contains no `type: "agent"` hooks
2. the post-change hook inventory matches the explicit replacement inventory in this spec
3. the plugin preserves current workflow policy for `UserPromptSubmit`, `TaskCompleted`, and both `Stop` gates
4. prompt hooks use only official Claude Code prompt-hook schema
5. regression tests covering hook configuration and current workflow behavior pass locally
6. the implementation does not introduce a new product-rule expansion beyond removing dependence on `agent`
