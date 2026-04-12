# Activation-Scoped Bash Traverse Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> This plan supersedes the Bash portion of `2026-04-12-bash-stop-command-hardening-implementation.md`. In substance, it rewrites the old Task 1 around `bash-traverse`, while carrying forward the same `Stop` command-only objective and the same final verification intent from the previous Task 2 / Task 3.

**Goal:** Make `PreToolUse:Bash` stable and activation-scoped with vendored `bash-traverse`, make `Stop` command-only, and keep inactive non-superpower usage free of user-visible workflow enforcement.

**Architecture:** Keep the plugin single-install. `PreToolUse:Bash` stays a Bash entrypoint, but after resolving project state it hands active-workflow Bash analysis to a vendored Node helper backed by `bash-traverse`. `Stop` becomes command-only and preserves the same inactive no-op boundary. Vendored parser build artifacts ship inside this repo so users do not need a second install/build step.

**Tech Stack:** Claude Code plugin hooks JSON, Bash, `jq`, Node.js runtime, vendored `bash-traverse` build artifacts, shell regression tests

---

## AGENTS Task-Splitting Rules

This plan follows `AGENTS.md`:

1. tasks are serial because they share `hooks/hooks.json` and the Bash gate test surface
2. each task has one primary goal and one main verification path
3. the default packet is one TDD loop plus one review/fix loop
4. no task widens into full hook-architecture redesign

## File Structure

### Files to modify

- `hooks/hooks.json`
- `scripts/check-bash-command-gate.sh`
- `scripts/check-stop-review-gate.sh`
- `tests/test_hooks_official_events.sh`
- `tests/test_bash_command_gate.sh`
- `tests/test_stop_gates.sh`
- `README.md`
- `README_cn.md`
- `CLAUDE.md`

### Files to create

- `scripts/check-bash-command-gate-node.cjs`
- `vendor/bash-traverse/dist/` (vendored runtime artifacts from pinned upstream build)
- `vendor/bash-traverse/LICENSE`
- `vendor/bash-traverse/upstream.json`

### Responsibility map

- `hooks/hooks.json`: final event inventory and hook wiring
- `scripts/check-bash-command-gate.sh`: Bash hook entrypoint, state resolution, inactive no-op boundary, runtime guard
- `scripts/check-bash-command-gate-node.cjs`: parser-backed active Bash policy logic
- `vendor/bash-traverse/dist/`: vendored parser runtime
- `vendor/bash-traverse/upstream.json`: pinned upstream version / commit metadata
- `scripts/check-stop-review-gate.sh`: final command-only Stop gate
- `tests/test_bash_command_gate.sh`: focused Bash gate regression
- `tests/test_stop_gates.sh`: focused Stop regression
- `tests/test_hooks_official_events.sh`: static wiring/contract checks
- `README.md` / `README_cn.md` / `CLAUDE.md`: runtime prerequisite and packaging behavior documentation

## Task 1: Activation Boundary And Vendored Runtime Scaffold

**User-facing goal:** Installing the plugin still feels like installing one plugin, not two. `PreToolUse:Bash` becomes silent while `workflow.active != true`, and active Bash enforcement has a deterministic runtime guard instead of hook noise.

**Files:**
- Modify: `hooks/hooks.json`
- Create: `scripts/check-bash-command-gate-node.cjs`
- Modify: `scripts/check-bash-command-gate.sh`
- Create: `vendor/bash-traverse/dist/`
- Create: `vendor/bash-traverse/LICENSE`
- Create: `vendor/bash-traverse/upstream.json`
- Modify: `tests/test_hooks_official_events.sh`
- Modify: `tests/test_bash_command_gate.sh`

- [ ] **Step 1: Write the failing static and runtime tests**

In `tests/test_hooks_official_events.sh`, add or rewrite assertions so they fail unless:

```python
assert ('PreToolUse', 'Bash', 'command') in inventory
assert ('PreToolUse', 'Bash', 'prompt') not in inventory
```

In `tests/test_bash_command_gate.sh`, add failing cases for:

1. inactive workflow returns empty output for `.claude/flow_state.json` Bash commands
2. active workflow with Node missing returns deterministic deny JSON with guidance
3. active workflow with vendored runtime present can enter the Node helper path without malformed JSON
4. existing but recoverable corrupt `flow_state.json` is normalized/reset via the existing path and then silent-allows because workflow remains inactive
5. active workflow with a still-unreadable/corrupt `flow_state.json` returns deterministic deny JSON with guidance instead of fail-open or malformed output
6. unresolved/non-project root returns silent allow, reinforcing the inactive/non-project boundary
7. inactive `.claude/` directory without a state file remains silent allow and does not create a new state file
8. active ordinary Bash commands that do not touch `.claude/flow_state.json` are not denied merely because the current parser runtime cannot parse a valid syntax form (for example `if true; then echo ok; fi` or `cat <<< "hi"`)

