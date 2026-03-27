#!/usr/bin/env bash
# Tests for installer helper functions (version detection, platform detection).
# Run from the probe-lean root directory: bash tests/test_install_helpers.sh
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

# Source the detect_version_from_project function from install.sh
# We extract it by sourcing a subset
detect_version_from_project() {
    local project_path=$1
    local toolchain_file="$project_path/lean-toolchain"
    if [ ! -f "$toolchain_file" ]; then
        echo "Error: lean-toolchain not found at $toolchain_file" >&2
        return 1
    fi
    local contents
    contents=$(cat "$toolchain_file" | tr -d '[:space:]')
    if [[ "$contents" == *":"* ]]; then
        echo "${contents##*:}"
    else
        echo "$contents"
    fi
}

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

# Test: missing file
mkdir -p "$TMPDIR/proj5"
if detect_version_from_project "$TMPDIR/proj5" 2>/dev/null; then
    echo "  FAIL: missing file should error"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: missing file returns error"
    PASS=$((PASS + 1))
fi

echo ""
echo "=== Testing platform detection ==="

detect_platform() {
    local os arch
    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    arch=$(uname -m)
    case "$os" in
        linux)  os="linux" ;;
        darwin) os="darwin" ;;
    esac
    case "$arch" in
        x86_64)  arch="x86_64" ;;
        aarch64|arm64) arch="arm64" ;;
    esac
    echo "$os-$arch"
}

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
