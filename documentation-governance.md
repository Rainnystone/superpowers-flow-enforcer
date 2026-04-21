# Documentation Governance

## What This Document Is For

This document defines documentation lifecycle and loading rules for `superpowers-flow-enforcer`.
It makes active surfaces, archive expectations, naming rules, and read order explicit.
It does not replace `AGENTS.md` or `coding-agent-guide.md`.

## Relationship To Other Docs

- `AGENTS.md` is the active workspace instruction file.
- `coding-agent-guide.md` is the quick routing and first-packet guide.
- `CLAUDE.md` is shipped as part of the plugin repository and is not the active workspace instruction file.
- `README.md` and `README_cn.md` are user-facing plugin docs.
- `docs/superpowers/specs/` and `docs/superpowers/plans/` are the reserved active surfaces for the next workstream, while prior implementation records now live in `archive/2026-04-superpowers-flow-enforcer-implementation/`.

## Active vs Archive Rules

- Active docs and archived docs must stay conceptually separate.
- Archive is not a default execution source.
- Archival is never automatic.
- Before archiving a workstream, ask the human whether it is truly complete.
- Root `task_plan.md`, `progress.md`, and `findings.md` may be reset or replaced only after human-approved archival of the related workstream.

## Active Documentation Surfaces

| Surface | Purpose | Should Not Remain There After Archival |
| --- | --- | --- |
| `AGENTS.md` | Stable workspace execution rules | Temporary task notes or implementation diary |
| `coding-agent-guide.md` | Quick routing and packet entry map | Long architecture writeups or archive inventories |
| `documentation-governance.md` | Lifecycle, loading, and archive rules | Task routing detail better kept in the guide |
| `README.md`, `README_cn.md` | User-facing plugin behavior and install docs | Workspace-only execution rules |
| `task_plan.md`, `progress.md`, `findings.md` | Active root tracking for the current workstream | Completed workstream records after archival |
| `docs/superpowers/specs/` | Active specs for the current workstream when one exists | Human-confirmed completed specs once archived |
| `docs/superpowers/plans/` | Active implementation plans for the current workstream when one exists | Human-confirmed completed plans once archived |

## Key Paths and Document Map

| What | Where |
| --- | --- |
| Active instruction file | `AGENTS.md` |
| Routing guide | `coding-agent-guide.md` |
| Documentation governance | `documentation-governance.md` |
| Plugin behavior docs | `README.md`, `README_cn.md`, `CLAUDE.md` |
| Active specs | `docs/superpowers/specs/` |
| Active plans | `docs/superpowers/plans/` |
| Conditional root tracking | `task_plan.md`, `progress.md`, `findings.md` |
| Current archive root | `archive/2026-04-superpowers-flow-enforcer-implementation/` |

## Archive Structure

- The current archived workstream lives at `archive/2026-04-superpowers-flow-enforcer-implementation/`.
- That container holds related specs, plans, and renamed tracking files for one completed implementation workstream.
- Future archived workstreams should follow the same distinct-container pattern, such as `archive/YYYY-MM-DD-topic/`.
- Do not leave archived snapshots mixed into active root tracking or active spec and plan directories once a deliberate archive pass is performed.

## Naming Rules

### Active Specs and Plans

- Keep the current date-prefixed naming pattern already used in `docs/superpowers/specs/` and `docs/superpowers/plans/`.
- New active docs should stay easy to sort and grep from the CLI.

### Archived Tracking Files

- Archived copies of `task_plan.md`, `progress.md`, and `findings.md` must be renamed to avoid generic collisions.
- Prefer names such as:
  - `archive-task-plan.md`
  - `archive-progress.md`
  - `archive-findings.md`

### Archived Workstream Containers

- Archive folders should be distinguishable by date and topic.
- Prefer names such as `archive/2026-04-15-nhk-bootstrap/`.

## Read Order and Loading Discipline

1. Read `AGENTS.md`, then `coding-agent-guide.md`, then `documentation-governance.md`.
2. Read `README.md` or `README_cn.md` when the task touches documented plugin behavior.
3. Read root tracking files when the task is part of the current active workstream.
4. Read only the specific spec or plan needed for the current topic.
5. Consult archive only when active docs and current tests are insufficient.

Do not load historical plans, broad spec collections, or stale tracking files by default.

## Current Workspace Reality

- `AGENTS.md` is the active instruction file for this workspace.
- `CLAUDE.md` remains in the repo because the repository itself is a Claude Code plugin.
- The previous implementation workstream has been archived under `archive/2026-04-superpowers-flow-enforcer-implementation/`.
- An active workstream is in progress with root `task_plan.md`, `progress.md`, and `findings.md` surfaces.
- Active spec and plan files exist under `docs/superpowers/specs/` and `docs/superpowers/plans/` for the current workstream.

## Transition Rules

1. A workstream reaches an apparent completion point.
2. Ask the human whether the workstream should remain active or move to archive.
3. Only after explicit confirmation:
  - move completed specs and plans into a dedicated archive container
  - archive the related tracking files with renamed filenames
  - reset or replace active root tracking files if a new workstream begins
4. If the human says the work is not complete, leave all active surfaces in place.
