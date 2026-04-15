#!/bin/bash
set -euo pipefail

source tests/helpers/assert.sh
source tests/helpers/state-fixtures.sh
source scripts/lib/task_flow_packets.sh

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PRETOOL_FIXTURE="tests/fixtures/pretool_agent_dispatch.json"
TASKCREATED_FIXTURE="tests/fixtures/taskcreated_agent_dispatch.json"
POSTTOOL_FIXTURE="tests/fixtures/posttool_agent_dispatch.json"

assert_agent_fixture_shape() {
  local file="$1"
  local hook_event_name="$2"

  assert_json_equals "$file" '.hook_event_name' "\"$hook_event_name\""
  assert_json_equals "$file" '.tool_name' '"Agent"'

  jq -e '.tool_input.description | type == "string"' "$file" >/dev/null
  jq -e '.tool_input.prompt | type == "string"' "$file" >/dev/null
  jq -e '.tool_input.subagent_type | type == "string"' "$file" >/dev/null
}

assert_taskcreated_fixture_minimum_contract() {
  local file="$1"
  local expected_task_id="$2"
  local expected_task_subject="$3"

  assert_json_equals "$file" '.hook_event_name' '"TaskCreated"'
  assert_json_equals "$file" '.task_id' "\"$expected_task_id\""
  assert_json_equals "$file" '.task_subject' "\"$expected_task_subject\""
  jq -e 'has("tool_input") | not' "$file" >/dev/null
}

assert_taskcreated_fixture_capture() {
  local file="$1"

  assert_json_equals "$file" '.task_description' '"This task note mentions SPFE_TASK_ID=task-001 and SPFE_PACKET_ROLE=implementer inside prose, but there is no Agent prompt prefix here."'
  assert_json_equals "$file" '.teammate_name' '"Claude Code"'
  assert_json_equals "$file" '.team_name' '"Superpowers"'
}

assert_extracts_metadata() {
  local file="$1"
  local expected_task_id="$2"
  local expected_role="$3"
  local output

  output="$(task_flow_packets_extract_packet_metadata < "$file")"
  assert_json_equals <(printf '%s' "$output") '.task_id' "\"$expected_task_id\""
  assert_json_equals <(printf '%s' "$output") '.role' "\"$expected_role\""
}

assert_extract_fails() {
  local file="$1"
  local status=0
  local output=""

  set +e
  output="$(task_flow_packets_extract_packet_metadata < "$file")"
  status=$?
  set -e

  [ "$status" -ne 0 ] || {
    echo "Expected extraction to fail for $file" >&2
    exit 1
  }
  [ -z "$output" ] || {
    echo "Expected extraction failure for $file to keep stdout empty, got: $output" >&2
    exit 1
  }
}

assert_selected_success_event() {
  local taskcreated_file="$1"
  local posttool_file="$2"
  local expected="$3"
  local selected

  selected="$(task_flow_packets_select_success_event "$taskcreated_file" "$posttool_file")"
  [ "$selected" = "$expected" ] || {
    echo "Expected success-event selection to return $expected, got $selected" >&2
    exit 1
  }
}

assert_selects_failure() {
  local taskcreated_file="$1"
  local fallback_file="$2"
  local status=0
  local output=""

  set +e
  output="$(task_flow_packets_select_success_event "$taskcreated_file" "$fallback_file")"
  status=$?
  set -e

  [ "$status" -ne 0 ] || {
    echo "Expected success-event selection to fail for $taskcreated_file and $fallback_file" >&2
    exit 1
  }
  [ -z "$output" ] || {
    echo "Expected selection failure to keep stdout empty, got: $output" >&2
    exit 1
  }
}

assert_agent_fixture_shape "$PRETOOL_FIXTURE" "PreToolUse"
assert_agent_fixture_shape "$POSTTOOL_FIXTURE" "PostToolUse"
assert_taskcreated_fixture_minimum_contract "$TASKCREATED_FIXTURE" "task-001" "Task 1: Pin Delegation Payload Contract"
assert_taskcreated_fixture_capture "$TASKCREATED_FIXTURE"

