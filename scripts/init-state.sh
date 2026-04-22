#!/bin/bash
set -euo pipefail

HOOK_INPUT="$(cat)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
# shellcheck source=lib/platform_compat.sh
source "$PLUGIN_ROOT/scripts/lib/platform_compat.sh"

TEMPLATE="${PLUGIN_ROOT}/templates/flow_state.json.tmpl"
MIGRATE_SCRIPT="${PLUGIN_ROOT}/scripts/migrate-state.sh"

resolve_project_dir() {
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    printf '%s\n' "$CLAUDE_PROJECT_DIR"
    return
  fi

  if [ -n "$HOOK_INPUT" ]; then
    local hook_cwd
    hook_cwd="$(printf '%s' "$HOOK_INPUT" | jq -r '
      if .hook_event_name == "SessionStart" and (.cwd | type) == "string" and .cwd != "" then
        .cwd
      else
        empty
      end
    ' 2>/dev/null || true)"

    if [ -n "$hook_cwd" ]; then
      printf '%s\n' "$hook_cwd"
      return
    fi
  fi

  printf '%s\n' "$PWD"
}

resolve_session_start_source() {
  if [ -z "$HOOK_INPUT" ]; then
    return
  fi

  printf '%s' "$HOOK_INPUT" | jq -r '
    if .hook_event_name == "SessionStart" and (.source | type) == "string" and .source != "" then
      .source
    else
      empty
    end
  ' 2>/dev/null || true
}

PROJECT_DIR="$(resolve_project_dir)"
STATE_FILE="$PROJECT_DIR/.claude/flow_state.json"
SESSION_START_SOURCE="$(resolve_session_start_source)"

initialize_state() {
  mkdir -p "$PROJECT_DIR/.claude"

  SESSION_ID="$(date +%s | platform_compat_hash_stdin_sha256 | head -c 16)"
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  jq --arg session "$SESSION_ID" \
     --arg project "$PROJECT_DIR" \
     --arg timestamp "$TIMESTAMP" \
     '.session_id = $session | .project_dir = $project | .initialized_at = $timestamp' \
     "$TEMPLATE" > "$STATE_FILE"
}

