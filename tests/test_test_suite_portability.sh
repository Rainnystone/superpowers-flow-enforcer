#!/bin/bash
set -euo pipefail

source scripts/lib/platform_compat.sh

OWNED_FILES=(
  tests/helpers/assert.sh
  tests/test_test_suite_portability.sh
  tests/test_bash_command_gate.sh
  tests/test_bypass_state.sh
  tests/test_agent_task_boundary_gate.sh
  tests/test_stop_gates.sh
  tests/test_brainstorming_findings_flow.sh
  tests/test_posttool_command_gates.sh
  tests/test_pretool_command_gates.sh
  tests/test_worktree_baseline_flow.sh
)

platform_compat_run_python - "${OWNED_FILES[@]}" <<'PY'
import pathlib
import re
import sys

pattern = re.compile(r"<\(|>\(")


def strip_comments_and_strings(line: str) -> str:
    out = []
    i = 0
    in_single = False
    in_double = False

    while i < len(line):
        ch = line[i]

        if ch == "'" and not in_double:
            in_single = not in_single
            i += 1
            continue

        if ch == '"' and not in_single:
            in_double = not in_double
            i += 1
            continue

        if ch == "#" and not in_single and not in_double:
            break

        if not in_single and not in_double:
            out.append(ch)

        i += 1

    return "".join(out)


for target in sys.argv[1:]:
    text = pathlib.Path(target).read_text(encoding="utf-8")
    for lineno, line in enumerate(text.splitlines(), start=1):
        if pattern.search(strip_comments_and_strings(line)):
            sys.stderr.write(
                f"Expected {target} to avoid process substitution in Task 5-owned files\n"
            )
            sys.stderr.write(f"{target}:{lineno}:{line}\n")
            raise SystemExit(1)
PY
