# Prompt Hook Contract Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align Claude Code model-driven hooks with official prompt/agent contracts and make `sync-user-prompt-state.sh` fail open on malformed state instead of crashing.

**Architecture:** Keep the fix narrow. Update `hooks/hooks.json` so each model-driven hook uses the correct hook type and official `ok/reason` response schema, using `$ARGUMENTS` instead of pseudo-placeholders. Separately, harden the `UserPromptSubmit` command hook so corrupt state cannot turn state sync into a hook error.

**Tech Stack:** Claude Code plugin hooks JSON, Bash, `jq`, shell regression tests

---

## AGENTS Task-Splitting Rules

This plan follows `AGENTS.md`:

1. each task owns one primary behavior change
2. each task has one main verification path
3. tasks run serially because they share the same plugin contract surface
4. no task should widen into unrelated workflow redesign

## File Structure

### Files to modify

- `hooks/hooks.json`
- `scripts/sync-user-prompt-state.sh`
- `tests/test_hooks_official_events.sh`
- `tests/test_bypass_state.sh`

### Responsibility map

- `hooks/hooks.json`: model-driven hook type selection, official prompt text semantics, `ok/reason` response contract
- `scripts/sync-user-prompt-state.sh`: command-hook state bootstrap and malformed-state fail-open behavior
- `tests/test_hooks_official_events.sh`: static regression for hook contract semantics
- `tests/test_bypass_state.sh`: bypass behavior plus malformed-state resilience

## Task 1: Harden Model-Driven Hook Contract

**User-facing goal:** Claude Code should no longer see invalid model-hook schema or unsupported prompt-hook pseudo-placeholders.

**Files:**
- Modify: `tests/test_hooks_official_events.sh`
- Modify: `hooks/hooks.json`

- [ ] **Step 1: Write the failing static regression**

Extend `tests/test_hooks_official_events.sh` so it fails on the current contract mismatch.

Add assertions that:

```bash
jq -e '
  [
    .. | objects
    | select(.type? == "prompt" or .type? == "agent")
    | .prompt
  ] as $prompts
  | ($prompts | length) > 0
  and all($prompts[]; contains("{\"ok\": true}") or contains("{\"ok\": false"))
' hooks/hooks.json >/dev/null
```

And add string-level assertions that:

```python
unsupported = [
    '$USER_PROMPT',
    '$TOOL_INPUT.file_path',
    '$TOOL_INPUT.command',
    '$TRANSCRIPT_PATH',
]
```

Plus type-shape assertions that:

1. hooks that read state/transcript are no longer `type: "prompt"`
2. hooks that remain `type: "prompt"` only rely on `$ARGUMENTS`
3. model-driven hook prompts no longer instruct the model to return `continue`, `decision`, `systemMessage`, or `hookSpecificOutput`
4. hooks converted to `type: "agent"` explicitly instruct the agent to inspect the relevant state/transcript path from the hook input JSON in `$ARGUMENTS`

- [ ] **Step 2: Run the regression to verify RED**

Run: `bash tests/test_hooks_official_events.sh`
Expected: FAIL because current hooks still use command-style schema and pseudo-placeholders

- [ ] **Step 3: Make the minimal hook contract change**

Update `hooks/hooks.json` with these exact rules:

1. keep only input-only checks as `type: "prompt"`
2. convert state/transcript-dependent checks to `type: "agent"`
3. rewrite model prompts around `$ARGUMENTS`
4. make every model prompt explicitly require:

```json
{"ok": true}
```

or

```json
{"ok": false, "reason": "explanation"}
```

Implementation target:

1. `UserPromptSubmit` gate becomes `type: "agent"`
2. `PreToolUse` state-reading gates become `type: "agent"`
3. `PostToolUse` state-reading gates become `type: "agent"`
4. the two current `Stop` gates become `type: "agent"` because both currently depend on state and/or transcript-backed checks instead of raw event input alone
5. the simple `PreToolUse` Bash command-inspection gate may remain `type: "prompt"` if it only uses `$ARGUMENTS`

For every converted agent hook prompt, state the decision method explicitly:

