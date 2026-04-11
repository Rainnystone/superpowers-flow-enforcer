# Superpowers Flow Enforcer

English | [中文](./README_cn.md)

A Claude Code plugin that acts as a supplement to [obra/superpowers](https://github.com/obra/superpowers) by enforcing workflow-aware hooks after a session explicitly enters the superpowers workflow. It is not a replacement, and this repo is designed to be used together with [planning-with-files](https://github.com/othmanadi/planning-with-files) for external memory.

## Overview

**Core Principle**: Don't skip steps during execution.

The plugin implements workflow-aware hooks that enforce:
- Workflow-only gates fail open until the session explicitly enters the superpowers workflow
- Brainstorming → SPEC → Planning → TDD → Review → Verification → Finishing workflow
- Two-stage code review (spec compliance + code quality)
- Fresh verification evidence before completion claims
- Systematic debugging methodology on test failures

Workflow entry is explicit, not inferred from every Claude Code session. In the current implementation, entry happens when the session records a skip request or writes canonical superpowers artifacts under `docs/superpowers/specs/*.md` or `docs/superpowers/plans/*.md`. Those artifact paths are recognized in repo-relative, `./...`, and project-root absolute forms.

`planning-with-files` provides the persistent external memory for this setup through `task_plan.md`, `findings.md`, and `progress.md`. This is especially useful in Claude Code setups that route to GLM-5 with a 128K context window, where disk-backed tracking helps keep long-running work aligned across sessions.

## Installation

Install in this order:

1. Install and use [obra/superpowers](https://github.com/obra/superpowers) first.
   ```
   /plugin install superpowers@claude-plugins-official
   ```
   If you use the community marketplace variant:
   ```
   /plugin marketplace add obra/superpowers-marketplace
   /plugin install superpowers@superpowers-marketplace
   ```
2. Install and use [planning-with-files](https://github.com/othmanadi/planning-with-files) next so the project has `task_plan.md`, `findings.md`, and `progress.md` as persistent memory.
   ```
   /plugin marketplace add OthmanAdi/planning-with-files
   /plugin install planning-with-files@planning-with-files
   ```
3. Install this plugin from local source (persistent installation):
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

4. If you install or change other plugins during a running session, run:
   ```
   /reload-plugins
   ```

The order matters: superpowers first, planning-with-files second, then this plugin.

## Usage

Use the three pieces together during brainstorming, spec, planning, and execution:

- `superpowers` drives the workflow and phase discipline.
- `planning-with-files` records the durable project state in `task_plan.md`, `findings.md`, and `progress.md`.
- This plugin enforces the handoff so you do not skip brainstorming, planning, review, or verification once the session has actually entered the superpowers workflow.

In practice, you start with superpowers for brainstorming and spec work, write the plan into planning-with-files, then keep updating `progress.md` while execution continues. If the user never enters the superpowers workflow, workflow-only gates stay inactive and ordinary Claude Code work is not blocked by those phase checks.

## Hook System

| Hook Event | Matcher | Enforcement |
|------------|---------|-------------|
| SessionStart | * | Initialize workflow state |
| UserPromptSubmit | * | Bypass / interrupt detection + missing-state bootstrap |
| PreToolUse | Edit\|Write | Workflow-aware write gating + TDD IRON LAW |
| PreToolUse | AskUserQuestion | Brainstorming findings update when workflow is active |
| PostToolUse | Write\|Edit | SPEC self-review required |
| PostToolUse | Write | Plan → Worktree transition |
| PostToolUse | Bash | Worktree → Baseline tests |
| PostToolUse | TaskCompleted | Two-stage review completion when workflow is active |
| PostToolUseFailure | Bash | Systematic debugging on test failure |
| Stop | * | Transcript-based completion verification + workflow-aware stop gate |

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

Pause handling is text keyword based: keywords in user text are recorded into `interrupt.allowed`, and `Stop` reads that state to allow a clean stop.

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
└── check-exception.sh # Legacy helper script (not called by current hooks)
templates/
└── flow_state.json.tmpl # State file template
```

## State Tracking

State file: `$CLAUDE_PROJECT_DIR/.claude/flow_state.json`

Tracks:
- `current_phase`: init → brainstorming → planning → tdd → review → finishing
- `workflow.*`: `active`, `activated_by`, `activated_at`
- `brainstorming.*`: `question_asked`, `findings_updated_after_question`, `spec_written`, `spec_reviewed`, `user_approved_spec`
- `planning.*`: `plan_written`, `plan_file`, `execution_mode`
- `worktree.*`: `created`, `path`, `baseline_verified`
- `tdd.*`: `pending_failure_record`, `last_failed_command`, `test_files_created`, `production_files_written`, `tests_verified_fail`, `tests_verified_pass`
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

**Workflow gate not applying**: Confirm the session has actually entered the superpowers workflow, for example through a skip request or by writing `docs/superpowers/specs/*.md` / `docs/superpowers/plans/*.md`.

**Bypass not working**: Ensure you stated your reason clearly. The plugin needs confirmation.

**Test verification failing**: Run the actual test command and show output. Don't just claim "tests pass".

## License

MIT