Example inactive case:

```bash
OUTPUT="$(
  jq -n --arg cwd "$PROJECT" --arg cmd 'cat .claude/flow_state.json' '{
    hook_event_name:"PreToolUse",
    tool_name:"Bash",
    cwd:$cwd,
    tool_input:{command:$cmd}
  }' | bash scripts/check-bash-command-gate.sh
)"
[ -z "$OUTPUT" ]
```

Example missing-Node case:

```bash
OUTPUT="$(
  jq -n --arg cwd "$PROJECT" --arg cmd 'cat .claude/flow_state.json' '{
    hook_event_name:"PreToolUse",
    tool_name:"Bash",
    cwd:$cwd,
    tool_input:{command:$cmd}
  }' | BASH_GATE_NODE_BIN='/nonexistent/node' bash scripts/check-bash-command-gate.sh
)"
assert_json_equals <(printf '%s' "$OUTPUT") '.hookSpecificOutput.permissionDecision' '"deny"'
```

- [ ] **Step 2: Run tests to verify RED**

Run:

```bash
bash tests/test_hooks_official_events.sh
bash tests/test_bash_command_gate.sh
```

Expected:

1. current Bash gate behavior does not yet honor the inactive boundary
2. current implementation has no vendored parser helper/runtime guard path

- [ ] **Step 3: Write the minimal implementation**

1. vendor the required `bash-traverse` build artifacts under `vendor/bash-traverse/dist/`
2. add `vendor/bash-traverse/LICENSE`
3. add `vendor/bash-traverse/upstream.json` containing:

```json
{
  "name": "bash-traverse",
  "source": "https://github.com/davidcoleman007/bash-traverse",
  "version": "0.6.0",
  "commit": "<pin-this-exactly-during-implementation>"
}
```

4. create `scripts/check-bash-command-gate-node.cjs` with a callable interface such as:

```js
const fs = require('fs');
const path = require('path');
const { parse, traverse } = require('../vendor/bash-traverse/dist/index.js');

function main() {
  const payload = JSON.parse(fs.readFileSync(0, 'utf8'));
  const state = JSON.parse(process.env.BASH_GATE_STATE_JSON);
  const command = payload.tool_input.command;
  // return JSON to stdout only on deny
}

main();
```

5. update `scripts/check-bash-command-gate.sh` so it:
   - resolves project/state root robustly
   - does not create/bootstrap a brand-new state file from the Bash gate when no state file exists
   - reuses the existing initialization/normalization path once only when a state file already exists and may be recoverable
   - returns silent allow when `workflow.active != true`
   - returns silent allow when no project root / no state root can be resolved
   - after bootstrap / normalization, returns deterministic deny JSON with guidance if state still exists but remains unreadable/corrupt
   - respects `BASH_GATE_NODE_BIN` override for tests
   - returns deterministic deny JSON if active and Node is unavailable
   - invokes `scripts/check-bash-command-gate-node.cjs` only after the above checks pass
   - does not turn parser unsupported-syntax failures into blanket denies for unrelated active Bash commands

6. keep `hooks/hooks.json` pointing `PreToolUse/Bash` at:

```json
{
  "type": "command",
  "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-bash-command-gate.sh"
}
```

- [ ] **Step 4: Run tests to verify GREEN**

Run:

```bash
bash tests/test_hooks_official_events.sh
bash tests/test_bash_command_gate.sh
```

Expected: PASS

- [ ] **Step 5: Run adjacent non-regression**

Run:

