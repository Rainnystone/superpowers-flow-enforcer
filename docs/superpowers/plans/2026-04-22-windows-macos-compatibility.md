# Windows and macOS Compatibility Baseline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the plugin hooks and shell test suite run without portability errors on macOS and on native Windows under Git Bash, and leave the repo with one documented test command maintainers can run on both platforms.

**Architecture:** Converge the repository onto a single Bash-first compatibility baseline rather than layering Windows-only exceptions. Centralize runtime-sensitive behavior into a small compatibility helper, route duplicated path traversal through one contract, then modernize the tests so the proving surface is as portable as the hook runtime.

**Tech Stack:** Bash, jq, small embedded Python helpers, Node 18+ for vendored `bash-traverse`, Git Bash on Windows, shell test suite under `tests/`

---

## File Structure

- `scripts/lib/platform_compat.sh`
  New shared helper for resolving Python and hashing without hard-coding one platform-specific binary contract.
- `scripts/lib/workflow_paths.sh`
  Shared path normalization and root traversal contract; should become the canonical source for upward traversal semantics.
- `scripts/init-state.sh`
  Session bootstrap and session hash generation; must adopt the shared compatibility helper.
- `scripts/lib/task_flow_packets.sh`
  Embedded Python parsing helper; must stop hard-coding `python3`.
- `scripts/sync-post-tool-state.sh`
  Embedded Python command classification helpers; must stop hard-coding `python3`.
- `scripts/check-pretool-gates.sh`
  TDD gate currently uses process substitution and needs a portable input collection path.
- `scripts/sync-user-prompt-state.sh`
  Canonical artifact scanning currently uses process substitution and duplicated root resolution.
- `scripts/check-bash-command-gate.sh`
  Duplicates root traversal logic; must align with shared traversal semantics.
- `scripts/check-stop-review-gate.sh`
  Duplicates root traversal logic; must align with shared traversal semantics.
- `scripts/check-task-completed.sh`
  Duplicates root traversal logic; must align with shared traversal semantics.
- `tests/helpers/assert.sh`
  Central test assertion helper; good place to add string-to-temp-file JSON helpers so tests stop using `<(...)`.
- `tests/helpers/platform.sh`
  New test helper for temp-path and symlink capability handling.
- `tests/test_platform_compat.sh`
  New focused compatibility test for Python/hash helpers.
- `tests/test_runtime_path_traversal.sh`
  New focused contract test for stagnation-based root traversal, including Windows drive-root behavior.
- `tests/test_runtime_shell_portability.sh`
  New focused contract test for forbidden runtime process substitution in hook scripts.
- `tests/test_test_suite_portability.sh`
  New focused contract test for forbidden test-only shell patterns such as process substitution.
- `tests/test_test_environment_portability.sh`
  New focused contract test for hard-coded temp paths and symlink prerequisite handling in the owned tests.
- `tests/test_*.sh`
  Existing regression suite; selected files will be updated to use portable helper paths and deterministic symlink handling.
- `scripts/run-test-suite.sh`
  New one-command verification entrypoint for both macOS and Windows Git Bash.
- `README.md`, `README_cn.md`, `CLAUDE.md`
  User-facing documentation for supported environments and the new test command.

## Task Order

All tasks are **serial by default**. Several packets touch shared helper files or shared tests, so parallel execution is not safe unless a later implementation pass proves the write sets are disjoint.

### Task 1: Add Shared Platform Compatibility Helper

**Packet Goal:** Introduce one shared runtime helper for Python resolution and SHA-256 hashing so later tasks stop open-coding platform-sensitive fallbacks.

**Files:**
- Create: `scripts/lib/platform_compat.sh`
- Create: `tests/test_platform_compat.sh`

**Verification:** `bash tests/test_platform_compat.sh`

**Parallel?:** No. This is the foundation for later runtime packets.

**Reviewer Focus:** Python fallback order, hash fallback order, explicit error behavior, and no dependence on Linux-only pseudo-files.

- [ ] **Step 1: Write the failing helper test**

Create `tests/test_platform_compat.sh` with focused coverage for:
- fallback from a non-working `python3` stub to a working `python`
- deterministic SHA-256 hashing when the first hashing command is missing
- failure when no Python interpreter is available

