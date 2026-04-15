# Resume Enforcer

Use this manual recovery flow when a resumed superpowers workflow is blocked until recovery is explicitly recorded.

## Manual Recovery Workflow

1. Read `.claude/flow_state.json`.
2. Read `.planning-with-files/task_plan.md`.
3. Read `.planning-with-files/progress.md`.
4. Read `.planning-with-files/findings.md` only when needed to resolve ambiguity or missing context.
5. Run `git status --short`.
6. Optionally run `git diff --stat` if the working tree summary is not enough.
7. Emit a structured recovery summary with:
   - current phase
   - open task / review state
   - last confirmed progress point
   - next required action
8. After the summary is complete, run `bash scripts/record-resume-state.sh completed resume`.

Do not clear the recovery gate before the structured summary has been explicitly recorded.
