# Bash And Stop Command Hardening Design

> Scope: stabilize the remaining flaky hooks by converting `PreToolUse:Bash` to a deterministic command hook and collapsing `Stop` to a conservative command-only implementation. For `PreToolUse:Bash`, this round explicitly adopts a more conservative product rule: `.claude/flow_state.json` is private plugin state, so non-helper Bash commands must not mention it directly, but only after the superpower workflow has actually been activated.

## Goal

Remove the remaining runtime instability from `PreToolUse:Bash` and `Stop` by eliminating their dependence on model-driven decisions in current Claude Code. Preserve the workflow policy outside these two hook surfaces, make `PreToolUse:Bash` intentionally more conservative so private hook-managed state stays encapsulated, and ensure both hook surfaces become complete no-ops while `workflow.active != true`.

## Baseline

This design is based on the current merged repository state and the persisted investigation record, not on any single hook file in isolation.

Baseline sources for this round are:

1. the current GitHub / `master` state of the plugin
2. `.planning-with-files/task_plan.md`
3. `.planning-with-files/progress.md`
4. `.planning-with-files/findings.md`

Those records matter here because the current hook layout and the current runtime findings were produced across multiple earlier repair rounds:

1. prompt-hook contract hardening
2. de-agentization of the broader hook set
3. subsequent path-resolution and normalization hardening

This design therefore treats the current merged repository plus the planning record as the authoritative starting point.

## Why This Change

The previous de-agentization pass fixed the broad `agent` runtime problem, but real Claude Code sessions still show two unstable surfaces:

1. `PreToolUse:Bash` can still fail with `hook error + JSON validation failed`
2. `Stop` can still fail intermittently in the current `prompt + command` shape

These are no longer broad policy-design failures. They are implementation-shape stability failures in the current merged baseline:

1. `PreToolUse:Bash` is a deterministic command inspection but still relies on `prompt`
2. `Stop` still relies partly on a model-driven freshness judgment that has proved unstable in the user’s real environment

The best-practice response for this round is to prefer deterministic `command` hooks over `prompt` or `agent` when the runtime has already demonstrated instability.

For `PreToolUse:Bash`, repeated implementation and review also established a second point: preserving a narrow “allow benign textual mentions of `.claude/flow_state.json` but deny only true direct file access” rule pushes this plugin into an ever-growing shell-and-interpreter parser. That is not aligned with the plugin’s real use case. In the superpower workflow, `.claude/flow_state.json` is internal hook-managed state, not a file Claude should access through arbitrary Bash.

## Non-Goals

1. Do not redesign the overall workflow state model.
2. Do not revisit earlier `UserPromptSubmit`, `PreToolUse/Edit|Write`, `PostToolUse`, or `TaskCompleted` hook migrations.
3. Do not add new workflow gates.
4. Do not widen bypass semantics.
5. Do not restore `agent` hooks as part of this round.

## Design Principles

### 1. Deterministic Bash gating belongs in `command`

If the policy is “inspect the Bash command string and protect private hook-managed state,” use a `command` hook that reads `tool_input.command` and returns `PreToolUse` decision control.

### 1a. Inactive workflow must mean no user-visible enforcement

The plugin may still receive official Claude Code hook events while installed, but workflow enforcement must not apply before the workflow is actually active. For this round, `workflow.active != true` must mean:

1. no `PreToolUse:Bash` deny decision
2. no `Stop` block decision
3. no user-visible interruption of ordinary non-superpower usage

### 2. Prefer a conservative state-privacy rule over a pseudo-parser

If preserving a narrow “only true file access is denied” rule would require an increasingly complex shell / interpreter parser, prefer the simpler product rule: non-helper Bash commands must not mention `.claude/flow_state.json` at all.

### 3. Prefer a conservative `Stop` gate over an unstable richer gate

If the current runtime cannot reliably support `prompt` or `agent` behavior for `Stop`, favor a narrower but deterministic command implementation over a richer but flaky one.