minimal_taskcreated_file="$TMP_DIR/taskcreated_minimum.json"
jq -n '{
  hook_event_name:"TaskCreated",
  task_id:"task-minimal",
  task_subject:"Minimal TaskCreated schema"
}' > "$minimal_taskcreated_file"
assert_taskcreated_fixture_minimum_contract "$minimal_taskcreated_file" "task-minimal" "Minimal TaskCreated schema"

assert_extracts_metadata "$PRETOOL_FIXTURE" "task-001" "implementer"
assert_extracts_metadata "$POSTTOOL_FIXTURE" "task-001" "code-reviewer"

misplaced_prompt_file="$TMP_DIR/misplaced_prompt.json"
jq -n '{
  hook_event_name:"PreToolUse",
  tool_name:"Agent",
  tool_input:{
    description:"prompt metadata is misplaced",
    prompt:"Start of the prompt.\n\nSPFE_TASK_ID=task-misplaced\nSPFE_PACKET_ROLE=spec-reviewer\n",
    subagent_type:"general"
  }
}' > "$misplaced_prompt_file"
assert_extract_fails "$misplaced_prompt_file"

missing_prefix_file="$TMP_DIR/missing_prefix.json"
jq -n '{
  hook_event_name:"PreToolUse",
  tool_name:"Agent",
  tool_input:{
    description:"missing packet metadata",
    prompt:"Implement the task without a prefix.",
    subagent_type:"general"
  }
}' > "$missing_prefix_file"
assert_extract_fails "$missing_prefix_file"

assert_selected_success_event "$TASKCREATED_FIXTURE" "$POSTTOOL_FIXTURE" "PostToolUse"
assert_selects_failure "$TASKCREATED_FIXTURE" "$PRETOOL_FIXTURE"

taskcreated_clean_metadata_file="$TMP_DIR/taskcreated_clean_metadata.json"
jq -n '{
  hook_event_name:"TaskCreated",
  task_id:"task-clean",
  task_subject:"TaskCreated future metadata candidate",
  task_description:"SPFE_TASK_ID=task-clean\nSPFE_PACKET_ROLE=spec-reviewer\n\nReview the task using the TaskCreated contract.",
  teammate_name:"Claude Code",
  team_name:"Superpowers"
}' > "$taskcreated_clean_metadata_file"
assert_selected_success_event "$taskcreated_clean_metadata_file" "$POSTTOOL_FIXTURE" "TaskCreated"

taskcreated_agent_shape_file="$TMP_DIR/taskcreated_agent_shape.json"
jq -n '{
  hook_event_name:"TaskCreated",
  task_id:"task-777",
  task_subject:"Synthetic taskcreated payload",
  task_description:"SPFE_TASK_ID=task-777\nSPFE_PACKET_ROLE=spec-reviewer\n\nThis appears inside prose and must not be treated as packet metadata.",
  tool_name:"Agent",
  tool_input:{
    description:"synthetic taskcreated packet",
    prompt:"SPFE_TASK_ID=task-777\nSPFE_PACKET_ROLE=spec-reviewer\n\nReview the task.",
    subagent_type:"general"
  }
}' > "$taskcreated_agent_shape_file"
assert_extract_fails "$taskcreated_agent_shape_file"
assert_selected_success_event "$taskcreated_agent_shape_file" "$POSTTOOL_FIXTURE" "PostToolUse"

PROJECT_DIR="$TMP_DIR/project"
STATE_FILE="$PROJECT_DIR/.claude/flow_state.json"
mkdir -p "$PROJECT_DIR/.claude"
export CLAUDE_PROJECT_DIR="$PROJECT_DIR"
export CLAUDE_PLUGIN_ROOT="$(pwd)"

assert_pretool_deny() {
  local output="$1"
  local reason_fragment="$2"
  [ -n "$output" ] || {
    echo "Expected PreToolUse command hook to deny, got empty output" >&2
    exit 1
  }
  assert_json_equals <(printf '%s' "$output") '.hookSpecificOutput.hookEventName' '"PreToolUse"'
  assert_json_equals <(printf '%s' "$output") '.hookSpecificOutput.permissionDecision' '"deny"'
  jq -e --arg frag "$reason_fragment" '.hookSpecificOutput.permissionDecisionReason | contains($frag)' <(printf '%s' "$output") >/dev/null 2>&1 || {
    echo "Expected deny reason to contain: $reason_fragment" >&2
    exit 1
  }
}

