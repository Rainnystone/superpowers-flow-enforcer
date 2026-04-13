# Task-Boundary Subagent Review Gate Implementation Plan

## Goal

Prevent Claude Code from dispatching the next implementor packet before the current task has completed separate spec-review and code-quality-review closure, while preserving same-task fix and re-review loops.

## Scope

This plan covers one subsystem only: task-boundary subagent dispatch discipline during packetized TDD execution.

Do not widen this plan into:

1. global `Agent` / `Task*` tool restrictions
2. Bash loophole fixes
3. transcript-level review inference
4. broader workflow state-machine cleanup
5. committing or tracking local-only `AGENTS.md`

## Execution Model

Run this plan with:

1. `subagent-driven-development`
2. `test-driven-development`
3. `AGENTS.md` discipline for subagent ownership, wait windows, and review ordering

All packets run serially. No parallel implementer packets.

## Files

### Create

1. `tests/fixtures/pretool_agent_dispatch.json`
2. `tests/fixtures/taskcreated_agent_dispatch.json`
3. `tests/fixtures/posttool_agent_dispatch.json`
4. `tests/test_agent_task_boundary_gate.sh`
5. `scripts/lib/task_flow_packets.sh`

### Modify

1. `templates/flow_state.json.tmpl`
2. `scripts/migrate-state.sh`
3. `scripts/init-state.sh`
4. `hooks/hooks.json`
5. `scripts/check-pretool-gates.sh`
6. `scripts/sync-post-tool-state.sh`
7. `tests/helpers/state-fixtures.sh`
8. `tests/test_init_state.sh`
9. `tests/test_hooks_official_events.sh`
10. `CLAUDE.md`

### Verify

1. `scripts/check-task-completed.sh`
2. `scripts/record-review-state.sh`
3. `tests/test_pretool_command_gates.sh`
4. `tests/test_posttool_command_gates.sh`
5. `tests/test_recorded_review_flow.sh`

## Task 1: Pin Delegation Payload Contract

### Goal

Stop guessing about the `Agent` tool payload and pin the success-event selection with fixtures.

### Allowed files

1. `tests/fixtures/pretool_agent_dispatch.json`
2. `tests/fixtures/taskcreated_agent_dispatch.json`
3. `tests/fixtures/posttool_agent_dispatch.json`
4. `tests/test_agent_task_boundary_gate.sh`
5. `scripts/lib/task_flow_packets.sh`

### TDD requirements

Write failing tests first for:

1. fixture contract for `PreToolUse`, `TaskCreated`, `PostToolUse`
2. official `Agent` input shape in `PreToolUse` / `PostToolUse`
3. deterministic prompt-prefix metadata extraction
4. failure on malformed or missing prefix
5. `select-success-event` preferring `TaskCreated` only if metadata extraction succeeds
6. current fallback to `PostToolUse`
7. `extract` returning `.task_id` / `.role`
8. `extract` failing with non-zero exit code when metadata is unavailable

### Verification

Run:

1. `bash tests/test_agent_task_boundary_gate.sh`

### Done condition

Task 1 is complete only when:

1. fixtures pin the live payload contract
2. metadata extraction uses official `Agent` schema
3. extraction reads only the prompt prefix contract, not arbitrary prose
4. `TaskCreated` currently fails the contract and therefore falls back to `PostToolUse`

## Task 2: Add `task_flow` State Schema And Migration

### Goal

Add a dedicated `task_flow` state surface that can be safely initialized, normalized, and migrated.

### Allowed files

1. `templates/flow_state.json.tmpl`
2. `scripts/migrate-state.sh`
3. `scripts/init-state.sh`
4. `tests/helpers/state-fixtures.sh`
5. `tests/test_init_state.sh`

### TDD requirements

Write failing tests first for:

1. fresh v2 state includes default `task_flow`
2. missing `task_flow` normalizes in place
3. partial `task_flow` normalizes in place
4. invalid `active_packet_role` string triggers backup-reset
5. invalid `active_packet_role` type triggers backup-reset
6. non-object `task_flow` triggers backup-reset
7. v1 -> v2 migration emits default `task_flow`
8. `migrate-state.sh --check-safe` includes `task_flow`

### Implementation requirements

`task_flow` must be:

```json
"task_flow": {
  "active_task_id": null,
  "active_packet_role": null,
  "last_dispatch_at": null
}
```

`active_packet_role` accepts only:

1. `null`
2. `implementer`
3. `spec-reviewer`
4. `code-reviewer`

### Verification

Run:

1. `bash tests/test_init_state.sh`
2. `bash tests/test_recorded_review_flow.sh`

## Task 3: Add The Pre-Dispatch Task-Boundary Gate

### Goal