### 4. Preserve existing state-driven `Stop` policy exactly

The `Stop` command gate must continue to enforce:

1. `stop_hook_active`
2. `interrupt.allowed`
3. `workflow.active`
4. `review.tasks`
5. `finishing.invoked`
6. `exceptions.skip_review` with `exceptions.user_confirmed`
7. `exceptions.skip_finishing` with `exceptions.user_confirmed`

### 5. Only degrade the unverifiable semantic part

This round may weaken only the LLM-style “fresh verification evidence” check if necessary. It must not weaken the deterministic review/finishing/interrupt policy.

### 6. Reuse existing command-hook conventions

This round must keep using official Claude Code event-specific command contracts:

1. `PreToolUse` uses `hookSpecificOutput.permissionDecision`
2. `Stop` uses top-level `decision: "block"` plus `reason`

## Alternatives Considered

### Option A: Keep current `prompt` hooks and tighten prompts

Pros:

1. smallest code diff
2. preserves current semantic richness

Cons:

1. does not address the observed real-world `JSON validation failed`
2. still depends on model output stability

Rejected because the user is already seeing persistent runtime errors on the remaining prompt surfaces.

### Option B: Revert `Stop` to `agent`

Pros:

1. richer semantic checking than prompt
2. user reports the earlier `agent`-based `Stop` did not show the current prompt error

Cons:

1. conflicts with the earlier confirmed runtime issue: `Messages are required for agent hooks. This is a bug`
2. reintroduces a previously removed unstable runtime surface

Rejected as the primary design for this round.

### Option C: Keep narrowing the Bash parser until all reviewed bypasses are covered

Pros:

1. preserves the narrower original Bash semantics
2. avoids changing the user-visible policy around textual mentions

Cons:

1. repeated reviews already show this expands toward a home-grown shell parser plus interpreter-specific handling
2. complexity no longer matches this plugin’s actual use case
3. review churn is likely to continue

Rejected.

### Option D: Convert `PreToolUse:Bash` to conservative `command` privacy gating and make `Stop` command-only

Pros:

1. fully deterministic
2. best aligned with the current real runtime stability goal
3. easiest to test locally
4. best aligned with the actual superpower workflow, where hook-managed state should stay internal

Cons:

1. `PreToolUse:Bash` becomes more conservative than the earlier “allow benign mentions” idea
2. `Stop` freshness enforcement becomes more conservative than the current prompt wording

Recommended.

## Target Architecture

After this change:

1. `PreToolUse:Bash` becomes a conservative `command` hook
2. `Stop` contains only a `command` hook
3. no remaining hook in the active config relies on `prompt` for `PreToolUse:Bash` or `Stop`

## Required Functional Changes

### A. Replace `PreToolUse:Bash` prompt with command

`PreToolUse:Bash` must:

