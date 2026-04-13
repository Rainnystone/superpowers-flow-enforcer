# Workflow Activation Hardening Design

> Scope: harden how `superpowers-flow-enforcer` activates and deactivates workflow enforcement. This round fixes activation semantics only. It does not redesign the broader workflow state machine and it does not solve the separate "Bash writes project files while active" loophole.

## Goal

Satisfy the user's two actual product goals:

1. when the user is running the superpowers workflow, hooks must activate reliably and the workflow gates must take effect
2. when the user does not want superpowers enforcement, especially before the workflow is activated, the plugin must not create random workflow interference

This design is intentionally narrower than a full workflow redesign. It focuses on activation because current behavior is too brittle:

1. auto-activation is currently tied to root-only canonical paths
2. multi-project or nested-project layouts can miss activation entirely
3. there is no explicit manual activation or manual shutdown control

## Baseline

This design is based on the current `master` / GitHub baseline and the recorded findings in `.planning-with-files`.

The current implementation behaves like this:

1. workflow auto-activates only when a successful `Write` or `Edit` hits:
   - `docs/superpowers/specs/*.md`
   - `docs/superpowers/plans/*.md`
2. those matches are root-relative only after normalization
3. most workflow-only gates then check `.workflow.active == true` and otherwise no-op

This is why a write such as `simulation-toolset/docs/superpowers/specs/...` fails to activate today even though it is still a valid superpowers artifact inside the current project.

## Problems To Solve

### 1. Root-only activation is too narrow

The plugin currently assumes the canonical superpowers documents live only at repository root. That is not general enough for:

1. monorepo-style layouts
2. nested tools or packages inside the current project
3. future reorganizations that still preserve the canonical `docs/superpowers/...` shape inside a subtree

### 2. Activation depends too much on model path choices

If the model writes the right kind of file to the wrong directory shape, workflow never activates and downstream enforcement never starts.

### 3. There is no explicit user-controlled activation boundary

Because this is a plugin-level hook system, hooks are globally installed when the plugin is enabled. That makes explicit user intent more important, not less.

The product needs a clear way to say:

1. start enforcing now
2. stop enforcing now

without forcing all activation to depend on file writes.

## Non-Goals

This round does **not** do the following:

1. it does not change the actual workflow phase rules
2. it does not redesign `PreToolUse:Bash` file-write enforcement
3. it does not migrate plugin hooks to skill/frontmatter hooks
4. it does not attempt to remove all plugin-side lifecycle activity while the plugin is installed
5. it does not add path-specific special cases such as hardcoding `simulation-toolset/...`

## Design Principles

### 1. Keep the existing canonical root behavior

Current root-level canonical paths must continue to work:

1. `docs/superpowers/specs/*.md`
2. `docs/superpowers/plans/*.md`

This round generalizes activation. It must not regress the existing root path behavior.

### 2. Generalize by canonical shape, not by special-case directory names

The system should recognize canonical superpowers artifacts anywhere inside the current project subtree, not just at repository root.

That means paths such as these should all be valid activation signals:

1. `docs/superpowers/specs/2026-04-13-demo.md`
2. `simulation-toolset/docs/superpowers/specs/2026-04-13-demo.md`
3. `packages/tooling/docs/superpowers/plans/2026-04-13-demo.md`

The rule is about the canonical suffix of the normalized project-relative path:

1. it must end with `docs/superpowers/specs/<filename>.md`
2. or it must end with `docs/superpowers/plans/<filename>.md`

Root-level canonical paths are the zero-prefix case of the same rule.

### 3. Add explicit user-controlled activation and deactivation

The plugin must support two exact manual control phrases:

1. `激活 superpowers enforcer`
2. `关闭 superpowers enforcer`

These phrases provide a stable control surface that does not depend on path choice.

Matching should use normalized prompt text:

1. trim leading and trailing whitespace
2. collapse internal repeated whitespace
3. match the exact control phrase as a normalized substring, so prompts such as `请先激活 superpowers enforcer` still count
4. do not treat vague paraphrases as equivalent in this round

### 4. Inactive workflow remains the no-op boundary

This round does not try to stop official Claude Code lifecycle events from firing. Instead, it preserves the practical product boundary:

1. hooks may still run because the plugin is installed
2. workflow-only enforcement must no-op while workflow is inactive

That distinction matters. "Not visibly interfering" is the achievable and correct goal at plugin scope.

## Recommended Design

## A. Activation is driven by three signals

The plugin should support three activation signals:

