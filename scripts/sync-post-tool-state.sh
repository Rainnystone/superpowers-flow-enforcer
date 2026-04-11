#!/bin/bash
set -euo pipefail

HOOK_EVENT="${HOOK_EVENT:-PostToolUse}"

allow_hook() {
  if [ "$HOOK_EVENT" = "PostToolUseFailure" ]; then
    echo '{"continue":true}'
  fi
  exit 0
}

block_posttool() {
  local reason="$1"
  jq -n --arg reason "$reason" '{decision:"block", reason:$reason}'
  exit 0
}

if ! command -v jq >/dev/null 2>&1; then
  if [ "$HOOK_EVENT" = "PostToolUseFailure" ]; then
    echo '{"continue":true,"systemMessage":"jq missing, skip post tool state sync"}'
    exit 0
  fi
  exit 0
fi

INPUT="$(cat)"
HOOK_CWD="$(printf '%s' "$INPUT" | jq -r '
  if (.cwd | type) == "string" and .cwd != "" then
    .cwd
  else
    empty
  end
' 2>/dev/null || true)"

resolve_state_root_from_candidate() {
  local candidate="$1"

  if [ -z "$candidate" ]; then
    return
  fi

  local current="$candidate"
  if [ ! -d "$current" ]; then
    current="$(dirname "$current")"
  fi

  if [ ! -d "$current" ]; then
    return
  fi

  current="$(cd "$current" 2>/dev/null && pwd -P)" || return

  while :; do
    if [ -f "$current/.claude/flow_state.json" ]; then
      printf '%s\n' "$current"
      return
    fi

    if [ "$current" = "/" ]; then
      return
    fi

    current="$(dirname "$current")"
  done
}

resolve_state_root_alias_from_candidate() {
  local candidate="$1"

  if [ -z "$candidate" ]; then
    return
  fi

  local current="$candidate"
  if [ ! -d "$current" ]; then
    current="$(dirname "$current")"
  fi

  if [ ! -d "$current" ]; then
    return
  fi

  while :; do
    if [ -f "$current/.claude/flow_state.json" ]; then
      printf '%s\n' "$current"
      return
    fi

    if [ "$current" = "/" ]; then
      return
    fi

    current="$(dirname "$current")"
  done
}

resolve_project_dir() {
  local resolved=""

  resolved="$(resolve_state_root_from_candidate "${CLAUDE_PROJECT_DIR:-}")"
  if [ -n "$resolved" ]; then
    printf '%s\n' "$resolved"
    return
  fi

  local hook_cwd
  hook_cwd="$HOOK_CWD"

  resolved="$(resolve_state_root_from_candidate "$hook_cwd")"
  if [ -n "$resolved" ]; then
    printf '%s\n' "$resolved"
  fi
}

PROJECT_DIR="$(resolve_project_dir)"
if [ -z "$PROJECT_DIR" ]; then
  allow_hook
fi

STATE_FILE="$PROJECT_DIR/.claude/flow_state.json"
if [ ! -f "$STATE_FILE" ]; then
  allow_hook
fi

TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // ""')"
NOW_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
tmp_file="${STATE_FILE}.tmp"
SPEC_WRITE_RECORDED=false
PLAN_WRITE_RECORDED=false
WORKTREE_ADD_RECORDED=false

update_state() {
  local expr="$1"
  jq "$expr" "$STATE_FILE" > "$tmp_file"
  mv "$tmp_file" "$STATE_FILE"
}

state_is_true() {
  local jq_expr="$1"
  jq -e "$jq_expr == true" "$STATE_FILE" >/dev/null 2>&1
}

