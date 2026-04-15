# Superpowers Flow Enforcer

English | [中文](./README_cn.md)

A Claude Code plugin that acts as a supplement to [obra/superpowers](https://github.com/obra/superpowers) by enforcing workflow-aware hooks after a session explicitly enters the superpowers workflow. It is not a replacement, and it is designed to be used together with [planning-with-files](https://github.com/othmanadi/planning-with-files) for external memory. This repo still ships as a single plugin install: the Bash gate uses the vendored `vendor/bash-traverse` runtime, so there is no separate parser repo clone or build step.

## Overview

**Core Principle**: Don't skip steps during execution.

The plugin implements workflow-aware hooks that enforce:
- Workflow-only gates fail open until the session explicitly enters the superpowers workflow
- Brainstorming → SPEC → Planning → TDD → Review → Verification → Finishing workflow
- Two-stage code review (spec compliance + code quality)
- Packetized subagent task-boundary gating during superpowers execution, so the next task's implementer cannot start before the current task passes both reviews
- Fresh verification evidence before completion claims
- Systematic debugging methodology on test failures

Workflow entry is explicit, not inferred from every Claude Code session. In the current implementation, entry happens when the session records a skip request, when the user explicitly says a supported manual entry command such as `开启 enforcer` / `enable enforcer` or the long-form compatibility prompts `激活 superpowers enforcer` / `activate superpowers enforcer`, or when Claude writes canonical superpowers artifacts under `docs/superpowers/specs/*.md` or `docs/superpowers/plans/*.md` within the current project scope. That automatic path-based entry keeps the root-level canonical paths and also recognizes subtree forms such as `packages/foo/docs/superpowers/specs/*.md`, while excluding trees like `.git`, `.worktrees`, `node_modules`, `vendor`, `.simulation`, and fixture/testdata directories.

`PreToolUse/Bash` only runs its active gate when `workflow.active == true`. If the workflow is not active, the hook exits silently and does nothing. When active, the gate depends on Node 18+ because it executes the vendored Bash parser runtime through Node.

`planning-with-files` remains part of the intended setup because it provides the durable `task_plan.md`, `findings.md`, and `progress.md` memory that this workflow expects. This is especially useful in Claude Code deployments that route to GLM-5 with a 128K context window, where disk-backed tracking reduces context loss across longer sessions.

## Installation

For the intended workflow, keep these three pieces together:

1. Install and use [obra/superpowers](https://github.com/obra/superpowers).
2. Install and use [planning-with-files](https://github.com/othmanadi/planning-with-files).
3. Install this plugin from local source:
   ```
   /plugin marketplace add /absolute/path/to/superpowers-flow-enforcer
   /plugin install superpowers-flow-enforcer@superpowers-flow-enforcer-marketplace
   /reload-plugins
   ```

   **Alternative: Temporary loading for development/testing**
   ```
   claude --plugin-dir /absolute/path/to/superpowers-flow-enforcer
   ```
   This loads the plugin for the current session only without installation.

If you install or change other plugins during a running session, run:
   ```
   /reload-plugins
   ```

No separate `bash-traverse` clone or build is required. The parser runtime is already vendored in this repository, but the active Bash gate does require Node 18+ on the machine where Claude Code runs.

## Usage

Use the three pieces together during brainstorming, spec, planning, execution, review, and verification:

- `superpowers` provides the workflow discipline.
- `planning-with-files` keeps the durable external memory in `task_plan.md`, `findings.md`, and `progress.md`.
- This plugin enforces the handoff and no-skip rules once the session has actually entered the superpowers workflow.

The plugin does not force workflow entry on every Claude Code session. If the workflow never becomes active, workflow-only gates remain inactive and ordinary Claude Code work is not blocked by those phase checks.

Manual control is also available when you do not want to rely on path-based auto-entry. The recommended control surface in this round is:

- `开启 enforcer`
- `关闭 enforcer`
- `enable enforcer`
- `disable enforcer`

Long-form compatibility still exists for existing habits and scripts:

- `激活 superpowers enforcer`
- `关闭 superpowers enforcer`
- `activate superpowers enforcer`
- `deactivate superpowers enforcer`

`启动 enforcer`, `停止 enforcer`, `start enforcer`, and `stop enforcer` are NOT SUPPORTED in this round. Use `disable enforcer` / `关闭 enforcer` to turn enforcement off. Do not rely on `stop` to disable enforcement.

## Hook System

| Hook Event | Matcher | Enforcement |
|------------|---------|-------------|
| SessionStart | * | Initialize workflow state |
| UserPromptSubmit | * | Bypass / interrupt detection + missing-state bootstrap |
| PreToolUse | Edit\|Write | Workflow-aware write gating + TDD IRON LAW |
| PreToolUse | AskUserQuestion | Brainstorming findings update when workflow is active |
| PreToolUse | Agent | Packetized task-boundary gate + reviewer-role enforcement for superpowers execution |
| PreToolUse | Bash | Active Bash gate only when `workflow.active == true`; otherwise silent no-op |
| PostToolUse | * | Workflow state sync, including successful Agent dispatch task-flow updates |
| TaskCompleted | * | Two-stage review completion when workflow is active |
| PostToolUseFailure | Bash | Systematic debugging on test failure |
| Stop | * | Command-only completion verification from `last_assistant_message` + workflow-aware stop gate |

## TDD Enforcement (Most Critical)

The PreToolUse hook enforces the TDD IRON LAW:

```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

When writing a production file (e.g., `src/utils/helper.ts`):
1. If no corresponding test exists → BLOCKED
2. If test exists but not verified as failing → BLOCKED
3. Only when test verified failing → ALLOWED

**Test file patterns recognized**:
- `test/`, `tests/`, `spec/`, `__tests__/` directories
- `.test.` or `.spec.` in filename
- `_test.` or `_spec.` suffix

**TDD exceptions** (config files, type definitions, docs, generated files):
- Handled by the PreToolUse path allow-list rules
- Categories: config, types, docs, generated, specs, plugin

## Packetized Subagent Execution

This gate is not a global Agent ban. It is a `PreToolUse/Agent` command hook that only constrains packetized superpowers execution once the workflow and task flow are active.

Runtime Agent prompts must start with:

- `SPFE_TASK_ID=<task-id>`
- `SPFE_PACKET_ROLE=implementer|spec-reviewer|code-reviewer`

Enforced behavior:

- A new task's `implementer` packet is blocked until the current open task has both `spec_review_passed == true` and `code_review_passed == true`.
- `spec-reviewer` and `code-reviewer` are separate reviewer roles; a combined or generic reviewer packet is rejected.
- `code-reviewer` cannot start before the current task has passed spec review.
- Same-task `implementer -> fix -> re-review` loops remain allowed, so review feedback can be addressed without reopening a new task.

## Bypass Mechanism

To skip a phase, state your reason:

**English**:
- "skip brainstorming - this is a simple bug fix"
- "skip tdd - this is a config file change"
- "skip review - this is a throwaway prototype"

**Chinese**:
- "跳过 brainstorming - 这是一个简单的 bug 修复"
- "跳过测试 - 这是一个配置文件修改"
- "不需要测试 - 这是自动生成的代码"

The plugin will:
1. Record your bypass request in state
2. Ask for confirmation
3. After confirmation, allow the skip

## Interrupt Handling

When you need to pause, use explicit interrupt vocabulary:

- `stop task`
- `pause task`
- `停止任务`
- `暂停任务`

These task-interrupt commands are distinct from enforcer control. `stop` does not disable workflow enforcement.

Pause handling is text keyword based: keywords in user text are recorded into `interrupt.allowed`, and `Stop` reads that state to allow a clean stop.

## Resume Recovery

When you resume an unfinished workflow, run `/superpowers-flow-enforcer:resume-enforcer` before any new edits or Agent dispatch. The recovery handshake is part of resuming work, not an optional cleanup step.

Repo-specific recovery planning records live under `.planning-with-files/`:

- `.planning-with-files/task_plan.md`
- `.planning-with-files/progress.md`
- `.planning-with-files/findings.md`

State tracking for resumed workflows includes:

- `resume.recovery_required`
- `resume.recovery_completed_at`
- `resume.last_resume_source`

## Verification Before Completion

When claiming completion ("done", "tests pass", "fixed"):
- Must show FRESH verification evidence in the current assistant message
- Cannot use "last time passed" or "should be fine"
- The Stop hook will block without fresh evidence

## Files

```
manifest.json          # Plugin metadata
CLAUDE.md              # Plugin instructions for Claude
README.md              # English docs
README_cn.md           # Chinese docs
hooks/
└── hooks.json         # All hook configurations
scripts/
├── init-state.sh      # SessionStart state initialization
├── update-state.sh    # State update helper
├── sync-user-prompt-state.sh # UserPromptSubmit state sync
├── sync-post-tool-state.sh   # PostToolUse state sync, including Agent task-flow sync
├── check-pretool-gates.sh # PreToolUse/Edit|Write, AskUserQuestion, and Agent gate
├── check-bash-command-gate.sh # PreToolUse/Bash gate
├── check-bash-command-gate-node.cjs # Vendored bash-traverse analysis runtime
├── check-task-completed.sh # TaskCompleted gate
├── check-stop-review-gate.sh # Stop completion verification gate
└── check-exception.sh # Legacy helper script (not called by current hooks)
templates/
└── flow_state.json.tmpl # State file template
vendor/
└── bash-traverse/      # Vendored Bash parser/runtime used by the Bash gate
```

## State Tracking

State file: `$CLAUDE_PROJECT_DIR/.claude/flow_state.json`

Tracks:
- `current_phase`: init → brainstorming → planning → tdd → review → finishing
- `workflow.*`: `active`, `override`, `activated_by`, `activated_at`, `deactivated_by`, `deactivated_at`
- `brainstorming.*`: `question_asked`, `findings_updated_after_question`, `spec_written`, `spec_reviewed`, `user_approved_spec`
- `planning.*`: `plan_written`, `plan_file`, `execution_mode`
- `worktree.*`: `created`, `path`, `baseline_verified`
- `tdd.*`: `pending_failure_record`, `last_failed_command`, `test_files_created`, `production_files_written`, `tests_verified_fail`, `tests_verified_pass`
- `task_flow.*`: `active_task_id`, `active_packet_role`, `last_dispatch_at`
- `resume.*`: `recovery_required`, `recovery_completed_at`, `last_resume_source`
- `review.tasks`: per-task review status
- `finishing.*`: `invoked`
- `debugging.*`: active, fixes attempted, root cause found
- `exceptions.*`: bypass flags, user confirmed
- `interrupt.*`: allowed, reason, keywords detected

## Skills Enforced

The plugin references these superpowers skills:
- `brainstorming` - Design phase with questions → SPEC
- `writing-plans` - Implementation plan creation
- `using-git-worktrees` - Isolated workspace setup
- `test-driven-development` - Write test first, verify fails, write code
- `subagent-driven-development` - Two-stage review per task
- `requesting-code-review` - Spec + code quality review
- `verification-before-completion` - Fresh test evidence required
- `systematic-debugging` - Root cause investigation before fixes
- `finishing-a-development-branch` - Final verification and merge options

## Troubleshooting

**Hook not firing**: Run `/plugin` and check the Installed/Errors tabs, then run `/reload-plugins`.

**Blocked unexpectedly**: Check state file for current phase status. May need to complete earlier phase.

**Workflow gate not applying**: Confirm the session has actually entered the superpowers workflow, for example through a skip request, by saying a supported manual entry command such as `开启 enforcer` / `enable enforcer` or the long-form compatibility prompts `激活 superpowers enforcer` / `activate superpowers enforcer`, or by writing a canonical workflow artifact under either `docs/superpowers/specs|plans/*.md` at the root or the same canonical path inside the current project subtree.

**Resumed unfinished workflow is blocked**: Run `/superpowers-flow-enforcer:resume-enforcer` first. Until recovery clears `resume.recovery_required`, do not start new edits or Agent dispatch. Recovery planning context is read from `.planning-with-files/`.

**Bash gate says Node is required**: Install Node 18+ or make `node` available on `PATH`. The active Bash gate runs the vendored parser runtime through Node.

**Bypass not working**: Ensure you stated your reason clearly. The plugin needs confirmation.

**Test verification failing**: Run the actual test command and show output. Don't just claim "tests pass".

## License

MIT