```bash
#!/bin/bash
set -euo pipefail

source tests/helpers/assert.sh
source scripts/lib/platform_compat.sh

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAKE_BIN="$TMP_DIR/bin"
mkdir -p "$FAKE_BIN"
SYSTEM_PYTHON="$(command -v python3 || command -v python)"

cat > "$FAKE_BIN/python3" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$FAKE_BIN/python3"

cat > "$FAKE_BIN/python" <<EOF
#!/bin/bash
exec "$SYSTEM_PYTHON" "\$@"
EOF
chmod +x "$FAKE_BIN/python"

PYTHON_STDOUT="$TMP_DIR/platform-python.out"
PYTHON_STDERR="$TMP_DIR/platform-python.err"

PATH="$FAKE_BIN" platform_compat_resolve_python_bin >"$PYTHON_STDOUT" 2>"$PYTHON_STDERR"
assert_file_contains "$PYTHON_STDOUT" "$FAKE_BIN/python"
```

Run: `bash tests/test_platform_compat.sh`  
Expected: FAIL because `scripts/lib/platform_compat.sh` does not exist yet.

- [ ] **Step 2: Write the minimal compatibility helper**

Create `scripts/lib/platform_compat.sh`:

```bash
#!/bin/bash

platform_compat_resolve_python_bin() {
  local candidate=""
  local candidate_path=""
  for candidate in python3 python; do
    candidate_path="$(command -v "$candidate" 2>/dev/null || true)"
    [ -n "$candidate_path" ] || continue
    "$candidate_path" -c 'import sys; sys.exit(0)' >/dev/null 2>&1 || continue
    printf '%s\n' "$candidate_path"
    return 0
  done

  echo "No working Python interpreter found; tried python3 then python" >&2
  return 1
}

platform_compat_run_python() {
  local python_bin=""
  python_bin="$(platform_compat_resolve_python_bin)" || return 1
  "$python_bin" "$@"
}

platform_compat_hash_stdin_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
    return 0
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
    return 0
  fi

  if command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 | awk '{print $NF}'
    return 0
  fi

  platform_compat_run_python -c 'import hashlib, sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())'
}
```

- [ ] **Step 3: Finish the focused test with fake hash backends**

Expand `tests/test_platform_compat.sh` to cover hash fallback and missing-Python failure:

```bash
cat > "$FAKE_BIN/openssl" <<'EOF'
#!/bin/bash
printf 'SHA2-256(stdin)= %s\n' "0123456789abcdef"
EOF
chmod +x "$FAKE_BIN/openssl"

HASH_OUTPUT="$(printf 'abc' | PATH="$FAKE_BIN" platform_compat_hash_stdin_sha256)"
[ "$HASH_OUTPUT" = "0123456789abcdef" ] || {
  echo "Expected openssl fallback hash, got $HASH_OUTPUT" >&2
  exit 1
}

EMPTY_BIN="$TMP_DIR/empty-bin"
mkdir -p "$EMPTY_BIN"
MISSING_STDOUT="$TMP_DIR/platform-missing.out"
MISSING_STDERR="$TMP_DIR/platform-missing.err"

if PATH="$EMPTY_BIN" platform_compat_resolve_python_bin >"$MISSING_STDOUT" 2>"$MISSING_STDERR"; then
  echo "Expected python resolution to fail when neither python3 nor python exists" >&2
  exit 1
fi
assert_file_contains "$MISSING_STDERR" "No working Python interpreter found"
```

- [ ] **Step 4: Run the focused test to green**

Run: `bash tests/test_platform_compat.sh`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/platform_compat.sh tests/test_platform_compat.sh
git commit -m "test: add shared platform compatibility helper"
```

### Task 2: Adopt the Shared Helper in Python/Hash Runtime Call Sites

**Packet Goal:** Replace direct `python3` and hash assumptions in the current runtime surfaces that already depend on embedded Python or hashing.

**Files:**
- Modify: `scripts/init-state.sh`
- Modify: `scripts/lib/task_flow_packets.sh`
- Modify: `scripts/sync-post-tool-state.sh`
- Modify: `tests/test_hooks_official_events.sh`
- Test: `tests/test_platform_compat.sh`
- Test: `tests/test_init_state.sh`
- Test: `tests/test_agent_task_boundary_gate.sh`
- Test: `tests/test_posttool_command_gates.sh`
- Test: `tests/test_hooks_official_events.sh`

**Verification:** `bash tests/test_platform_compat.sh && bash tests/test_init_state.sh && bash tests/test_agent_task_boundary_gate.sh && bash tests/test_posttool_command_gates.sh && bash tests/test_hooks_official_events.sh`

**Parallel?:** No. This packet depends on Task 1 and touches shared runtime entrypoints.

**Reviewer Focus:** Every direct `python3` replacement is source-compatible, hash generation still produces non-empty IDs, and macOS behavior is unchanged.

- [ ] **Step 1: Add the failing runtime adoption assertions**

Before editing runtime files, add/adjust one or two focused assertions that prove the repo no longer hard-codes `python3` in these owned files:

```bash
rg -n '\bpython3\b' scripts/init-state.sh scripts/lib/task_flow_packets.sh scripts/sync-post-tool-state.sh tests/test_hooks_official_events.sh
```

Run: the `rg` command above  
Expected: FAIL with current `python3` hits.

- [ ] **Step 2: Wire the helper into `init-state.sh`**

Modify the top of `scripts/init-state.sh`:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
source "$PLUGIN_ROOT/scripts/lib/platform_compat.sh"
```

