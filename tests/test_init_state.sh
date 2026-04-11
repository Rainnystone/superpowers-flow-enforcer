#!/bin/bash
set -euo pipefail

source tests/helpers/assert.sh
source tests/helpers/state-fixtures.sh

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

assert_fresh_v2_state() {
  local file="$1"
  assert_json_equals "$file" '.state_version' '2'
  assert_json_equals "$file" '.current_phase' '"init"'
  assert_json_equals "$file" '.brainstorming.question_asked' 'false'
  assert_json_equals "$file" '.brainstorming.findings_updated_after_question' 'false'
  assert_json_equals "$file" '.worktree.baseline_verified' 'false'
  assert_json_equals "$file" '.tdd.pending_failure_record' 'false'
  assert_json_equals "$file" '.tdd.last_failed_command' 'null'
}

assert_backup_matches_original() {
  local original="$1" backup="$2"
  cmp -s "$original" "$backup" || {
    echo "Expected backup $backup to match original $original" >&2
    exit 1
  }
}

export CLAUDE_PROJECT_DIR="$TMP_DIR/project"
export CLAUDE_PLUGIN_ROOT="$(pwd)"

mkdir -p "$CLAUDE_PROJECT_DIR/.claude"

cat > "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" <<'EOF'
{
  "current_phase": "brainstorming",
  "brainstorming": {
    "spec_written": true,
    "findings_updated": false,
    "skill_invoked": true,
    "questions_asked": 2,
    "spec_self_reviewed": true
  },
  "planning": {
    "plan_written": false
  },
  "worktree": {
    "created": true,
    "path": "/tmp/worktree",
    "baseline_tests_passed": true
  },
  "tdd": {
    "tests_verified_fail": []
  },
  "finishing": {
    "skill_invoked": true,
    "tests_verified": true,
    "choice_made": true,
    "choice": "merge"
  },
  "exceptions": {
    "skip_brainstorming": false,
    "skip_tdd": false,
    "skip_review": false,
    "skip_finishing": false,
    "user_confirmed": false
  },
  "interrupt": {
    "allowed": false
  }
}
EOF

bash scripts/init-state.sh >/dev/null

assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.state_version' '2'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.brainstorming.spec_written' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.brainstorming.findings_updated_after_question' 'false'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.baseline_verified' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.tdd.pending_failure_record' 'false'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.tdd.last_failed_command' 'null'
assert_json_missing "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.brainstorming.skill_invoked'
assert_json_missing "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.brainstorming.questions_asked'
assert_json_missing "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.brainstorming.spec_self_reviewed'
assert_json_missing "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.baseline_tests_passed'
assert_json_missing "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.finishing.tests_verified'
assert_json_missing "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.finishing.choice_made'
assert_json_missing "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.finishing.choice'

cat > "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" <<'EOF'
{"current_phase":"planning","brainstorming":{"spec_written":true,"findings_updated":false},"planning":{"plan_written":false},"tdd":{"tests_verified_fail":[]}}
EOF

if ! bash scripts/init-state.sh >/tmp/test-init-state.out 2>/tmp/test-init-state.err; then
  echo "Expected init-state.sh to migrate a minimal v1 state with missing optional objects" >&2
  cat /tmp/test-init-state.err >&2
  exit 1
fi

assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.state_version' '2'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.current_phase' '"planning"'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.brainstorming.spec_written' 'true'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.worktree.baseline_verified' 'false'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.tdd.pending_failure_record' 'false'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.tdd.last_failed_command' 'null'
assert_json_missing "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.brainstorming.questions_asked'

rm -rf "$CLAUDE_PROJECT_DIR"
mkdir -p "$CLAUDE_PROJECT_DIR/.claude"

bash scripts/init-state.sh >/dev/null

assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.state_version' '2'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.current_phase' '"init"'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.brainstorming.question_asked' 'false'
assert_json_equals "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.brainstorming.findings_updated_after_question' 'false'
assert_json_missing "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" '.brainstorming.skill_invoked'