1. manual activation phrase
2. manual deactivation phrase
3. canonical artifact auto-activation

### Manual activation

When `UserPromptSubmit` contains `激活 superpowers enforcer`, the plugin should:

1. set workflow to active immediately
2. record that activation came from an explicit user prompt
3. set a manual override state that prevents later ambiguity with auto-activation rules

### Manual deactivation

When `UserPromptSubmit` contains `关闭 superpowers enforcer`, the plugin should:

1. set workflow to inactive immediately
2. record that deactivation came from an explicit user prompt
3. set a manual override state that blocks later auto-activation until the user explicitly re-activates

### Canonical artifact auto-activation

When a successful `Write` or `Edit` targets a canonical superpowers spec or plan document inside the current project scope, the plugin should auto-activate workflow if and only if there is no active manual-off override.

### Existing skip-style prompt activation remains explicit intent

This round does not retire the existing skip-style prompt handling such as:

1. `skip brainstorming`
2. `skip planning`
3. `skip tdd`
4. `skip review`
5. `skip finishing`

Those prompts already represent explicit workflow intent in the current product. They should continue to count as explicit prompt-driven activation, not passive auto-activation.

That means:

1. skip-style prompt activation is still allowed to set workflow active
2. skip-style prompt activation clears a prior manual-off override, because the user has issued a new explicit workflow-intent prompt
3. manual-off only blocks passive canonical-path auto-activation, not later explicit workflow-intent prompts

## B. Activation priority

Priority must be explicit and deterministic:

1. manual deactivation wins over passive auto-activation
2. later explicit workflow-intent prompts win over a previous manual deactivation
3. explicit manual activation is explicit workflow intent
4. existing skip-style prompt activation is also explicit workflow intent
5. canonical path auto-activation is fallback only

That means:

1. if the user has manually deactivated, later matching spec/plan writes must not silently turn enforcement back on
2. if the user later issues `激活 superpowers enforcer`, workflow turns back on immediately
3. if the user later issues a skip-style workflow prompt, workflow also turns back on immediately because that is explicit workflow intent
4. if there is no manual-off override, canonical artifact writes can activate workflow automatically

## C. Current project scope

Auto-activation should not use a repository-global substring search.

Instead, path resolution should work like this:

1. normalize the written file path against the resolved current project root
2. require the resolved target to remain inside that project root
3. evaluate the normalized project-relative path

### Source of truth for the current project root

This round must use one concrete root-resolution algorithm shared with the existing command-hook state logic.

The current project root is defined as:

1. start from `CLAUDE_PROJECT_DIR` when it is available
2. otherwise start from hook input `cwd`
3. canonicalize that starting candidate to a physical directory path
4. walk upward until the nearest directory containing `.claude/flow_state.json`
5. if such a directory is found, that directory is the current project root
6. if no such directory is found, fall back to the canonicalized starting candidate itself

This keeps activation aligned with the same project root that existing command hooks already use for state lookup.

### Path comparison semantics

Path matching must not be string-only.

Instead:

1. relative target paths are interpreted against the resolved current project root
2. absolute target paths are canonicalized to the same physical path space as the resolved current project root
3. alias-mixed or symlink-mixed paths that resolve to the same physical target must be treated as the same project path
4. once the physical project root is known, the implementation may compute a normalized project-relative path lexically, but only after the root itself has been physically resolved

This is the intended behavior behind the required root-relative, absolute, alias-mixed, and cwd-derived tests.

The relative path should auto-activate when, after normalization, it remains inside the current project root and its project-relative path ends with either:

1. `docs/superpowers/specs/<filename>.md`
2. `docs/superpowers/plans/<filename>.md`

Examples:

1. `docs/superpowers/specs/2026-04-13-demo.md`
2. `simulation-toolset/docs/superpowers/specs/2026-04-13-demo.md`
3. `packages/tooling/docs/superpowers/plans/2026-04-13-demo.md`

### Default exclusions

Even if a path textually contains `docs/superpowers/...`, it should not auto-activate when the relative path lives under clearly non-project-content prefixes such as:

1. `.git/`
2. `.worktrees/`
3. `node_modules/`
4. `vendor/`
5. `.simulation/`
6. fixture or testdata directories

The point is not to build an enormous denylist. The point is to avoid obvious cache, dependency, and artifact trees that should never carry live workflow intent.

## D. State model changes

The current `workflow.active` boolean is not enough to represent manual override semantics cleanly.