Replace the session hash line:

```bash
SESSION_ID="$(date +%s | platform_compat_hash_stdin_sha256 | cut -c 1-16)"
```

- [ ] **Step 3: Wire the helper into the embedded Python runtime files**

At the top of `scripts/lib/task_flow_packets.sh`:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
source "$PLUGIN_ROOT/scripts/lib/platform_compat.sh"
```

Replace every `python3 -c` call with:

```bash
platform_compat_run_python -c "$(cat <<'PY'
...
PY
)"
```

In `scripts/sync-post-tool-state.sh`:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
source "$PLUGIN_ROOT/scripts/lib/platform_compat.sh"
```

Replace every `python3 - "$command" <<'PY'` with:

```bash
platform_compat_run_python - "$command" <<'PY'
...
PY
```

Update `tests/test_hooks_official_events.sh`:

```bash
source scripts/lib/platform_compat.sh

platform_compat_run_python - <<'PY'
...
PY
```

- [ ] **Step 4: Run the owned verification set**

Run:

```bash
bash tests/test_platform_compat.sh
bash tests/test_init_state.sh
bash tests/test_agent_task_boundary_gate.sh
bash tests/test_posttool_command_gates.sh
bash tests/test_hooks_official_events.sh
```

Expected: all PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/init-state.sh scripts/lib/task_flow_packets.sh scripts/sync-post-tool-state.sh tests/test_hooks_official_events.sh
git commit -m "refactor: adopt shared platform helper in runtime scripts"
```

### Task 3: Converge Runtime Path Traversal

**Packet Goal:** Make state-root traversal terminate safely on both POSIX roots and Windows drive roots, and centralize that contract in `workflow_paths.sh`.

**Files:**
- Modify: `scripts/lib/workflow_paths.sh`
- Modify: `scripts/check-bash-command-gate.sh`
- Modify: `scripts/sync-user-prompt-state.sh`
- Modify: `scripts/check-stop-review-gate.sh`
- Modify: `scripts/check-task-completed.sh`
- Create: `tests/test_runtime_path_traversal.sh`
- Test: `tests/test_bash_command_gate.sh`
- Test: `tests/test_resume_recovery_flow.sh`
- Test: `tests/test_stop_gates.sh`

**Verification:** `node --version && bash tests/test_runtime_path_traversal.sh && bash tests/test_bash_command_gate.sh && bash tests/test_resume_recovery_flow.sh && bash tests/test_stop_gates.sh`

**Parallel?:** No. This packet owns the shared traversal contract used by multiple runtime scripts.

**Reviewer Focus:** Traversal stops on stagnation instead of assuming `/` semantics, Windows drive-root behavior is explicitly covered, and owned scripts no longer carry divergent upward-walk logic.

**Handoff Note:** `scripts/sync-user-prompt-state.sh` is shared with Task 4. Task 3 owns traversal-only edits in that file; Task 4 may touch it later only for process-substitution removal.

- [ ] **Step 1: Write the failing traversal contract test**

Create `tests/test_runtime_path_traversal.sh`:

```bash
#!/bin/bash
set -euo pipefail

source scripts/lib/workflow_paths.sh

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PROJECT_DIR="$TMP_DIR/project"
mkdir -p "$PROJECT_DIR/.claude" "$PROJECT_DIR/nested/deep"
: > "$PROJECT_DIR/.claude/flow_state.json"

EXPECTED_ROOT="$(cd "$PROJECT_DIR" && pwd -P)"
RESOLVED_ROOT="$(workflow_paths_resolve_state_root_from_candidate "$PROJECT_DIR/nested/deep/file.txt")"
[ "$RESOLVED_ROOT" = "$EXPECTED_ROOT" ] || {
  echo "Expected helper to resolve nested path back to $EXPECTED_ROOT, got $RESOLVED_ROOT" >&2
  exit 1
}