normalize_workflow_state() {
  jq '
    if (.workflow | type) == "object" then
      .workflow.active = (.workflow.active // false)
      | .workflow.activated_by = (.workflow.activated_by // null)
      | .workflow.activated_at = (.workflow.activated_at // null)
      | .workflow.override = (.workflow.override // null)
      | .workflow.deactivated_by = (.workflow.deactivated_by // null)
      | .workflow.deactivated_at = (.workflow.deactivated_at // null)
    else
      .workflow = {
        "active": false,
        "activated_by": null,
        "activated_at": null,
        "override": null,
        "deactivated_by": null,
        "deactivated_at": null
      }
    end
  ' "$STATE_FILE" > "${STATE_FILE}.tmp"
  mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

normalize_task_flow_state() {
  jq '
    if (.task_flow | type) == "object" then
      .task_flow.active_task_id = (.task_flow.active_task_id // null)
      | .task_flow.active_packet_role = (.task_flow.active_packet_role // null)
      | .task_flow.last_dispatch_at = (.task_flow.last_dispatch_at // null)
    else
      .task_flow = {
        "active_task_id": null,
        "active_packet_role": null,
        "last_dispatch_at": null
      }
    end
  ' "$STATE_FILE" > "${STATE_FILE}.tmp"
  mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

normalize_resume_state() {
  jq '
    if (.resume | type) == "object" then
      .resume.recovery_required = (.resume.recovery_required // false)
      | .resume.recovery_completed_at = (.resume.recovery_completed_at // null)
      | .resume.last_resume_source = (.resume.last_resume_source // null)
    else
      .resume = {
        "recovery_required": false,
        "recovery_completed_at": null,
        "last_resume_source": null
      }
    end
  ' "$STATE_FILE" > "${STATE_FILE}.tmp"
  mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

backup_and_reset_state() {
  cp "$STATE_FILE" "${STATE_FILE}.bak"
  initialize_state
}

sync_resume_recovery_state() {
  local tmp_file="${STATE_FILE}.tmp"

  jq --arg source "$SESSION_START_SOURCE" '
    def review_tasks:
      if (.review.tasks | type) == "object" then .review.tasks else {} end;
    def cleanly_finished:
      .finishing.invoked == true
      and .task_flow.active_task_id == null
      and (
        (review_tasks | length) == 0
        or all(review_tasks[]?; .spec_review_passed == true and .code_review_passed == true)
      );
    def progressed:
      .current_phase != "init"
      or .brainstorming.question_asked == true
      or .brainstorming.spec_written == true
      or .planning.plan_written == true
      or .worktree.created == true
      or .task_flow.active_task_id != null
      or (review_tasks | length) > 0
      or ((.tdd.test_files_created // []) | length) > 0
      or ((.tdd.production_files_written // []) | length) > 0
      or ((.tdd.tests_verified_fail // []) | length) > 0
      or ((.tdd.tests_verified_pass // []) | length) > 0;
    def clear_recovery:
      .workflow.active != true
      or .workflow.override == "manual_off"
      or cleanly_finished;
    if $source == "resume" then
      .resume.last_resume_source = "resume"
      | if clear_recovery then
          .resume.recovery_required = false
        elif progressed then
          .resume.recovery_required = true
        else
          .
        end
    elif clear_recovery then
      .resume.recovery_required = false
    else
      .
    end
  ' "$STATE_FILE" > "$tmp_file"
  mv "$tmp_file" "$STATE_FILE"
}

resume_hint_required() {
  jq -e '.resume.recovery_required == true' "$STATE_FILE" >/dev/null 2>&1
}

emit_success() {
  local base_message="$1"

  if resume_hint_required; then
    echo '{"continue": true, "systemMessage": "检测到 resumed 的未完成 workflow，请先执行 /superpowers-flow-enforcer:resume-enforcer。"}'
    return
  fi

  printf '{"continue": true, "systemMessage": "%s"}\n' "$base_message"
}

if [ -f "$STATE_FILE" ]; then
  if ! jq -e 'type == "object"' "$STATE_FILE" >/dev/null 2>&1; then
    backup_and_reset_state
    echo "{\"continue\": true, \"systemMessage\": \"Flow state backed up and reset at $STATE_FILE\"}"
    exit 0
  fi

  VERSION="$(jq -r '.state_version // 1' "$STATE_FILE")"

  if ! [[ "$VERSION" =~ ^[0-9]+$ ]]; then
    echo "unsupported flow state version: $VERSION" >&2
    exit 1
  fi

  if [ "$VERSION" -gt 2 ]; then
    echo "unsupported flow state version: $VERSION" >&2
    exit 1
  fi

  if ! bash "$MIGRATE_SCRIPT" --check-safe "$STATE_FILE"; then
    backup_and_reset_state
    echo "{\"continue\": true, \"systemMessage\": \"Flow state backed up and reset at $STATE_FILE\"}"
    exit 0
  fi

  if [ "$VERSION" -lt 2 ]; then
    bash "$MIGRATE_SCRIPT" "$STATE_FILE"
    normalize_workflow_state
    normalize_task_flow_state
    normalize_resume_state
    sync_resume_recovery_state
    emit_success "Flow state migrated to v2 at $STATE_FILE"
    exit 0
  fi

  WORKFLOW_STATUS="$(jq -r '
    if has("workflow") then
      if (.workflow | type) != "object" then
        "unsafe"
      else
        def workflow_field_status($key; $allowed_types):
          if (.workflow | has($key)) then
            (.workflow[$key] | type) as $field_type
            | if ($allowed_types | index($field_type)) then
                "valid"
              elif $field_type == "null" then
                "needs_normalization"
              else
                "unsafe"
              end
          else
            "needs_normalization"
          end;

        (workflow_field_status("active"; ["boolean"])) as $active_status
        | (workflow_field_status("activated_by"; ["string"])) as $activated_by_status
        | (workflow_field_status("activated_at"; ["string"])) as $activated_at_status
        | (workflow_field_status("override"; ["string"])) as $override_status
        | (workflow_field_status("deactivated_by"; ["string"])) as $deactivated_by_status
        | (workflow_field_status("deactivated_at"; ["string"])) as $deactivated_at_status
        | if (
            $active_status == "unsafe"
            or $activated_by_status == "unsafe"
            or $activated_at_status == "unsafe"
            or $override_status == "unsafe"
            or $deactivated_by_status == "unsafe"
            or $deactivated_at_status == "unsafe"
          ) then
            "unsafe"
          elif (
            $active_status == "needs_normalization"
            or $activated_by_status == "needs_normalization"
            or $activated_at_status == "needs_normalization"
            or $override_status == "needs_normalization"
            or $deactivated_by_status == "needs_normalization"
            or $deactivated_at_status == "needs_normalization"
          ) then
            "needs_normalization"
          else
            "valid"
          end
      end
    else
      "missing"
    end
  ' "$STATE_FILE")"

  if [ "$WORKFLOW_STATUS" = "missing" ] || [ "$WORKFLOW_STATUS" = "needs_normalization" ]; then
    normalize_workflow_state
  elif [ "$WORKFLOW_STATUS" = "unsafe" ]; then
    backup_and_reset_state
    echo "{\"continue\": true, \"systemMessage\": \"Flow state backed up and reset at $STATE_FILE\"}"
    exit 0
  fi

  TASK_FLOW_STATUS="$(jq -r '
    if has("task_flow") then
      if (.task_flow | type) != "object" then
        "unsafe"
      else
        def nullable_string_field_status($key):
          if (.task_flow | has($key)) then
            (.task_flow[$key] | type) as $field_type
            | if ($field_type == "string" or $field_type == "null") then
                "valid"
              else
                "unsafe"
              end
          else
            "needs_normalization"
          end;

        def role_field_status:
          if (.task_flow | has("active_packet_role")) then
            (.task_flow.active_packet_role | type) as $role_type
            | if $role_type == "null" then
                "valid"
              elif $role_type != "string" then
                "unsafe"
              elif (
                .task_flow.active_packet_role == "implementer"
                or .task_flow.active_packet_role == "spec-reviewer"
                or .task_flow.active_packet_role == "code-reviewer"
              ) then
                "valid"
              else
                "unsafe"
              end
          else
            "needs_normalization"
          end;

        (nullable_string_field_status("active_task_id")) as $active_task_status
        | (role_field_status) as $active_role_status
        | (nullable_string_field_status("last_dispatch_at")) as $last_dispatch_status
        | if (
            $active_task_status == "unsafe"
            or $active_role_status == "unsafe"
            or $last_dispatch_status == "unsafe"
          ) then
            "unsafe"
          elif (
            $active_task_status == "needs_normalization"
            or $active_role_status == "needs_normalization"
            or $last_dispatch_status == "needs_normalization"
          ) then
            "needs_normalization"
          else
            "valid"
          end
      end
    else
      "missing"
    end
  ' "$STATE_FILE")"

  if [ "$TASK_FLOW_STATUS" = "missing" ] || [ "$TASK_FLOW_STATUS" = "needs_normalization" ]; then
    normalize_task_flow_state
  elif [ "$TASK_FLOW_STATUS" = "unsafe" ]; then
    backup_and_reset_state
    echo "{\"continue\": true, \"systemMessage\": \"Flow state backed up and reset at $STATE_FILE\"}"
    exit 0
  fi

  RESUME_STATUS="$(jq -r '
    if has("resume") then
      if (.resume | type) != "object" then
        "unsafe"
      else
        def resume_field_status($key; $allowed_types):
          if (.resume | has($key)) then
            (.resume[$key] | type) as $field_type
            | if ($allowed_types | index($field_type)) then
                "valid"
              elif (
                $field_type == "null"
                and ($allowed_types | index("string")) != null
              ) then
                "valid"
              elif $field_type == "null" then
                "needs_normalization"
              else
                "unsafe"
              end
          else
            "needs_normalization"
          end;

        (resume_field_status("recovery_required"; ["boolean"])) as $recovery_required_status
        | (resume_field_status("recovery_completed_at"; ["string"])) as $recovery_completed_at_status
        | (resume_field_status("last_resume_source"; ["string"])) as $last_resume_source_status
        | if (
            $recovery_required_status == "unsafe"
            or $recovery_completed_at_status == "unsafe"
            or $last_resume_source_status == "unsafe"
          ) then
            "unsafe"
          elif (
            $recovery_required_status == "needs_normalization"
            or $recovery_completed_at_status == "needs_normalization"
            or $last_resume_source_status == "needs_normalization"
          ) then
            "needs_normalization"
          else
            "valid"
          end
      end
    else
      "missing"
    end
  ' "$STATE_FILE")"

  if [ "$RESUME_STATUS" = "missing" ] || [ "$RESUME_STATUS" = "needs_normalization" ]; then
    normalize_resume_state
  elif [ "$RESUME_STATUS" = "unsafe" ]; then
    backup_and_reset_state
    echo "{\"continue\": true, \"systemMessage\": \"Flow state backed up and reset at $STATE_FILE\"}"
    exit 0
  fi

  sync_resume_recovery_state
  emit_success "Flow state file exists and valid"
  exit 0
fi

initialize_state
sync_resume_recovery_state

emit_success "Flow state initialized at $STATE_FILE"
exit 0