printf '{bad json\n' > "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
cp "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" "$TMP_DIR/bad-json.original"
if ! bash scripts/init-state.sh >/tmp/test-init-state.out 2>/tmp/test-init-state.err; then
  echo "Expected init-state.sh to recover from bad JSON" >&2
  cat /tmp/test-init-state.err >&2
  exit 1
fi
assert_file_exists "$CLAUDE_PROJECT_DIR/.claude/flow_state.json.bak"
assert_backup_matches_original "$TMP_DIR/bad-json.original" "$CLAUDE_PROJECT_DIR/.claude/flow_state.json.bak"
assert_fresh_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

write_unsafe_v1_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
cp "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" "$TMP_DIR/unsafe-v1.original"
if ! bash scripts/init-state.sh >/tmp/test-init-state.out 2>/tmp/test-init-state.err; then
  echo "Expected init-state.sh to recover from unsafe v1 state" >&2
  cat /tmp/test-init-state.err >&2
  exit 1
fi
assert_file_exists "$CLAUDE_PROJECT_DIR/.claude/flow_state.json.bak"
assert_backup_matches_original "$TMP_DIR/unsafe-v1.original" "$CLAUDE_PROJECT_DIR/.claude/flow_state.json.bak"
assert_fresh_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

cat > "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" <<'EOF'
{
  "current_phase":"brainstorming",
  "brainstorming":{"spec_written":true,"findings_updated":false,"skill_invoked":true},
  "planning":{"plan_written":false},
  "worktree":"broken",
  "tdd":{"tests_verified_fail":[]},
  "exceptions":{"skip_brainstorming":false,"skip_tdd":false,"skip_review":false,"skip_finishing":false,"user_confirmed":false},
  "interrupt":{"allowed":false}
}
EOF
cp "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" "$TMP_DIR/unsafe-v1-worktree.original"
if ! bash scripts/init-state.sh >/tmp/test-init-state.out 2>/tmp/test-init-state.err; then
  echo "Expected init-state.sh to recover from unsafe v1 worktree scalar" >&2
  cat /tmp/test-init-state.err >&2
  exit 1
fi
assert_file_exists "$CLAUDE_PROJECT_DIR/.claude/flow_state.json.bak"
assert_backup_matches_original "$TMP_DIR/unsafe-v1-worktree.original" "$CLAUDE_PROJECT_DIR/.claude/flow_state.json.bak"
assert_fresh_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

cat > "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" <<'EOF'
{
  "state_version": 2,
  "current_phase": "init",
  "brainstorming": {
    "question_asked": false,
    "findings_updated_after_question": false,
    "spec_written": false,
    "spec_file": null,
    "spec_reviewed": false,
    "user_approved_spec": false
  },
  "planning": {
    "plan_written": false,
    "plan_file": null,
    "execution_mode": null
  },
  "worktree": {
    "created": false,
    "path": null,
    "baseline_verified": false
  },
  "tdd": {
    "current_task": null,
    "current_step": null,
    "test_files_created": [],
    "production_files_written": [],
    "tests_verified_fail": [],
    "tests_verified_pass": []
  },
  "review": {
    "tasks": {}
  },
  "finishing": {
    "invoked": false
  },
  "debugging": "broken",
  "exceptions": {
    "skip_brainstorming": false,
    "skip_planning": false,
    "skip_tdd": false,
    "skip_review": false,
    "skip_finishing": false,
    "pending_confirmation_for": null,
    "reason": null,
    "user_confirmed": false,
    "confirmed_at": null
  },
  "interrupt": {
    "allowed": false,
    "reason": null,
    "keywords_detected": []
  }
}
EOF
cp "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" "$TMP_DIR/unsafe-v2-debugging.original"
if ! bash scripts/init-state.sh >/tmp/test-init-state.out 2>/tmp/test-init-state.err; then
  echo "Expected init-state.sh to recover from unsafe v2 debugging scalar" >&2
  cat /tmp/test-init-state.err >&2
  exit 1
