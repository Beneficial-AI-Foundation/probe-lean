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
echo "=== resolve_cli_rev (install.sh) agrees with tools/resolve-cli-rev.sh ==="

# The inline resolver in install.sh and the canonical tools/resolve-cli-rev.sh
# carry an identical awk algorithm kept consistent only by a "keep in sync"
# comment (install.sh must be standalone for `curl | bash`, so it cannot call the
# script). This differential test is the guard against drift: feed both the same
# tag list and target set, assert stdout AND exit code match. Cases stress the
# ordering the awk owns — multi-digit patch, RC ordering, stable-target-with-only-
# RCs, untagged minor, and malformed input.
RESOLVER="$HERE/../tools/resolve-cli-rev.sh"
DIFF_TAGS=$(mktemp)
cat > "$DIFF_TAGS" <<'EOF'
v4.28.0
v4.28.0-rc1
v4.31.0
v4.32.0
v4.32.2
v4.32.9
v4.32.0-rc2
v4.32.0-rc10
v4.33.0-rc1
EOF
export LEAN_CLI_TAGS_FILE="$DIFF_TAGS"

diff_targets=(v4.28.0 v4.28.1 v4.31.0 v4.31.9 v4.32.0 v4.32.2 v4.32.10 \
              v4.32.0-rc2 v4.32.0-rc10 v4.33.0 v4.33.0-rc1 v4.34.0 v4.32 badinput)

diff_fail=0
declare -a REV_OUT
i=0
for t in "${diff_targets[@]}"; do
    ra=0; A=$(resolve_cli_rev "$t" 2>/dev/null) || ra=$?         # install.sh inline
    rb=0; B=$("$RESOLVER" "$t" 2>/dev/null) || rb=$?             # canonical script
    REV_OUT[$i]="$A"
    if [ "$A" != "$B" ] || [ "$ra" != "$rb" ]; then
        echo "  FAIL: resolvers disagree on $t (install='$A'/$ra, script='$B'/$rb)"
        diff_fail=$((diff_fail + 1))
    fi
    i=$((i + 1))
done

# Absolute spot-checks on the ordering the awk owns (agreement alone could be
# jointly wrong).
assert_eq "multi-digit patch picks highest stable <= target" "v4.32.9" "${REV_OUT[6]}"   # v4.32.10
assert_eq "rc10 > rc2 ordering" "v4.32.0-rc10" "${REV_OUT[8]}"                            # v4.32.0-rc10
if [ "$diff_fail" -eq 0 ]; then
    echo "  PASS: resolvers agree on all ${#diff_targets[@]} targets (stdout + exit)"
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + diff_fail))
fi

unset LEAN_CLI_TAGS_FILE
rm -f "$DIFF_TAGS"

echo ""
echo "=== Testing release_tag_from_url ==="

assert_eq "tag from download URL" "v0.9.4" \
    "$(release_tag_from_url "https://github.com/o/r/releases/download/v0.9.4/probe-lean-v4.28.0-rc1-linux-x86_64.tar.gz")"
assert_eq "no tag in URL" "" "$(release_tag_from_url "https://example.com/probe-lean.tar.gz")"
assert_eq "empty URL" "" "$(release_tag_from_url "")"

echo ""
echo "=== Testing version_older_than ==="

older_case() { if version_older_than "$1" "$2"; then echo yes; else echo no; fi; }
assert_eq "0.9.4 < v0.18.2" "yes" "$(older_case 0.9.4 v0.18.2)"
assert_eq "multi-digit: 0.9.6 < 0.18.2" "yes" "$(older_case 0.9.6 0.18.2)"
assert_eq "v-prefixed both" "yes" "$(older_case v0.9.4 v0.18.2)"
assert_eq "major wins" "yes" "$(older_case 0.99.99 1.0.0)"
assert_eq "equal" "no" "$(older_case 0.18.2 v0.18.2)"
assert_eq "newer" "no" "$(older_case 0.19.0 v0.18.2)"
assert_eq "empty first" "no" "$(older_case "" v0.18.2)"
assert_eq "empty second" "no" "$(older_case 0.9.4 "")"
assert_eq "malformed" "no" "$(older_case 0.9 v0.18.2)"

echo ""
echo "=== Testing stale_asset_warning ==="

OUT=$(stale_asset_warning v4.28.0-rc1 v0.9.4 v0.18.2 2>&1 >/dev/null)
assert_eq "older asset warns" "Warning: the newest probe-lean release (v0.18.2) has no asset for Lean v4.28.0-rc1." \
    "$(printf '%s\n' "$OUT" | head -1)"