assert_pretool_allow() {
  local output="$1"
  [ -z "$output" ] || {
    echo "Expected PreToolUse command hook to allow with empty output, got: $output" >&2
    exit 1
  }
}

run_agent_gate() {
  local prompt="$1"
  jq -n --arg prompt "$prompt" '{
    hook_event_name:"PreToolUse",
    tool_name:"Agent",
    tool_input:{
      description:"Task-boundary dispatch",
      prompt:$prompt,
      subagent_type:"general"
    }
  }' | bash scripts/check-pretool-gates.sh
}

assert_posttool_allow() {
  local output="$1"
  [ -z "$output" ] || {
    echo "Expected PostToolUse sync hook to allow with empty output, got: $output" >&2
    exit 1
  }
}

run_posttool_agent_dispatch() {
  local task_id="$1"
  local role="$2"
  jq -n --arg task_id "$task_id" --arg role "$role" '{
    hook_event_name:"PostToolUse",
    tool_name:"Agent",
    tool_input:{
      description:"Task-boundary dispatch",
      prompt:("SPFE_TASK_ID=" + $task_id + "\nSPFE_PACKET_ROLE=" + $role + "\n\nDispatch packet."),
      subagent_type:"general"
    }
  }' | bash scripts/sync-post-tool-state.sh
}

write_v2_state "$STATE_FILE"
allow_output="$(run_agent_gate 'Implement without metadata prefix.')"
assert_pretool_allow "$allow_output"

jq '.workflow.active = true' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"
allow_output="$(run_agent_gate 'Implement without metadata prefix.')"
assert_pretool_allow "$allow_output"

jq '.workflow.active = true | .worktree.created = true' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"
allow_output="$(run_agent_gate 'Implement without metadata prefix.')"
assert_pretool_allow "$allow_output"

write_v2_state "$STATE_FILE"
jq '
  .workflow.active = true
  | .resume.recovery_required = true
  | .worktree.created = true
  | .worktree.baseline_verified = true
  | .task_flow.active_task_id = "task-recovery-open"
  | .review.tasks["task-recovery-open"] = {spec_review_passed:false, code_review_passed:false}
' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"
deny_output="$(run_agent_gate 'Implement without metadata prefix.')"
assert_pretool_deny "$deny_output" '/superpowers-flow-enforcer:resume-enforcer'

write_v2_state "$STATE_FILE"
jq '
  .workflow.active = true
  | .worktree.created = true
  | .worktree.baseline_verified = true
' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"
deny_output="$(run_agent_gate 'Implement without metadata prefix.')"
assert_pretool_deny "$deny_output" 'SPFE_TASK_ID'
assert_pretool_deny "$deny_output" 'SPFE_PACKET_ROLE'

# reviewer packets are invalid when no active task exists
deny_output="$(run_agent_gate $'SPFE_TASK_ID=task-without-active\nSPFE_PACKET_ROLE=spec-reviewer\n\nSpec review without active task.')"
assert_pretool_deny "$deny_output" 'no active task'
deny_output="$(run_agent_gate $'SPFE_TASK_ID=task-without-active\nSPFE_PACKET_ROLE=code-reviewer\n\nCode review without active task.')"
assert_pretool_deny "$deny_output" 'no active task'

write_v2_state "$STATE_FILE"
jq '.task_flow.active_task_id = "task-open-1"' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"
deny_output="$(run_agent_gate 'Implement without metadata prefix.')"
assert_pretool_deny "$deny_output" 'SPFE_TASK_ID'

write_v2_state "$STATE_FILE"
jq '
  .workflow.active = true
  | .worktree.created = true
  | .worktree.baseline_verified = true
  | .task_flow.active_task_id = "task-open-1"
  | .review.tasks["task-open-1"] = {spec_review_passed:false, code_review_passed:true}
' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"
deny_output="$(run_agent_gate $'SPFE_TASK_ID=task-open-2\nSPFE_PACKET_ROLE=implementer\n\nImplement next task.')"
assert_pretool_deny "$deny_output" 'task-open-1'
assert_pretool_deny "$deny_output" 'finish current review loop first'

