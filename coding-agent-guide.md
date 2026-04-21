# Coding Agent Guide

## What This Guide Is For

This guide helps a coding agent route work quickly in `superpowers-flow-enforcer`.
Read it after `AGENTS.md` and before opening large historical specs or plans.
It covers task routing, first packet landing zones, and default verification.

## Relationship To Other Docs

- `AGENTS.md` is the active workspace instruction file and defines stable execution and verification rules.
- `documentation-governance.md` defines active versus archive rules, loading discipline, and tracking-file lifecycle.
- `CLAUDE.md` is part of the plugin payload and product documentation, not the active workspace instruction surface.
- This plugin is a strong adaptation layer on top of two upstream skills already installed in the environment: `using-superpowers` and `planning-with-files-zh`.
- For workflow, phase, tracking-file, resume, review, or verification behavior, treat those two skills as upstream execution sources rather than treating this repo as self-defining.
- Archived design and implementation history for the previous workstream now lives under `archive/2026-04-superpowers-flow-enforcer-implementation/`.

## First Read Order

1. `AGENTS.md`
2. `coding-agent-guide.md`
3. `documentation-governance.md`
4. The relevant upstream skill docs for `using-superpowers` and `planning-with-files-zh` when the task touches workflow semantics
5. `README.md` or `README_cn.md`
6. `hooks/hooks.json`
7. The specific scripts and tests for the affected behavior
8. Root `task_plan.md`, `progress.md`, and `findings.md` when the task touches the current active workstream

## Current Execution State

- The active instruction file is `AGENTS.md`.
- The repository does not own the full workflow contract by itself; it supplements `using-superpowers` and `planning-with-files-zh`.
- An active workstream is in progress: `docs/superpowers/specs/fix-p0-p1-compatibility.md` and `docs/superpowers/plans/2026-04-21-fix-p0-p1-p2-p3-compatibility.md` are the current active spec and plan surfaces.
- Root `task_plan.md`, `progress.md`, and `findings.md` are active for the current workstream.
- Historical implementation context for the archived workstream now lives under `archive/2026-04-superpowers-flow-enforcer-implementation/`.

## Task Routing

| Task Type | Read Here First |
| --- | --- |
| Hook event mismatch or missing hook | `hooks/hooks.json`, `tests/test_hooks_official_events.sh` |
| Workflow-phase, review, finishing, or verification semantic drift | Upstream `using-superpowers` skill doc first, then `README.md`, `CLAUDE.md`, and the enforcing scripts/tests |
| Tracking-file lifecycle, recovery, or active-root-file behavior drift | Upstream `planning-with-files-zh` skill doc first, then root tracking files and resume-related scripts/tests |
| Historical implementation context for prior work | `archive/2026-04-superpowers-flow-enforcer-implementation/`, then the current scripts/tests the change would affect |
| State bootstrap or migration bug | `templates/flow_state.json.tmpl`, `scripts/init-state.sh`, `scripts/migrate-state.sh`, `tests/test_init_state.sh` |
| PreTool gating bug for Edit, Write, AskUserQuestion, or Agent | `scripts/check-pretool-gates.sh`, related `tests/test_pretool_command_gates.sh` or focused shell tests |
| Bash gate or command classification bug | `scripts/check-bash-command-gate.sh`, `scripts/check-bash-command-gate-node.cjs`, `tests/test_bash_command_gate.sh` |
| PostTool, TaskCompleted, Stop, or resume bug | `scripts/sync-post-tool-state.sh`, `scripts/check-task-completed.sh`, `scripts/check-stop-review-gate.sh`, `tests/test_stop_gates.sh`, `tests/test_posttool_command_gates.sh`, `tests/test_resume_recovery_flow.sh` |
| README or workflow-doc drift | `AGENTS.md`, `documentation-governance.md`, `README.md`, then the matching scripts/tests |
| Skill-specific plugin surface | `skills/`, then the hook or script that consumes that skill state |

## High-Frequency Packet Routing