if workflow_paths__next_parent "/" >/dev/null 2>&1; then
  echo "Expected workflow_paths__next_parent to fail at POSIX root" >&2
  exit 1
fi

if (
  dirname() { printf 'C:/\n'; }
  source scripts/lib/workflow_paths.sh
  workflow_paths__next_parent 'C:/' >/dev/null 2>&1
); then
  echo "Expected workflow_paths__next_parent to fail when dirname stagnates at a Windows drive root" >&2
  exit 1
fi

if ! rg -n 'source .*workflow_paths\.sh|\. .*workflow_paths\.sh' \
  scripts/check-bash-command-gate.sh \
  scripts/sync-user-prompt-state.sh \
  scripts/check-stop-review-gate.sh \
  scripts/check-task-completed.sh >/dev/null; then
  echo "Expected owned runtime scripts to route traversal through workflow_paths.sh" >&2
  exit 1
fi

if ! rg -n 'workflow_paths_resolve_state_root_from_candidate' \
  scripts/check-bash-command-gate.sh \
  scripts/sync-user-prompt-state.sh \
  scripts/check-stop-review-gate.sh \
  scripts/check-task-completed.sh >/dev/null; then
  echo "Expected owned runtime scripts to call workflow_paths_resolve_state_root_from_candidate directly" >&2
  exit 1
fi

if rg -n '^resolve_state_root_from_candidate\(\)' \
  scripts/check-bash-command-gate.sh \
  scripts/sync-user-prompt-state.sh \
  scripts/check-stop-review-gate.sh \
  scripts/check-task-completed.sh >/dev/null; then
  echo "Expected owned runtime scripts to drop local resolve_state_root_from_candidate wrappers" >&2
  exit 1
fi
```

Run: `bash tests/test_runtime_path_traversal.sh`  
Expected: FAIL because the current traversal contract does not yet prove stagnation-based termination everywhere.

- [ ] **Step 2: Define the shared stagnation-based traversal helper**

Update `scripts/lib/workflow_paths.sh` so upward traversal stops whenever `dirname` returns the same value it was given, and keep `workflow_paths_resolve_state_root_from_candidate` as the public entrypoint that routes through that helper:

```bash
workflow_paths__next_parent() {
  local current="$1"
  local parent=""

  parent="$(dirname "$current")"
  if [ "$parent" = "$current" ]; then
    return 1
  fi

  printf '%s\n' "$parent"
}

workflow_paths__traverse_up_until_state_root() {
  local current="$1"
  local parent=""

  while :; do
    if [ -f "$current/.claude/flow_state.json" ]; then
      printf '%s\n' "$current"
      return 0
    fi

    parent="$(workflow_paths__next_parent "$current")" || return 1
    current="$parent"
  done
}

workflow_paths_resolve_state_root_from_candidate() {
  local candidate="${1:-}"
  local current=""

  current="$(workflow_paths_normalize_candidate_dir "$candidate")" || return 1
  workflow_paths__traverse_up_until_state_root "$current"
}
```

- [ ] **Step 3: Route the owned runtime scripts through the shared helper**

In `scripts/check-bash-command-gate.sh`, `scripts/sync-user-prompt-state.sh`, `scripts/check-stop-review-gate.sh`, and `scripts/check-task-completed.sh`, source `workflow_paths.sh`, remove any local traversal wrapper, and call the exported helper directly:

```bash
source "$PLUGIN_ROOT/scripts/lib/workflow_paths.sh"

STATE_ROOT="$(workflow_paths_resolve_state_root_from_candidate "${candidate_path:-}")" || exit 0
```

- [ ] **Step 4: Run the owned verification set and commit**

Run:

```bash
node --version
bash tests/test_runtime_path_traversal.sh
bash tests/test_bash_command_gate.sh
bash tests/test_resume_recovery_flow.sh
bash tests/test_stop_gates.sh
```

Expected: all PASS

Commit:

```bash
git add scripts/lib/workflow_paths.sh scripts/check-bash-command-gate.sh scripts/sync-user-prompt-state.sh scripts/check-stop-review-gate.sh scripts/check-task-completed.sh tests/test_runtime_path_traversal.sh
git commit -m "refactor: converge runtime path traversal"
```

### Task 4: Remove Runtime Process Substitution

**Packet Goal:** Remove runtime `<(...)` usage from the hook scripts that still depend on Bash-specific process substitution.

**Files:**
- Modify: `scripts/check-pretool-gates.sh`
- Modify: `scripts/sync-user-prompt-state.sh`
- Create: `tests/test_runtime_shell_portability.sh`
- Test: `tests/test_pretool_command_gates.sh`
- Test: `tests/test_workflow_activation.sh`

**Verification:** `bash tests/test_runtime_shell_portability.sh && bash tests/test_pretool_command_gates.sh && bash tests/test_workflow_activation.sh`

**Parallel?:** No. This packet owns runtime shell input collection for the remaining hook scripts.

**Reviewer Focus:** No runtime `<(...)` remains in the owned scripts, temp-file replacements are explicit and cleaned up, and the behavior of candidate/test collection is unchanged.

**Handoff Note:** This packet follows Task 3 serially. In `scripts/sync-user-prompt-state.sh`, Task 4 must preserve the traversal contract established by Task 3 and limit edits to shell input collection only.

- [ ] **Step 1: Write the failing runtime shell portability contract**

Create `tests/test_runtime_shell_portability.sh`:

```bash
#!/bin/bash
set -euo pipefail

