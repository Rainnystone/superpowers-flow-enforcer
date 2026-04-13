# Superpowers Flow Enforcer Plugin

> This plugin supplements superpowers with workflow-aware hooks. Workflow-only gates fail open until the session explicitly enters the superpowers workflow, then the hooks enforce critical phases like brainstorming, TDD, review, and verification.

## How It Works

The plugin uses Claude Code hooks to enforce workflow only after explicit workflow entry:

- **Workflow Entry**: The current implementation treats skip requests, the explicit prompt `激活 superpowers enforcer`, and canonical `docs/superpowers/specs/*.md` / `docs/superpowers/plans/*.md` writes within the current project scope as entry signals. Root-level canonical paths remain valid, subtree canonical paths such as `packages/foo/docs/superpowers/specs/*.md` also activate, and excluded trees like `.git`, `.worktrees`, `node_modules`, `vendor`, `.simulation`, and fixture/testdata do not.
- **Pre-Activation Behavior**: If the session never enters the workflow, workflow-only gates stay inactive and ordinary Claude Code work is not blocked by those phase checks.
- **Manual Control**: `激活 superpowers enforcer` turns workflow enforcement on explicitly. `关闭 superpowers enforcer` turns it off explicitly and prevents passive path-based reactivation until a new explicit workflow-intent signal appears.
- **Bash Runtime**: `PreToolUse/Bash` is command-only, silent while `workflow.active != true`, and uses the vendored `vendor/bash-traverse` runtime through Node 18+ once the workflow is active.
- **Brainstorming / Planning**: After activation, SPEC writing still requires self-review and user approval before planning can proceed.
- **TDD Phase**: Production code is blocked without a verified failing test.
- **Review Phase**: Task completion requires two-stage review (spec + code quality).
- **Verification / Stop**: Completion claims still need fresh verification evidence from the current `last_assistant_message`. The Stop hook is command-only, and state-based stop gates fail open when state is missing, unreadable, or workflow is inactive.
- **Debugging Phase**: Failed test commands still trigger debugging-state sync.

## Bypass Mechanism

If you need to skip a phase, state your reason clearly:

- "skip tdd - this is a config file change" → Plugin will ask for confirmation
- "跳过测试 - 这个文件是自动生成的" → Plugin will ask for confirmation

After confirmation, the bypass is recorded in state and hooks will allow the skip.

## Interrupt Handling

When you need to pause work, say:
- "停止" / "stop" / "pause" / "暂停" / "明天继续"

Pause handling is text keyword based: keywords in user text set `interrupt.allowed`, and the command-only `Stop` hook reads that state to allow a clean stop.

## State File

The plugin maintains state at `$CLAUDE_PROJECT_DIR/.claude/flow_state.json` tracking:
- Current workflow phase
- Workflow activation status (`workflow.active`, `workflow.override`, `workflow.activated_by`, `workflow.activated_at`, `workflow.deactivated_by`, `workflow.deactivated_at`)
- Phase completion status
- Bypass exceptions and confirmations
- Interrupt status

## Hook Types

| Hook | Purpose |
|------|---------|
| SessionStart | Initialize state file |
| UserPromptSubmit | Detect bypass / interrupt requests and self-heal missing state |
| PreToolUse (Edit\|Write) | Workflow-aware write gating + TDD enforcement |
| PreToolUse (AskUserQuestion) | Brainstorming findings gate when workflow is active |
| PreToolUse (Bash) | Active Bash gate only when `workflow.active == true`; otherwise silent no-op |
| PostToolUse (Write\|Edit) | SPEC self-review gate |
| PostToolUse (Write) | Plan → Worktree gate |
| PostToolUse (TaskCompleted) | Two-stage review completion check when workflow is active |
| PostToolUseFailure (Bash) | Trigger debugging-state sync on failed commands |
| Stop | Command-only completion verification from `last_assistant_message` + workflow-aware stop gate |

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
