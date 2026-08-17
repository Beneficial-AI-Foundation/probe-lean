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
# fixture tags minors 4.28-4.31 (incl. patch v4.30.1) and only RCs for 4.32, but
# nothing for 4.33/4.34 — so v4.31.1 (patch on a tagged minor) is KEPT via its
# minor's tag, while v4.33.0/v4.34.0 (untagged minors) are dropped.
export LEAN_CLI_TAGS_FILE="$HERE/fixtures/cli-tags.txt"

# Disable the checked-in pinned-extras list so the policy tests assert the
# derived set alone; the extras mechanism has its own section below.
export LEAN_VERSION_EXTRAS_FILE=/dev/null

EXTRAS_TMP="$(mktemp -d)"
trap 'rm -rf "$EXTRAS_TMP"' EXIT

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

# Default floor (v4.28.0-rc1): stable lines collapse to their stable; the only line
# without a stable (4.32.0) yields its latest RC (rc10 > rc2). v4.30.1 and v4.31.1
# are patches kept via their tagged minors; v4.33.0/v4.34.0 have untagged minors
# and are dropped.
assert_eq "default policy" \
    $'v4.28.0\nv4.29.0\nv4.30.0\nv4.30.1\nv4.31.0\nv4.31.1\nv4.32.0-rc10' \
    "$(LEAN_RELEASES_FILE="$FIXTURE" "$SCRIPT")"

# JSON mode is a valid array in the same order.
assert_eq "json mode" \
    '["v4.28.0","v4.29.0","v4.30.0","v4.30.1","v4.31.0","v4.31.1","v4.32.0-rc10"]' \
    "$(LEAN_RELEASES_FILE="$FIXTURE" "$SCRIPT" --json | jq -c .)"

# Raising the floor to v4.30.0 drops 4.28/4.29.
assert_eq "floor=v4.30.0" \
    $'v4.30.0\nv4.30.1\nv4.31.0\nv4.31.1\nv4.32.0-rc10' \
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

# lean4-cli compatibility filter: a patch on a tagged minor is KEPT (resolves to
# the minor's tag); a version whose whole major.minor line is untagged is dropped.
default_out="$(LEAN_RELEASES_FILE="$FIXTURE" "$SCRIPT")"
if printf '%s\n' "$default_out" | grep -qx "v4.31.1"; then
    echo "  PASS: patch on a tagged minor (v4.31.1) is kept"; PASS=$((PASS + 1))
else
    echo "  FAIL: v4.31.1 should be kept (minor 4.31 is tagged)"; FAIL=$((FAIL + 1))
fi
if printf '%s\n' "$default_out" | grep -qx "v4.33.0"; then
    echo "  FAIL: v4.33.0 should be dropped (minor 4.33 is untagged)"; FAIL=$((FAIL + 1))
else
    echo "  PASS: untagged minor (v4.33.0) is dropped"; PASS=$((PASS + 1))
fi
if printf '%s\n' "$default_out" | grep -qx "v4.30.1"; then
    echo "  PASS: tagged patch v4.30.1 is kept"; PASS=$((PASS + 1))
else
    echo "  FAIL: tagged patch v4.30.1 should be kept"; FAIL=$((FAIL + 1))
fi

echo
echo "Testing pinned extras..."

# A pinned superseded RC ships, sorted below its own stable, alongside the
# derived set; comments and blank lines in the extras file are ignored.
cat > "$EXTRAS_TMP/rc8.txt" <<'EOF'
# superseded RC pinned for a target project

v4.29.0-rc8   # trailing comment
EOF
assert_eq "pinned superseded RC ships in sorted position" \
    $'v4.28.0\nv4.29.0-rc8\nv4.29.0\nv4.30.0\nv4.30.1\nv4.31.0\nv4.31.1\nv4.32.0-rc10' \
    "$(LEAN_VERSION_EXTRAS_FILE="$EXTRAS_TMP/rc8.txt" LEAN_RELEASES_FILE="$FIXTURE" "$SCRIPT")"

# An extra that the policy already derives is deduplicated, not doubled.
printf 'v4.29.0\n' > "$EXTRAS_TMP/dup.txt"
assert_eq "extra duplicating a derived version dedups" \
    "$(LEAN_RELEASES_FILE="$FIXTURE" "$SCRIPT")" \
    "$(LEAN_VERSION_EXTRAS_FILE="$EXTRAS_TMP/dup.txt" LEAN_RELEASES_FILE="$FIXTURE" "$SCRIPT")"