append_unique_string_to_array() {
  local jq_path="$1"
  local value="$2"
  jq --arg path "$jq_path" --arg value "$value" '
    def setpathstr($path; $v):
      if $path == "tdd.test_files_created" then .tdd.test_files_created = ((.tdd.test_files_created // []) + [$v] | unique)
      elif $path == "tdd.production_files_written" then .tdd.production_files_written = ((.tdd.production_files_written // []) + [$v] | unique)
      elif $path == "tdd.tests_verified_fail" then .tdd.tests_verified_fail = ((.tdd.tests_verified_fail // []) + [$v] | unique)
      elif $path == "tdd.tests_verified_pass" then .tdd.tests_verified_pass = ((.tdd.tests_verified_pass // []) + [$v] | unique)
      else .
      end;
    setpathstr($path; $value)
  ' "$STATE_FILE" > "$tmp_file"
  mv "$tmp_file" "$STATE_FILE"
}

normalize_workflow_entry_path() {
  local path="$1"
  local root_alias
  local path_physical=""
  local path_dir=""
  local path_name=""

  while [[ "$path" == ./* ]]; do
    path="${path#./}"
  done

  if [[ "$path" = /* ]]; then
    path_dir="$(dirname "$path")"
    path_name="${path##*/}"
    if [ -d "$path_dir" ]; then
      path_physical="$(cd "$path_dir" 2>/dev/null && pwd -P)/$path_name"
    fi
  fi

  for root_alias in \
    "$PROJECT_DIR" \
    "$(resolve_state_root_alias_from_candidate "${CLAUDE_PROJECT_DIR:-}")" \
    "$(resolve_state_root_alias_from_candidate "$HOOK_CWD")"
  do
    if [ -n "$root_alias" ] && [[ "$path" == "$root_alias"/* ]]; then
      path="${path#"$root_alias"/}"
      break
    fi
  done

  if [ -n "$path_physical" ] && [ -n "$PROJECT_DIR" ] && [[ "$path_physical" == "$PROJECT_DIR"/* ]]; then
    path="${path_physical#"$PROJECT_DIR"/}"
  fi

  printf '%s\n' "$path"
}

extract_worktree_path() {
  local command="$1"
  python3 - "$command" <<'PY'
import os
import shlex
import sys

command = sys.argv[1]

try:
    argv = shlex.split(command)
except ValueError:
    raise SystemExit(1)

if not argv:
    raise SystemExit(1)


def basename(token):
    return os.path.basename(token)


def normalize(tokens):
    if not tokens:
        return tokens

    i = 0
    while i < len(tokens) and "=" in tokens[i] and not tokens[i].startswith("-") and tokens[i].split("=", 1)[0].replace("_", "a").isalnum():
        i += 1
    tokens = tokens[i:]

    if tokens and basename(tokens[0]) == "env":
        i = 1
        while i < len(tokens) and (
            tokens[i] == "-i"
            or tokens[i] == "--"
            or "=" in tokens[i] and not tokens[i].startswith("-") and tokens[i].split("=", 1)[0].replace("_", "a").isalnum()
        ):
            if tokens[i] == "--":
                i += 1
                break
            i += 1
        tokens = tokens[i:]

    if tokens and basename(tokens[0]) in {"bash", "sh", "zsh"}:
        for idx, token in enumerate(tokens[1:], start=1):
            if token == "--":
                break
            if token.startswith("-") and "c" in token[1:]:
                if idx + 1 >= len(tokens):
                    raise SystemExit(1)
                try:
                    return normalize(shlex.split(tokens[idx + 1]))
                except ValueError:
                    raise SystemExit(1)
        return tokens

    return tokens


def strip_leading_shell_chain(tokens):
    shell_chain_ops = {"&&", ";", "||", "&"}

    while True:
        if len(tokens) >= 4 and tokens[0] == "cd" and tokens[2] in shell_chain_ops:
            tokens = tokens[3:]
            continue
        return tokens


argv = normalize(argv)
argv = strip_leading_shell_chain(argv)
if len(argv) < 3:
    raise SystemExit(1)
if basename(argv[0]) != "git":
    raise SystemExit(1)

i = 1
git_flags_with_values = {"-C", "-c", "--git-dir", "--work-tree", "--namespace"}
while i < len(argv):
    token = argv[i]
    if token in git_flags_with_values:
        i += 2
        continue
    if any(token.startswith(f"{flag}=") for flag in {"--git-dir", "--work-tree", "--namespace"}):
        i += 1
        continue
    break

if i + 1 >= len(argv) or argv[i] != "worktree" or argv[i + 1] != "add":
    raise SystemExit(1)

i += 2
while i < len(argv):
    token = argv[i]
    if token in {"-b", "-B", "--branch", "--reason"}:
        i += 2
        continue
    if token.startswith("-"):
        i += 1
        continue
    print(token)
    raise SystemExit(0)

raise SystemExit(1)
PY
}

command_is_test() {
  local command="$1"
  python3 - "$command" <<'PY'
import os
import re
import shlex
import sys

command = sys.argv[1]

try:
    argv = shlex.split(command)
except ValueError:
    raise SystemExit(1)

if not argv:
    raise SystemExit(1)

assignment_re = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*=.*$')
shell_test_script_re = re.compile(r'(^|.*/)?tests?/.*\.sh$')
test_runners = {"pytest", "jest", "vitest"}
dir_option_value_flags = {
    "--dir",
    "--directory",
    "--cwd",
    "--prefix",
    "-C",
}
selector_option_value_flags = {
    "--workspace",
    "-w",
    "--filter",
    "-F",
    "--scope",
    "--project",
}
cli_option_value_flags = dir_option_value_flags | selector_option_value_flags
shell_chain_ops = {"&&", ";", "||", "&"}


def is_assignment(token):
    return bool(assignment_re.match(token))


def command_basename(token):
    return os.path.basename(token)


def canonicalize_path(token):
    while token.startswith("./"):
        token = token[2:]
    return token


def split_trailing_chain_token(token):
    for op in sorted(shell_chain_ops, key=len, reverse=True):
        if token != op and token.endswith(op):
            head = token[:-len(op)]
            if head:
                return head
    return None


def strip_leading_shell_chain(tokens):
    while True:
        if len(tokens) >= 4 and tokens[0] == "cd" and tokens[2] in shell_chain_ops:
            tokens = tokens[3:]
            tokens = strip_env_prefix(tokens)
            continue

        if len(tokens) >= 3 and tokens[0] == "cd":
            dir_token = split_trailing_chain_token(tokens[1])
            if dir_token is not None:
                tokens = tokens[2:]
                tokens = strip_env_prefix(tokens)
                continue

        if tokens and tokens[0] == "export":
            i = 1
            while i < len(tokens):
                token = tokens[i]
                if is_assignment(token):
                    i += 1
                    continue
                assignment_token = split_trailing_chain_token(token)
                if assignment_token is not None and is_assignment(assignment_token) and i >= 1:
                    tokens = tokens[i + 1 :]
                    tokens = strip_env_prefix(tokens)
                    break
                if token in shell_chain_ops and i > 1:
                    tokens = tokens[i + 1 :]
                    tokens = strip_env_prefix(tokens)
                    break
                return tokens
            else:
                return tokens
            continue

        if tokens and tokens[0] in {"source", "."}:
            if len(tokens) >= 3 and tokens[2] in shell_chain_ops:
                tokens = tokens[3:]
                tokens = strip_env_prefix(tokens)
                continue
            if len(tokens) >= 2 and split_trailing_chain_token(tokens[1]) is not None:
                tokens = tokens[2:]
                tokens = strip_env_prefix(tokens)
                continue
            return tokens

        if tokens and tokens[0] == "set":
            if len(tokens) >= 3 and tokens[1].startswith("-") and tokens[2] in shell_chain_ops:
                tokens = tokens[3:]
                tokens = strip_env_prefix(tokens)
                continue
            set_arg = split_trailing_chain_token(tokens[1]) if len(tokens) >= 2 else None
            if set_arg is not None and set_arg.startswith("-"):
                tokens = tokens[2:]
                tokens = strip_env_prefix(tokens)
                continue
            return tokens

        return tokens


def skip_leading_cli_options(tokens):
    i = 0
    while i < len(tokens):
        token = tokens[i]
        if token == "--":
            return i + 1
        if token in dir_option_value_flags or token in selector_option_value_flags:
            if i + 1 >= len(tokens):
                return None
            i += 2
            continue
        if any(token.startswith(f"{flag}=") for flag in cli_option_value_flags):
            i += 1
            continue
        if token.startswith("-"):
            i += 1
            continue
        return i
    return None


def strip_env_prefix(tokens):
    i = 0

    if i < len(tokens) and command_basename(tokens[i]) == "env":
        i += 1
        while i < len(tokens):
            token = tokens[i]
            if token == "--":
                i += 1
                break
            if token == "-S":
                if i + 1 >= len(tokens):
                    return []
                try:
                    return shlex.split(tokens[i + 1])
                except ValueError:
                    return []
            if token == "-i":
                i += 1
                continue
            if token in {"-u", "--unset"}:
                if i + 1 >= len(tokens):
                    return []
                i += 2
                continue
            if token.startswith("--unset="):
                i += 1
                continue
            if token.startswith("-"):
                i += 1
                continue
            if is_assignment(token):
                i += 1
                continue
            break

    while i < len(tokens) and is_assignment(tokens[i]):
        i += 1

    return tokens[i:]


def normalize_tokens(tokens):
    tokens = strip_env_prefix(tokens)

    while True:
        if not tokens:
            return tokens

        head = tokens[0]
        head_name = command_basename(head)

        if head_name in {"bash", "sh", "zsh"}:
            shell_payload_index = None
            for idx, token in enumerate(tokens[1:], start=1):
                if token == "--":
                    break
                if token.startswith("-") and not token.startswith("--") and "c" in token[1:]:
                    shell_payload_index = idx + 1
                    break

            if shell_payload_index is not None:
                if shell_payload_index >= len(tokens):
                    return []
                try:
                    tokens = shlex.split(tokens[shell_payload_index])
                except ValueError:
                    return []
                tokens = strip_env_prefix(tokens)
                tokens = strip_leading_shell_chain(tokens)
                continue

        tokens = strip_leading_shell_chain(tokens)

        if (head_name == "py" or head_name.startswith("python")) and len(tokens) >= 3 and tokens[1] == "-m" and tokens[2] == "pytest":
            tokens = ["pytest"] + tokens[3:]
            continue

        if head_name == "uv":
            run_index = skip_leading_cli_options(tokens[1:])
            if run_index is not None and tokens[1 + run_index] == "run":
                payload = tokens[2 + run_index :]
                payload = strip_env_prefix(payload)
                payload = strip_leading_shell_chain(payload)
                payload_index = skip_leading_cli_options(payload)
                if payload_index is None or payload_index >= len(payload):
                    return []
                tokens = payload[payload_index:]
                continue

        if head_name in {"npx", "pnpx"}:
            i = 1
            while i < len(tokens):
                token = tokens[i]
                if token == "--":
                    i += 1
                    break
                if token in {"-y", "--yes", "--no-install"}:
                    i += 1
                    continue
                if token in {"-p", "--package"}:
                    if i + 1 >= len(tokens):
                        return []
                    i += 2
                    continue
                if token in cli_option_value_flags:
                    if i + 1 >= len(tokens):
                        return []
                    i += 2
                    continue
                if any(token.startswith(f"{flag}=") for flag in cli_option_value_flags):
                    i += 1
                    continue
                if token.startswith("-"):
                    i += 1
                    continue
                break

            if i < len(tokens) and tokens[i] in test_runners:
                tokens = [tokens[i]] + tokens[i + 1:]
                continue

            return tokens

        if head_name in {"npm", "pnpm", "yarn", "bun"}:
            command_index = skip_leading_cli_options(tokens[1:])
            if command_index is not None and tokens[1 + command_index] == "exec":
                payload = tokens[2 + command_index :]
                payload = strip_env_prefix(payload)
                payload = strip_leading_shell_chain(payload)
                payload_index = skip_leading_cli_options(payload)
                if payload_index is None or payload_index >= len(payload):
                    return []
                if payload[payload_index] in test_runners:
                    tokens = [payload[payload_index]] + payload[payload_index + 1:]
                    continue

                return tokens

        return tokens


def is_test_script(name):
    return name == "test" or name.startswith("test:")


def is_package_manager_test(tokens):
    if not tokens or command_basename(tokens[0]) not in {"npm", "pnpm", "yarn", "bun"}:
        return False

    flags_with_values = {
        "--workspace",
        "-w",
        "--filter",
        "--dir",
        "--cwd",
        "--prefix",
        "-C",
        "-F",
        "--scope",
    }

    words = []
    i = 1
    while i < len(tokens):
        token = tokens[i]

        if token == "--":
            words.extend(tokens[i + 1:])
            break

        if token in {"-r", "--recursive"}:
            words.append("recursive")
            i += 1
            continue

        if token in flags_with_values:
            if i + 1 >= len(tokens):
                return False
            i += 2
            continue

        if any(token.startswith(f"{flag}=") for flag in flags_with_values):
            i += 1
            continue

        if token.startswith("-"):
            i += 1
            continue

        words.append(token)
        i += 1

    def is_test_sequence(seq):
        return bool(seq) and (
            seq[0] in test_runners
            or is_test_script(seq[0])
            or (len(seq) >= 2 and seq[0] == "run" and (seq[1] in test_runners or is_test_script(seq[1])))
        )

    if not words:
        return False

    head = words[0]
    if head in {"workspace", "workspaces"}:
        return len(words) >= 3 and is_test_sequence(words[2:])

    if head == "recursive":
        return is_test_sequence(words[1:])

    return is_test_sequence(words)


def is_test_command(tokens):
    tokens = normalize_tokens(tokens)
    if not tokens:
        return False

    cmd = tokens[0]
    cmd_name = command_basename(cmd)

    if cmd_name in test_runners:
        return True

    if cmd_name in {"cargo", "go"} and len(tokens) > 1 and tokens[1] == "test":
        return True

    if shell_test_script_re.search(cmd):
        return True

    if cmd_name in {"bash", "sh", "zsh"} and any(shell_test_script_re.search(token) for token in tokens[1:]):
        return True

    return is_package_manager_test(tokens)


tokens = normalize_tokens(argv)
if not is_test_command(tokens):
    raise SystemExit(1)

raise SystemExit(0)
PY
}

classify_failure_test_command() {
  local command="$1"
  python3 - "$command" <<'PY'
import os
import re
import shlex
import sys

command = sys.argv[1]

try:
    argv = shlex.split(command)
except ValueError:
    print("none")
    raise SystemExit(0)

assignment_re = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*=.*$')
test_path_re = re.compile(r'(^|.*/)(tests?/.*|test_[^/]+\.[^/]+|[^/]+_test\.[^/]+|[^/]+_spec\.[^/]+|[^/]+\.test\.[^/]+|[^/]+\.spec\.[^/]+)$')


def command_basename(token):
    return os.path.basename(token)


def canonicalize_path(token):
    while token.startswith("./"):
        token = token[2:]
    return token


def strip_assignments(tokens):
    i = 0
    while i < len(tokens) and assignment_re.match(tokens[i]):
        i += 1
    return tokens[i:]


def looks_like_test_path(token):
    token = canonicalize_path(token)
    return bool(test_path_re.search(token))


def shell_payload_index(tokens):
    for idx, token in enumerate(tokens[1:], start=1):
        if token == "--":
            break
        if token == "-c" or (token.startswith("-") and not token.startswith("--") and "c" in token[1:]):
            return idx + 1
    return None


def strip_leading_shell_prefix(tokens):
    if len(tokens) >= 4 and tokens[0] == "cd" and tokens[2] in {"&&", ";", "||", "&"}:
        return tokens[3:]
    return tokens


def classify_package_manager_test(tokens):
    if len(tokens) < 2:
        return False

    test_runners = {"vitest", "pytest", "jest"}
    flags_with_values = {"--workspace", "-w", "--filter", "-F", "--project", "--scope", "--dir", "--cwd", "--prefix", "-C"}
    i = 1
    while i < len(tokens):
        token = tokens[i]
        if token == "--":
            i += 1
            break
        if token in {"-r", "--recursive", "recursive"}:
            i += 1
            continue
        if token in flags_with_values:
            if i + 1 >= len(tokens):
                return False
            i += 2
            continue
        if any(token.startswith(f"{flag}=") for flag in flags_with_values):
            i += 1
            continue
        if token.startswith("-"):
            i += 1
            continue
        break

    if i >= len(tokens):
        return False

    head = tokens[i]

    if head == "exec" and i + 1 < len(tokens) and tokens[i + 1] == "vitest":
        return True

    if head == "test":
        return True

    if head == "workspace" and i + 2 < len(tokens):
        subcommand = tokens[i + 2]
        if subcommand == "test":
            return True
        if subcommand in test_runners:
            return True
        if subcommand == "run" and i + 3 < len(tokens) and tokens[i + 3].startswith("test"):
            return True
        if subcommand == "run" and i + 3 < len(tokens) and tokens[i + 3] in test_runners:
            return True

    if head == "run" and i + 1 < len(tokens) and tokens[i + 1].startswith("test"):
        return True
    if head == "run" and i + 1 < len(tokens) and tokens[i + 1] in test_runners:
        return True

    return False


def classify(tokens):
    tokens = strip_assignments(tokens)
    if not tokens:
        return "none"

    payload_index = shell_payload_index(tokens)
    if payload_index is not None:
        if payload_index >= len(tokens):
            return "none"
        try:
            payload_tokens = shlex.split(tokens[payload_index])
        except ValueError:
            return "none"
        payload_tokens = strip_leading_shell_prefix(strip_assignments(payload_tokens))
        return "ambiguous" if classify(payload_tokens) != "none" else "none"

    head_name = command_basename(tokens[0])

    if head_name == "vitest" and len(tokens) == 2 and looks_like_test_path(tokens[1]):
        return f"auto:{canonicalize_path(tokens[1])}"

    if head_name == "pytest" and len(tokens) == 2 and looks_like_test_path(tokens[1]):
        return f"auto:{canonicalize_path(tokens[1])}"

    if (head_name == "py" or head_name.startswith("python")) and len(tokens) == 4 and tokens[1] == "-m" and tokens[2] == "pytest" and looks_like_test_path(tokens[3]):
        return f"auto:{canonicalize_path(tokens[3])}"

    if head_name == "pnpm" and len(tokens) == 4 and tokens[1] == "exec" and tokens[2] == "vitest" and looks_like_test_path(tokens[3]):
        return f"auto:{canonicalize_path(tokens[3])}"

    if head_name in {"bash", "sh", "zsh"} and len(tokens) == 2 and looks_like_test_path(tokens[1]):
        return "ambiguous"

    if head_name in {"vitest", "pytest"}:
        return "ambiguous"

    if (head_name == "py" or head_name.startswith("python")) and len(tokens) >= 3 and tokens[1] == "-m" and tokens[2] == "pytest":
        return "ambiguous"

    if head_name in {"pnpm", "npm", "yarn"} and classify_package_manager_test(tokens):
        return "ambiguous"

    if head_name == "cargo" and len(tokens) >= 2 and tokens[1] == "test":
        return "ambiguous"

    if head_name == "go" and len(tokens) >= 2 and tokens[1] == "test":
        return "ambiguous"

    return "none"


print(classify(argv))
PY
}

test_target_path() {
  local command="$1"
  python3 - "$command" <<'PY'
import os
import re
import shlex
import sys

command = sys.argv[1]

try:
    argv = shlex.split(command)
except ValueError:
    raise SystemExit(1)

if not argv:
    raise SystemExit(1)

assignment_re = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*=.*$')
shell_test_script_re = re.compile(r'(^|.*/)?tests?/.*\.sh$')
test_file_re = re.compile(r'(^|.*/)(test_[^/]+\.[^/]+|[^/]+_test\.[^/]+|[^/]+_spec\.[^/]+|[^/]+\.test\.[^/]+|[^/]+\.spec\.[^/]+)$')
test_runners = {"pytest", "jest", "vitest"}
dir_option_value_flags = {
    "--dir",
    "--directory",
    "--cwd",
    "--prefix",
    "-C",
}
selector_option_value_flags = {
    "--workspace",
    "-w",
    "--filter",
    "-F",
    "--scope",
    "--project",
}
cli_option_value_flags = dir_option_value_flags | selector_option_value_flags
shell_chain_ops = {"&&", ";", "||", "&"}


def is_assignment(token):
    return bool(assignment_re.match(token))


def command_basename(token):
    return os.path.basename(token)


def canonicalize_path(token):
    while token.startswith("./"):
        token = token[2:]
    return token


def canonicalize_record_path(path_prefix, token):
    token = canonicalize_path(token)
    if not path_prefix:
        return token
    if token == path_prefix or token.startswith(f"{path_prefix}/"):
        return token
    return f"{path_prefix}/{token}"


def apply_prefix(path_prefix, value):
    value = canonicalize_path(value)
    if not value or value == ".":
        return path_prefix
    if not path_prefix:
        return value
    if value == path_prefix or value.startswith(f"{path_prefix}/"):
        return value
    return f"{path_prefix}/{value}"


def split_trailing_chain_token(token):
    for op in sorted(shell_chain_ops, key=len, reverse=True):
        if token != op and token.endswith(op):
            head = token[:-len(op)]
            if head:
                return head
    return None


def strip_leading_shell_chain(tokens, path_prefix):
    while True:
        if len(tokens) >= 4 and tokens[0] == "cd" and tokens[2] in shell_chain_ops:
            path_prefix = apply_prefix(path_prefix, tokens[1])
            tokens = tokens[3:]
            tokens = strip_env_prefix(tokens)
            continue

        if len(tokens) >= 3 and tokens[0] == "cd":
            dir_token = split_trailing_chain_token(tokens[1])
            if dir_token is not None:
                path_prefix = apply_prefix(path_prefix, dir_token)
                tokens = tokens[2:]
                tokens = strip_env_prefix(tokens)
                continue

        if tokens and tokens[0] == "export":
            i = 1
            while i < len(tokens):
                token = tokens[i]
                if is_assignment(token):
                    i += 1
                    continue
                assignment_token = split_trailing_chain_token(token)
                if assignment_token is not None and is_assignment(assignment_token) and i >= 1:
                    tokens = tokens[i + 1 :]
                    tokens = strip_env_prefix(tokens)
                    break
                if token in shell_chain_ops and i > 1:
                    tokens = tokens[i + 1 :]
                    tokens = strip_env_prefix(tokens)
                    break
                return tokens, path_prefix
            else:
                return tokens, path_prefix
            continue

        if tokens and tokens[0] in {"source", "."}:
            if len(tokens) >= 3 and tokens[2] in shell_chain_ops:
                tokens = tokens[3:]
                tokens = strip_env_prefix(tokens)
                continue
            if len(tokens) >= 2 and split_trailing_chain_token(tokens[1]) is not None:
                tokens = tokens[2:]
                tokens = strip_env_prefix(tokens)
                continue
            return tokens, path_prefix

        if tokens and tokens[0] == "set":
            if len(tokens) >= 3 and tokens[1].startswith("-") and tokens[2] in shell_chain_ops:
                tokens = tokens[3:]
                tokens = strip_env_prefix(tokens)
                continue
            set_arg = split_trailing_chain_token(tokens[1]) if len(tokens) >= 2 else None
            if set_arg is not None and set_arg.startswith("-"):
                tokens = tokens[2:]
                tokens = strip_env_prefix(tokens)
                continue
            return tokens, path_prefix

        return tokens, path_prefix


def skip_leading_cli_options(tokens, path_prefix):
    i = 0
    while i < len(tokens):
        token = tokens[i]
        if token == "--":
            return i + 1, path_prefix
        if token in dir_option_value_flags:
            if i + 1 >= len(tokens):
                return None, path_prefix
            path_prefix = apply_prefix(path_prefix, tokens[i + 1])
            i += 2
            continue
        if token in selector_option_value_flags:
            if i + 1 >= len(tokens):
                return None, path_prefix
            i += 2
            continue
        if any(token.startswith(f"{flag}=") for flag in dir_option_value_flags):
            path_prefix = apply_prefix(path_prefix, token.split("=", 1)[1])
            i += 1
            continue
        if any(token.startswith(f"{flag}=") for flag in selector_option_value_flags):
            i += 1
            continue
        if token.startswith("-"):
            i += 1
            continue
        return i, path_prefix
    return None, path_prefix


def strip_env_prefix(tokens):
    i = 0

    if i < len(tokens) and command_basename(tokens[i]) == "env":
        i += 1
        while i < len(tokens):
            token = tokens[i]
            if token == "--":
                i += 1
                break
            if token == "-S":
                if i + 1 >= len(tokens):
                    return []
                try:
                    return shlex.split(tokens[i + 1])
                except ValueError:
                    return []
            if token == "-i":
                i += 1
                continue
            if token in {"-u", "--unset"}:
                if i + 1 >= len(tokens):
                    return []
                i += 2
                continue
            if token.startswith("--unset="):
                i += 1
                continue
            if token.startswith("-"):
                i += 1
                continue
            if is_assignment(token):
                i += 1
                continue
            break

    while i < len(tokens) and is_assignment(tokens[i]):
        i += 1

    return tokens[i:]


def normalize_tokens(tokens):
    tokens = strip_env_prefix(tokens)
    path_prefix = ""

    while True:
        if not tokens:
            return tokens, path_prefix

        head = tokens[0]
        head_name = command_basename(head)

        if head_name in {"bash", "sh", "zsh"}:
            shell_payload_index = None
            for idx, token in enumerate(tokens[1:], start=1):
                if token == "--":
                    break
                if token.startswith("-") and not token.startswith("--") and "c" in token[1:]:
                    shell_payload_index = idx + 1
                    break

            if shell_payload_index is not None:
                if shell_payload_index >= len(tokens):
                    return [], path_prefix
                try:
                    tokens = shlex.split(tokens[shell_payload_index])
                except ValueError:
                    return [], path_prefix
                tokens = strip_env_prefix(tokens)
                tokens, path_prefix = strip_leading_shell_chain(tokens, path_prefix)
                continue

        tokens, path_prefix = strip_leading_shell_chain(tokens, path_prefix)

        if (head_name == "py" or head_name.startswith("python")) and len(tokens) >= 3 and tokens[1] == "-m" and tokens[2] == "pytest":
            tokens = ["pytest"] + tokens[3:]
            continue

        if head_name == "uv":
            run_index, path_prefix = skip_leading_cli_options(tokens[1:], path_prefix)
            if run_index is not None and tokens[1 + run_index] == "run":
                payload = tokens[2 + run_index :]
                payload = strip_env_prefix(payload)
                payload, path_prefix = strip_leading_shell_chain(payload, path_prefix)
                payload_index, path_prefix = skip_leading_cli_options(payload, path_prefix)
                if payload_index is None or payload_index >= len(payload):
                    return [], path_prefix
                tokens = payload[payload_index:]
                continue

        if head_name in {"npx", "pnpx"}:
            command_index, path_prefix = skip_leading_cli_options(tokens[1:], path_prefix)
            if command_index is None:
                return [], path_prefix
            i = 1 + command_index
            while i < len(tokens):
                token = tokens[i]
                if token == "--":
                    i += 1
                    break
                if token in {"-y", "--yes", "--no-install"}:
                    i += 1
                    continue
                if token in {"-p", "--package"}:
                    if i + 1 >= len(tokens):
                        return []
                    i += 2
                    continue
                if token in cli_option_value_flags:
                    if i + 1 >= len(tokens):
                        return []
                    i += 2
                    continue
                if any(token.startswith(f"{flag}=") for flag in cli_option_value_flags):
                    i += 1
                    continue
                if token.startswith("-"):
                    i += 1
                    continue
                break

            if i < len(tokens) and tokens[i] in test_runners:
                tokens = [tokens[i]] + tokens[i + 1:]
                continue

            return tokens

        if head_name in {"npm", "pnpm", "yarn", "bun"}:
            command_index, path_prefix = skip_leading_cli_options(tokens[1:], path_prefix)
            if command_index is not None and tokens[1 + command_index] == "exec":
                i = 2 + command_index
                while i < len(tokens):
                    token = tokens[i]
                    if token == "--":
                        i += 1
                        break
                    if token in {"-p", "--package"}:
                        if i + 1 >= len(tokens):
                            return [], path_prefix
                        i += 2
                        continue
                    if token in cli_option_value_flags:
                        if i + 1 >= len(tokens):
                            return [], path_prefix
                        i += 2
                        continue
                    if any(token.startswith(f"{flag}=") for flag in cli_option_value_flags):
                        i += 1
                        continue
                    if token.startswith("-"):
                        i += 1
                        continue
                    break

                if i < len(tokens) and tokens[i] in test_runners:
                    tokens = [tokens[i]] + tokens[i + 1:]
                    continue

        return tokens, path_prefix


def is_test_script(name):
    return name == "test" or name.startswith("test:")


def positional_tokens(args):
    result = []
    i = 0
    while i < len(args):
        token = args[i]
        if token == "--":
            result.extend(args[i + 1 :])
            break
        if token in dir_option_value_flags or token in selector_option_value_flags:
            if i + 1 >= len(args):
                break
            i += 2
            continue
        if any(token.startswith(f"{flag}=") for flag in cli_option_value_flags):
            i += 1
            continue
        if token.startswith("-"):
            i += 1
            continue
        result.append(token)
        i += 1
    return result


def candidate_target_tokens(tokens):
    cmd_name = command_basename(tokens[0])

    if shell_test_script_re.search(tokens[0]):
        return [tokens[0]]

    if cmd_name in {"bash", "sh", "zsh"}:
        return positional_tokens(tokens[1:])

    if cmd_name in test_runners:
        return positional_tokens(tokens[1:])

    if cmd_name in {"cargo", "go"} and len(tokens) > 1 and tokens[1] == "test":
        return positional_tokens(tokens[2:])

    if cmd_name not in {"npm", "pnpm", "yarn", "bun"}:
        return []

    command_index, _ = skip_leading_cli_options(tokens[1:], "")
    if command_index is None:
        return []

    i = 1 + command_index
    if i >= len(tokens):
        return []

    head = tokens[i]
    if head in test_runners:
        return positional_tokens(tokens[i + 1 :])

    if head in {"workspace", "workspaces"}:
        if i + 2 >= len(tokens):
            return []
        subcommand = tokens[i + 2]
        if subcommand in test_runners:
            return positional_tokens(tokens[i + 3 :])
        if subcommand == "run" and i + 3 < len(tokens) and tokens[i + 3] in test_runners:
            return positional_tokens(tokens[i + 4 :])
        if subcommand == "run" and i + 3 < len(tokens) and is_test_script(tokens[i + 3]):
            return positional_tokens(tokens[i + 4 :])
        if is_test_script(subcommand):
            return positional_tokens(tokens[i + 3 :])
        return []

    if head == "recursive":
        if i + 1 < len(tokens) and tokens[i + 1] in test_runners:
            return positional_tokens(tokens[i + 2 :])
        return []

    if head == "run" and i + 1 < len(tokens) and tokens[i + 1] in test_runners:
        return positional_tokens(tokens[i + 2 :])

    if head == "run" and i + 1 < len(tokens) and is_test_script(tokens[i + 1]):
        return positional_tokens(tokens[i + 2 :])

    if is_test_script(head):
        return positional_tokens(tokens[i + 1 :])

    return []


tokens, path_prefix = normalize_tokens(argv)
if not tokens:
    raise SystemExit(1)

for token in candidate_target_tokens(tokens):
    if shell_test_script_re.search(token) or test_file_re.search(token):
        print(canonicalize_record_path(path_prefix, token))
        raise SystemExit(0)

raise SystemExit(1)
PY
}

if [ "$TOOL_NAME" = "AskUserQuestion" ]; then
  update_state '.current_phase = "brainstorming" | .brainstorming.question_asked = true | .brainstorming.findings_updated_after_question = false'
fi

if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ]; then
  FILE_PATH="$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')"
  if [ -n "$FILE_PATH" ]; then
    NORMALIZED_FILE_PATH="$(normalize_workflow_entry_path "$FILE_PATH")"

    if [ "$(basename "$FILE_PATH")" = "findings.md" ]; then
      jq --arg now "$NOW_UTC" '.current_phase = "brainstorming" | .brainstorming.findings_updated_after_question = true | .brainstorming.findings_last_update = $now' "$STATE_FILE" > "$tmp_file"
      mv "$tmp_file" "$STATE_FILE"
    fi

    if echo "$NORMALIZED_FILE_PATH" | grep -qE '^docs/superpowers/specs/.*\.md$'; then
      jq --arg path "$FILE_PATH" --arg now "$NOW_UTC" '
        .current_phase = "brainstorming"
        | .brainstorming.spec_written = true
        | .brainstorming.spec_file = $path
        | .workflow.active = true
        | .workflow.activated_by = "spec_write"
        | .workflow.activated_at = $now
      ' "$STATE_FILE" > "$tmp_file"
      mv "$tmp_file" "$STATE_FILE"
      SPEC_WRITE_RECORDED=true
    fi

    if echo "$NORMALIZED_FILE_PATH" | grep -qE '^docs/superpowers/plans/.*\.md$'; then
      jq --arg path "$FILE_PATH" --arg now "$NOW_UTC" '
        .current_phase = "planning"
        | .planning.plan_written = true
        | .planning.plan_file = $path
        | .workflow.active = true
        | .workflow.activated_by = "plan_write"
        | .workflow.activated_at = $now
      ' "$STATE_FILE" > "$tmp_file"
      mv "$tmp_file" "$STATE_FILE"
      PLAN_WRITE_RECORDED=true
    fi

    if echo "$FILE_PATH" | grep -qE '(^|/)(test|tests|spec|__tests__)/|\.test\.|\.spec\.|_test\.|_spec\.'; then
      append_unique_string_to_array "tdd.test_files_created" "$FILE_PATH"
    else
      append_unique_string_to_array "tdd.production_files_written" "$FILE_PATH"
    fi
  fi
fi

if [ "$TOOL_NAME" = "Bash" ]; then
  COMMAND="$(echo "$INPUT" | jq -r '.tool_input.command // ""')"
  RESULT_TEXT="$(echo "$INPUT" | jq -r '.tool_result | if . == null then "" elif type == "string" then . else tostring end')"
  DEBUGGING_ACTIVE="$(jq -r '.debugging.active // false' "$STATE_FILE")"
  WORKTREE_PATH="$(extract_worktree_path "$COMMAND" || true)"

  if [ "$HOOK_EVENT" = "PostToolUseFailure" ]; then
    FAILURE_ROUTE="$(classify_failure_test_command "$COMMAND")"

    if [ "$FAILURE_ROUTE" != "none" ]; then
      case "$FAILURE_ROUTE" in
        auto:*)
          TEST_PATH="${FAILURE_ROUTE#auto:}"
          append_unique_string_to_array "tdd.tests_verified_fail" "$TEST_PATH"
          update_state '.tdd.pending_failure_record = false | .tdd.last_failed_command = null'
          ;;
        ambiguous)
          jq --arg command "$COMMAND" '.tdd.pending_failure_record = true | .tdd.last_failed_command = $command' "$STATE_FILE" > "$tmp_file"
          mv "$tmp_file" "$STATE_FILE"
          ;;
      esac

      if [ "$DEBUGGING_ACTIVE" = "true" ]; then
        echo '{"continue":true}'
        exit 0
      fi

      update_state '.current_phase = "debugging" | .debugging.active = true'

      echo '{"continue":false,"systemMessage":"检测到测试失败，请先执行 systematic-debugging 再改代码。"}'
      exit 0
    fi
  fi

  if [ -n "$WORKTREE_PATH" ]; then
    if ! echo "$RESULT_TEXT" | grep -qiE '^[[:space:]]*(fatal:|error:)'; then
      jq --arg path "$WORKTREE_PATH" '.current_phase = "worktree" | .worktree.created = true | .worktree.path = $path | .worktree.baseline_verified = false' "$STATE_FILE" > "$tmp_file"
      mv "$tmp_file" "$STATE_FILE"
      WORKTREE_ADD_RECORDED=true
    fi
  fi

  if command_is_test "$COMMAND"; then
    TEST_PATH="$(test_target_path "$COMMAND" || true)"
    if [ -n "$TEST_PATH" ]; then
      if echo "$RESULT_TEXT" | grep -qiE 'pass|passed|ok'; then
        append_unique_string_to_array "tdd.tests_verified_pass" "$TEST_PATH"
      fi
    fi
  fi
fi

if [ "$HOOK_EVENT" = "PostToolUse" ]; then
  if [ "$SPEC_WRITE_RECORDED" = "true" ] && ! state_is_true '.brainstorming.spec_reviewed'; then
    block_posttool "SPEC 已写入，必须先完成 Self-Review 并让用户批准后再进入 planning。"
  fi

  if [ "$PLAN_WRITE_RECORDED" = "true" ] && ! state_is_true '.worktree.created'; then
    block_posttool "Plan 已写完，先执行 using-git-worktrees 创建隔离工作区并跑 baseline tests。"
  fi

  if [ "$WORKTREE_ADD_RECORDED" = "true" ] && ! state_is_true '.worktree.baseline_verified'; then
    block_posttool "Worktree 已创建，必须先完成 setup 和 baseline verification。"
  fi
fi

allow_hook
