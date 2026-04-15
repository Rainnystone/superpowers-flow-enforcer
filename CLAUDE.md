# Superpowers Flow Enforcer Plugin

> This plugin supplements superpowers with workflow-aware hooks. Workflow-only gates fail open until the session explicitly enters the superpowers workflow, then the hooks enforce critical phases like brainstorming, TDD, review, and verification.

## How It Works

The plugin uses Claude Code hooks to enforce workflow only after explicit workflow entry:

- **Workflow Entry**: The current implementation treats skip requests, the recommended short commands `开启 enforcer` / `enable enforcer`, the long-form compatibility prompts `激活 superpowers enforcer` / `activate superpowers enforcer`, and canonical `docs/superpowers/specs/*.md` / `docs/superpowers/plans/*.md` writes within the current project scope as entry signals. Root-level canonical paths remain valid, subtree canonical paths such as `packages/foo/docs/superpowers/specs/*.md` also activate, and excluded trees like `.git`, `.worktrees`, `node_modules`, `vendor`, `.simulation`, and fixture/testdata do not.
- **Pre-Activation Behavior**: If the session never enters the workflow, workflow-only gates stay inactive and ordinary Claude Code work is not blocked by those phase checks.
- **Manual Control**: Prefer `开启 enforcer` / `enable enforcer` to turn workflow enforcement on and `关闭 enforcer` / `disable enforcer` to turn it off. Long-form compatibility still exists for `激活 superpowers enforcer` / `activate superpowers enforcer` and `关闭 superpowers enforcer` / `deactivate superpowers enforcer`. `启动 enforcer`, `停止 enforcer`, `start enforcer`, and `stop enforcer` are not the recommended control surface in this round, and `stop` must not be interpreted as disabling enforcement.
- **Bash Runtime**: `PreToolUse/Bash` is command-only, silent while `workflow.active != true`, and uses the vendored `vendor/bash-traverse` runtime through Node 18+ once the workflow is active.
- **Brainstorming / Planning**: After activation, SPEC writing still requires self-review and user approval before planning can proceed.
- **Resume Recovery**: On resumed unfinished workflows, run `/superpowers-flow-enforcer:resume-enforcer` before any new edits or Agent dispatch. Recovery planning context lives under `.planning-with-files/`, and state tracking includes `resume.recovery_required`, `resume.recovery_completed_at`, and `resume.last_resume_source`.
- **TDD Phase**: Production code is blocked without a verified failing test.
- **Review Phase**: Task completion requires two-stage review (spec + code quality), and packetized Agent dispatch cannot start the next task's implementer before the current open task has passed both review stages.
- **Verification / Stop**: Completion claims still need fresh verification evidence from the current `last_assistant_message`. The Stop hook is command-only, and state-based stop gates fail open when state is missing, unreadable, or workflow is inactive.
- **Debugging Phase**: Failed test commands still trigger debugging-state sync.

## Bypass Mechanism

If you need to skip a phase, state your reason clearly:

- "skip tdd - this is a config file change" → Plugin will ask for confirmation
- "跳过测试 - 这个文件是自动生成的" → Plugin will ask for confirmation

After confirmation, the bypass is recorded in state and hooks will allow the skip.

## Interrupt Handling

When you need to pause work, say:
- `stop task` / `pause task` / `停止任务` / `暂停任务`

Pause handling is text keyword based: keywords in user text set `interrupt.allowed`, and the command-only `Stop` hook reads that state to allow a clean stop. These interrupt phrases are separate from enforcer control; `stop` does not disable enforcement.

## State File

The plugin maintains state at `$CLAUDE_PROJECT_DIR/.claude/flow_state.json` tracking:
- Current workflow phase
- Workflow activation status (`workflow.active`, `workflow.override`, `workflow.activated_by`, `workflow.activated_at`, `workflow.deactivated_by`, `workflow.deactivated_at`)
- Phase completion status
- Active packetized task boundary state (`task_flow.active_task_id`, `task_flow.active_packet_role`, `task_flow.last_dispatch_at`)
- Bypass exceptions and confirmations
- Interrupt status

## Hook Types

| Hook | Purpose |
|------|---------|
| SessionStart | Initialize state file |
| UserPromptSubmit | Detect bypass / interrupt requests and self-heal missing state |
| PreToolUse (Edit\|Write) | Workflow-aware write gating + TDD enforcement |
| PreToolUse (AskUserQuestion) | Brainstorming findings gate when workflow is active |
| PreToolUse (Agent) | Packetized task-boundary gate + reviewer-role enforcement during superpowers execution |
| PreToolUse (Bash) | Active Bash gate only when `workflow.active == true`; otherwise silent no-op |
| PostToolUse (*) | Workflow state sync, including successful Agent dispatch task-flow updates |
| TaskCompleted (*) | Two-stage review completion check when workflow is active |
| PostToolUseFailure (Bash) | Trigger debugging-state sync on failed commands |
| Stop | Command-only completion verification from `last_assistant_message` + workflow-aware stop gate |

## Packetized Subagent Execution

Runtime packet dispatch must follow this prefix contract in Agent prompts:

- Implementer packets must include `SPFE_TASK_ID=<task-id>` and `SPFE_PACKET_ROLE=implementer` on the first two lines.
- Spec review packets must use `SPFE_PACKET_ROLE=spec-reviewer`.
- Code quality review packets must use `SPFE_PACKET_ROLE=code-reviewer`.
- This is a `PreToolUse/Agent` command hook for packetized superpowers execution, not a global Agent ban.
- The next task's implementer packet must not start until the current open task has both `spec_review_passed == true` and `code_review_passed == true`.
- Same-task fix and re-review loops are expected: failed spec or code review should be followed by implementer fixes on the same `SPFE_TASK_ID`, then re-dispatch of the required reviewer role.

## Skills Referenced

This plugin enforces workflow from these superpowers skills:
- `superpowers:brainstorming`
- `superpowers:writing-plans`
- `superpowers:using-git-worktrees`
- `superpowers:test-driven-development`
- `superpowers:subagent-driven-development`
- `superpowers:requesting-code-review`
- `superpowers:verification-before-completion`
- `superpowers:systematic-debugging`
- `superpowers:finishing-a-development-branch`