This round should extend workflow state with an explicit override field:

1. `null`
2. `"manual_on"`
3. `"manual_off"`

Recommended workflow semantics:

1. `.workflow.active` remains the effective activation flag used by existing gates
2. `.workflow.override` records whether the current state is being forced on or forced off by explicit user intent
3. `.workflow.activated_by` and `.workflow.activated_at` continue to record the last activation event
4. add `.workflow.deactivated_by` and `.workflow.deactivated_at` to record the last manual shutdown event

This is more explicit than overloading `activated_by` to mean both activation and deactivation.

### Effective state transitions

Manual activate:

1. `.workflow.active = true`
2. `.workflow.override = "manual_on"`
3. `.workflow.activated_by = "manual_prompt"`
4. `.workflow.activated_at = now`

Manual deactivate:

1. `.workflow.active = false`
2. `.workflow.override = "manual_off"`
3. `.workflow.deactivated_by = "manual_prompt"`
4. `.workflow.deactivated_at = now`

Auto-activate from canonical artifact:

1. if `.workflow.override == "manual_off"`, do nothing
2. otherwise set `.workflow.active = true`
3. if `.workflow.override != "manual_on"`, set `.workflow.override = null`
4. record `activated_by = "spec_write"` or `activated_by = "plan_write"`
5. update `activated_at`

This preserves the user's explicit stop request.

Skip-style prompt activation:

1. `.workflow.active = true`
2. `.workflow.override = null`
3. keep the existing skip-specific exception bookkeeping
4. record `activated_by = "user_prompt_skip"`
5. update `activated_at`

## E. Scope of this activation round

This round intentionally stops at activation behavior.

It must not silently broaden into a second unrelated enforcement redesign. In particular:

1. it does not yet make Bash file writes equivalent to `Write/Edit` for worktree or TDD gates
2. it does not reinterpret ordinary `docs/*.md` writes as workflow activation
3. it does not infer activation from vague superpowers-like wording beyond the approved exact phrases
4. it does not retire the existing skip-style prompt activation behavior in this round

That separate Bash file-write loophole is real, but it should be handled in a later focused spec so the activation work remains simple and verifiable.

## Error Handling

### 1. Unknown or malformed prompt input

If `UserPromptSubmit` input is valid JSON but has no usable prompt string, manual activation and manual deactivation logic should no-op rather than fail.

### 2. Missing workflow fields in older state

The activation logic must continue to normalize older state files before using the new override fields.

### 3. Out-of-project canonical-looking paths

If a path looks canonical but resolves outside the current project root, it must not activate workflow.

### 4. Conflicting manual state and auto path writes

When manual-off override is active, canonical path writes should update the normal spec/plan bookkeeping only if current implementation already depends on it, but they must not reactivate workflow.

## Acceptance Criteria

This work is complete only when all of the following are true:

1. root canonical spec writes still auto-activate
2. root canonical plan writes still auto-activate
3. subtree canonical spec writes auto-activate
4. subtree canonical plan writes auto-activate
5. ordinary non-canonical `docs/*.md` writes do not auto-activate
6. out-of-project canonical-looking paths do not auto-activate
7. `激活 superpowers enforcer` activates workflow immediately through `UserPromptSubmit`
8. `关闭 superpowers enforcer` deactivates workflow immediately through `UserPromptSubmit`
9. after manual deactivation, later canonical path writes do not auto-reactivate until the user issues a new explicit workflow-intent prompt
10. existing skip-style prompt activation still works and explicitly re-activates workflow
11. existing workflow-only gates still no-op while `.workflow.active != true`

## Testing Requirements

At minimum, implementation must add or update tests for:

1. root-relative, dotted-relative, absolute, alias-mixed, and cwd-derived canonical root paths
2. subtree canonical paths in the same variants
3. excluded prefixes such as `.simulation/.../docs/superpowers/specs/...`
4. manual activation phrase
5. manual deactivation phrase
6. manual-off override preventing later auto-reactivation from canonical path writes
7. skip-style prompt activation clearing manual-off override
8. old state normalization for new workflow override/deactivation fields

## Why This Is The Recommended Shape

This design is the smallest direct change that satisfies the product goal without repeating the same mistakes:

1. it preserves existing working root behavior
2. it generalizes to real multi-project layouts without special-casing one directory name
3. it gives the user an explicit on/off control surface
4. it keeps inactive workflow as the practical no-op boundary
5. it avoids dragging the separate Bash file-write loophole into the same implementation packet