1. parse the event input from `$ARGUMENTS`
2. derive the state or transcript path from that JSON
3. read the referenced file before making the `ok/reason` decision

- [ ] **Step 4: Run the regression to verify GREEN**

Run: `bash tests/test_hooks_official_events.sh`
Expected: PASS

- [ ] **Step 5: Run adjacent non-regression checks**

Run: `bash tests/test_interrupt_state.sh`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add hooks/hooks.json tests/test_hooks_official_events.sh
git commit -m "fix: align Claude model-driven hook contracts"
```

## Task 2: Make UserPromptSubmit State Sync Fail Open

**User-facing goal:** a malformed `flow_state.json` should not produce a hook error during `UserPromptSubmit`.

**Files:**
- Modify: `tests/test_bypass_state.sh`
- Modify: `scripts/sync-user-prompt-state.sh`

- [ ] **Step 1: Write the failing malformed-state regression**

Extend `tests/test_bypass_state.sh` with a case like:

```bash
BROKEN_PROJECT="$TMP_DIR/project-broken"
mkdir -p "$BROKEN_PROJECT/.claude"
printf '{\"state_version\":2,' > "$BROKEN_PROJECT/.claude/flow_state.json"

OUTPUT="$(
  printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"skip planning"}' "$BROKEN_PROJECT" \
    | bash scripts/sync-user-prompt-state.sh
)"
STATUS=$?

[ "$STATUS" -eq 0 ] || {
  echo "Expected exit 0 on malformed state" >&2
  exit 1
}

[ -z "$OUTPUT" ] || printf '%s' "$OUTPUT" | jq empty >/dev/null 2>&1 || {
  echo "Expected empty stdout or valid JSON" >&2
  exit 1
}
```

Keep the existing valid-state bypass assertions unchanged.

- [ ] **Step 2: Run the regression to verify RED**

Run: `bash tests/test_bypass_state.sh`
Expected: FAIL because current script exits non-zero on malformed state after bootstrap

- [ ] **Step 3: Write the minimal hardening**

In `scripts/sync-user-prompt-state.sh`:

1. after `bootstrap_state_if_missing`, re-check that `STATE_FILE` exists and parses
2. if parsing fails, exit 0 immediately
3. ensure all subsequent direct `jq` reads that are only advisory are stderr-suppressed or guarded

Minimal shape:

```bash
state_is_readable() {
  [ -f "$STATE_FILE" ] && jq empty "$STATE_FILE" >/dev/null 2>&1
}

bootstrap_state_if_missing

if ! state_is_readable; then
  exit 0
fi
```

- [ ] **Step 4: Run the regression to verify GREEN**

Run: `bash tests/test_bypass_state.sh`
Expected: PASS

- [ ] **Step 5: Re-run adjacent behavior checks**

Run: `bash tests/test_interrupt_state.sh`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add scripts/sync-user-prompt-state.sh tests/test_bypass_state.sh
git commit -m "fix: fail open on malformed user prompt state"
```

## Task 3: Final Verification

**User-facing goal:** the narrow fix works end-to-end and does not reopen unrelated regressions.

**Files:**
- Modify: none unless verification exposes a real defect

- [ ] **Step 1: Run targeted regression pack**

Run: `bash tests/test_hooks_official_events.sh`
Expected: PASS

Run: `bash tests/test_bypass_state.sh`
Expected: PASS

Run: `bash tests/test_interrupt_state.sh`
Expected: PASS

- [ ] **Step 2: Run broader smoke coverage**

Run: `bash tests/test_init_state.sh`
Expected: PASS

Run: `bash tests/test_workflow_activation.sh`
Expected: PASS

- [ ] **Step 3: If all green, commit only if verification forced follow-up fixes**

If no new code changes were needed, do not create an extra commit.

## Review Handoff Notes

Spec reviewers and code reviewers should evaluate against:

1. `docs/superpowers/specs/2026-04-11-prompt-hook-schema-hardening-design.md`
2. the explicit out-of-scope rule that broader workflow redesign is not part of this fix
3. the requirement that command hooks and model-driven hooks keep distinct output contracts
