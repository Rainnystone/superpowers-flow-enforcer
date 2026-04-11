#!/bin/bash
set -euo pipefail

MODE="${1:-}"

if [ "$MODE" = "--check-safe" ]; then
  STATE_FILE="${2:?state file required}"
  jq -e '
    (.current_phase // "") as $phase
    | (["init", "brainstorming", "planning", "worktree", "tdd", "review", "finishing", "debugging"] | index($phase) != null or $phase == "")
    and (
      if ((.state_version // 1) >= 2) then
        (.brainstorming | type) == "object"
        and (.planning | type) == "object"
        and (.worktree | type) == "object"
        and (.tdd | type) == "object"
        and (.review | type) == "object"
        and (.finishing | type) == "object"
        and (.debugging | type) == "object"
        and (.exceptions | type) == "object"
        and (.interrupt | type) == "object"
        and (.review.tasks | type) == "object"
        and (.tdd.test_files_created | type) == "array"
        and (.tdd.production_files_written | type) == "array"
        and ((.tdd.pending_failure_record // false) | type) == "boolean"
        and (
          ((.tdd.last_failed_command // null) | type) == "string"
          or ((.tdd.last_failed_command // null) | type) == "null"
        )
        and (.tdd.tests_verified_fail | type) == "array"
        and (.tdd.tests_verified_pass | type) == "array"
        and (.interrupt.keywords_detected | type) == "array"
      else
        (.brainstorming | type) == "object"
        and (.planning | type) == "object"
        and (.worktree == null or (.worktree | type) == "object")
        and (.tdd | type) == "object"
        and (.exceptions == null or (.exceptions | type) == "object")
        and (.interrupt == null or (.interrupt | type) == "object")
        and ((.tdd.tests_verified_fail // []) | type) == "array"
      end
    )
  ' "$STATE_FILE" >/dev/null
  exit $?
fi

STATE_FILE="${1:?state file required}"

if ! jq empty "$STATE_FILE" >/dev/null 2>&1; then
  echo "invalid flow state JSON: $STATE_FILE" >&2
  exit 1
fi

VERSION="$(jq -r '.state_version // 1' "$STATE_FILE")"

if ! [[ "$VERSION" =~ ^[0-9]+$ ]]; then
  echo "migrate-state.sh only accepts v1 input" >&2
  exit 1
fi

if [ "$VERSION" -ne 1 ]; then
  echo "migrate-state.sh only accepts v1 input" >&2
  exit 1
fi

TMP_FILE="${STATE_FILE}.tmp"

jq '
  {
    "state_version": 2,
    "current_phase": (.current_phase // "init"),
    "session_id": (.session_id // ""),
    "project_dir": (.project_dir // ""),
    "initialized_at": (.initialized_at // ""),
    "brainstorming": {
      "question_asked": false,
      "findings_updated_after_question": (.brainstorming.findings_updated // false),
      "spec_written": (.brainstorming.spec_written // false),
      "spec_file": (.brainstorming.spec_file // null),
      "spec_reviewed": false,
      "user_approved_spec": (.brainstorming.user_approved_spec // false)
    },
    "planning": {
      "plan_written": (.planning.plan_written // false),
      "plan_file": (.planning.plan_file // null),
      "execution_mode": (.planning.execution_mode // null)
    },
    "worktree": {
      "created": (.worktree.created // false),
      "path": (.worktree.path // null),
      "baseline_verified": (.worktree.baseline_verified // .worktree.baseline_tests_passed // false)
    },
    "tdd": {
      "current_task": (.tdd.current_task // null),
      "current_step": (.tdd.current_step // null),
      "pending_failure_record": (
        if ((.tdd.pending_failure_record // false) | type) == "boolean"
        then (.tdd.pending_failure_record // false)
        else false
        end
      ),
      "last_failed_command": (
        if ((.tdd.last_failed_command // null) | type) == "string"
          or ((.tdd.last_failed_command // null) | type) == "null"
        then (.tdd.last_failed_command // null)
        else null
        end
      ),
      "test_files_created": (.tdd.test_files_created // []),
      "production_files_written": (.tdd.production_files_written // []),
      "tests_verified_fail": (.tdd.tests_verified_fail // []),
      "tests_verified_pass": (.tdd.tests_verified_pass // [])
    },
    "review": {
      "tasks": (.review.tasks // {})
    },
    "finishing": {
      "invoked": false
    },
    "debugging": {
      "active": (.debugging.active // false),
      "phase": (.debugging.phase // null),
      "fixes_attempted": (.debugging.fixes_attempted // 0),
      "root_cause_found": (.debugging.root_cause_found // false)
    },
    "exceptions": {
      "skip_brainstorming": (.exceptions.skip_brainstorming // false),
      "skip_planning": (.exceptions.skip_planning // false),
      "skip_tdd": (.exceptions.skip_tdd // false),
      "skip_review": (.exceptions.skip_review // false),
      "skip_finishing": (.exceptions.skip_finishing // false),
      "pending_confirmation_for": null,
      "reason": (.exceptions.reason // null),
      "user_confirmed": (.exceptions.user_confirmed // false),
      "confirmed_at": (.exceptions.confirmed_at // null)
    },
    "interrupt": {
      "allowed": (.interrupt.allowed // false),
      "reason": (.interrupt.reason // null),
      "keywords_detected": (.interrupt.keywords_detected // [])
    }
  }
' "$STATE_FILE" > "$TMP_FILE"

mv "$TMP_FILE" "$STATE_FILE"