1. read `tool_input.command` deterministically from stdin
2. resolve the project state file and read `workflow.active`
3. return allow/no-op whenever `workflow.active != true`
4. treat `.claude/flow_state.json` as private plugin state once `workflow.active == true`
5. deny any non-helper Bash command that mentions `.claude/flow_state.json` once workflow is active
6. allow straightforward invocation of the approved helper script
7. allow unrelated Bash commands that do not mention `.claude/flow_state.json`
8. use the official `PreToolUse` command-hook schema:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "..."
  }
}
```

This is an intentional product choice for this round. It trades some Bash flexibility for a rule that is simple, deterministic, and aligned with the plugin’s real workflow: once the workflow is active, Claude should not inspect or manipulate hook-managed state through arbitrary Bash. Before the workflow is active, the Bash gate must stay silent.

### B. Collapse `Stop` to command-only

The current `Stop` implementation is split between:

1. a prompt-based verification-evidence check
2. a command-based review/finishing gate

This round should collapse them into a single command hook that:

1. preserves all deterministic allow/block rules already enforced by `check-stop-review-gate.sh`
2. adds a conservative completion-claim guard using only the official `Stop` input JSON, especially:
   - `stop_hook_active`
   - `last_assistant_message`
3. blocks only when the command hook can deterministically infer a risky completion claim
4. avoids any attempt to read transcript files or invoke model reasoning

The resulting command-only `Stop` gate must also preserve the inactive-workflow boundary: when `workflow.active != true`, it must allow without user-visible enforcement.

### C. Conservative `Stop` completion detection

The `Stop` command gate should use a deliberately conservative heuristic:

1. if `stop_hook_active == true`, allow
2. if `interrupt.allowed == true`, allow
3. if `workflow.active != true`, allow
4. if review/finishing state requires blocking, block exactly as today
5. otherwise inspect `last_assistant_message`
6. if no completion-style keywords appear, allow
7. if completion-style keywords appear but no obvious passing verification evidence appears in the same message, block
8. if completion-style keywords appear with obvious passing verification evidence in the same message, allow

This is intentionally narrower than a model-based semantic interpretation. The priority is runtime stability.

### D. No `agent` reintroduction in this round

Even though the earlier agent-based `Stop` appeared more stable than the current prompt-based `Stop`, this round must not reintroduce `agent` hooks because:

1. the repository already has confirmed findings about `agent` runtime instability
2. the direct trigger for the previous migration was an `agent` runtime bug

## Files Expected To Change

### Modify

1. `hooks/hooks.json`
2. `scripts/check-stop-review-gate.sh`
3. `tests/test_hooks_official_events.sh`
4. `tests/test_stop_gates.sh`

### Create

1. `scripts/check-bash-command-gate.sh`
2. `tests/test_bash_command_gate.sh`

### Possibly modify

1. `tests/test_interrupt_state.sh` if `Stop` command-only behavior changes the expected path

## Testing Requirements

### Static configuration coverage

Tests must assert:

1. `PreToolUse:Bash` is `type: "command"`
2. `Stop` has exactly one hook and it is `type: "command"`
3. no `prompt` hook remains for `Stop`

### Behavioral coverage for `PreToolUse:Bash`

Tests must prove:

1. when `workflow.active != true`, `PreToolUse:Bash` allows and produces no deny decision
2. when `workflow.active == true`, any non-helper Bash command that mentions `.claude/flow_state.json` is denied
3. straightforward approved helper-script usage is allowed
4. unrelated Bash commands that do not mention `.claude/flow_state.json` are allowed

### Behavioral coverage for `Stop`

Tests must prove:

1. `stop_hook_active` still allows
2. `interrupt.allowed` still allows
3. `workflow.active != true` still allows
4. missing review records still block
5. finishing-required state still blocks
6. skip-review confirmed still allows
7. skip-finishing confirmed still allows
8. completion-claim-without-obvious-passing-evidence blocks
9. completion-claim-with-obvious-passing-evidence allows
10. non-completion messages allow

### Runtime safety coverage

Tests must continue to prove:

1. no active `agent` hooks remain
2. state root resolution is stable under:
   - missing `CLAUDE_PROJECT_DIR`
   - `CLAUDE_PROJECT_DIR` pointing at subdirectories
   - alias/realpath absolute paths where relevant

## Acceptance Criteria

This fix is complete only if all of the following are true:

1. `PreToolUse:Bash` no longer uses `prompt`
2. `Stop` no longer uses `prompt`
3. neither hook uses `agent`
4. `workflow.active != true` causes both `PreToolUse:Bash` and `Stop` to no-op without user-visible enforcement
5. deterministic Bash gating blocks any non-helper Bash mention of `.claude/flow_state.json` only after workflow activation
6. deterministic `Stop` gating still preserves review/finishing/interrupt behavior
7. the new conservative completion heuristic is covered by regression tests
8. the targeted regression suite passes locally
9. the implementation does not widen or remove unrelated workflow policy
