#!/bin/bash
set -euo pipefail

write_v1_state() {
  cat > "$1" <<'EOF'
{"current_phase":"brainstorming","brainstorming":{"spec_written":true,"findings_updated":false,"skill_invoked":true},"planning":{"plan_written":false},"tdd":{"tests_verified_fail":[]},"exceptions":{"skip_brainstorming":false,"skip_tdd":false,"skip_review":false,"skip_finishing":false,"user_confirmed":false},"interrupt":{"allowed":false}}
EOF
}

write_v2_state() {
  cat > "$1" <<'EOF'
{"state_version":2,"current_phase":"init","brainstorming":{"question_asked":false,"findings_updated_after_question":false,"spec_written":false,"spec_file":null,"spec_reviewed":false,"user_approved_spec":false},"planning":{"plan_written":false,"plan_file":null,"execution_mode":null},"worktree":{"created":false,"path":null,"baseline_verified":false},"workflow":{"active":false,"activated_by":null,"activated_at":null},"tdd":{"current_task":null,"current_step":null,"pending_failure_record":false,"last_failed_command":null,"test_files_created":[],"production_files_written":[],"tests_verified_fail":[],"tests_verified_pass":[]},"review":{"tasks":{}},"finishing":{"invoked":false},"debugging":{"active":false,"phase":null,"fixes_attempted":0,"root_cause_found":false},"exceptions":{"skip_brainstorming":false,"skip_planning":false,"skip_tdd":false,"skip_review":false,"skip_finishing":false,"pending_confirmation_for":null,"reason":null,"user_confirmed":false,"confirmed_at":null},"interrupt":{"allowed":false,"reason":null,"keywords_detected":[]}}
EOF
}

write_v2_state_without_workflow() {
  write_v2_state "$1"
  jq 'del(.workflow)' "$1" > "$1.tmp"
  mv "$1.tmp" "$1"
}

write_v2_state_with_broken_workflow() {
  write_v2_state "$1"
  jq '.workflow = "broken"' "$1" > "$1.tmp"
  mv "$1.tmp" "$1"
}

write_v2_state_with_partial_workflow() {
  write_v2_state "$1"
  jq 'del(.workflow.activated_by, .workflow.activated_at)' "$1" > "$1.tmp"
  mv "$1.tmp" "$1"
}

write_v2_state_with_invalid_workflow_types() {
  write_v2_state "$1"
  jq '.workflow = {"active":"yes","activated_by":[],"activated_at":{}}' "$1" > "$1.tmp"
  mv "$1.tmp" "$1"
}

write_unsafe_v1_state() {
  cat > "$1" <<'EOF'
{"current_phase":"planning","brainstorming":"broken","planning":{"plan_written":true},"tdd":{"tests_verified_fail":"bad"}}
EOF
}