```bash
bash tests/test_workflow_activation.sh
bash tests/test_pretool_command_gates.sh
```

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add hooks/hooks.json scripts/check-bash-command-gate.sh scripts/check-bash-command-gate-node.cjs vendor/bash-traverse tests/test_hooks_official_events.sh tests/test_bash_command_gate.sh
git commit -m "fix: add activation-scoped bash parser scaffold"
```

## Task 2: Parser-Backed Active Bash Enforcement

**User-facing goal:** Once superpower workflow is active, `PreToolUse:Bash` enforces the private-state rule through parser-backed structural analysis instead of brittle string matching.

**Files:**
- Modify: `scripts/check-bash-command-gate-node.cjs`
- Modify: `tests/test_bash_command_gate.sh`

- [ ] **Step 1: Write the failing parser-coverage tests**

Extend `tests/test_bash_command_gate.sh` with active-workflow cases that currently fail unless parser-backed handling is implemented:

1. `cat .claude/flow_state.json`
2. `echo ok && cat .claude/flow_state.json`
3. multi-line `echo ok` followed by `cat .claude/flow_state.json`
4. `[ -f .claude/flow_state.json ]`
5. `[[ -f .claude/flow_state.json ]]`
6. `echo $(cat .claude/flow_state.json)`
7. `bash -lc 'cat .claude/flow_state.json'`
8. `python3 -c 'open(".claude/flow_state.json").read()'`
9. `node -e 'require("fs").readFileSync(".claude/flow_state.json","utf8")'`

Also keep a clear allow case:

1. straightforward approved helper invocation
2. valid active-workflow Bash that does not touch `.claude/flow_state.json` must continue to allow even if parser coverage for that syntax lands later

Example assertion:

```bash
assert_json_equals <(printf '%s' "$OUTPUT") '.hookSpecificOutput.permissionDecision' '"deny"'
```

- [ ] **Step 2: Run tests to verify RED**

Run:

```bash
bash tests/test_bash_command_gate.sh
```

Expected: FAIL on at least wrapper / substitution / test-expression / inline-interpreter cases

- [ ] **Step 3: Write the minimal implementation**

In `scripts/check-bash-command-gate-node.cjs`:

1. parse the active Bash command with vendored `bash-traverse`
2. walk the AST to detect protected-path use in:
   - plain command arguments
   - `Pipeline` command lists
   - `CommandSubstitution`
   - `TestExpression`
3. explicitly recurse into shell wrappers:
   - `bash -c`
   - `bash -lc`
   - `sh -c`
   - `zsh -c`
4. add narrow deterministic fallback checks for inline-eval interpreter wrappers:
   - `python -c`
   - `python3 -c`
   - `node -e`
   - `ruby -e`
   - `perl -e`
5. keep policy conservative:
   - direct helper invocation allowed
   - helper plus extra direct protected-path handling denied
   - active protected-path access denied

Suggested internal shape:

```js
function analyzeShellSource(source) { /* parse + traverse */ }
function analyzeCommandNode(node) { /* command name + args */ }
function analyzeShellWrapper(name, args) { /* recursive parse */ }
function analyzeInterpreterWrapper(name, args) { /* conservative string check */ }
```

- [ ] **Step 4: Run tests to verify GREEN**

Run:

```bash
bash tests/test_bash_command_gate.sh
```

Expected: PASS

- [ ] **Step 5: Run adjacent non-regression**

Run:

```bash
bash tests/test_hooks_official_events.sh
bash tests/test_pretool_command_gates.sh
```

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add scripts/check-bash-command-gate-node.cjs tests/test_bash_command_gate.sh
git commit -m "fix: enforce active bash gate with vendored parser"
```

## Task 3: Collapse Stop To Command-Only

**User-facing goal:** `Stop` no longer depends on prompt output stability and stays silent outside active workflow.

**Files:**
- Modify: `hooks/hooks.json`
- Modify: `scripts/check-stop-review-gate.sh`
- Modify: `tests/test_hooks_official_events.sh`
- Modify: `tests/test_stop_gates.sh`

- [ ] **Step 1: Write the failing tests**

In `tests/test_hooks_official_events.sh`, add assertions that fail unless:

```python
assert ('Stop', '*', 'command') in inventory
assert ('Stop', '*', 'prompt') not in inventory
```

Extend `tests/test_stop_gates.sh` so it covers:

1. `stop_hook_active == true` allows
2. `interrupt.allowed == true` allows
3. `workflow.active != true` allows silently
4. missing review records blocks
5. finishing-required state blocks
6. completion-style message without fresh passing evidence blocks
7. completion-style message with fresh passing evidence allows

- [ ] **Step 2: Run tests to verify RED**

Run:

```bash
bash tests/test_hooks_official_events.sh
bash tests/test_stop_gates.sh
```

Expected:

1. static inventory still finds a Stop prompt hook
2. current Stop script does not yet cover the final command-only completion heuristic

- [ ] **Step 3: Write the minimal implementation**

1. remove the Stop prompt hook from `hooks/hooks.json`
2. keep exactly one Stop command hook:

```json
{
  "matcher": "*",
  "hooks": [
    {
      "type": "command",
      "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-stop-review-gate.sh",
      "timeout": 10
    }
  ]
}
```

