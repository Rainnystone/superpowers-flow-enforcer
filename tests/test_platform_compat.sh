#!/bin/bash
set -euo pipefail

source tests/helpers/assert.sh
source scripts/lib/platform_compat.sh

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAKE_BIN="$TMP_DIR/bin"
mkdir -p "$FAKE_BIN"

cat > "$FAKE_BIN/python3" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$FAKE_BIN/python3"

cat > "$FAKE_BIN/python" <<EOF
#!/bin/bash
exit 0
EOF
chmod +x "$FAKE_BIN/python"

PYTHON_STDOUT="$TMP_DIR/platform-python.out"
PYTHON_STDERR="$TMP_DIR/platform-python.err"

PATH="$FAKE_BIN" platform_compat_resolve_python_bin >"$PYTHON_STDOUT" 2>"$PYTHON_STDERR"
assert_file_contains "$PYTHON_STDOUT" "$FAKE_BIN/python"

cat > "$FAKE_BIN/shasum" <<'EOF'
#!/bin/bash
while IFS= read -r _; do
  :
done
printf '%s  -\n' "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
EOF
chmod +x "$FAKE_BIN/shasum"

cat > "$FAKE_BIN/openssl" <<'EOF'
#!/bin/bash
while IFS= read -r _; do
  :
done
printf '%s\n' "SHA256(stdin)= 0000000000000000000000000000000000000000000000000000000000000000"
EOF
chmod +x "$FAKE_BIN/openssl"

cat > "$FAKE_BIN/sha256sum" <<'EOF'
#!/bin/bash
while IFS= read -r _; do
  :
done
echo "sha256sum failed on purpose" >&2
exit 1
EOF
chmod +x "$FAKE_BIN/sha256sum"

HASH_OUTPUT="$(hash -r; printf 'abc' | PATH="$FAKE_BIN" platform_compat_hash_stdin_sha256)"
[ "$HASH_OUTPUT" = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" ] || {
  echo "Expected shasum fallback hash after sha256sum failure, got $HASH_OUTPUT" >&2
  exit 1
}

EMPTY_BIN="$TMP_DIR/empty-bin"
mkdir -p "$EMPTY_BIN"
MISSING_STDOUT="$TMP_DIR/platform-missing.out"
MISSING_STDERR="$TMP_DIR/platform-missing.err"

if hash -r; PATH="$EMPTY_BIN" platform_compat_resolve_python_bin >"$MISSING_STDOUT" 2>"$MISSING_STDERR"; then
  echo "Expected python resolution to fail when neither python3 nor python exists" >&2
  exit 1
fi
assert_file_contains "$MISSING_STDERR" "No working Python interpreter found"