if rg -n '<\(|done < <\(' \
  scripts/check-pretool-gates.sh \
  scripts/sync-user-prompt-state.sh >/dev/null; then
  echo "Expected owned runtime scripts to stop using process substitution" >&2
  exit 1
fi
```

Run: `bash tests/test_runtime_shell_portability.sh`  
Expected: FAIL with the current process-substitution usage.

- [ ] **Step 2: Replace runtime process substitution with explicit temp files**

In `scripts/check-pretool-gates.sh`, replace:

```bash
while IFS= read -r line; do
  candidates+=("$line")
done < <(infer_candidate_tests "$path")
```

with:

```bash
candidate_file="$(mktemp)"
infer_candidate_tests "$path" > "$candidate_file"
while IFS= read -r line; do
  candidates+=("$line")
done < "$candidate_file"
rm -f "$candidate_file"
```

and replace:

```bash
while IFS= read -r line; do
  failed_tests+=("$line")
done < <(jq -r '.tdd.tests_verified_fail[]? | select(type == "string")' "$STATE_FILE")
```

with:

```bash
failed_test_file="$(mktemp)"
jq -r '.tdd.tests_verified_fail[]? | select(type == "string")' "$STATE_FILE" > "$failed_test_file"
while IFS= read -r line; do
  failed_tests+=("$line")
done < "$failed_test_file"
rm -f "$failed_test_file"
```

In `scripts/sync-user-prompt-state.sh`, replace the `find ... -print0` process substitution loop with an explicit temp file:

```bash
find_list_file="$(mktemp)"
find "$project_dir" -type f -name '*.md' -print0 > "$find_list_file" 2>/dev/null || true
while IFS= read -r -d '' candidate; do
  ...
done < "$find_list_file"
rm -f "$find_list_file"
```

- [ ] **Step 3: Run the owned verification set and commit**

Run:

```bash
bash tests/test_runtime_shell_portability.sh
bash tests/test_pretool_command_gates.sh
bash tests/test_workflow_activation.sh
```

Expected: all PASS

Commit:

```bash
git add scripts/check-pretool-gates.sh scripts/sync-user-prompt-state.sh tests/test_runtime_shell_portability.sh
git commit -m "refactor: remove runtime process substitution"
```

### Task 5: Modernize JSON Assertions and Remove Test-Suite Process Substitution

**Packet Goal:** Stop the test suite from depending on process substitution by standardizing JSON assertion input through helpers.

**Files:**
- Modify: `tests/helpers/assert.sh`
- Create: `tests/test_test_suite_portability.sh`
- Modify: `tests/test_bash_command_gate.sh`
- Modify: `tests/test_bypass_state.sh`
- Modify: `tests/test_agent_task_boundary_gate.sh`
- Modify: `tests/test_stop_gates.sh`
- Modify: `tests/test_brainstorming_findings_flow.sh`
- Modify: `tests/test_posttool_command_gates.sh`
- Modify: `tests/test_pretool_command_gates.sh`
- Modify: `tests/test_worktree_baseline_flow.sh`

**Verification:** `bash tests/test_test_suite_portability.sh && bash tests/test_bash_command_gate.sh && bash tests/test_bypass_state.sh && bash tests/test_agent_task_boundary_gate.sh && bash tests/test_stop_gates.sh && bash tests/test_brainstorming_findings_flow.sh && bash tests/test_posttool_command_gates.sh && bash tests/test_pretool_command_gates.sh && bash tests/test_worktree_baseline_flow.sh`

**Parallel?:** No. This packet touches the shared assertion helper and many tests.

**Reviewer Focus:** No remaining `<(...)` in the owned tests, helper behavior is simple and explicit, and converted assertions are still readable.

**Handoff Note:** `tests/test_pretool_command_gates.sh` is shared with Task 6. Task 5 owns JSON assertion conversion in that file; Task 6 may touch it later only for temp-path or symlink prerequisite handling.

- [ ] **Step 1: Write the failing test-suite portability contract**

Create `tests/test_test_suite_portability.sh`:

```bash
#!/bin/bash
set -euo pipefail