case "$OUT" in *"issues?q=label%3Alean-build-failure"*) R=yes ;; *) R=no ;; esac
assert_eq "older asset warning has the build hint" "yes" "$R"
assert_eq "older asset prints nothing on stdout" "" "$(stale_asset_warning v4.28.0-rc1 v0.9.4 v0.18.2 2>/dev/null)"
assert_eq "same tag prints nothing" "" "$(stale_asset_warning v4.28.0 v0.18.2 v0.18.2 2>&1)"
assert_eq "empty newest tag prints nothing" "" "$(stale_asset_warning v4.28.0 v0.9.4 "" 2>&1)"
assert_eq "empty asset tag prints nothing" "" "$(stale_asset_warning v4.28.0 "" v0.18.2 2>&1)"

echo ""
echo "=== Testing installed_binary_warning ==="

OUT=$(installed_binary_warning v4.28.0 0.9.6 v0.18.2 1 2>&1 >/dev/null)
assert_eq "older binary, newest has asset: first line" \
    "Warning: the installed probe-lean-v4.28.0 is version 0.9.6. The newest release is v0.18.2." \
    "$(printf '%s\n' "$OUT" | head -1)"
case "$OUT" in *"--force"*) R=yes ;; *) R=no ;; esac
assert_eq "older binary, newest has asset: --force hint" "yes" "$R"
case "$OUT" in *"lean-build-failure"*) R=yes ;; *) R=no ;; esac
assert_eq "older binary, newest has asset: no build hint" "no" "$R"
OUT=$(installed_binary_warning v4.28.0-rc1 0.9.4 v0.18.2 0 2>&1 >/dev/null)
case "$OUT" in *"issues?q=label%3Alean-build-failure"*) R=yes ;; *) R=no ;; esac
assert_eq "older binary, no asset: build hint" "yes" "$R"
case "$OUT" in *"--force"*) R=yes ;; *) R=no ;; esac
assert_eq "older binary, no asset: no --force hint" "no" "$R"
assert_eq "equal version prints nothing" "" "$(installed_binary_warning v4.28.0 0.18.2 v0.18.2 1 2>&1)"
assert_eq "newer version prints nothing" "" "$(installed_binary_warning v4.28.0 0.19.0 v0.18.2 1 2>&1)"
assert_eq "empty version prints nothing" "" "$(installed_binary_warning v4.28.0 "" v0.18.2 1 2>&1)"
assert_eq "empty newest tag prints nothing" "" "$(installed_binary_warning v4.28.0 0.9.6 "" 1 2>&1)"

echo ""
echo "=== Testing find_release_asset (fake curl) ==="

# The fake curl serves "$FAKE_PAGES/page<N>.json" for the page=<N> query, and
# "[]" when the file does not exist.
FAKE_PAGES=$(mktemp -d)
curl() {
    local arg page=""
    for arg in "$@"; do
        case "$arg" in *"page="*) page=$(printf '%s' "$arg" | sed 's/.*[?&]page=\([0-9]*\).*/\1/') ;; esac
    done
    if [ -f "$FAKE_PAGES/page$page.json" ]; then cat "$FAKE_PAGES/page$page.json"; else echo "[]"; fi
}
PLAT=$(detect_platform)
release_json() {  # <tag> [lean-version...]: one release object with assets
    local tag=$1 v sep=""
    shift
    printf '{\n    "tag_name": "%s",\n    "assets": [' "$tag"
    for v in "$@"; do
        printf '%s\n      {"browser_download_url": "https://github.com/o/r/releases/download/%s/probe-lean-%s-%s.tar.gz"}' \
            "$sep" "$tag" "$v" "$PLAT"
        sep=","
    done
    printf '\n    ]\n  }'
}

printf '[\n  %s,\n  %s\n]\n' "$(release_json v0.18.2 v4.28.0)" "$(release_json v0.18.1 v4.28.0)" > "$FAKE_PAGES/page1.json"
printf '[\n  %s\n]\n' "$(release_json v0.9.4 v4.28.0-rc1 v4.28.0)" > "$FAKE_PAGES/page2.json"

find_release_asset v4.28.0
assert_eq "asset on newest: tag" "v0.18.2" "$(release_tag_from_url "$ASSET_URL")"
assert_eq "asset on newest: NEWEST_TAG" "v0.18.2" "$NEWEST_TAG"

find_release_asset v4.28.0-rc1
assert_eq "asset only on page 2: tag" "v0.9.4" "$(release_tag_from_url "$ASSET_URL")"
assert_eq "asset only on page 2: NEWEST_TAG from page 1" "v0.18.2" "$NEWEST_TAG"

find_release_asset v4.99.0
assert_eq "no asset: ASSET_URL empty" "" "$ASSET_URL"
assert_eq "no asset: NEWEST_TAG still set" "v0.18.2" "$NEWEST_TAG"

rm -f "$FAKE_PAGES/page2.json"
printf '{"message": "API rate limit exceeded"}\n' > "$FAKE_PAGES/page1.json"
find_release_asset v4.28.0 2>/dev/null
assert_eq "error body: ASSET_URL empty" "" "$ASSET_URL"
assert_eq "error body: NEWEST_TAG empty" "" "$NEWEST_TAG"

unset -f curl
rm -rf "$FAKE_PAGES"

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
