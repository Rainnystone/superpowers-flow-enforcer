# Prompt Hook Contract Hardening Design

> Scope: fix the concrete causes behind Claude Code `UserPromptSubmit hook error` and `JSON validation failed` without reopening the broader workflow redesign.

## Goal

Make the plugin compatible with Claude Code's official prompt and agent hook contracts, while ensuring the `UserPromptSubmit` command hook fails open instead of crashing when `flow_state.json` is missing, corrupt, or temporarily unreadable.

## Out Of Scope

1. Do not redesign the broader workflow state model.
2. Do not add new enforced workflow phases.
3. Do not change bypass product behavior beyond what is required for compatibility and robustness.
4. Do not add `planning-with-files-zh` as a new hard dependency.

## Problem Statement

Current diagnosis shows two distinct issues:

1. All `type: "prompt"` hooks in `hooks/hooks.json` describe command-style return JSON such as:
   - `{"continue": true}`
   - `{"decision": "block"}`
   - `{"hookSpecificOutput": ...}`
2. Claude Code prompt hooks officially require:
   - allow: `{"ok": true}`
   - block: `{"ok": false, "reason": "..."}`
3. Claude Code `type: "prompt"` hooks only receive hook input JSON. Official configuration supports `$ARGUMENTS` for that input. Prompt hooks do not have tool access and should not be written as if they can read project files, state files, or transcripts directly.
4. Several current hooks are written as prompt hooks but ask the model to read:
   - the project state file
   - the transcript file
   - other repository files
5. `scripts/sync-user-prompt-state.sh` still assumes that `flow_state.json` is readable after bootstrap. If the file is corrupt or unreadable, later `jq` reads can exit non-zero under `set -euo pipefail`, which turns a state-sync helper into a hook failure.

The first issue explains the observed `JSON validation failed` symptom directly. The third and fourth issues mean that even after schema correction, some hooks would still rely on unsupported prompt-hook capabilities. The fifth issue is a separate robustness gap that can still surface as hook execution failure.

## Design Principles

### 1. Fix the actual Claude Code contract mismatch first

The plugin is for Claude Code. Official Claude Code prompt-hook and agent-hook behavior is the source of truth.

### 2. Keep behavior changes minimal

Do not reinterpret workflow policy. Only translate existing allow/block intent into the correct Claude Code prompt hook schema.

### 3. Match hook type to actual capability

If a hook decision depends only on the event input JSON, it may stay `type: "prompt"`.
If it needs to inspect files, transcripts, or repository state, it must be `type: "agent"`.

### 4. Fail open on unreadable state in command hooks

State-sync helpers should never make the user-facing hook system more fragile than the guarded workflow itself.

### 5. Preserve existing observable behavior where possible

If a hook previously meant "allow", keep it as `{"ok": true}`.
If a hook previously meant "deny/block", keep it as `{"ok": false, "reason": "..."}`

## Required Functional Changes

### A. Hook prompts must use official Claude Code input semantics

Update every model-driven hook in `hooks/hooks.json` so that:

1. the prompt text is written around `$ARGUMENTS`, or otherwise around the official hook input JSON semantics
2. no prompt or agent hook prompt text relies on unsupported placeholders such as:
   - `$USER_PROMPT`
   - `$TOOL_INPUT.file_path`
   - `$TOOL_INPUT.command`
   - `$TRANSCRIPT_PATH`
3. if a hook needs to inspect a state file or transcript file, the prompt text must explicitly tell the agent to use the paths from hook input JSON

### B. Hooks that require file access must not remain `type: "prompt"`

The following current hooks depend on project files or transcripts and therefore must be implemented as `type: "agent"` rather than `type: "prompt"`:

1. `UserPromptSubmit` gate that checks state before blocking skip requests
2. `PreToolUse` gates that read `flow_state.json`
3. `PostToolUse` gates that read `flow_state.json`
4. `Stop` gates that read state or transcript-derived artifacts beyond the raw event input

Hooks that depend only on hook input JSON may remain `type: "prompt"`, but must still follow the official prompt-hook response schema.

### C. Prompt and agent hooks must use official response schema

For every remaining `type: "prompt"` hook and every converted `type: "agent"` hook:

1. allow branches return `{"ok": true}`
2. deny/block branches return `{"ok": false, "reason": "..."}`
3. no model-driven hook response examples mention:
   - `continue`
   - `decision`
   - `systemMessage`
   - `hookSpecificOutput`

### D. Keep current gate intent, only translate response shape and hook type

Examples:

1. "allow when workflow is inactive" stays semantically identical, but now returns `{"ok": true}`
2. "block when findings.md was not updated after a brainstorming question" keeps the same reason text, but returns `{"ok": false, "reason": "..."}`
3. "block completion without fresh verification evidence" keeps the same policy, but returns `{"ok": false, "reason": "..."}`
4. hooks that formerly pretended to read files as prompt hooks keep the same policy intent, but become agent hooks so the implementation matches Claude Code's actual capability model

### E. Harden `sync-user-prompt-state.sh`

After bootstrap, before reading fields from the state file:

1. verify that the file exists and parses as JSON
2. if not, exit 0 without blocking and without emitting non-JSON stdout
3. suppress non-essential parse noise from helper `jq` reads

Required behavior:

1. malformed or truncated state file must not crash the hook
2. hook stdout on the fail-open path must be empty or valid command-hook JSON, never malformed output
3. for the fail-open path, the script may skip state mutation entirely, but must not block the session
4. this command hook must not be rewritten to use prompt-hook `ok/reason` schema

## Testing Requirements

### Static hook contract coverage

Add or update a regression test that asserts:

1. every remaining `type: "prompt"` hook and every `type: "agent"` hook in `hooks/hooks.json` uses `ok`
2. no model-driven hook still references command-style response keys as its required output shape
3. no model-driven hook prompt text still relies on unsupported pseudo-placeholders instead of `$ARGUMENTS` and official hook input semantics
4. hooks that require file or transcript access are no longer declared as `type: "prompt"`

### Command hook robustness coverage

Add or update a regression test that proves:

1. `sync-user-prompt-state.sh` exits 0 when `flow_state.json` is malformed
2. the script does not emit invalid stdout in that case
3. no stderr noise is required for the success path

### Non-regression coverage

Keep the existing bypass and interrupt behavior coverage intact for valid state files.

## Acceptance Criteria

This work is complete only if all of the following are true:

1. `hooks/hooks.json` contains no prompt hook examples using command-style response schema.
2. all model-driven hooks express allow/block decisions via `ok` and `reason`.
3. hooks that need file or transcript inspection no longer remain `type: "prompt"`.
4. `sync-user-prompt-state.sh` no longer crashes on malformed state during normal hook execution.
5. updated regression tests pass locally.
6. no unrelated workflow redesign is introduced.
