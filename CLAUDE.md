# Superpowers Flow Enforcer Plugin

> This plugin enforces the superpowers workflow through hooks, preventing you from skipping critical phases like brainstorming, TDD, review, and verification.

## How It Works

The plugin uses Claude Code hooks to block operations that would skip required workflow steps:

- **Brainstorming Phase**: Blocks SPEC writing without self-review and user approval
- **Planning Phase**: Requires worktree creation before TDD starts
- **TDD Phase**: Blocks production code without verified failing test (IRON LAW)
- **Review Phase**: Requires two-stage review (spec + code quality) before task completion
- **Verification Phase**: Blocks completion claims without fresh test evidence
- **Debugging Phase**: Requires systematic debugging on test failures

## Bypass Mechanism

If you need to skip a phase, state your reason clearly:

- "skip tdd - this is a config file change" → Plugin will ask for confirmation
- "跳过测试 - 这个文件是自动生成的" → Plugin will ask for confirmation

After confirmation, the bypass is recorded in state and hooks will allow the skip.

## Interrupt Handling

When you need to pause work, say:
- "停止" / "stop" / "pause" / "暂停" / "明天继续"

The plugin records the interrupt in state and allows you to stop cleanly.

## State File

The plugin maintains state at `$CLAUDE_PROJECT_DIR/.claude/flow_state.json` tracking:
- Current workflow phase
- Phase completion status
- Bypass exceptions and confirmations
- Interrupt status

## Hook Types

| Hook | Purpose |
|------|---------|
| SessionStart | Initialize state file |
| UserPromptSubmit | Detect bypass requests |
| PreToolUse (Edit|Write) | TDD enforcement - most critical |
| PostToolUse | Phase transition checks |
| Stop | Verification before completion |

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