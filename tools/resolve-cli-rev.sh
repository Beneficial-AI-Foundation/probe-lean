#!/usr/bin/env bash
# Resolve the leanprover/lean4-cli tag to build probe-lean against for a given
# Lean version. lean4-cli tags major.minor lines and RCs, not every patch, so an
# exact match often does not exist (Lean v4.32.2 -> lean4-cli v4.32.0). Print the
# highest tag in the target's major.minor line that is <= the target; a STABLE
# target pairs only with a STABLE tag (never a prerelease Cli).
#
# Canonical resolver, used by tools/lean-versions.sh (version policy) and by the
# release.yml / lean-watch.yml build steps. tools/bash/install.sh carries an
# inline copy of the same algorithm because it must stay standalone for
# `curl | bash`; the differential test in tests/test_install_helpers.sh guards
# the two against drift.
#
# Usage: resolve-cli-rev.sh <vMAJOR.MINOR.PATCH[-rcN]>
# Tags come from $LEAN_CLI_TAGS_FILE if set (one per line; used by tests and by
# lean-versions.sh to reuse an already-fetched list), else `git ls-remote`.
# Prints the resolved tag on stdout. Exit: 0 printed; 1 no compatible tag;
# 2 malformed version; 3 could not fetch tags.
set -euo pipefail

CLI_REPO_URL="https://github.com/leanprover/lean4-cli"

target="${1:-}"
if [ -z "$target" ]; then
    echo "Usage: resolve-cli-rev.sh <lean-version>" >&2
    exit 2
fi
if ! printf '%s' "$target" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?$'; then
    echo "Error: malformed Lean version '$target' (expected vMAJOR.MINOR.PATCH[-rcN])" >&2
    exit 2
fi

if [ -n "${LEAN_CLI_TAGS_FILE:-}" ]; then
    if [ ! -f "$LEAN_CLI_TAGS_FILE" ]; then
        echo "Error: Cli tags file not found: $LEAN_CLI_TAGS_FILE" >&2
        exit 3
    fi
    tags=$(cat "$LEAN_CLI_TAGS_FILE")
else
    if ! tags=$(git ls-remote --tags "$CLI_REPO_URL" 2>/dev/null | sed 's#.*refs/tags/##; s/\^{}$//' | sort -u); then
        echo "Error: could not fetch lean4-cli tags from $CLI_REPO_URL" >&2
        exit 3
    fi
fi
[ -n "$tags" ] || { echo "Error: no lean4-cli tags found" >&2; exit 3; }

best=$(printf '%s\n' "$tags" | awk -v target="$target" '
    function parse(tag,   t, rc, n, a) {
        delete P
        if (match(tag, /^v[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?$/) == 0) return 0
        t = substr(tag, 2); rc = -1
        if (t ~ /-rc[0-9]+$/) { rc = t; sub(/^.*-rc/, "", rc); rc += 0; sub(/-rc[0-9]+$/, "", t) }
        n = split(t, a, "."); if (n != 3) return 0
        P["maj"]=a[1]+0; P["min"]=a[2]+0; P["pat"]=a[3]+0
        P["isrc"]=(rc>=0)?1:0; P["rc"]=(rc>=0)?rc:0
        return 1
    }
    # Leading "v" + fixed-width digits (maj|min|pat|1-isrc|rc) so comparisons are
    # exact STRING compares: an all-digit key is 21 chars > double precision and
    # could be lossily numeric-coerced on some awks. Stable outranks its own RCs.
    # Matches tools/bash/install.sh.
    function key() { return "v" sprintf("%05d%05d%05d%d%05d", P["maj"],P["min"],P["pat"],1-P["isrc"],P["rc"]) }
    BEGIN { parse(target); tmaj=P["maj"]; tmin=P["min"]; tstable=(P["isrc"]==0); tkey=key() }
    { if (parse($0)==0) next
      if (P["maj"]!=tmaj || P["min"]!=tmin) next        # same major.minor only
      if (tstable && P["isrc"]==1) next                 # stable target: no RC Cli
      k=key(); if (k<=tkey && k>bestk) { bestk=k; best=$0 } }
    END { if (best!="") print best }
')
[ -n "$best" ] || exit 1
printf '%s\n' "$best"
