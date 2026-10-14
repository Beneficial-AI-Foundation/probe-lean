#!/usr/bin/env bash
# Tests for tools/lean-versions.sh (version-policy derivation).
# Run from the probe-lean root directory: bash tests/lean-versions/run.sh
#
# Uses fixed fixtures so the policy is exercised without the network:
#   fixtures/releases.json  — leanprover/lean4 releases
#   fixtures/cli-tags.txt   — leanprover/lean4-cli tags (LEAN_CLI_TAGS_FILE)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../../tools/lean-versions.sh"
FIXTURE="$HERE/fixtures/releases.json"

# Inject the lean4-cli tag list for every invocation so tests stay offline. The
# fixture tags minors 4.27-4.31 (incl. patch v4.30.1) and only RCs for 4.32, but
# nothing for 4.33/4.34. So v4.31.1 (patch on a tagged minor) is KEPT via its
# minor's tag. v4.33.1 (untagged minor) and v4.31.0-rc1 (the only 4.31 tag is
# the stable above it) reach the resolver and are dropped.
export LEAN_CLI_TAGS_FILE="$HERE/fixtures/cli-tags.txt"

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

# Default floor (v4.28.0-rc1): every stable and RC at or above the floor, with
# superseded RCs kept. Each RC sorts below its own stable, and RC numbers sort
# numerically (rc10 > rc2).
DEFAULT_LIST=$'v4.28.0-rc1\nv4.28.0\nv4.29.0-rc4\nv4.29.0-rc8\nv4.29.0\nv4.30.0-rc2\nv4.30.0\nv4.30.1\nv4.31.0\nv4.31.1\nv4.32.0-rc2\nv4.32.0-rc10'
assert_eq "default policy" \
    "$DEFAULT_LIST" \
    "$(LEAN_RELEASES_FILE="$FIXTURE" "$SCRIPT")"

# JSON mode is a valid array in the same order.
assert_eq "json mode" \
    '["v4.28.0-rc1","v4.28.0","v4.29.0-rc4","v4.29.0-rc8","v4.29.0","v4.30.0-rc2","v4.30.0","v4.30.1","v4.31.0","v4.31.1","v4.32.0-rc2","v4.32.0-rc10"]' \
    "$(LEAN_RELEASES_FILE="$FIXTURE" "$SCRIPT" --json | jq -c .)"

# Raising the floor to v4.30.0 drops 4.28, 4.29 and v4.30.0-rc2.
assert_eq "floor=v4.30.0" \
    $'v4.30.0\nv4.30.1\nv4.31.0\nv4.31.1\nv4.32.0-rc2\nv4.32.0-rc10' \
    "$(LEAN_VERSION_FLOOR=v4.30.0 LEAN_RELEASES_FILE="$FIXTURE" "$SCRIPT")"

# A floor that is itself an RC is honored, and RCs compare numerically.
assert_eq "floor=v4.32.0-rc2 (RC-valued floor)" \
    $'v4.32.0-rc2\nv4.32.0-rc10' \
    "$(LEAN_VERSION_FLOOR=v4.32.0-rc2 LEAN_RELEASES_FILE="$FIXTURE" "$SCRIPT")"

# A floor above everything yields zero tags: plain mode prints *no* lines (not a
# blank line), JSON mode prints an empty array.
assert_eq "empty plain output has no lines" "" \
    "$(LEAN_VERSION_FLOOR=v999.0.0 LEAN_RELEASES_FILE="$FIXTURE" "$SCRIPT")"
assert_eq "empty json output is []" "[]" \
    "$(LEAN_VERSION_FLOOR=v999.0.0 LEAN_RELEASES_FILE="$FIXTURE" "$SCRIPT" --json | jq -c .)"

# An empty release list gives an empty array, not an error.
assert_eq "empty release list gives []" "[]" \
    "$(LEAN_RELEASES_FILE="$HERE/fixtures/empty.json" "$SCRIPT" --json | jq -c .)"

default_out="$(LEAN_RELEASES_FILE="$FIXTURE" "$SCRIPT")"
assert_in() {
    local name=$1 tag=$2
    if printf '%s\n' "$default_out" | grep -qx "$tag"; then
        echo "  PASS: $name"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $name ($tag missing)"; FAIL=$((FAIL + 1))
    fi
}
assert_out() {
    local name=$1 tag=$2
    if printf '%s\n' "$default_out" | grep -qx "$tag"; then
        echo "  FAIL: $name ($tag present)"; FAIL=$((FAIL + 1))
    else
        echo "  PASS: $name"; PASS=$((PASS + 1))
    fi
}

# A superseded RC (its line has a stable) stays in the list.
assert_in "superseded RC v4.29.0-rc4 is kept" "v4.29.0-rc4"

# lean4-cli compatibility filter: a patch on a tagged minor is KEPT (resolves to
# the minor's tag). A version with no compatible tag is dropped.
assert_in "patch on a tagged minor (v4.31.1) is kept" "v4.31.1"
assert_in "tagged patch v4.30.1 is kept" "v4.30.1"
assert_out "stable on an untagged minor (v4.33.1) is dropped" "v4.33.1"
assert_out "RC below its line's only tag (v4.31.0-rc1) is dropped" "v4.31.0-rc1"

# Tags that the policy drops before the resolver runs. Each one is on a minor
# with a lean4-cli tag, so only the policy filter can drop it.
assert_out "draft (v4.30.2) is dropped" "v4.30.2"
assert_out "stable-shaped prerelease (v4.31.2) is dropped" "v4.31.2"
assert_out "below-floor v4.27.0 is dropped" "v4.27.0"

# The fixture lists v4.30.0 twice.
assert_eq "no duplicate lines" "" \
    "$(printf '%s\n' "$default_out" | sort | uniq -d)"

echo
# Failure paths must exit non-zero, not silently produce wrong output.
assert_fails "non-array API response (rate limit) fails" \
    env LEAN_RELEASES_FILE="$HERE/fixtures/rate-limited.json" "$SCRIPT"
assert_fails "version component above the 5-digit bound fails" \
    env LEAN_RELEASES_FILE="$HERE/fixtures/oversized.json" "$SCRIPT"
assert_fails "--releases-file with no path fails" \
    "$SCRIPT" --releases-file
assert_fails "unknown argument fails" \
    "$SCRIPT" --bogus
assert_fails "missing cli-tags file fails" \
    env LEAN_RELEASES_FILE="$FIXTURE" LEAN_CLI_TAGS_FILE="$HERE/fixtures/does-not-exist.txt" "$SCRIPT"

echo
echo "Passed: $PASS, Failed: $FAIL"
[ "$FAIL" -eq 0 ]
