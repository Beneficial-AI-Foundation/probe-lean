#!/usr/bin/env bash
# Tests for installer helper functions (version detection, platform detection,
# lean4-cli tag resolution). Run from the probe-lean root:
#   bash tests/test_install_helpers.sh
#
# Sources the REAL functions from tools/bash/install.sh via the INSTALL_SH_LIB
# guard, so these tests exercise the shipped code rather than copies.
set -euo pipefail

PASS=0
FAIL=0

assert_eq() {
    local name=$1 expected=$2 actual=$3
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $name (expected '$expected', got '$actual')"
        FAIL=$((FAIL + 1))
    fi
}

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
INSTALL_SH_LIB=1 source "$HERE/../tools/bash/install.sh"

echo "=== Testing detect_version_from_project ==="

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Test: standard lean-toolchain format
mkdir -p "$TMPDIR/proj1"
echo "leanprover/lean4:v4.28.0-rc1" > "$TMPDIR/proj1/lean-toolchain"
RESULT=$(detect_version_from_project "$TMPDIR/proj1")
assert_eq "standard format" "v4.28.0-rc1" "$RESULT"

# Test: with trailing newline
mkdir -p "$TMPDIR/proj2"
printf "leanprover/lean4:v4.29.0-rc3\n" > "$TMPDIR/proj2/lean-toolchain"
RESULT=$(detect_version_from_project "$TMPDIR/proj2")
assert_eq "trailing newline" "v4.29.0-rc3" "$RESULT"

# Test: bare version (no channel prefix)
mkdir -p "$TMPDIR/proj3"
echo "v4.28.0-rc1" > "$TMPDIR/proj3/lean-toolchain"
RESULT=$(detect_version_from_project "$TMPDIR/proj3")
assert_eq "bare version" "v4.28.0-rc1" "$RESULT"

# Test: release version (not rc)
mkdir -p "$TMPDIR/proj4"
echo "leanprover/lean4:v4.27.0" > "$TMPDIR/proj4/lean-toolchain"
RESULT=$(detect_version_from_project "$TMPDIR/proj4")
assert_eq "release version" "v4.27.0" "$RESULT"

# detect_version_from_project errors via `exit`, so error-path calls run in a
# subshell ( ... ) to avoid terminating this test script.

# Test: missing file
mkdir -p "$TMPDIR/proj5"
if (detect_version_from_project "$TMPDIR/proj5") 2>/dev/null; then
    echo "  FAIL: missing file should error"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: missing file returns error"
    PASS=$((PASS + 1))
fi

# Test: nonexistent path errors with a distinct message
ERR=$( (detect_version_from_project "$TMPDIR/does-not-exist") 2>&1 ) || true
if [[ "$ERR" == *"path does not exist"* ]]; then
    echo "  PASS: nonexistent path reports 'does not exist'"
    PASS=$((PASS + 1))
else
    echo "  FAIL: nonexistent path message (got '$ERR')"
    FAIL=$((FAIL + 1))
fi

# Test: path is a file, not a directory
echo "leanprover/lean4:v4.30.0" > "$TMPDIR/afile"
ERR=$( (detect_version_from_project "$TMPDIR/afile") 2>&1 ) || true
if [[ "$ERR" == *"not a directory"* ]]; then
    echo "  PASS: file path reports 'not a directory'"
    PASS=$((PASS + 1))
else
    echo "  FAIL: file path message (got '$ERR')"
    FAIL=$((FAIL + 1))
fi

# Test: directory without top-level toolchain auto-detects from a subdirectory
mkdir -p "$TMPDIR/monorepo/lean-pkg"
echo "leanprover/lean4:v4.30.0" > "$TMPDIR/monorepo/lean-pkg/lean-toolchain"
RESULT=$(detect_version_from_project "$TMPDIR/monorepo" 2>/dev/null)
assert_eq "auto-detect from subdirectory" "v4.30.0" "$RESULT"

# Test: multiple subdirs with the SAME version resolve to that version
mkdir -p "$TMPDIR/mono2/a" "$TMPDIR/mono2/b"
echo "leanprover/lean4:v4.30.0" > "$TMPDIR/mono2/a/lean-toolchain"
echo "leanprover/lean4:v4.30.0" > "$TMPDIR/mono2/b/lean-toolchain"
RESULT=$(detect_version_from_project "$TMPDIR/mono2" 2>/dev/null)
assert_eq "same version across subdirs" "v4.30.0" "$RESULT"

