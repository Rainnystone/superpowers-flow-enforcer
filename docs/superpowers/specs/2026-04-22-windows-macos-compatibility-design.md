# SPEC: Windows and macOS Compatibility Baseline for Hooks and Test Suite

## Context

`superpowers-flow-enforcer` is a Claude Code plugin implemented as Bash hooks plus a shell-based test suite. The repository already enforces a workflow contract correctly on macOS, but recent work and Windows usage exposed a second class of problems: the plugin and its tests still assume several Linux-like shell/runtime behaviors that are not stable on native Windows with Git Bash.

This matters because Claude Code's current official support boundary already includes native Windows, with Git for Windows required for native Windows setups. Official documentation also states that on native Windows, Claude Code continues to use Git Bash internally for command execution even when launched from PowerShell or CMD. That means this plugin cannot treat Windows support as an afterthought or as a future enhancement. If the repo claims cross-platform support, the plugin runtime and its proving tests must both hold under:

- macOS
- native Windows with Git for Windows / Git Bash

Current findings show several portability hazards:

1. `process substitution` (`<(...)`) is still used in tests and in TDD gate code paths, but that construct depends on `/dev/fd` / FIFO behavior that is not a stable portability baseline for Git Bash.
2. Multiple scripts invoke `python3` directly, but native Windows environments may only expose a working `python`, while `python3` can resolve to a non-working Store stub or be absent altogether.
3. Some tests hard-code `/tmp/...` paths instead of deriving temporary files from the test-owned temp directory.
4. Root-directory traversal logic still assumes POSIX root termination (`/`) in more than one place, which is unsafe on Windows path roots.
5. Several tests depend on `ln -s`, even though symlink creation on Windows is permission-sensitive and often requires Developer Mode or other OS configuration.
6. Hash generation still assumes `sha256sum` or `shasum`, but native Windows environments may not expose either one consistently.

The repository should not solve this with an ad hoc series of one-off Windows exceptions. Instead, it should define and enforce a single compatibility baseline that is stable on both macOS and native Windows + Git Bash.

## Goals

### Goal 1: Define a precise support contract

This workstream must make the repo's compatibility claim explicit and testable.

**Acceptance criteria**:
- The spec, plan, and user-facing docs define the supported environments as:
  - macOS
  - native Windows with Git for Windows / Git Bash
- The repo does **not** claim PowerShell-only or CMD-only execution of the Bash hook scripts as part of this batch
- The repo does **not** claim Windows support in terms so vague that future contributors cannot tell whether a portability regression is real

### Goal 2: Establish a cross-platform shell/runtime baseline

The implementation must define a small set of shell/runtime capabilities that are treated as the only allowed baseline for shared hook code and tests.

**Acceptance criteria**:
- Shared hook logic does not depend on `process substitution`
- Shared hook logic does not require `python3` specifically when a working `python` is available
- Shared hook logic does not assume POSIX root detection by comparing only against `/`
- Shared hook logic does not assume `sha256sum` or `shasum` is always present
- Shared hook logic continues to work on macOS without introducing Windows-only branches that degrade the existing code path

### Goal 3: Make the test suite itself portable

Compatibility is not complete if the runtime works but the proving tests fail for platform-specific reasons.

**Acceptance criteria**:
- Tests do not use `process substitution` as an input transport
- Tests do not hard-code `/tmp/...` output files when a test-owned temp directory already exists
- Tests that require symlink behavior either:
  - switch to a portable assertion strategy, or
  - explicitly detect unsupported Windows conditions and skip deterministically with a clear reason
- The repo has a documented one-command test entrypoint that maintainers can run on macOS and Windows Git Bash

### Goal 4: Keep compatibility fixes structural, not incidental

This batch should reduce future portability regressions rather than just clearing the current error list.

**Acceptance criteria**:
- Common compatibility-sensitive behaviors are centralized into helpers where appropriate
- Duplicated path/root detection logic is either removed or brought under the same contract
- New helper behavior is covered by focused tests
- The repo's documentation makes the expected execution environment explicit enough that future contributors do not reintroduce forbidden patterns casually