if rg -n '<\(' tests --glob '!test_test_suite_portability.sh' >/dev/null; then
  echo "Expected test suite to stop using process substitution" >&2
  exit 1
fi
```

Run: `bash tests/test_test_suite_portability.sh`  
Expected: FAIL with current `<(...)` hits.

- [ ] **Step 2: Add JSON text assertion helpers**

Extend `tests/helpers/assert.sh`:

```bash
assert_json_text_equals() {
  local text="$1" jq_expr="$2" expected="$3"
  local tmp_file
  tmp_file="$(mktemp)"
  printf '%s' "$text" > "$tmp_file"
  assert_json_equals "$tmp_file" "$jq_expr" "$expected"
  rm -f "$tmp_file"
}

assert_json_text_contains() {
  local text="$1" jq_expr="$2" fragment="$3"
  local tmp_file
  tmp_file="$(mktemp)"
  printf '%s' "$text" > "$tmp_file"
  jq -e --arg frag "$fragment" "$jq_expr | contains(\$frag)" "$tmp_file" >/dev/null 2>&1 || {
    rm -f "$tmp_file"
    echo "Expected $jq_expr to contain $fragment" >&2
    exit 1
  }
  rm -f "$tmp_file"
}
```

- [ ] **Step 3: Convert the owned tests**

Representative conversion:

```bash
# Before
assert_json_equals <(printf '%s' "$output") '.decision' '"block"'

# After
assert_json_text_equals "$output" '.decision' '"block"'
```

And:

```bash
# Before
jq -e --arg frag "$reason_fragment" '.reason | contains($frag)' <(printf '%s' "$output") >/dev/null 2>&1

# After
assert_json_text_contains "$output" '.reason' "$reason_fragment"
```

Apply the same pattern across all files owned by this task.

- [ ] **Step 4: Run the owned verification set**

Run:

```bash
bash tests/test_test_suite_portability.sh
bash tests/test_bash_command_gate.sh
bash tests/test_bypass_state.sh
bash tests/test_agent_task_boundary_gate.sh
bash tests/test_stop_gates.sh
bash tests/test_brainstorming_findings_flow.sh
bash tests/test_posttool_command_gates.sh
bash tests/test_pretool_command_gates.sh
bash tests/test_worktree_baseline_flow.sh
```

Expected: all PASS

- [ ] **Step 5: Commit**

```bash
git add tests/helpers/assert.sh tests/test_test_suite_portability.sh tests/test_bash_command_gate.sh tests/test_bypass_state.sh tests/test_agent_task_boundary_gate.sh tests/test_stop_gates.sh tests/test_brainstorming_findings_flow.sh tests/test_posttool_command_gates.sh tests/test_pretool_command_gates.sh tests/test_worktree_baseline_flow.sh
git commit -m "test: remove process substitution from json assertions"
```

### Task 6: Make Test Temp Paths and Symlink Expectations Portable

**Packet Goal:** Remove Unix-only `/tmp/...` assumptions from tests and make symlink-sensitive coverage deterministic on Windows.

**Files:**
- Create: `tests/helpers/platform.sh`
- Create: `tests/test_test_environment_portability.sh`
- Modify: `tests/test_init_state.sh`
- Modify: `tests/test_workflow_activation.sh`
- Modify: `tests/test_pretool_command_gates.sh`
- Modify: `tests/test_worktree_baseline_flow.sh`
- Test: `tests/test_init_state.sh`
- Test: `tests/test_workflow_activation.sh`
- Test: `tests/test_pretool_command_gates.sh`
- Test: `tests/test_worktree_baseline_flow.sh`

**Verification:** `bash tests/test_test_environment_portability.sh && bash tests/test_init_state.sh && bash tests/test_workflow_activation.sh && bash tests/test_pretool_command_gates.sh && bash tests/test_worktree_baseline_flow.sh`

**Parallel?:** No. This packet owns the remaining test-environment portability surface for temp paths and symlink prerequisites.

**Reviewer Focus:** `/tmp` literals are removed where they are not the thing under test, symlink-sensitive tests declare their prerequisite explicitly, and the packet does not broaden into unrelated test files.

**Handoff Note:** This packet follows Task 5 serially. In `tests/test_pretool_command_gates.sh` and `tests/test_workflow_activation.sh`, keep prior assertion-helper conversions intact and limit edits to temp-path or symlink prerequisite handling.

- [ ] **Step 1: Write the failing portability checks for `/tmp` and symlink handling**

Create `tests/test_test_environment_portability.sh`:

```bash
#!/bin/bash
set -euo pipefail