Block next-task implementor dispatch while the current task still lacks one or both review passes.

### Allowed files

1. `hooks/hooks.json`
2. `scripts/check-pretool-gates.sh`
3. `scripts/lib/task_flow_packets.sh`
4. `tests/test_hooks_official_events.sh`
5. `tests/test_agent_task_boundary_gate.sh`

### TDD requirements

Write failing tests first for:

1. `PreToolUse` matcher includes the `Agent` tool
2. gate activates only when:
   - `workflow.active == true`
   - `worktree.created == true`
   - `worktree.baseline_verified == true`
   - or an active task is already open
3. missing packet metadata is denied with a hint
4. different-task implementer is denied if the current task lacks either review pass
5. same-task implementer remains allowed
6. if an active task already exists, later partial workflow rollback does not silently disable the gate
7. deny output names the current open task id and tells Claude to continue the current review loop

### Verification

Run:

1. `bash tests/test_agent_task_boundary_gate.sh`
2. `bash tests/test_hooks_official_events.sh`
3. `bash tests/test_pretool_command_gates.sh`

## Task 4: Sync `task_flow` On Successful Dispatch

### Goal

Record successful implementer and reviewer dispatches on the confirmed success event.

### Allowed files

1. `scripts/sync-post-tool-state.sh`
2. `scripts/lib/task_flow_packets.sh`
3. `tests/test_agent_task_boundary_gate.sh`

If Task 1 later proves that another success handler is needed, substitute the actual handler file. The behavior requirements stay the same.

### TDD requirements

Write failing tests first for:

1. successful implementer dispatch sets:
   - `task_flow.active_task_id`
   - `task_flow.active_packet_role`
   - `task_flow.last_dispatch_at`
2. first successful implementer dispatch initializes review defaults if absent
3. successful reviewer dispatch updates only role and timestamp while keeping `active_task_id`
4. same-task implementer follow-up does not reset passed review flags

### Verification

Run:

1. `bash tests/test_agent_task_boundary_gate.sh`
2. `bash tests/test_posttool_command_gates.sh`

## Task 5: Enforce Reviewer Separation, Ordering, And Loop Preservation

### Goal

Accept only two separate reviewer roles, enforce `spec-reviewer` before `code-reviewer`, and keep the same-task fix loop alive.

### Allowed files

1. `scripts/check-pretool-gates.sh`
2. `scripts/lib/task_flow_packets.sh`
3. `tests/test_agent_task_boundary_gate.sh`
4. `CLAUDE.md`

### TDD requirements

Write failing tests first for:

1. generic `reviewer` is denied
2. combined reviewer role is denied
3. `code-reviewer` before spec pass is denied
4. `spec-reviewer` for the current task is allowed
5. failed spec review -> same-task implementer follow-up is allowed
6. passed spec review -> `code-reviewer` is allowed
7. failed code review -> same-task implementer follow-up is allowed
8. once both reviews pass, next-task implementer is allowed
9. deny output includes open task id and tells Claude to finish current review loop first

### Documentation requirements

Update `CLAUDE.md` with runtime-facing packet guidance only:

1. implementer packets must include `SPFE_TASK_ID` and `SPFE_PACKET_ROLE=implementer`
2. spec review uses `spec-reviewer`
3. code quality review uses `code-reviewer`
4. the next implementer may not start until the current task has both review passes
5. same-task fix and re-review loops are expected

Do not copy Codex-only `AGENTS.md` content into `CLAUDE.md`.

### Verification

Run:

1. `bash tests/test_agent_task_boundary_gate.sh`
2. `rg -n "Packetized Subagent Execution|SPFE_TASK_ID|spec-reviewer|code-reviewer" CLAUDE.md`
3. `bash tests/test_init_state.sh`
4. `bash tests/test_hooks_official_events.sh`
5. `bash tests/test_pretool_command_gates.sh`
6. `bash tests/test_posttool_command_gates.sh`
7. `git diff --check`

## Completion Criteria

This plan is complete only when:

1. `Agent` payload contract and success-event selection are pinned with fixtures
2. `task_flow` state exists and migrates safely
3. pre-dispatch gate activates only for packetized execution or while an active task is already open
4. next-task implementer dispatch is blocked until the current task has both review passes
5. same-task implementer follow-up remains allowed
6. same-task implementer follow-up does not reset already-passed review flags
7. `spec-reviewer` and `code-reviewer` are the only accepted reviewer roles
8. `code-reviewer` is blocked until spec review has passed for the same task
9. once the current task has both review passes, the next implementer is allowed
10. deny output names the currently open task id and redirects Claude into the current review loop
11. `TaskCompleted` remains the final completion backstop
12. `CLAUDE.md` teaches only the shipped runtime packet contract