## Non-Goals

- No PowerShell rewrite of the plugin's hook implementation
- No parallel Bash and PowerShell runtime maintenance model
- No promise that hooks can be run directly under bare `cmd.exe`
- No dual-platform CI rollout in this batch
- No attempt to work around Claude Code core bugs such as Git Bash discovery failures or native Windows CLI defects outside this repo
- No expansion of the compatibility claim to WSL-specific behavior beyond what already falls out naturally from Bash-safe implementation

## Design

### 1. Supported environment contract

The repository should explicitly adopt the following compatibility contract:

- **macOS**: hooks and tests run under the repo's current Bash-based workflow
- **Windows**: hooks and tests run under **native Windows + Git Bash**, aligned with Claude Code's official native Windows execution model

This contract is intentionally narrower than "all Windows shells" and broader than "WSL only". It matches the platform Anthropic currently documents for native Windows usage while keeping this repo Bash-first.

### 2. Compatibility baseline rules

All shared hook code and shell tests in this repository should follow these baseline rules:

1. Do not use `process substitution` for file-like inputs.
2. Do not require a hard-coded Python executable name when the logic only needs "a working Python 3 runtime".
3. Do not treat `/` as the only valid filesystem traversal terminator.
4. Do not assume `/tmp` is the canonical writable temp location.
5. Do not assume symlink creation is available to unprivileged Windows users.
6. Do not assume one specific hashing utility exists.

These rules are design constraints, not optional recommendations.

### 3. Runtime structure

The runtime changes should follow a "compatibility baseline convergence" strategy rather than isolated patching.

#### 3.1 Python entrypoint helper

Create or reuse a small shared helper that resolves a working Python interpreter in this order:

1. `python3`
2. `python`

If neither works, the script should fail with a clear, deterministic error at the point where Python is actually required.

This helper should be used by:
- `scripts/lib/workflow_paths.sh`
- `scripts/lib/task_flow_packets.sh`
- `scripts/sync-post-tool-state.sh`
- any focused tests that currently call `python3` directly for repo-owned validation logic

The goal is not "support arbitrary Python versions". The goal is "require a working Python runtime without hard-coding the executable name in a platform-fragile way."

#### 3.2 Root traversal helper contract

Path-upward traversal should stop on either:
- successful discovery of the state root, or
- traversal stagnation, meaning `dirname "$current"` is equal to `"$current"`

This prevents infinite or undefined traversal on Windows roots such as drive roots, and it removes the hidden assumption that all termination points compare equal to `/`.

Any duplicated root-resolution code paths should either:
- reuse the existing shared helper in `scripts/lib/workflow_paths.sh`, or
- be updated to implement the same stagnation-based contract

This applies in particular to the Bash gate wrapper, which currently duplicates root resolution logic.

#### 3.3 Hash fallback helper

Session or state hashing should resolve through a deterministic fallback chain, for example:

1. `sha256sum`
2. `shasum -a 256`
3. `openssl dgst -sha256`
4. Python `hashlib`

The exact order can vary if implementation details require it, but the contract must be:
- success on both macOS and Windows Git Bash with reasonable default tooling
- no silent empty hash
- clear failure if all options are unavailable

#### 3.4 Temporary file contract

Portable code should avoid relying on shell features that synthesize pseudo-files dynamically. When file-like input is needed:

- prefer explicit temp files owned by the current test or script
- prefer pipe/stdin-based helpers when that keeps the call site simple

The important rule is that input transport must not depend on `/dev/fd` behavior.

### 4. Test suite structure

#### 4.1 Replace process substitution in tests

Tests should stop passing JSON via `<(printf '%s' "$output")`. Instead, the suite should standardize on one of these patterns:

- write the JSON to a temp file, then assert on that file
- add helper functions that read JSON from stdin and materialize a temp file internally

The choice should prioritize clarity and low risk. The repo does not need a clever abstraction here; it needs a stable one.

#### 4.2 Replace hard-coded `/tmp/...` test artifacts

Tests that currently redirect stdout/stderr or create expected paths under `/tmp/...` should derive those paths from `TMP_DIR`, not from a global temp-root guess.

