#!/bin/bash
set -euo pipefail

write_v1_state() {
  cat > "$1" <<'EOF'
{"current_phase":"brainstorming","brainstorming":{"spec_written":true,"findings_updated":false,"skill_invoked":true},"planning":{"plan_written":false},"tdd":{"tests_verified_fail":[]},"exceptions":{"skip_brainstorming":false,"skip_tdd":false,"skip_review":false,"skip_finishing":false,"user_confirmed":false},"interrupt":{"allowed":false}}
EOF
}

write_v2_state() {
  cat > "$1" <<'EOF'
{"state_version":2,"current_phase":"init","brainstorming":{"question_asked":false,"findings_updated_after_question":false,"spec_written":false,"spec_file":null,"spec_reviewed":false,"user_approved_spec":false},"planning":{"plan_written":false,"plan_file":null},"worktree":{"created":false,"path":null,"baseline_verified":false},"tdd":{"pending_failure_record":false,"last_failed_command":null,"tests_verified_fail":[],"tests_verified_pass":[]},"review":{"tasks":{}},"finishing":{"invoked":false},"exceptions":{"skip_brainstorming":false,"skip_planning":false,"skip_tdd":false,"skip_review":false,"skip_finishing":false,"pending_confirmation_for":null,"reason":null,"user_confirmed":false},"interrupt":{"allowed":false,"reason":null}}
EOF
}

write_unsafe_v1_state() {
  cat > "$1" <<'EOF'
{"current_phase":"planning","brainstorming":"broken","planning":{"plan_written":true},"tdd":{"tests_verified_fail":"bad"}}
EOF
}
