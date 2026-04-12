# Activation-Scoped Bash Traverse Design

> Scope: replace the current `PreToolUse:Bash` repair direction with an activation-scoped parser-backed design, and keep `Stop` on the command-only path. This spec supersedes the Bash portion of `2026-04-12-bash-stop-command-hardening-design.md`.

## Goal

Satisfy the user's two actual completion criteria:

1. when superpower workflow is active, hooks must run stably, enforce the intended workflow, and stop cleanly without prompt/agent runtime errors
2. when superpower workflow is not active, the plugin must not create user-visible workflow enforcement or random Bash/Stop interference

This round keeps the plugin as a single installable repo/plugin, but changes the Bash strategy:

1. `PreToolUse:Bash` stays a `command` hook
2. it becomes activation-scoped: `workflow.active != true` means no-op
3. once active, it uses vendored `bash-traverse` build output for shell-structure analysis instead of continuing the current heuristic string gate
4. `Stop` continues toward `command-only`, with the same inactive-workflow no-op boundary

## Baseline

This design is based on:

1. current `master` / GitHub baseline
2. `.planning-with-files/task_plan.md`
3. `.planning-with-files/findings.md`
4. `.planning-with-files/progress.md`
5. the completed `bash-traverse` spike recorded in findings

Key spike conclusions that matter here:

1. `bash-traverse` can be cloned, installed, built, and used locally
2. it materially improves handling of shell structures we repeatedly failed on with heuristic rules:
   - pipelines / `&&`
   - multi-line commands
   - `$(...)`
   - `[ ... ]` / `[[ ... ]]`
3. it does not solve everything automatically:
   - shell wrappers like `bash -lc '...'` still need explicit recursive handling
   - interpreter strings such as `python -c 'open(...)'` still need separate treatment
   - current redirection support is not reliable enough to trust blindly for file-use semantics
4. there is no usable npm registry package today, and `npm install github:davidcoleman007/bash-traverse` does not produce directly loadable build artifacts

## Why The Previous Bash Direction Is No Longer Correct

The previous same-day design assumed we could finish this round by:

1. keeping Bash enforcement entirely inside a simple command script
2. using a conservative mention-based rule
3. tightening activation behavior around that rule

That direction no longer matches what we now know.

It was good enough to surface the real constraints, but it does not give the best available shape for the user's actual goals:

1. the heuristic gate continues to drift toward repeated parser work
2. the main user concern is no longer "allow some benign mentions while active"
3. the main user concern is:
   - stable enforcement while active
   - no user-visible interference while inactive

Given the completed spike, the better design is no longer "tighten the heuristic Bash gate." It is:

1. put the activation boundary first
2. replace the heuristic shell analysis with a parser-backed implementation
3. ship the parser capability as part of this plugin, not as a second thing the user must install

## Non-Goals

1. do not redesign the overall workflow state model
2. do not migrate the whole plugin from plugin hooks to skill/frontmatter hooks in this round
3. do not restore any `agent` hook
4. do not attempt full interpreter-language semantic analysis
5. do not require users to build parser dependencies manually after installing the plugin

## Design Principles

### 1. Inactive workflow must be a hard no-op boundary

This is now the first acceptance rule for this work.

While the plugin may still receive official Claude Code lifecycle events, user-visible workflow enforcement must not occur when `workflow.active != true`.

For this round that means:

1. `PreToolUse:Bash` must allow silently while inactive
2. `Stop` must allow silently while inactive
3. ordinary non-superpower usage must not be interrupted by these two gates

### 2. Bash enforcement remains deterministic

`PreToolUse:Bash` remains a `command` hook. The goal is not to bring model reasoning back. The goal is to replace brittle string heuristics with deterministic structural parsing.

### 3. Bundle parser capability into the plugin repo

The plugin should remain a single thing to install.

That means this round should not depend on:

1. the user manually cloning `bash-traverse`
2. the user manually running `npm install` in a second repository
3. a live npm registry package that does not currently exist

Instead, the plugin should vendor the parser build artifacts it needs, plus the upstream license and version pin metadata.

### 4. Prefer a Bash wrapper plus vendored Node helper

The most practical integration shape for this repo is:

1. a Bash wrapper script stays as the hook entrypoint
2. the Bash wrapper resolves project root and `flow_state.json`
3. the Bash wrapper exits early when inactive
4. once active, the Bash wrapper invokes a vendored Node parser helper

This preserves the plugin's existing command-hook structure while keeping parser logic out of shell.