fi
assert_file_exists "$CLAUDE_PROJECT_DIR/.claude/flow_state.json.bak"
assert_backup_matches_original "$TMP_DIR/unsafe-v2-debugging.original" "$CLAUDE_PROJECT_DIR/.claude/flow_state.json.bak"
assert_fresh_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

cat > "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" <<'EOF'
{
  "state_version": 2,
  "current_phase": "init",
  "brainstorming": {
    "question_asked": false,
    "findings_updated_after_question": false,
    "spec_written": false,
    "spec_file": null,
    "spec_reviewed": false,
    "user_approved_spec": false
  },
  "planning": {
    "plan_written": false,
    "plan_file": null,
    "execution_mode": null
  },
  "worktree": {
    "created": false,
    "path": null,
    "baseline_verified": false
  },
  "tdd": {
    "current_task": null,
    "current_step": null,
    "pending_failure_record": "bad",
    "last_failed_command": [],
    "test_files_created": [],
    "production_files_written": [],
    "tests_verified_fail": [],
    "tests_verified_pass": []
  },
  "review": {
    "tasks": {}
  },
  "finishing": {
    "invoked": false
  },
  "debugging": {
    "active": false,
    "phase": null,
    "fixes_attempted": 0,
    "root_cause_found": false
  },
  "exceptions": {
    "skip_brainstorming": false,
    "skip_planning": false,
    "skip_tdd": false,
    "skip_review": false,
    "skip_finishing": false,
    "pending_confirmation_for": null,
    "reason": null,
    "user_confirmed": false,
    "confirmed_at": null
  },
  "interrupt": {
    "allowed": false,
    "reason": null,
    "keywords_detected": []
  }
}
EOF
cp "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" "$TMP_DIR/unsafe-v2-tdd-recording.original"
if ! bash scripts/init-state.sh >/tmp/test-init-state.out 2>/tmp/test-init-state.err; then
  echo "Expected init-state.sh to recover from unsafe v2 tdd recording types" >&2
  cat /tmp/test-init-state.err >&2
  exit 1
fi
assert_file_exists "$CLAUDE_PROJECT_DIR/.claude/flow_state.json.bak"
assert_backup_matches_original "$TMP_DIR/unsafe-v2-tdd-recording.original" "$CLAUDE_PROJECT_DIR/.claude/flow_state.json.bak"
assert_fresh_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

cat > "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" <<'EOF'
{
  "state_version": 2,
  "current_phase": "init",
  "brainstorming": {
    "question_asked": false,
    "findings_updated_after_question": false,
    "spec_written": false,
    "spec_file": null,
    "spec_reviewed": false,
    "user_approved_spec": false
  },
  "planning": {
    "plan_written": false,
    "plan_file": null,
    "execution_mode": null
  },
  "worktree": {
    "created": false,
    "path": null,
    "baseline_verified": false
  },
  "tdd": {
    "current_task": null,
    "current_step": null,
    "test_files_created": [],
    "production_files_written": [],
    "tests_verified_fail": [],
    "tests_verified_pass": []
  },
  "review": {
    "tasks": {}
  },
  "finishing": {
    "invoked": false
  },
  "debugging": {
    "active": false,
    "phase": null,
    "fixes_attempted": 0,
    "root_cause_found": false
  },
  "exceptions": {
    "skip_brainstorming": false,
    "skip_planning": false,
    "skip_tdd": false,
    "skip_review": false,
    "skip_finishing": false,
    "pending_confirmation_for": null,
    "reason": null,
    "user_confirmed": false,
    "confirmed_at": null
  },
  "interrupt": {
    "allowed": false,
    "reason": null,
    "keywords_detected": "bad"
  }
}
EOF
cp "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" "$TMP_DIR/unsafe-v2-interrupt.original"
if ! bash scripts/init-state.sh >/tmp/test-init-state.out 2>/tmp/test-init-state.err; then
  echo "Expected init-state.sh to recover from unsafe v2 interrupt scalar" >&2
  cat /tmp/test-init-state.err >&2
  exit 1
