# Manual Control And Resume Enforcer Design

> Scope: improve the human control surface for workflow activation and add a deterministic recovery handshake for resumed superpowers sessions. This round is intentionally narrow. It does not redesign the broader workflow state machine and it does not turn planning-with-files into a hidden default dependency outside the recovery path.

## Goal

This design satisfies two concrete product goals:

1. make manual enforcer control shorter and easier to remember without weakening the current workflow boundary
2. stop resumed unfinished workflow sessions from drifting back into "start over" behavior by requiring an explicit recovery step before execution resumes

The intended result is:

1. users can quickly turn enforcement on or off with shorter recommended phrases
2. resumed unfinished workflow sessions are forced through one deterministic recovery handshake
3. ordinary non-workflow resumes still remain quiet and unblocked

## Baseline

The current repository behaves like this:

1. manual workflow control is recognized only through the longer phrases:
   - `激活 superpowers enforcer`
   - `关闭 superpowers enforcer`
   - `activate superpowers enforcer`
   - `deactivate superpowers enforcer`
2. those phrases are handled inside `scripts/sync-user-prompt-state.sh`
3. text pause / interrupt intent is also handled in `scripts/sync-user-prompt-state.sh` through broad keyword detection such as:
   - `停止`
   - `stop`
   - `pause`
   - `暂停`
   - `break`
4. the plugin currently has no dedicated resume state surface and no workflow-specific recovery handshake for resumed sessions
5. `SessionStart` currently initializes or normalizes state, but it does not treat `source == "resume"` as a distinct product path
6. the repo already follows a deterministic state-recording pattern for key workflow facts:
   - `record-spec-state.sh`
   - `record-review-state.sh`
   - `record-finishing-state.sh`
   - `record-worktree-state.sh`

This round should extend that pattern rather than replacing it with free-form prompt inference.

## Official Claude Code Constraints

This design follows the official Claude Code boundaries that matter here:

1. resumed conversations are already supported through `/resume`, `claude --continue`, and `claude --resume`
2. resumed sessions restore prior conversation history and tool state
3. `SessionStart` receives a `source` field such as `startup`, `resume`, `clear`, or `compact`
4. `SessionStart` may inject context through stdout / command output, but it runs on every session start and should stay fast
5. skills are the preferred place for reusable multi-step procedures
6. skills can be manual-only and do not need to be auto-invoked
7. hook logic should remain deterministic when a direct observable state or event is available

The practical consequence is:

1. do not try to rebuild all workflow understanding inside `SessionStart`
2. use `SessionStart` only to detect the resume path and set up the recovery gate
3. use a dedicated manual skill for the heavier recovery procedure

## Problems To Solve

### 1. Manual control is still too verbose

The current control phrases are correct but unnecessarily long for everyday use. Users should not need to remember the full `superpowers` wording every time they want to enable or disable enforcement.

### 2. `stop` is already overloaded

The natural short verbs `停止` and `stop` are already bound to pause / interrupt semantics. Reusing them as primary enforcer control verbs would mix two different intentions:

1. stop or pause the current conversation flow
2. disable workflow enforcement itself

That ambiguity is avoidable and should not be introduced in this round.

### 3. Resumed unfinished workflow sessions have no recovery handshake

Claude Code can resume the prior conversation, but this plugin currently has no workflow-specific handshake that tells Claude:

1. whether the prior workflow was left unfinished
2. where execution actually stopped
3. which phase or task is currently open
4. which skill or state-recording command must run next

Without that handshake, resumed workflow sessions can continue from a vague or stale mental model and effectively behave like a partial restart.

### 4. The existing gate set cannot distinguish "workflow is active" from "workflow is active but must be re-synced first"

Today the repo mainly reasons about:

1. `workflow.active`
2. phase-specific state such as spec/plan/worktree/review flags

It does not model the intermediate state:

1. workflow is active
2. session has resumed
3. the workflow must be recovered before execution continues

