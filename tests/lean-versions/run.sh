#!/usr/bin/env bash
# Tests for tools/lean-versions.sh (version-policy derivation).
# Run from the probe-lean root directory: bash tests/lean-versions/run.sh
#
# Uses a fixed releases fixture so the policy is exercised without the network.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../../tools/lean-versions.sh"
FIXTURE="$HERE/fixtures/releases.json"

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

# Asserts the given command exits non-zero (a failure that must be surfaced).
assert_fails() {
    local name=$1; shift
    if "$@" >/dev/null 2>&1; then
        echo "  FAIL: $name (expected non-zero exit, got success)"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: $name"
        PASS=$((PASS + 1))
    fi
}

echo "Testing version policy..."

# Default floor (v4.28.0-rc1): stable lines collapse to their stable; the only
# line without a stable (4.32.0) yields its latest RC (rc10 > rc2, numerically).
assert_eq "default policy" \
    $'v4.28.0\nv4.29.0\nv4.30.0\nv4.31.0\nv4.32.0-rc10' \
    "$(LEAN_RELEASES_FILE="$FIXTURE" "$SCRIPT")"

# JSON mode is a valid array in the same order.
assert_eq "json mode" \
    '["v4.28.0","v4.29.0","v4.30.0","v4.31.0","v4.32.0-rc10"]' \
    "$(LEAN_RELEASES_FILE="$FIXTURE" "$SCRIPT" --json | jq -c .)"

# Raising the floor to v4.30.0 drops 4.28/4.29.
assert_eq "floor=v4.30.0" \
    $'v4.30.0\nv4.31.0\nv4.32.0-rc10' \
    "$(LEAN_VERSION_FLOOR=v4.30.0 LEAN_RELEASES_FILE="$FIXTURE" "$SCRIPT")"

# A floor that is itself an RC is honored (v4.32.0-rc10 >= v4.32.0-rc2).
assert_eq "floor=v4.32.0-rc2 (RC-valued floor)" \
    'v4.32.0-rc10' \
    "$(LEAN_VERSION_FLOOR=v4.32.0-rc2 LEAN_RELEASES_FILE="$FIXTURE" "$SCRIPT")"

# A floor above everything yields zero tags: plain mode prints *no* lines (not a
# blank line), JSON mode prints an empty array.
assert_eq "empty plain output has no lines" "" \
    "$(LEAN_VERSION_FLOOR=v999.0.0 LEAN_RELEASES_FILE="$FIXTURE" "$SCRIPT")"
assert_eq "empty json output is []" "[]" \
    "$(LEAN_VERSION_FLOOR=v999.0.0 LEAN_RELEASES_FILE="$FIXTURE" "$SCRIPT" --json | jq -c .)"

# Failure paths must exit non-zero, not silently produce wrong output.
assert_fails "non-array API response (rate limit) fails" \
    env LEAN_RELEASES_FILE="$HERE/fixtures/rate-limited.json" "$SCRIPT"
assert_fails "version component above the 5-digit bound fails" \
    env LEAN_RELEASES_FILE="$HERE/fixtures/oversized.json" "$SCRIPT"
assert_fails "--releases-file with no path fails" \
    "$SCRIPT" --releases-file
assert_fails "unknown argument fails" \
    "$SCRIPT" --bogus

echo
echo "Passed: $PASS, Failed: $FAIL"
[ "$FAIL" -eq 0 ]