fi
assert_file_exists "$CLAUDE_PROJECT_DIR/.claude/flow_state.json.bak"
assert_backup_matches_original "$TMP_DIR/unsafe-v2-interrupt.original" "$CLAUDE_PROJECT_DIR/.claude/flow_state.json.bak"
assert_fresh_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

cat > "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" <<'EOF'
{
  "state_version": 2,
  "current_phase": "planning",
  "brainstorming": "broken",
  "planning": {
    "plan_written": true
  },
  "tdd": {
    "tests_verified_fail": "bad"
  }
}
EOF
if ! bash scripts/init-state.sh >/tmp/test-init-state.out 2>/tmp/test-init-state.err; then
  echo "Expected init-state.sh to recover from unsafe v2 structure" >&2
  cat /tmp/test-init-state.err >&2
  exit 1
fi
assert_file_exists "$CLAUDE_PROJECT_DIR/.claude/flow_state.json.bak"
assert_fresh_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

cat > "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" <<'EOF'
{
  "state_version": 2,
  "current_phase": "archived",
  "brainstorming": {
    "question_asked": false,
    "findings_updated_after_question": false,
    "spec_written": false,
    "spec_file": null,
    "spec_reviewed": false,
    "user_approved_spec": false
  },
  "planning": {
    "plan_written": false,
    "plan_file": null,
    "execution_mode": null
  },
  "worktree": {
    "created": false,
    "path": null,
    "baseline_verified": false
  },
  "tdd": {
    "current_task": null,
    "current_step": null,
    "test_files_created": [],
    "production_files_written": [],
    "tests_verified_fail": [],
    "tests_verified_pass": []
  },
  "review": {
    "tasks": {}
  },
  "finishing": {
    "invoked": false
  },
  "exceptions": {
    "skip_brainstorming": false,
    "skip_planning": false,
    "skip_tdd": false,
    "skip_review": false,
    "skip_finishing": false,
    "pending_confirmation_for": null,
    "reason": null,
    "user_confirmed": false,
    "confirmed_at": null
  },
  "interrupt": {
    "allowed": false,
    "reason": null,
    "keywords_detected": []
  }
}
EOF
if ! bash scripts/init-state.sh >/tmp/test-init-state.out 2>/tmp/test-init-state.err; then
  echo "Expected init-state.sh to recover from contradictory phase state" >&2
  cat /tmp/test-init-state.err >&2
  exit 1
fi
assert_file_exists "$CLAUDE_PROJECT_DIR/.claude/flow_state.json.bak"
assert_fresh_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"

cat > "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" <<'EOF'
{"state_version":"two","current_phase":"init"}
EOF
if bash scripts/init-state.sh >/tmp/test-init-state.out 2>/tmp/test-init-state.err; then
  echo "Expected init-state.sh to fail for non-numeric state_version" >&2
  exit 1
fi
assert_file_contains /tmp/test-init-state.err "unsupported"

cat > "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" <<'EOF'
{"state_version":3,"current_phase":"init"}
EOF
if bash scripts/init-state.sh >/tmp/test-init-state.out 2>/tmp/test-init-state.err; then
  echo "Expected init-state.sh to fail for unknown higher state_version" >&2
  exit 1
fi
assert_file_contains /tmp/test-init-state.err "unsupported"

write_v2_state "$CLAUDE_PROJECT_DIR/.claude/flow_state.json"
cp "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" "$CLAUDE_PROJECT_DIR/.claude/flow_state.before.json"
if bash scripts/migrate-state.sh "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" >/tmp/test-migrate-state.out 2>/tmp/test-migrate-state.err; then
  echo "Expected migrate-state.sh to reject v2 state" >&2
  exit 1
fi
assert_file_contains /tmp/test-migrate-state.err "v1"
cmp -s \
  "$CLAUDE_PROJECT_DIR/.claude/flow_state.json" \
  "$CLAUDE_PROJECT_DIR/.claude/flow_state.before.json" || {
  echo "Expected v2 state to remain unchanged after rejected migration" >&2
  exit 1
}