That missing state is exactly why resumed unfinished sessions can drift.

## Non-Goals

This round does **not** do the following:

1. it does not redesign the full workflow state machine
2. it does not auto-advance workflow phases during recovery
3. it does not automatically repair missing review, finishing, or planning-with-files records
4. it does not make `planning-with-files` a hidden hard dependency for all plugin usage
5. it does not add `启动/停止 enforcer` or `start/stop enforcer` as preferred control phrases
6. it does not move the workflow into a fully automatic resume path

## Design Principles

### 1. Prefer shorter but unambiguous control phrases

Shorter commands are valuable only if they do not collide with existing pause / interrupt semantics.

### 2. Keep compatibility with the current long phrases

Existing documented phrases should continue to work. This round adds a better default entry point; it should not break the current one.

### 3. Recovery must be explicit

If a workflow was left unfinished, the repo should require one explicit recovery action before allowing new edits, writes, or subagent dispatches. The goal is not convenience at all costs. The goal is deterministic recovery.

### 4. Keep hooks deterministic and keep the heavy work in a skill

`SessionStart` should stay fast. The heavy interpretation step belongs in a manual recovery skill that reads the persisted state and working tree deliberately.

### 5. Do not silently complete state work on the user’s behalf

Recovery should tell Claude what is true and what should happen next. It should not silently mark review as done, mark finishing as invoked, or fabricate planning-with-files progress.

## Alternatives Considered

### Option A: Recommended short commands + explicit recovery gate

Add shorter recommended control phrases while keeping current long phrases, and add a resume-specific recovery gate that requires a dedicated recovery skill before execution resumes.

Pros:

1. shortens the human control surface immediately
2. avoids `stop`/interrupt ambiguity
3. gives resumed unfinished workflows a deterministic handshake
4. stays aligned with the repo’s explicit fact-recording style

Cons:

1. resumed unfinished workflow sessions require one extra explicit step

Recommended.

### Option B: Use `start/stop enforcer` as the new preferred control surface

Pros:

1. even shorter wording

Cons:

1. collides with the existing pause / interrupt path
2. would force priority rules that mix workflow control and conversation stop semantics
3. would make future debugging harder because the same verb would mean two different things

Rejected.

### Option C: Fully automatic resume recovery inside `SessionStart`

Pros:

1. no manual recovery step

Cons:

1. too much logic in a hook that should stay fast
2. higher risk of wrong phase inference
3. harder to test and explain
4. encourages the plugin to guess workflow meaning instead of reading explicit state

Rejected.

### Option D: Resume skill as advisory only

Pros:

1. minimal friction

Cons:

1. does not solve the actual failure mode
2. Claude can still continue writing code before its workflow state is re-synced

Rejected.

## Recommended Design

## A. Shorter manual control phrases

### Default recommended phrases

This round should document and support the shorter phrases:

1. `开启 enforcer`
2. `关闭 enforcer`
3. `enable enforcer`
4. `disable enforcer`

These become the preferred user-facing commands in docs and prompts.

### Backward compatibility

The existing longer phrases must continue to work:

1. `激活 superpowers enforcer`
2. `关闭 superpowers enforcer`
3. `activate superpowers enforcer`
4. `deactivate superpowers enforcer`

The shorter phrases are additive, not a replacement.

### Not supported as primary control phrases in this round

Do **not** promote or newly support these as the preferred manual control surface:

1. `启动 enforcer`
2. `停止 enforcer`
3. `start enforcer`
4. `stop enforcer`

The reason is explicit product clarity: `停止` / `stop` already belong to the interrupt path.

### Matching semantics

The current normalized clause matching style should be preserved:

1. trim outer whitespace
2. collapse repeated internal whitespace
3. allow polite or mid-sentence command clauses
4. reject explanatory, hypothetical, quoted, or negated discussion of the command phrase

Representative accepted forms:

1. `请开启 enforcer`
2. `先整理上下文，然后关闭 enforcer 再继续`
3. `Please enable enforcer, thanks`