| Symptom / Goal | First Packet Owned Files | Default Verification | Parallel Hint |
| --- | --- | --- | --- |
| Hook wiring does not match documented event flow | `hooks/hooks.json`, `tests/test_hooks_official_events.sh` | `bash tests/test_hooks_official_events.sh` | Usually serial with any script change touching the same event |
| State field missing or drifted | `templates/flow_state.json.tmpl`, `scripts/init-state.sh`, `scripts/migrate-state.sh`, `tests/test_init_state.sh` | `bash tests/test_init_state.sh` | Keep serial if another packet also edits state schema |
| Write gate blocks or allows at the wrong time | `scripts/check-pretool-gates.sh` plus the narrowest affected test | Focused gate test under `tests/` | Parallel-safe only if no shared test file |
| Stop or completion verification is wrong | `scripts/check-stop-review-gate.sh`, `scripts/check-task-completed.sh`, focused tests | `bash tests/test_posttool_command_gates.sh` | Usually serial with posttool state changes |
| Resume recovery is stale or broken | `scripts/record-resume-state.sh`, `scripts/sync-post-tool-state.sh`, `tests/test_resume_recovery_flow.sh` | `bash tests/test_resume_recovery_flow.sh` | Serial with any task-flow state refactor |

## Implementation Packet Checklist

A valid packet in this repo should declare:
- `Packet Goal`
- `Owned Files`
- `Verification`
- `Parallel?`
- `Reviewer Focus`

Prefer one hook surface or one state-transition path per packet.
If a packet changes state semantics, it should normally own template, bootstrap or migration, and the narrowest proving test together.

## Code Entry Map

| Area | Open First |
| --- | --- |
| Plugin manifest and install identity | `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` |
| Hook routing | `hooks/hooks.json` |
| State schema and lifecycle | `templates/flow_state.json.tmpl`, `scripts/init-state.sh`, `scripts/migrate-state.sh` |
| Enforcement logic | `scripts/check-pretool-gates.sh`, `scripts/check-bash-command-gate.sh`, `scripts/check-task-completed.sh`, `scripts/check-stop-review-gate.sh` |
| State synchronization and recorders | `scripts/sync-user-prompt-state.sh`, `scripts/sync-post-tool-state.sh`, `scripts/record-*.sh`, `scripts/lib/` |
| Verification roots | `tests/`, `tests/helpers/`, `tests/fixtures/` |
| Vendored runtime | `vendor/bash-traverse/` |

## Key Architectural Boundaries

| Boundary | Rule |
| --- | --- |
| Upstream skills vs plugin enforcement | `using-superpowers` and `planning-with-files-zh` define upstream workflow expectations; this repo adapts and enforces them for Claude Code hooks |
| Hook declarations vs policy logic | `hooks/hooks.json` routes events; scripts own behavior |
| Gate logic vs state recording | Gate scripts decide block or allow; sync and record scripts persist state |
| Template vs migration | New fields must be reflected in both the template and migration path |
| Repo docs vs plugin docs | `AGENTS.md` governs the workspace; `CLAUDE.md` describes the plugin behavior |

## Default Verification

- Minimum for behavior changes: run the narrowest affected shell test first.
- Common targeted commands:
  - `bash tests/test_init_state.sh`
  - `bash tests/test_hooks_official_events.sh`
  - `bash tests/test_pretool_command_gates.sh`
  - `bash tests/test_posttool_command_gates.sh`
  - `bash tests/test_workflow_activation.sh`
  - `bash tests/test_resume_recovery_flow.sh`
- For syntax or manifest edits, also run:
  - `bash -n <script>`
  - `jq empty hooks/hooks.json`
  - `jq empty .claude-plugin/plugin.json`

## Anti-Detour Advice

- Before changing any workflow rule, re-read the relevant upstream skill doc instead of inferring intent from this repo alone.
- Do not let plugin behavior drift away from `using-superpowers` or `planning-with-files-zh` just because the current tests happen to pass.
- Do not start from README prose when the question is really about enforced behavior; inspect the matching script and its proving test first.
- Do not change `vendor/bash-traverse/` unless the issue is genuinely in the vendored runtime boundary.
- Do not broaden packets across multiple hook surfaces just because the same state file is involved.
- Load only the spec or plan that matches the current topic and date instead of reading the entire `docs/superpowers/` tree.
