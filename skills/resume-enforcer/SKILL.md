# Resume Enforcer

Use this manual recovery flow when a resumed superpowers workflow is blocked until recovery is explicitly recorded.

## Manual Recovery Workflow

1. Read `.claude/flow_state.json`.
2. If any of `task_plan.md`, `progress.md`, or `findings.md` exist at the project root, read the root-level planning files that exist.
3. Only if none of those root-level planning files exist, read `.planning-with-files/task_plan.md`, `.planning-with-files/progress.md`, and `.planning-with-files/findings.md` when present.
4. If neither planning location exists, continue recovery using state plus git context.
5. Run `git status --short`.
6. Optionally run `git diff --stat` if the working tree summary is not enough.
7. Emit a structured recovery summary with:
   - current phase
   - open task / review state
   - last confirmed progress point
   - next required action
8. After the summary is complete, run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/record-resume-state.sh" completed resume`.

Do not clear the recovery gate before the structured summary has been explicitly recorded.