Representative rejected forms:

1. `如果用户输入 开启 enforcer 会发生什么？`
2. `不是要关闭 enforcer，只是在解释命令`

## B. Manual control takes priority over interrupt detection

When a prompt contains a recognized enforcer control clause:

1. process the enforcer control action first
2. do **not** record `interrupt.allowed` from the same prompt
3. do **not** treat that prompt as a pause request

This preserves a clean boundary:

1. `关闭 enforcer` means workflow control
2. `暂停一下` means conversational interrupt intent

The repo should not try to combine both semantics in one submission during this round.

## C. Add a dedicated resume state surface

Add a new top-level state object:

```json
"resume": {
  "recovery_required": false,
  "recovery_completed_at": null,
  "last_resume_source": null
}
```

Semantics:

1. `recovery_required`
   - true when a resumed unfinished workflow must be re-synced before execution continues
2. `recovery_completed_at`
   - timestamp of the last successful recovery handshake
3. `last_resume_source`
   - last `SessionStart.source` value observed for recovery logic, primarily `resume`

This state stores only deterministic facts. It must not store free-form model conclusions about the phase.

## D. Treat `SessionStart(source=resume)` as a lightweight recovery trigger

`SessionStart` should remain narrow and fast.

When `source != "resume"`:

1. do not apply the resume recovery path

When `source == "resume"`:

1. normalize or bootstrap the resume state object if needed
2. record `resume.last_resume_source = "resume"`
3. evaluate deterministic clear conditions first
4. if a deterministic clear condition holds:
   - set `resume.recovery_required = false`
5. otherwise evaluate whether recovery is required
6. if recovery is required:
   - set `resume.recovery_required = true`
   - inject a short context hint telling Claude to run the dedicated recovery skill before continuing
7. otherwise preserve the existing `resume.recovery_required` value

### Recovery-required rule

Recovery should be required only when all of the following are true:

1. `workflow.active == true`
2. the workflow was not cleanly closed through manual deactivation
3. the workflow does not already appear cleanly finished
4. there is evidence the workflow had actually progressed beyond a trivial inactive shell

For this round, those conditions must be made deterministic and testable.

### Cleanly finished predicate

For the purpose of skipping the recovery gate, a workflow counts as cleanly finished only when all of the following are true:

1. `finishing.invoked == true`
2. `task_flow.active_task_id == null`
3. either:
   - `review.tasks` is empty
   - or every recorded task in `review.tasks` has both `spec_review_passed == true` and `code_review_passed == true`

This is separate from manual shutdown:

1. `workflow.override == "manual_off"` is a clean manual closure path
2. an active session with partial review state is **not** cleanly finished

### Task-flow closure requirement

This round must also make the clean-finish predicate achievable.

That means the implementation must include one deterministic path that clears:

1. `task_flow.active_task_id`
2. `task_flow.active_packet_role`

when the workflow reaches a cleanly finished state.

For planning purposes, this responsibility belongs to the normal completion path rather than to the recovery skill. The implementation plan may choose the narrowest existing deterministic recording surface, but it must explicitly cover and test this task-flow cleanup so that a normally finished workflow can actually satisfy the clean-finish predicate above.

### Exact progress predicate for recovery-required evaluation

For this round, `there is evidence the workflow had actually progressed beyond a trivial inactive shell` must be implemented as this exact OR predicate:

1. `current_phase != "init"`
2. `brainstorming.question_asked == true`
3. `brainstorming.spec_written == true`
4. `planning.plan_written == true`
5. `worktree.created == true`
6. `task_flow.active_task_id != null`
7. non-empty `review.tasks`
8. any of the TDD tracking arrays are non-empty:
   - `tdd.test_files_created`
   - `tdd.production_files_written`
   - `tdd.tests_verified_fail`
   - `tdd.tests_verified_pass`

Representative no-gate cases include:

1. `workflow.active != true`
2. `workflow.override == "manual_off"`
3. workflow already satisfies the cleanly finished predicate above

