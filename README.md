# Superpowers Flow Enforcer

English | [中文](./README_cn.md)

A Claude Code Plugin that enforces the superpowers workflow through hooks, preventing you from skipping critical development phases.

## Overview

**Core Principle**: Don't skip steps during execution.

The plugin implements hard blocking hooks that enforce:
- Brainstorming → SPEC → Planning → TDD → Review → Verification → Finishing workflow
- Two-stage code review (spec compliance + code quality)
- Fresh verification evidence before completion claims
- Systematic debugging methodology on test failures

## Installation

1. Copy this repository's files into your Claude plugins folder:
   ```
   ~/.claude/plugins/superpowers-flow-enforcer/
   ```

2. Restart Claude Code to load the plugin.

## Hook System

| Hook Event | Matcher | Enforcement |
|------------|---------|-------------|
| SessionStart | * | Initialize workflow state |
| UserPromptSubmit | * | Bypass request detection |
| PreToolUse | Edit\|Write | TDD IRON LAW - no production code without failing test |
| PostToolUse | AskUserQuestion | Brainstorming findings update |
| PostToolUse | Write\|Edit | SPEC self-review required |
| PostToolUse | Write | Plan → Worktree transition |
| PostToolUse | Bash | Worktree → Baseline tests |
| PostToolUse | TaskUpdate | Two-stage review completion |
| PostToolUse | Bash | Systematic debugging on test failure |
| Stop | * | Verification before completion + Interrupt handling |

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
- Checked automatically via `check-exception.sh`
- Categories: config, types, docs, generated, specs, plugin

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

When you need to pause:

**English**: "stop", "pause", "break"

**Chinese**: "停止", "暂停", "暂停一下", "休息一下", "明天继续", "稍后继续"

The plugin records the interrupt and allows clean stop.

## Verification Before Completion

When claiming completion ("done", "tests pass", "fixed"):
- Must show FRESH verification evidence (test output in current message)
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
├── sync-post-tool-state.sh   # PostToolUse state sync
└── check-exception.sh # TDD exception detection
templates/
└── flow_state.json.tmpl # State file template
```

## State Tracking

State file: `$CLAUDE_PROJECT_DIR/.claude/flow_state.json`

Tracks:
- `current_phase`: init → brainstorming → planning → tdd → review → finishing
- `brainstorming.*`: skill invoked, findings updated, spec written/approved
- `planning.*`: plan written, execution mode
- `worktree.*`: created, baseline tests passed
- `tdd.*`: test files, production files, verified failing tests
- `review.tasks`: per-task review status
- `finishing.*`: tests verified, choice made
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

**Hook not firing**: Check that the plugin is installed in `~/.claude/plugins/`.

**Blocked unexpectedly**: Check state file for current phase status. May need to complete earlier phase.

**Bypass not working**: Ensure you stated your reason clearly. The plugin needs confirmation.

**Test verification failing**: Run the actual test command and show output. Don't just claim "tests pass".

## License

MIT