allow_output="$(run_agent_gate $'SPFE_TASK_ID=task-open-1\nSPFE_PACKET_ROLE=implementer\n\nContinue same task fix loop.')"
assert_pretool_allow "$allow_output"

jq '.review.tasks["task-open-1"] = {spec_review_passed:true, code_review_passed:true}' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"
allow_output="$(run_agent_gate $'SPFE_TASK_ID=task-open-2\nSPFE_PACKET_ROLE=implementer\n\nImplement next task.')"
assert_pretool_allow "$allow_output"

write_v2_state "$STATE_FILE"
jq '
  .workflow.active = false
  | .worktree.created = false
  | .worktree.baseline_verified = false
  | .task_flow.active_task_id = "task-open-rollback"
  | .review.tasks["task-open-rollback"] = {spec_review_passed:true, code_review_passed:false}
' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"
deny_output="$(run_agent_gate $'SPFE_TASK_ID=task-next\nSPFE_PACKET_ROLE=implementer\n\nImplement next task.')"
assert_pretool_deny "$deny_output" 'task-open-rollback'
assert_pretool_deny "$deny_output" 'finish current review loop first'

write_v2_state "$STATE_FILE"
jq '
  .workflow.active = true
  | .worktree.created = true
  | .worktree.baseline_verified = true
  | .task_flow.active_task_id = "task-review-open"
  | .review.tasks["task-review-open"] = {spec_review_passed:false, code_review_passed:false}
' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"

# 1) generic reviewer is denied
deny_output="$(run_agent_gate $'SPFE_TASK_ID=task-review-open\nSPFE_PACKET_ROLE=reviewer\n\nGeneric review.')"
assert_pretool_deny "$deny_output" 'task-review-open'
assert_pretool_deny "$deny_output" 'spec-reviewer'
assert_pretool_deny "$deny_output" 'code-reviewer'
assert_pretool_deny "$deny_output" 'finish current review loop first'

# 2) combined reviewer role is denied
deny_output="$(run_agent_gate $'SPFE_TASK_ID=task-review-open\nSPFE_PACKET_ROLE=spec-reviewer+code-reviewer\n\nCombined review.')"
assert_pretool_deny "$deny_output" 'task-review-open'
assert_pretool_deny "$deny_output" 'finish current review loop first'

# 3) code-reviewer before spec pass is denied
deny_output="$(run_agent_gate $'SPFE_TASK_ID=task-review-open\nSPFE_PACKET_ROLE=code-reviewer\n\nCode review before spec pass.')"
assert_pretool_deny "$deny_output" 'task-review-open'
assert_pretool_deny "$deny_output" 'spec-reviewer'
assert_pretool_deny "$deny_output" 'finish current review loop first'

# 4) spec-reviewer for the current task is allowed
allow_output="$(run_agent_gate $'SPFE_TASK_ID=task-review-open\nSPFE_PACKET_ROLE=spec-reviewer\n\nSpec review for current task.')"
assert_pretool_allow "$allow_output"

# 5) failed spec review -> same-task implementer follow-up is allowed
allow_output="$(run_agent_gate $'SPFE_TASK_ID=task-review-open\nSPFE_PACKET_ROLE=implementer\n\nApply spec fixes in same task.')"
assert_pretool_allow "$allow_output"

# 6) passed spec review -> code-reviewer is allowed
jq '.review.tasks["task-review-open"].spec_review_passed = true' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"
allow_output="$(run_agent_gate $'SPFE_TASK_ID=task-review-open\nSPFE_PACKET_ROLE=code-reviewer\n\nCode review after spec pass.')"
assert_pretool_allow "$allow_output"

# 7) failed code review -> same-task implementer follow-up is allowed
allow_output="$(run_agent_gate $'SPFE_TASK_ID=task-review-open\nSPFE_PACKET_ROLE=implementer\n\nApply code-review fixes in same task.')"
assert_pretool_allow "$allow_output"

# 8) once both reviews pass, next-task implementer is allowed
jq '.review.tasks["task-review-open"].code_review_passed = true' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"
allow_output="$(run_agent_gate $'SPFE_TASK_ID=task-review-next\nSPFE_PACKET_ROLE=implementer\n\nImplement next task after both passes.')"
assert_pretool_allow "$allow_output"

