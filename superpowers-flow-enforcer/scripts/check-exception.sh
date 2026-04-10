#!/bin/bash
set -euo pipefail

# Check if file path matches TDD exception patterns
# Returns JSON: {"is_exception": true/false, "category": "config|types|docs|generated|specs|plugin"}

FILE_PATH="${1:-}"

# Normalize path - strip leading ./ prefix
FILE_PATH="${FILE_PATH#./}"

if [ -z "$FILE_PATH" ]; then
  echo '{"error": "No file path provided"}' >&2
  exit 1
fi

# Exception patterns (glob-style) - read via heredoc to prevent glob expansion
# IMPORTANT: More specific patterns must come BEFORE general patterns
read -r -d '' EXCEPTIONS <<'EOF' || true
docs/superpowers/specs/*
docs/superpowers/plans/*
docs/design/*
superpowers-flow-enforcer/*
.claude/*
package.json
package-lock.json
Cargo.toml
Cargo.lock
pyproject.toml
poetry.lock
*.config.*
*.json
*.yaml
*.yml
.env*
.env.*
*.d.ts
types/*.ts
*.types.ts
*.pyx
*.pyi
*.generated.*
dist/*
build/*
node_modules/*
__pycache__/*
.venv/*
*.md
docs/*
README*
CHANGELOG*
EOF

# Check each pattern (disable globbing to prevent expansion)
IS_EXCEPTION=false
CATEGORY=""

# Use set -f to disable glob expansion during iteration
set -f
for pattern in $EXCEPTIONS; do
  set +f
  case "$FILE_PATH" in
    $pattern)
      IS_EXCEPTION=true
      # Determine category - order matters: more specific patterns first
      case "$pattern" in
        docs/superpowers/specs/*|docs/superpowers/plans/*|docs/design/*)
          CATEGORY="specs"
          ;;
        superpowers-flow-enforcer/*|.claude/*)
          CATEGORY="plugin"
          ;;
        package.json|package-lock.json|Cargo.toml|Cargo.lock|pyproject.toml|poetry.lock)
          CATEGORY="config"
          ;;
        *.config.*|*.json|*.yaml|*.yml|.env*)
          CATEGORY="config"
          ;;
        *.d.ts|types/*.ts|*.types.ts|*.pyx|*.pyi)
          CATEGORY="types"
          ;;
        *.generated.*|dist/*|build/*|node_modules/*|__pycache__/*|.venv/*)
          CATEGORY="generated"
          ;;
        *.md|README*|CHANGELOG*)
          CATEGORY="docs"
          ;;
        docs/*)
          CATEGORY="docs"
          ;;
      esac
      # Default category fallback if pattern not in category mapping
      if [ -z "$CATEGORY" ]; then
        CATEGORY="unknown"
      fi
      break
      ;;
  esac
  set -f
done
set +f

echo "{\"is_exception\": $IS_EXCEPTION, \"category\": \"$CATEGORY\"}"
exit 0