3. extend `scripts/check-stop-review-gate.sh` so it:
   - preserves the current review / finishing / interrupt behavior
   - exits early when `workflow.active != true`
   - reads `last_assistant_message`
   - blocks completion claims that lack obvious fresh passing verification evidence

Keep the command output contract:

```json
{"decision":"block","reason":"..."}
```

Allow path remains silent.

- [ ] **Step 4: Run tests to verify GREEN**

Run:

```bash
bash tests/test_hooks_official_events.sh
bash tests/test_stop_gates.sh
```

Expected: PASS

- [ ] **Step 5: Run adjacent non-regression**

Run:

```bash
bash tests/test_interrupt_state.sh
```

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add hooks/hooks.json scripts/check-stop-review-gate.sh tests/test_hooks_official_events.sh tests/test_stop_gates.sh
git commit -m "fix: make stop hook command-only"
```

## Task 4: Document Runtime Prerequisites And Packaging

**User-facing goal:** Users still install one plugin, but the docs now truthfully state the Node runtime prerequisite and explain that parser runtime artifacts ship inside the repo.

**Files:**
- Modify: `README.md`
- Modify: `README_cn.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Write the failing doc checks**

Add a temporary shell check in your session that fails unless all three docs mention:

1. active Bash enforcement now requires Node
2. users install only this plugin, not a second parser repo
3. vendored parser runtime ships inside this plugin repo

Example:

```bash
rg -n "Node|bash-traverse|single plugin|vendored" README.md README_cn.md CLAUDE.md
```

- [ ] **Step 2: Run the check to verify RED**

Run:

```bash
rg -n "bash-traverse|vendored|Node runtime" README.md README_cn.md CLAUDE.md
```

Expected: missing or incomplete matches

- [ ] **Step 3: Write the minimal documentation updates**

Update each document so it clearly states:

1. inactive workflow remains no-op
2. active Bash enforcement uses a vendored parser runtime
3. Node is required on machines that need active Bash enforcement to work
4. users still install only this plugin repo/plugin

- [ ] **Step 4: Run the check to verify GREEN**

Run:

```bash
rg -n "bash-traverse|vendored|Node runtime|single plugin" README.md README_cn.md CLAUDE.md
```

Expected: all three docs match the new runtime model

- [ ] **Step 5: Commit**

```bash
git add README.md README_cn.md CLAUDE.md
git commit -m "docs: clarify parser-backed bash runtime requirements"
```

## Task 5: Final Verification

**User-facing goal:** The plugin meets the two actual success criteria: stable active enforcement and no user-visible inactive interference.

**Files:**
- Modify: none unless verification exposes a real defect

- [ ] **Step 1: Run targeted regression pack**

Run:

```bash
bash tests/test_hooks_official_events.sh
bash tests/test_bash_command_gate.sh
bash tests/test_stop_gates.sh
```

Expected: PASS

- [ ] **Step 2: Run adjacent safety coverage**

Run:

```bash
bash tests/test_bypass_state.sh
bash tests/test_interrupt_state.sh
bash tests/test_pretool_command_gates.sh
bash tests/test_posttool_command_gates.sh
bash tests/test_workflow_activation.sh
```

Expected: PASS

- [ ] **Step 3: Run a Node/runtime smoke check**

Run:

```bash
node -e "const mod=require('./vendor/bash-traverse/dist/index.js'); console.log(Object.keys(mod).includes('parse'))"
```

Expected: prints `true`

- [ ] **Step 4: Confirm final hook inventory**

Run:

```bash
python3 - <<'PY'
import json
from pathlib import Path

hooks = json.loads(Path('hooks/hooks.json').read_text())['hooks']
inventory = {
    (event, group.get('matcher', '*'), hook.get('type', ''))
    for event, groups in hooks.items()
    for group in groups
    for hook in group.get('hooks', [])
}
assert ('PreToolUse', 'Bash', 'command') in inventory
assert ('PreToolUse', 'Bash', 'prompt') not in inventory
assert ('Stop', '*', 'command') in inventory
assert ('Stop', '*', 'prompt') not in inventory
assert ('Stop', '*', 'agent') not in inventory
PY
```

Expected: exit 0

- [ ] **Step 5: If verification exposes a real defect, fix it in a focused follow-up commit**

Do not create an extra commit unless verification reveals a real bug.

## Review Handoff Notes

Reviewers should evaluate against:

1. `docs/superpowers/specs/2026-04-12-activation-scoped-bash-traverse-design.md`
2. the hard rule that `workflow.active != true` must no-op
3. the requirement that active Bash enforcement uses vendored parser runtime, not user-managed external setup
4. the requirement that `Stop` ends as command-only