# JSON mode carries extras like any other version.
assert_eq "json mode includes pinned extra" \
    '["v4.28.0","v4.29.0-rc8","v4.29.0","v4.30.0","v4.30.1","v4.31.0","v4.31.1","v4.32.0-rc10"]' \
    "$(LEAN_VERSION_EXTRAS_FILE="$EXTRAS_TMP/rc8.txt" LEAN_RELEASES_FILE="$FIXTURE" "$SCRIPT" --json | jq -c .)"

# A pin is a promise to ship an asset, so every bad entry is FATAL, never a
# silent drop: malformed, non-canonical, interior whitespace, below floor,
# not a published (non-draft) lean4 release, no compatible lean4-cli tag
# (v4.34.0 is a non-draft release on an untagged minor), an explicitly named
# extras file that does not exist, and a pin whose release list is empty.
printf 'banana\n' > "$EXTRAS_TMP/malformed.txt"
assert_fails "malformed extras entry fails" \
    env LEAN_VERSION_EXTRAS_FILE="$EXTRAS_TMP/malformed.txt" LEAN_RELEASES_FILE="$FIXTURE" "$SCRIPT"
printf 'v04.29.0-rc8\n' > "$EXTRAS_TMP/non-canonical.txt"
assert_fails "non-canonical extras entry fails" \
    env LEAN_VERSION_EXTRAS_FILE="$EXTRAS_TMP/non-canonical.txt" LEAN_RELEASES_FILE="$FIXTURE" "$SCRIPT"
printf 'v4. 29.0-rc8\n' > "$EXTRAS_TMP/inner-space.txt"
assert_fails "extras entry with interior whitespace fails" \
    env LEAN_VERSION_EXTRAS_FILE="$EXTRAS_TMP/inner-space.txt" LEAN_RELEASES_FILE="$FIXTURE" "$SCRIPT"
printf 'v4.27.0\n' > "$EXTRAS_TMP/below-floor.txt"
assert_fails "below-floor extras entry fails" \
    env LEAN_VERSION_EXTRAS_FILE="$EXTRAS_TMP/below-floor.txt" LEAN_RELEASES_FILE="$FIXTURE" "$SCRIPT"
printf 'v4.29.0-rc7\n' > "$EXTRAS_TMP/unpublished.txt"
assert_fails "extras entry that is not a published release fails" \
    env LEAN_VERSION_EXTRAS_FILE="$EXTRAS_TMP/unpublished.txt" LEAN_RELEASES_FILE="$FIXTURE" "$SCRIPT"
printf 'v4.34.0\n' > "$EXTRAS_TMP/untagged.txt"
assert_fails "extras entry on a lean4-cli-untagged minor fails" \
    env LEAN_VERSION_EXTRAS_FILE="$EXTRAS_TMP/untagged.txt" LEAN_RELEASES_FILE="$FIXTURE" "$SCRIPT"
assert_fails "missing explicit extras file fails" \
    env LEAN_VERSION_EXTRAS_FILE="$EXTRAS_TMP/does-not-exist.txt" LEAN_RELEASES_FILE="$FIXTURE" "$SCRIPT"
assert_fails "pin with an empty release list fails" \
    env LEAN_VERSION_EXTRAS_FILE="$EXTRAS_TMP/rc8.txt" LEAN_RELEASES_FILE="$HERE/fixtures/empty.json" "$SCRIPT"

# The checked-in default extras file is picked up when the env override is
# absent, and its current pins (v4.29.0-rc8) are emitted.
default_extras_out="$(env -u LEAN_VERSION_EXTRAS_FILE LEAN_RELEASES_FILE="$FIXTURE" LEAN_CLI_TAGS_FILE="$LEAN_CLI_TAGS_FILE" "$SCRIPT")"
if printf '%s\n' "$default_extras_out" | grep -qx "v4.29.0-rc8"; then
    echo "  PASS: checked-in extras file ships v4.29.0-rc8"; PASS=$((PASS + 1))
else
    echo "  FAIL: checked-in extras file should ship v4.29.0-rc8"; FAIL=$((FAIL + 1))
fi

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