### 5. Parser scope is shell structure, not general code semantics

`bash-traverse` should be used for what it is good at:

1. shell structure
2. command segmentation
3. command substitution
4. test expressions
5. nested shell wrapper recursion

It should not be described as solving:

1. Python/Node/Ruby inline code semantics
2. runtime-dependent expansions
3. every redirection edge case by itself

Where needed, this round may add narrow deterministic fallback handling for known inline-eval wrappers such as `python -c` / `node -e`, but the parser is not a promise of universal language understanding.

### 6. State resolution fallback must be explicit

For this round, `PreToolUse:Bash` must distinguish three cases instead of leaving fallback behavior implicit:

1. no project root or no `flow_state.json` can be resolved:
   - treat as inactive / non-project usage
   - allow silently
2. state file is absent:
   - do not create or bootstrap a new state file from the Bash gate
   - treat this as inactive / non-enforced usage
   - allow silently
3. state file exists but is unreadable/corrupt:
   - first run the existing bootstrap / normalization path once
   - if the recovered state becomes readable and inactive, allow silently
   - if the recovered state becomes readable and active, continue normal enforcement
   - only if it still remains unreadable/corrupt after that path:
   - do not emit malformed hook output
   - return a deterministic deny/guidance response for active Bash enforcement, because the plugin can no longer safely trust workflow state

This avoids the ambiguous middle ground between "always fail open" and "always fail closed."

## Recommended Architecture

## A. `PreToolUse:Bash` becomes activation-scoped and parser-backed

`PreToolUse:Bash` will continue to enter through a Bash command hook, but the internal flow changes to:

1. read stdin hook JSON
2. resolve project dir and state file using the same robust path logic already used in adjacent command hooks
3. if a state file already exists but cannot be read safely, attempt one existing recovery/normalization pass before controlled failure
4. if `workflow.active != true`, exit silently
5. if `workflow.active == true`, invoke a Node helper backed by vendored `bash-traverse`
6. return official `PreToolUse` deny JSON only when the parser-backed policy decides to block

### Active-workflow Bash policy

Within active workflow, the rule remains conservative:

1. direct approved helper invocation is allowed
2. arbitrary Bash access to `.claude/flow_state.json` remains disallowed
3. shell-structural bypasses that previously escaped the heuristic gate must be covered through AST/traversal logic

Concrete examples to keep implementation and tests aligned:

Allowed:

1. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/update-state.sh brainstorming spec_written true`
2. direct helper invocation without extra shell chaining or extra `flow_state.json` handling

Denied:

1. `cat .claude/flow_state.json`
2. `bash -lc 'cat .claude/flow_state.json'`
3. helper invocation chained with extra direct state access in the same command

Temporarily allowed during this round's scaffold, even when active:

1. ordinary Bash commands that do not reference the protected state path but happen to use shell constructs not yet parsed by the current vendored runtime
2. parser-unsupported syntax must not become a blanket hard deny for unrelated Bash commands

This round does **not** attempt to re-open a broad "benign textual mention" policy while active. The parser is being introduced first for reliability and maintainability, not to broaden permissions.

### Parser-backed coverage targets

The parser-backed Bash gate must explicitly cover:

1. simple direct commands
2. pipelines and logical operators
3. multi-line command lists
4. command substitution
5. test expressions
6. shell wrappers such as `bash -c` / `bash -lc` through recursive parse of nested shell source

### Known active-workflow residual risks

This design accepts that the parser route still leaves bounded residual work, but it does **not** permit shipping known low-cost inline-interpreter bypasses for the protected state path:

1. narrow deterministic wrapper handling for common inline-eval interpreters is required in this round for commands such as:
   - `python -c`
   - `python3 -c`
   - `node -e`
   - `ruby -e`
   - `perl -e`
2. the required behavior for those wrappers is conservative:
   - if their inline code string mentions `.claude/flow_state.json` during active workflow, deny
   - if they do not mention the protected path, continue normal evaluation
3. redirection detection must be validated against real parser output before relying on parser-provided redirect fields

Those are implementation details to resolve in plan/tasks, not reasons to fall back to the old heuristic direction.

### Task-1 scaffold guardrail

Because the parser-backed helper is being introduced incrementally, this round's first implementation packet must preserve normal active-workflow Bash for commands that do not touch `.claude/flow_state.json`.

That means:

1. missing Node runtime remains a deterministic active-workflow deny with guidance
2. missing vendored runtime remains a deterministic active-workflow deny with guidance
3. but parser unsupported-syntax failures must not hard-deny unrelated Bash commands during Task 1
4. direct protected-path handling may still be denied through narrow deterministic fallback while Task 2 expands real AST coverage

## B. Ship vendored build artifacts, not just source dependency references

Because `bash-traverse` does not currently provide a usable npm registry package for this repo's needs, and git dependency install does not produce ready-to-load artifacts, the plugin should ship vendored parser build assets.

The design target is:

1. commit the upstream MIT license
2. commit pinned upstream version / commit metadata
3. commit only the minimum runtime artifacts required by the plugin
4. avoid requiring end users to run a separate build after plugin install

This keeps installation closer to today's experience:

1. install this plugin
2. ensure required runtime prerequisites exist

## C. Runtime prerequisites must be explicit and controlled

This round changes the plugin's runtime assumptions.

Today the core path is mostly Bash + `jq`.
After this change, active Bash enforcement will also require Node.

Therefore the design must explicitly define behavior when Node is unavailable:

1. while inactive, still no-op silently
2. while active, do not crash or emit hook schema noise
3. instead, return a clear deterministic deny/guidance response explaining that Node is required for active Bash enforcement

This is preferable to silent bypass or runtime error spam.

## D. `Stop` remains command-only and inactive-scoped

The `Stop` direction does not need parser work.

This round keeps the same decision:

1. remove prompt dependence
2. keep review / finishing / interrupt enforcement deterministic
3. preserve `workflow.active != true` as an early allow boundary

## Alternatives Considered

### Option A: Keep tightening the current heuristic Bash gate

Rejected because:

1. the spike already proved a better shell-structure path exists
2. continued tightening repeats the same failure mode
3. it does not justify another full implementation loop on the same brittle base

### Option B: Move immediately to full skill/frontmatter enforcement architecture

Rejected for this round because:

1. it is a larger architectural change than this repair cycle needs
2. it would blur the immediate goal of stabilizing `PreToolUse:Bash` and `Stop`

This remains a valid future direction, not the scope of this spec.

### Option C: Parser-backed active Bash gate plus inactive hard no-op boundary

Recommended because:

1. it aligns with both user goals
2. it uses the completed spike instead of guessing
3. it keeps the plugin single-install
4. it reduces future review churn on Bash parsing

## Files Expected To Change

### Modify

1. `hooks/hooks.json`
2. `scripts/check-bash-command-gate.sh`
3. `scripts/check-stop-review-gate.sh`
4. `tests/test_hooks_official_events.sh`
5. `tests/test_bash_command_gate.sh`
6. `tests/test_stop_gates.sh`

### Add

1. a vendored runtime directory for `bash-traverse` build artifacts and license metadata
2. a Node helper for parser-backed Bash analysis

## Testing Requirements

### Inactive-scope coverage

Tests must prove:

1. `PreToolUse:Bash` silently allows when `workflow.active != true`
2. `Stop` silently allows when `workflow.active != true`
3. no user-visible deny/block occurs in those inactive cases

### Active Bash parser coverage

Tests must prove the active Bash gate handles:

1. direct command access to `.claude/flow_state.json`
2. `&&` and multi-line command lists
3. `$(...)`
4. `[ ... ]` / `[[ ... ]]`
5. nested shell wrappers such as `bash -lc '...'`
6. common inline-eval interpreter wrappers that mention `.claude/flow_state.json`

### Runtime guard coverage

Tests must prove:

1. missing Node does not create malformed hook output
2. missing Node while active produces deterministic guidance, not runtime noise
3. vendored parser assets are sufficient for local execution without extra user build steps
4. unreadable/corrupt state produces the explicit fallback behavior defined above

### Stop coverage

Tests must continue to prove:

1. `stop_hook_active` allows
2. `interrupt.allowed` allows
3. inactive workflow allows
4. missing review records still block
5. finishing-required state still blocks
6. completion claims without obvious fresh verification evidence still block

## Acceptance Criteria

This spec is satisfied only if all of the following are true:

1. `PreToolUse:Bash` is no longer driven by heuristic shell-string matching
2. parser-backed Bash enforcement runs only when `workflow.active == true`
3. inactive workflow causes both Bash and Stop gates to no-op
4. the plugin remains installable as a single repo/plugin without requiring users to build parser dependencies manually
5. active Bash enforcement does not depend on `prompt` or `agent`
6. `Stop` is command-only
7. the implementation introduces no new user-visible hook schema/runtime errors
8. the active Bash gate covers the shell-structure classes already validated in the spike