# Test: multiple subdirs with DIFFERING versions error (ambiguous, no auto-pick)
mkdir -p "$TMPDIR/mono3/a" "$TMPDIR/mono3/b"
echo "leanprover/lean4:v4.30.0" > "$TMPDIR/mono3/a/lean-toolchain"
echo "leanprover/lean4:v4.31.0" > "$TMPDIR/mono3/b/lean-toolchain"
ERR=$( (detect_version_from_project "$TMPDIR/mono3") 2>&1 ) || true
if [[ "$ERR" == *"differing versions"* ]]; then
    echo "  PASS: differing subdir versions error as ambiguous"
    PASS=$((PASS + 1))
else
    echo "  FAIL: ambiguous versions (got '$ERR')"
    FAIL=$((FAIL + 1))
fi

# Test: .lake dependency toolchains are excluded from the search
mkdir -p "$TMPDIR/mono4/.lake/packages/dep" "$TMPDIR/mono4/pkg"
echo "leanprover/lean4:v4.99.0" > "$TMPDIR/mono4/.lake/packages/dep/lean-toolchain"
echo "leanprover/lean4:v4.30.0" > "$TMPDIR/mono4/pkg/lean-toolchain"
RESULT=$(detect_version_from_project "$TMPDIR/mono4" 2>/dev/null)
assert_eq "ignores .lake dependency toolchains" "v4.30.0" "$RESULT"

echo ""
echo "=== Testing resolve_cli_rev (lean4-cli tag resolution) ==="

# Fixed lean4-cli tag list injected via LEAN_CLI_TAGS_FILE. Minor 4.32 has a
# stable tag plus RCs; minor 4.33 has ONLY an RC; minor 4.35 is absent entirely.
CLI_TAGS=$(mktemp)
cat > "$CLI_TAGS" <<'EOF'
v4.31.0
v4.32.0
v4.32.0-rc2
v4.32.0-rc10
v4.33.0-rc1
EOF
export LEAN_CLI_TAGS_FILE="$CLI_TAGS"

# Helper: capture output and exit status of resolve_cli_rev without set -e abort.
resolve_case() {  # <target> -> sets OUT and RC
    RC=0
    OUT=$(resolve_cli_rev "$1" 2>/dev/null) || RC=$?
}

# Exact stable match wins.
resolve_case "v4.32.0"
assert_eq "exact stable -> itself" "v4.32.0" "$OUT"
assert_eq "exact stable exit 0" "0" "$RC"

# Patch release with no patch tag resolves to the minor's stable tag.
resolve_case "v4.32.2"
assert_eq "patch -> minor stable" "v4.32.0" "$OUT"
assert_eq "patch exit 0" "0" "$RC"

# Exact RC match wins (stable v4.32.0 is > rc2, so excluded by <=).
resolve_case "v4.32.0-rc2"
assert_eq "exact rc -> itself" "v4.32.0-rc2" "$OUT"
assert_eq "exact rc exit 0" "0" "$RC"

# Stable target whose minor line has ONLY RC tags -> no pairing (stable != RC).
resolve_case "v4.33.0"
assert_eq "stable target, RC-only minor -> empty" "" "$OUT"
assert_eq "stable/RC constraint exit 1" "1" "$RC"

# Entire major.minor line untagged -> empty, exit 1.
resolve_case "v4.35.0"
assert_eq "untagged minor -> empty" "" "$OUT"
assert_eq "untagged minor exit 1" "1" "$RC"

# Malformed target (missing patch component) -> exit 2, before any resolution.
resolve_case "v4.32"
assert_eq "malformed (no patch) -> empty" "" "$OUT"
assert_eq "malformed exit 2" "2" "$RC"

# Malformed target (toolchain-prefixed string, not stripped) -> exit 2.
resolve_case "leanprover/lean4:v4.32.2"
assert_eq "malformed (prefixed) -> empty" "" "$OUT"
assert_eq "malformed prefixed exit 2" "2" "$RC"

unset LEAN_CLI_TAGS_FILE
rm -f "$CLI_TAGS"

echo ""
echo "=== Testing platform detection ==="

PLATFORM=$(detect_platform)
# Just verify it produces something reasonable
if [[ "$PLATFORM" =~ ^(linux|darwin)-(x86_64|arm64)$ ]]; then
    echo "  PASS: platform detection ($PLATFORM)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: unexpected platform: $PLATFORM"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