TMP_PORTABILITY_TESTS=(
  tests/test_init_state.sh
  tests/test_pretool_command_gates.sh
  tests/test_workflow_activation.sh
  tests/test_worktree_baseline_flow.sh
)

SYMLINK_PORTABILITY_TESTS=(
  tests/test_workflow_activation.sh
  tests/test_pretool_command_gates.sh
)

if rg -n '/tmp/' "${TMP_PORTABILITY_TESTS[@]}" >/dev/null; then
  echo "Expected owned tests to stop hard-coding /tmp paths" >&2
  exit 1
fi

if rg -n 'ln -s' "${SYMLINK_PORTABILITY_TESTS[@]}" >/dev/null && \
  ! rg -n 'skip_unless_symlink_supported' "${SYMLINK_PORTABILITY_TESTS[@]}" >/dev/null; then
  echo "Expected symlink-sensitive tests to use deterministic skip handling" >&2
  exit 1
fi
```

Run: `bash tests/test_test_environment_portability.sh`  
Expected: FAIL on current literals and missing helper use.

- [ ] **Step 2: Add the test platform helper**

Create `tests/helpers/platform.sh`:

```bash
#!/bin/bash

skip_unless_symlink_supported() {
  local tmp_dir=""
  tmp_dir="$(mktemp -d)"
  mkdir -p "$tmp_dir/target"
  if ln -s "$tmp_dir/target" "$tmp_dir/link" >/dev/null 2>&1; then
    rm -rf "$tmp_dir"
    return 0
  fi

  rm -rf "$tmp_dir"
  echo "SKIP: symlink creation is not available in this environment" >&2
  exit 0
}
```

- [ ] **Step 3: Replace hard-coded `/tmp` artifacts with `TMP_DIR`-owned paths**

Representative `tests/test_init_state.sh` conversion:

```bash
INIT_STDOUT="$TMP_DIR/test-init-state.out"
INIT_STDERR="$TMP_DIR/test-init-state.err"

if ! bash scripts/init-state.sh >"$INIT_STDOUT" 2>"$INIT_STDERR"; then
  cat "$INIT_STDERR" >&2
  exit 1
fi
```

Representative `tests/test_worktree_baseline_flow.sh` conversion:

```bash
WT1_PATH="$TMP_DIR/wt-1"
WT2_PATH="$TMP_DIR/wt-2"