### Lifecycle of `resume.recovery_required`

`resume.recovery_required` is workflow-scoped, not merely session-scoped.

That means:

1. `SessionStart(source=resume)` may set it to `true`
2. once true, it must remain true across later session starts, including non-resume starts, until a deterministic clear condition occurs
3. non-resume `SessionStart` must not blindly clear it just because the new source is not `resume`

Deterministic clear conditions for this round are:

1. successful completion of the dedicated recovery skill
2. `workflow.active != true`
3. `workflow.override == "manual_off"`
4. the cleanly finished predicate above is satisfied

If none of those conditions hold, later `startup` or additional `resume` starts should preserve the recovery gate rather than silently dropping it.

### Explicit implementation boundary for the resume trigger

The implementation plan must treat the resume trigger as a narrow change to:

1. `hooks/hooks.json`
2. the `SessionStart` command-hook path
3. the official `SessionStart` input field `source`

This round must not invent a pseudo-event or transcript-based resume detector.

## E. Add a dedicated manual recovery skill

Add a manual recovery skill referred to in this design as `resume-enforcer`.

This round pins the skill to a concrete repo boundary:

1. primary skill file: `skills/resume-enforcer/SKILL.md`
2. explicit resume-state recording helper: `scripts/record-resume-state.sh`

This round explicitly ships the recovery skill as a real plugin-bundled skill from the boundary above. For this plugin packaging model, the user-facing installed invocation should be documented as:

1. `/superpowers-flow-enforcer:resume-enforcer`

Within this design document, `resume-enforcer` may still be used as shorthand for the skill itself. There is no additional alias in this round. The implementation plan must plan against the concrete file boundary above and the fully qualified installed invocation surface above.

### Canonical planning-record location for this round

For this repository, the recovery skill must read planning-with-files records only from the project-local directory:

1. `.planning-with-files/task_plan.md`
2. `.planning-with-files/progress.md`
3. `.planning-with-files/findings.md`

This round must not treat root-level `task_plan.md`, `progress.md`, or `findings.md` as the canonical recovery source for this repo.

### Invocation model

This skill should be manual-first, not automatically invoked by the model.

### Responsibilities

The skill must:

1. read `.claude/flow_state.json`
2. read `.planning-with-files/task_plan.md` if present
3. read `.planning-with-files/progress.md` if present
4. read `.planning-with-files/findings.md` only when needed for reconstruction
5. inspect the current working tree using:
   - `git status --short`
   - and, when needed, `git diff --stat`
6. produce a structured recovery summary that tells Claude:
   - current inferred workflow phase
   - current open task and review state, if any
   - the last confirmed progress point
   - the next required action
   - which skill, recording script, or workflow step should run next

### Explicit non-responsibilities

The skill must **not**:

1. auto-advance the phase machine
2. silently mark review as passed
3. silently mark finishing as invoked
4. silently write planning-with-files progress on the user’s behalf
5. bypass the recovery gate without actually completing the recovery procedure

### Recovery completion

A recovery run counts as successful when all of the following are true:

1. the skill completed its required reads
2. the skill emitted the structured recovery summary
3. the explicit resume-state recording helper completed successfully

This success condition does **not** require Claude to complete later follow-up repairs or workflow actions. Recovery success means "the workflow position has been reconstructed and recorded," not "the unfinished workflow is now fully solved."

At the end of a successful recovery run, the skill must record:

1. `resume.recovery_required = false`
2. `resume.recovery_completed_at = <timestamp>`

The recording path must stay aligned with the repo’s existing explicit state-update discipline and should use the dedicated helper above rather than ad-hoc mutation.

## F. Add a resume recovery gate to execution hooks

When `resume.recovery_required == true`, the repo must temporarily deny:

1. `PreToolUse Edit`
2. `PreToolUse Write`
3. `PreToolUse Agent`

The deny reason must clearly direct Claude back to the recovery skill.

