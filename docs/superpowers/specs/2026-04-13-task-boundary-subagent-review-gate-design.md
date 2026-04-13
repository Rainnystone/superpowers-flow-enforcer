# Task-Boundary Subagent Review Gate Design

## Goal

Close the loophole where Claude Code can dispatch the next implementor task before the current task has completed the required two-stage review.

This round is intentionally narrow:

1. block only task-boundary progression during packetized TDD execution
2. do not introduce a global ban on all subagent or task usage
3. preserve same-task fix and re-review loops

## Problem Statement

The current repo enforces review too late. `TaskCompleted` can block completion if a task is missing review state, but it cannot stop Claude Code from starting the next implementor packet while the current task is still unfinished.

This creates a real loophole:

1. current task starts
2. review is incomplete
3. Claude dispatches the next implementor anyway
4. only the final completion hook notices the missing review state

The intended discipline is stricter:

1. implement current task
2. complete spec review loop
3. complete code-quality review loop
4. only then start the next task's implementor

## Non-Goals

This design does not:

1. block every `Agent` or `Task*` tool use globally
2. infer review role from arbitrary natural-language prose
3. redesign the whole workflow state machine
4. replace `TaskCompleted` as the final backstop

## Official Claude Code Constraints

This design follows Claude Code official hook and tool behavior:

1. `Agent` is the built-in subagent tool name used in `PreToolUse` / `PostToolUse`
2. `TaskCreated` and `TaskCompleted` are separate top-level hook events
3. `TaskCreated` input contains `task_id`, `task_subject`, and optionally `task_description`, `teammate_name`, `team_name`
4. the exact dispatch metadata field for `Agent` must come from real hook payload fixtures

Because the `Agent` tool input shape is official and stable, packet metadata must stay inside that shape. The repo must not invent synthetic top-level hook fields that Claude Code does not emit.

## Packet Metadata Contract

Any subagent dispatch that participates in packetized execution must declare:

1. `SPFE_TASK_ID=<task-id>`
2. `SPFE_PACKET_ROLE=implementer|spec-reviewer|code-reviewer`

The contract must be deterministic. For the current Claude Code `Agent` tool shape, the repo will treat these as a fixed prefix at the top of `tool_input.prompt`:

```text
SPFE_TASK_ID=<task-id>
SPFE_PACKET_ROLE=<role>

<natural-language packet prompt>
```

Important boundaries:

1. extraction must read one deterministic field path
2. extraction must use the fixed prefix position, not search the whole prompt body
3. malformed or missing metadata must fail closed

## Success Event Selection

Successful-dispatch sync must bind to the narrowest official success event that carries deterministic packet metadata.

Preference order:

1. `TaskCreated` if it exposes equivalent packet metadata cleanly
2. otherwise successful `PostToolUse` for `tool_name == "Agent"`

This repo must pin the decision with fixtures and a helper instead of assuming the answer.

## Gate Activation Boundary

The task-boundary gate should activate only once packetized implementation execution is underway.

Recommended activation condition:

1. `workflow.active == true`
2. `worktree.created == true`
3. `worktree.baseline_verified == true`

Additionally:

1. if `task_flow.active_task_id` is already non-null, the same gate should stay active until that task is closed
2. later partial state rollback must not silently reopen the loophole

## Dedicated State Surface

Do not overload this onto `tdd.current_task`.

Add a dedicated top-level state object:

```json
"task_flow": {
  "active_task_id": null,
  "active_packet_role": null,
  "last_dispatch_at": null
}
```

Semantics:

1. `active_task_id`: current task under review/execution discipline
2. `active_packet_role`: the most recently allowed packet role for that task
3. `last_dispatch_at`: last successful dispatch timestamp

`review.tasks` remains the source of truth for review completion.

## Dispatch Rules

### Missing metadata

If the gate is active and the `Agent` dispatch does not provide valid packet metadata, deny it with a hint that tells Claude to add `SPFE_TASK_ID` and `SPFE_PACKET_ROLE`.

### `implementer`

Allow when:

1. no active task exists yet
2. the dispatch targets the same active task
3. the dispatch targets a different task, but the current task already has both review passes

Deny when:

1. the dispatch targets a different task
2. the current active task is still missing either review pass

The deny reason must:

1. name the current open task id
2. state that spec review and code review must both complete first
3. direct Claude back into the current task's review loop

### `spec-reviewer`

Allow when:

1. it targets the current active task

Deny when:

1. it targets a different task while another task is open
2. it uses a generic combined role instead of explicit `spec-reviewer`

### `code-reviewer`

Allow when:

1. it targets the current active task
2. the same task already has `spec_review_passed == true`

Deny when:

1. spec review has not yet passed
2. it targets a different task while another task is open
3. it tries to combine spec review and code review in one packet

### Same-task repair loop

If a review fails, re-dispatching `implementer` for the same `task-id` must stay allowed. This preserves:

1. fix after failed spec review
2. fix after failed code review
3. re-review loops without fake task transitions

## Review-State Progression

Existing review recording stays in place:

1. `record-review-state.sh <task-id> spec pass|fail`
2. `record-review-state.sh <task-id> code pass|fail`

Expected progression:

1. implementer starts task `A`
2. `spec-reviewer` reviews task `A`
3. if spec fails, implementer for task `A` is allowed again
4. spec re-review continues until pass
5. `code-reviewer` reviews task `A`
6. if code fails, implementer for task `A` is allowed again
7. code re-review continues until pass
8. only then may task `B` implementer start

## Successful-Dispatch Sync

The gate must not guess that a task changed merely because `PreToolUse` allowed a dispatch. State changes belong on a successful-dispatch path.

Required behavior:

1. successful implementer dispatch for a new task:
   - set `task_flow.active_task_id`
   - set `task_flow.active_packet_role = "implementer"`
   - set `task_flow.last_dispatch_at`
   - initialize `review.tasks[task-id]` defaults if absent
2. successful reviewer dispatch:
   - keep `active_task_id` unchanged
   - update only `active_packet_role`
   - update `last_dispatch_at`
3. same-task implementer follow-up must not reset already-passed review flags back to `false`

## Deny Behavior

Representative deny text:

1. next-task implementor too early:
   - `当前 task <task-id> 尚未完成双 review。先完成当前 task 的 spec review 与 code review（必要时继续 fix -> re-review），再派发下一个 implementor。`
2. missing packet metadata:
   - `当前已进入 packetized TDD 执行阶段。派发 subagent 时必须显式声明 SPFE_TASK_ID 和 SPFE_PACKET_ROLE，否则无法判断 task 边界。`
3. combined reviewer role:
   - `spec review 与 code quality review 必须由两个独立 reviewer packet 先后执行，不能合并为一个 reviewer dispatch。`
4. code review before spec pass:
   - `当前 task 还没有通过 spec review，不能直接进入 code quality review。先完成 spec review loop。`

These messages should redirect Claude, not dead-end the workflow.

## Acceptance Criteria

This design is satisfied only when:

1. during packetized TDD execution, starting implementer task `B` while active task `A` lacks either review pass is denied
2. same-task implementer follow-up remains allowed
3. `spec-reviewer` and `code-reviewer` are the only accepted reviewer roles
4. `code-reviewer` is blocked until spec review has passed for the same task
5. once the current task has both review passes, the next task's implementer is allowed
6. missing packet metadata is denied with a corrective hint
7. successful-dispatch sync is pinned to the narrowest working official success event
8. `TaskCompleted` remains the final completion backstop
