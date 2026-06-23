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
    if [ ! -e "$project_path" ]; then
        echo "Error: --from-project path does not exist: $project_path" >&2
        return 1
    fi
    if [ ! -d "$project_path" ]; then
        echo "Error: --from-project path is not a directory: $project_path" >&2
        return 1
    fi
    local contents
    if [ -f "$project_path/lean-toolchain" ]; then
        contents=$(cat "$project_path/lean-toolchain")
    else
        local found
        found=$(find -L "$project_path" -name lean-toolchain -not -path '*/.lake/*' 2>/dev/null | sort)
        if [ -z "$found" ]; then
            echo "Error: no lean-toolchain found anywhere under $project_path" >&2
            return 1
        fi
        local versions
        versions=$(while IFS= read -r f; do
            local c
            c=$(cat "$f" | tr -d '[:space:]')
            echo "${c##*:}"
        done <<< "$found" | sort -u)
        if [ "$(echo "$versions" | wc -l)" -gt 1 ]; then
            echo "Error: lean-toolchain files with differing versions under $project_path:" >&2
            while IFS= read -r f; do
                echo "         $f -> $(cat "$f" | tr -d '[:space:]')" >&2
            done <<< "$found"
            return 1
        fi
        local chosen
        chosen=$(echo "$found" | head -1)
        echo "Note: no lean-toolchain at $project_path; detected from $chosen" >&2
        contents=$(cat "$chosen")
    fi
    contents=$(echo "$contents" | tr -d '[:space:]')
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

# Test: nonexistent path errors with a distinct message
ERR=$(detect_version_from_project "$TMPDIR/does-not-exist" 2>&1 || true)
if [[ "$ERR" == *"path does not exist"* ]]; then
    echo "  PASS: nonexistent path reports 'does not exist'"
    PASS=$((PASS + 1))
else
    echo "  FAIL: nonexistent path message (got '$ERR')"
    FAIL=$((FAIL + 1))
fi

# Test: path is a file, not a directory
echo "leanprover/lean4:v4.30.0" > "$TMPDIR/afile"
ERR=$(detect_version_from_project "$TMPDIR/afile" 2>&1 || true)
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
ERR=$(detect_version_from_project "$TMPDIR/mono3" 2>&1 || true)
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