Representative deny text:

`检测到 resumed 的未完成 superpowers workflow。先执行 /superpowers-flow-enforcer:resume-enforcer 完成恢复摘要，再继续 Edit/Write/Agent。`

This gate is intentionally narrow:

1. it blocks execution progression
2. it does not block ordinary resume startup itself
3. it does not block non-execution hooks that are needed to bootstrap or inspect state

### Bash boundary for this round

This round does **not** extend the resume recovery gate to `PreToolUse:Bash`.

That is an intentional scope boundary, not an omission:

1. the repo already treats Bash gating as a separate policy surface
2. the purpose of this design is to control primary workflow execution surfaces:
   - `Edit`
   - `Write`
   - `Agent`
3. the implementation plan must not overclaim that this round closes arbitrary shell-based mutation paths
4. if later product requirements need recovery-gated Bash mutation control, that should be a follow-up design

## G. Documentation changes

This round must update:

1. `README.md`
2. `README_cn.md`
3. `CLAUDE.md`
4. the recovery skill documentation itself

Docs must clearly show:

1. the new preferred control phrases
2. that the longer phrases still work
3. that `start/stop enforcer` is not the recommended control surface
4. the recovery behavior for unfinished resumed workflows
5. that the recovery skill explains what to do next but does not auto-complete workflow state

## Testing Requirements

The implementation plan must include tests for at least the following behaviors.

### Manual control phrases

1. `开启 enforcer` activates workflow
2. `enable enforcer` activates workflow
3. `关闭 enforcer` deactivates workflow
4. `disable enforcer` deactivates workflow
5. existing long phrases still work
6. explanatory or negated uses of the short phrases do not mutate state
7. matched enforcer-control prompts do not also write `interrupt.allowed`
8. ordinary `停止` / `stop` / `pause` prompts still retain existing interrupt behavior when they are not enforcer-control phrases

### Resume state initialization

1. fresh state includes the `resume` object with defaults
2. older or partial state normalizes the `resume` object safely
3. invalid `resume` shapes fail closed using the repo’s current safety policy

### Resume trigger behavior

1. `SessionStart(source=resume)` on an unfinished active workflow sets `resume.recovery_required = true`
2. the same path injects a short recovery hint
3. normal startup does not set the resume recovery gate
4. resume on an inactive workflow does not set the gate
5. resume after manual shutdown does not set the gate
6. resume after a cleanly finished workflow does not set the gate

### Recovery gate behavior

1. when `resume.recovery_required == true`, `Edit` is denied
2. when `resume.recovery_required == true`, `Write` is denied
3. when `resume.recovery_required == true`, `Agent` is denied
4. deny text tells Claude to run the recovery skill first
5. once recovery completes, the gate clears and normal execution resumes

### Recovery skill behavior

1. the skill reads state plus planning-with-files records in the intended order
2. the skill produces a structured summary rather than free-form vague prose
3. the skill clears `resume.recovery_required`
4. the skill writes `resume.recovery_completed_at`
5. the skill does not mutate unrelated workflow completion state

## Acceptance Criteria

This design is complete when all of the following are true:

1. users have a shorter recommended manual control surface:
   - `开启/关闭 enforcer`
   - `enable/disable enforcer`
2. the existing longer phrases still work
3. enforcer control no longer risks colliding with interrupt semantics in the same prompt path
4. resumed unfinished workflows cannot continue directly into new `Edit`, `Write`, or subagent execution
5. resumed unfinished workflows must first run the dedicated recovery skill
6. the recovery skill reconstructs the current workflow position from state plus persisted records without silently advancing the workflow
7. resumed inactive or cleanly finished workflows remain quiet and unblocked

## Open Questions

None at the design level for this round.

## Recommended Next Step

After spec review, write one focused implementation plan that covers:

1. state schema extension
2. short manual command matching
3. `SessionStart(source=resume)` recovery trigger
4. recovery skill creation
5. pretool recovery gate
6. docs and regression tests