# 9) deny output includes open task id and tells Claude to finish current review loop first
jq '.review.tasks["task-review-open"].code_review_passed = false' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"
deny_output="$(run_agent_gate $'SPFE_TASK_ID=task-review-next\nSPFE_PACKET_ROLE=implementer\n\nAttempt next task too early.')"
assert_pretool_deny "$deny_output" 'task-review-open'
assert_pretool_deny "$deny_output" 'finish current review loop first'

write_v2_state "$STATE_FILE"
posttool_output="$(run_posttool_agent_dispatch 'task-sync-impl-1' 'implementer')"
assert_posttool_allow "$posttool_output"
assert_json_equals "$STATE_FILE" '.task_flow.active_task_id' '"task-sync-impl-1"'
assert_json_equals "$STATE_FILE" '.task_flow.active_packet_role' '"implementer"'
jq -e '(.task_flow.last_dispatch_at | type) == "string" and (.task_flow.last_dispatch_at | length) > 0' "$STATE_FILE" >/dev/null 2>&1 || {
  echo 'Expected implementer dispatch to record task_flow.last_dispatch_at' >&2
  exit 1
}

write_v2_state "$STATE_FILE"
posttool_output="$(run_posttool_agent_dispatch 'task-sync-impl-2' 'implementer')"
assert_posttool_allow "$posttool_output"
assert_json_equals "$STATE_FILE" '.review.tasks["task-sync-impl-2"].spec_review_passed' 'false'
assert_json_equals "$STATE_FILE" '.review.tasks["task-sync-impl-2"].code_review_passed' 'false'

write_v2_state "$STATE_FILE"
jq '
  .task_flow.active_task_id = "task-sync-review-1"
  | .task_flow.active_packet_role = "implementer"
  | .task_flow.last_dispatch_at = "2026-01-01T00:00:00Z"
  | .review.tasks["task-sync-review-1"] = {spec_review_passed:true, code_review_passed:false}
' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"
previous_dispatch_at="$(jq -r '.task_flow.last_dispatch_at' "$STATE_FILE")"
posttool_output="$(run_posttool_agent_dispatch 'task-sync-review-1' 'code-reviewer')"
assert_posttool_allow "$posttool_output"
assert_json_equals "$STATE_FILE" '.task_flow.active_task_id' '"task-sync-review-1"'
assert_json_equals "$STATE_FILE" '.task_flow.active_packet_role' '"code-reviewer"'
jq -e --arg previous "$previous_dispatch_at" '.task_flow.last_dispatch_at != $previous' "$STATE_FILE" >/dev/null 2>&1 || {
  echo 'Expected reviewer dispatch to refresh task_flow.last_dispatch_at' >&2
  exit 1
}
assert_json_equals "$STATE_FILE" '.review.tasks["task-sync-review-1"].spec_review_passed' 'true'
assert_json_equals "$STATE_FILE" '.review.tasks["task-sync-review-1"].code_review_passed' 'false'

write_v2_state "$STATE_FILE"
jq '
  .task_flow.active_task_id = "task-sync-followup-1"
  | .task_flow.active_packet_role = "code-reviewer"
  | .task_flow.last_dispatch_at = "2026-01-01T00:00:00Z"
  | .review.tasks["task-sync-followup-1"] = {spec_review_passed:true, code_review_passed:true}
' "$STATE_FILE" > "$TMP_DIR/state.json"
mv "$TMP_DIR/state.json" "$STATE_FILE"
posttool_output="$(run_posttool_agent_dispatch 'task-sync-followup-1' 'implementer')"
assert_posttool_allow "$posttool_output"
assert_json_equals "$STATE_FILE" '.task_flow.active_task_id' '"task-sync-followup-1"'
assert_json_equals "$STATE_FILE" '.task_flow.active_packet_role' '"implementer"'
assert_json_equals "$STATE_FILE" '.review.tasks["task-sync-followup-1"].spec_review_passed' 'true'
assert_json_equals "$STATE_FILE" '.review.tasks["task-sync-followup-1"].code_review_passed' 'true'