bash scripts/record-worktree-state.sh created "$WT1_PATH"
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.path' "\"$WT1_PATH\""
```

Representative `tests/test_workflow_activation.sh` conversion for outside-path checks:

```bash
OUTSIDE_ROOT="$TMP_DIR/outside"
mkdir -p "$OUTSIDE_ROOT/docs/superpowers/specs"
printf '%s' "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$OUTSIDE_ROOT/docs/superpowers/specs/2026-04-11-demo.md\"}}" | ...
```

- [ ] **Step 4: Gate symlink-sensitive tests**

At the top of the symlink-requiring tests:

```bash
source tests/helpers/platform.sh
skip_unless_symlink_supported
```

Apply to:
- `tests/test_workflow_activation.sh`
- `tests/test_pretool_command_gates.sh`

If a subset of symlink tests can be rewritten without symlinks, prefer that rewrite instead of a blanket skip.

- [ ] **Step 5: Run the owned verification set and commit**

Run:

```bash
bash tests/test_test_environment_portability.sh
bash tests/test_init_state.sh
bash tests/test_workflow_activation.sh
bash tests/test_pretool_command_gates.sh
bash tests/test_worktree_baseline_flow.sh
```

Expected: all PASS, or deterministic `SKIP:` only where symlink creation is genuinely unavailable.

Commit:

```bash
git add tests/helpers/platform.sh tests/test_test_environment_portability.sh tests/test_init_state.sh tests/test_workflow_activation.sh tests/test_pretool_command_gates.sh tests/test_worktree_baseline_flow.sh
git commit -m "test: make temp path and symlink coverage portable"
```

### Task 7: Add One-Command Verification Entry Point and Sync Docs

**Packet Goal:** Leave the repo with one documented verification command that maintainers can run on both macOS and Windows Git Bash.

**Files:**
- Create: `scripts/run-test-suite.sh`
- Modify: `README.md`
- Modify: `README_cn.md`
- Modify: `CLAUDE.md`
- Test: `tests/test_hooks_official_events.sh`
- Test: `tests/test_platform_compat.sh`
- Test: `tests/test_runtime_path_traversal.sh`
- Test: `tests/test_runtime_shell_portability.sh`
- Test: `tests/test_test_suite_portability.sh`
- Test: `tests/test_test_environment_portability.sh`

**Verification:** `node -e 'process.exit(Number(process.versions.node.split(\".\")[0]) >= 18 ? 0 : 1)' && bash scripts/run-test-suite.sh && rg -n 'native Windows with Git for Windows / Git Bash' README.md CLAUDE.md && rg -n 'Windows 支持指的是 Git for Windows / Git Bash' README_cn.md && rg -n 'bash scripts/run-test-suite\\.sh' README.md README_cn.md CLAUDE.md && rg -n 'python3.*python|python.*python3' README.md README_cn.md CLAUDE.md`

**Parallel?:** No. This packet depends on all earlier runtime/test portability work.

**Reviewer Focus:** One-command entrypoint is simple and Bash-portable, docs match the actual support contract, and broad verification output is easy to reproduce.

- [ ] **Step 1: Write the failing broad-entrypoint check**

Create `scripts/run-test-suite.sh`:

```bash
#!/bin/bash
set -euo pipefail

for t in tests/test_*.sh; do
  bash "$t"
done
```

Run: `bash scripts/run-test-suite.sh`  
Expected: FAIL until prior compatibility tasks are complete, but the command itself exists and becomes the final contract.

- [ ] **Step 2: Make the entrypoint explicit and stable**

If ordering or setup is needed, expand the script minimally:

```bash
#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

for t in tests/test_*.sh; do
  printf '==> %s\n' "$t"
  bash "$t"
done
```

- [ ] **Step 3: Sync the docs to the new contract**

Add a verification section to `README.md`:

````md
## Cross-Platform Verification

Supported environments for this repo:
- macOS
- native Windows with Git for Windows / Git Bash

Prerequisites:
- Node 18+
- `jq`
- A working Python runtime resolvable as `python3` or `python`

Run the full shell test suite with:

```bash
bash scripts/run-test-suite.sh
```
````

Mirror the same contract in `README_cn.md` and `CLAUDE.md`, including the note that Windows support here means Git Bash rather than PowerShell-only execution of the hook scripts, and that embedded helpers still require a working Python runtime.

- [ ] **Step 4: Run the broad verification command**

Run: `bash scripts/run-test-suite.sh`  
Expected: PASS, with deterministic `SKIP:` output only for unsupported symlink creation environments.

Also run:

```bash
node --version
node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 18 ? 0 : 1)'
rg -n 'native Windows with Git for Windows / Git Bash' README.md CLAUDE.md
rg -n 'Windows 支持指的是 Git for Windows / Git Bash' README_cn.md
rg -n 'bash scripts/run-test-suite\.sh' README.md README_cn.md CLAUDE.md
rg -n 'python3.*python|python.*python3' README.md README_cn.md CLAUDE.md
```

Expected: `node --version` reports an installed runtime, the explicit major-version check confirms Node 18+, and the exact `rg` checks prove the support contract plus one-command guidance landed in each owned doc.

- [ ] **Step 5: Commit**

```bash
git add scripts/run-test-suite.sh README.md README_cn.md CLAUDE.md
git commit -m "docs: add cross-platform test suite entrypoint"
```

## Self-Review Checklist

- [ ] Every task has one primary objective, one main module/surface area, and one default verification path.
- [ ] No two tasks share the same primary production file without being explicitly serial.
- [ ] Every runtime-sensitive change has a focused test before the implementation step.
- [ ] The final documented verification command is the same on macOS and Windows Git Bash.
- [ ] The plan does not accidentally promise PowerShell-only or CMD-only support.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-22-windows-macos-compatibility.md`.

Execution mode selected for this workstream:
- `superpowers:test-driven-development`
- `superpowers:subagent-driven-development`

Default execution pattern:
- one packet at a time
- write or tighten the focused failing test first
- implement only the packet-owned files
- run the packet verification command
- perform self-review, then request one independent subagent review before moving to the next packet