This includes:
- shell redirection outputs
- any test fixture path that currently encodes `/tmp/` as part of the expected value

If the test is asserting "this exact path string is preserved", it should assert against a path derived inside the test, not against a Unix-only literal.

#### 4.3 Symlink-sensitive tests

Tests whose purpose is canonical path semantics or alias resolution should not depend blindly on `ln -s` succeeding on Windows.

Allowed strategies:
- detect whether symlink creation is truly available and skip with a clear message when it is not
- refactor the test to assert the intended behavior without requiring filesystem symlink creation

Disallowed strategy:
- keep using `ln -s` unconditionally and accept flaky Windows behavior as "environmental"

### 5. Verification and maintainability

The repo should expose a documented one-command verification path for this compatibility workstream. That command should be appropriate for both macOS and Windows Git Bash, and it should be the same command unless there is a strong reason not to.

The design assumption here is:
- targeted tests prove each compatibility-sensitive helper or gate
- one broader command proves the whole repository-level baseline

The docs should also explicitly record the environment prerequisites for Windows:
- Claude Code native Windows support path
- Git for Windows / Git Bash required
- Python runtime required where the repo uses embedded Python helpers

## Error Handling

Compatibility-sensitive failures should be explicit and local.

### Fail fast with clear error

Use deterministic failures when:
- no working Python runtime can be resolved for a script that genuinely requires it
- no hash backend can be resolved where a hash is required
- an expected temp file or helper output cannot be created

These are environment or runtime boundary failures and should not silently degrade into incorrect behavior.

### Convert fragile assumptions into deterministic behavior

Do **not** fail just because:
- `/dev/fd` is unavailable
- `/tmp` is not the expected path string
- symlink creation is unavailable to the current Windows user

Instead:
- use a portable input transport
- use test-owned temp paths
- skip or refactor symlink-sensitive tests explicitly

### External platform limits stay external

If Claude Code itself fails on native Windows because Git Bash cannot be discovered or because of unrelated CLI bugs, this spec treats that as an external prerequisite issue, not plugin behavior the repo must emulate around internally.

## Test Plan

### Runtime-focused tests

1. Add a focused test for Python runtime resolution proving fallback from `python3` to `python`.
2. Add or update a focused test for root traversal that proves stagnation-based termination rather than `/`-only termination.
3. Add or update a focused test for hash fallback proving the repo can still generate a session hash when the first-choice utility is unavailable.
4. Re-run the affected runtime tests for:
   - init-state bootstrap
   - pretool gate logic
   - posttool state sync
   - workflow activation / path classification

### Test infrastructure-focused tests

1. Replace every process-substitution-based JSON assertion in the test suite.
2. Add helper coverage if a new assertion/temp helper is introduced.
3. Replace `/tmp/...`-based test artifacts with `TMP_DIR`-derived paths where the exact Unix path is not the thing under test.
4. Update symlink-sensitive tests so that unsupported Windows conditions become deterministic skips or portable assertions.

### Broad verification

The final plan must define:
- one broad repo test command for macOS
- the same or equivalent command for Windows Git Bash

The preferred outcome is a single broad command such as:

```bash
for t in tests/test_*.sh; do bash "$t"; done
```

If that exact command needs a small wrapper for portability, the wrapper must become the documented one-command entrypoint.

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Compatibility fixes become scattered instead of structural | Medium | High | Centralize runtime-sensitive behaviors into shared helpers and update duplicated logic together |
| Windows support drifts into accidental PowerShell requirements | Low | Medium | Keep the support contract explicitly Git Bash-based |
| Replacing process substitution makes tests harder to read | Low | Low | Prefer simple temp-file helpers over clever abstractions |
| Symlink tests become under-specified after portability changes | Medium | Medium | Preserve the semantic assertion and only relax the filesystem mechanism |
| Hash/Python fallback logic introduces hidden behavior differences on macOS | Low | Medium | Add focused tests for the helper contract and rerun the broad suite |
| Contributors reintroduce fragile shell constructs later | Medium | Medium | Document the compatibility baseline clearly in the spec, plan, and user docs |
