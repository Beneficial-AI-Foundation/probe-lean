#!/usr/bin/env bash
# Derive the set of supported Lean toolchain versions from the leanprover/lean4
# GitHub releases, applying the probe-lean support policy.
#
# Policy:
#   - Consider non-draft releases whose tag is v<MAJOR>.<MINOR>.<PATCH> or
#     v<MAJOR>.<MINOR>.<PATCH>-rc<N>, at or above the floor (LEAN_VERSION_FLOOR).
#   - Output every *stable* tag (no -rc) >= floor, plus the *latest* RC of any
#     version line that has not yet shipped a stable release.
#   - RCs sort numerically (rc10 > rc2) and below their own stable
#     (v4.29.0-rc8 < v4.29.0).
#
# Output is sorted ascending and deduplicated. Default is newline-separated;
# --json emits a JSON array suitable for a GitHub Actions matrix.
#
# Sources of release data, in order of precedence:
#   1. --releases-file PATH / $LEAN_RELEASES_FILE  (a JSON file; used by tests)
#   2. `gh api --paginate`                          (handles auth + pagination)
#   3. `curl` paginated against the public API
set -euo pipefail

REPO="leanprover/lean4"
CLI_REPO_URL="https://github.com/leanprover/lean4-cli"
FLOOR="${LEAN_VERSION_FLOOR:-v4.28.0-rc1}"
JSON=false
RELEASES_FILE="${LEAN_RELEASES_FILE:-}"
CLI_TAGS_FILE="${LEAN_CLI_TAGS_FILE:-}"

usage() {
    cat <<EOF
Usage: lean-versions.sh [--json] [--releases-file PATH]

Print the Lean versions probe-lean supports, per the support policy.

Options:
  --json                 Emit a JSON array (for a GitHub Actions matrix)
  --releases-file PATH   Read releases JSON from PATH instead of the GitHub API
                         (the file must be the array returned by the releases API)
  -h, --help             Show this help

Environment:
  LEAN_VERSION_FLOOR     Minimum version to consider (default: $FLOOR)
  LEAN_RELEASES_FILE     Same as --releases-file
  LEAN_CLI_TAGS_FILE     Read leanprover/lean4-cli tags from PATH instead of git
                         (one tag per line; used by tests)
  GH_TOKEN / GITHUB_TOKEN  Auth for the GitHub API (avoids rate limits)
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --json) JSON=true ;;
        --releases-file)
            if [ $# -lt 2 ]; then
                echo "Error: --releases-file requires a path argument" >&2
                exit 2
            fi
            RELEASES_FILE="$2"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

fetch_releases() {
    if [ -n "$RELEASES_FILE" ]; then
        if [ ! -f "$RELEASES_FILE" ]; then
            echo "Error: releases file not found: $RELEASES_FILE" >&2
            exit 1
        fi
        cat "$RELEASES_FILE"
        return
    fi
    if command -v gh >/dev/null 2>&1; then
        # --paginate walks every page; --slurp wraps the pages as [[...],[...]],
        # so `add // []` flattens them back into a single releases array (and an
        # empty result stays an array rather than becoming null).
        gh api --paginate --slurp "repos/${REPO}/releases?per_page=100" | jq 'add // []'
        return
    fi
    # curl fallback: page until an empty array comes back. A failed request aborts
    # loudly — never loop forever on a network error or rate limit.
    # Resolve a single token so we never send two Authorization headers.
    local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
    local page=1 body all="[]"
    while :; do
        if ! body=$(curl -sSfL \
            ${token:+-H "Authorization: Bearer $token"} \
            "https://api.github.com/repos/${REPO}/releases?per_page=100&page=${page}"); then
            echo "Error: failed to fetch Lean releases (page $page) from the GitHub API" >&2
            return 1
        fi
        if [ "$(printf '%s' "$body" | jq 'if type == "array" then length else error("not an array") end')" -eq 0 ]; then
            break
        fi
        all=$(jq -s '.[0] + .[1]' <(printf '%s' "$all") <(printf '%s' "$body"))
        page=$((page + 1))
    done
    printf '%s' "$all"
}

# Extract "<tag>\t<prerelease>" for non-draft releases. jq parses the JSON so we
# never grep/sed structured data.
extract() {
    jq -r '.[] | select(.draft != true) | "\(.tag_name)\t\(.prerelease)"'
}

# Apply the policy. awk computes a numeric sort key per tag so RC/stable ordering
# and the floor comparison are exact rather than lexical.
apply_policy() {
    awk -F'\t' -v floor="$FLOOR" '
        function parse(tag,    t, rc, n, a) {
            # Fills the P[] globals (maj/min/pat/isrc/rc); returns 0 on parse failure.
            delete P
            if (match(tag, /^v[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?$/) == 0) return 0
            t = substr(tag, 2)                     # strip leading v
            rc = -1
            if (t ~ /-rc[0-9]+$/) {
                rc = t
                sub(/^.*-rc/, "", rc)   # rc = the trailing number, as a string
                rc = rc + 0             # coerce to a number
                sub(/-rc[0-9]+$/, "", t)
            }
            n = split(t, a, ".")
            if (n != 3) return 0
            P["maj"] = a[1] + 0; P["min"] = a[2] + 0; P["pat"] = a[3] + 0
            P["isrc"] = (rc >= 0) ? 1 : 0
            P["rc"]   = (rc >= 0) ? rc : 0
            # The fixed-width key below assumes each component fits in 5 digits.
            # Reject anything larger so the lexical comparison can never be wrong.
            if (P["maj"] > 99999 || P["min"] > 99999 || P["pat"] > 99999 || P["rc"] > 99999) {
                print "Error: version component out of supported range (>99999): " tag > "/dev/stderr"
                exit 4
            }
            return 1
        }
        function key() {
            # stable (isrc=0) must outrank any rc of the same patch: slot = 1-isrc,
            # so stable->1, rc->0. rc number is the final tiebreak. Every field is
            # exactly 5 digits (bounded above), so lexical comparison is exact.
            return sprintf("%05d%05d%05d%d%05d", P["maj"], P["min"], P["pat"], 1 - P["isrc"], P["rc"])
        }
        BEGIN {
            if (parse(floor) == 0) { print "Error: invalid LEAN_VERSION_FLOOR: " floor > "/dev/stderr"; exit 3 }
            floorkey = key()
        }
        {
            tag = $1; pre = $2
            if (parse(tag) == 0) next                       # malformed tag
            # Skip a stable-shaped tag (no -rc) that GitHub flags as a prerelease:
            # treat it as not-yet-released rather than emitting it as stable. RCs
            # carry the -rc suffix (isrc==1) and are unaffected by this guard.
            if (pre == "true" && P["isrc"] == 0) next
            isrc = P["isrc"]; line = P["maj"] "." P["min"] "." P["pat"]; k = key()
            if (k < floorkey) next                           # below floor
            keyOf[tag] = k
            if (isrc == 0) {
                stable[line] = 1
                emit[tag] = 1
            } else if (k > bestRcKey[line]) {                # latest rc for the line
                bestRcKey[line] = k
                bestRcTag[line] = tag
            }
        }
        END {
            for (line in bestRcTag) {
                if (!(line in stable)) emit[bestRcTag[line]] = 1
            }
            # Emit "key\ttag" so the caller can sort by key then strip it.
            for (tag in emit) print keyOf[tag] "\t" tag
        }
    '
}

# List the tags leanprover/lean4-cli has published (one git call — no auth or
# pagination needed). Tests inject a fixed list via LEAN_CLI_TAGS_FILE.
fetch_cli_tags() {
    if [ -n "$CLI_TAGS_FILE" ]; then
        if [ ! -f "$CLI_TAGS_FILE" ]; then
            echo "Error: Cli tags file not found: $CLI_TAGS_FILE" >&2
            return 1
        fi
        cat "$CLI_TAGS_FILE"
        return
    fi
    git ls-remote --tags "$CLI_REPO_URL" 2>/dev/null \
        | sed 's#.*refs/tags/##; s/\^{}$//' | sort -u
}

if ! releases_json="$(fetch_releases)"; then
    echo "Error: could not retrieve Lean releases." >&2
    exit 1
fi

# Rate-limit / error responses come back as a JSON object, not an array; fail
# clearly rather than letting jq emit a cryptic type error downstream.
if [ "$(printf '%s' "$releases_json" | jq -r 'type' 2>/dev/null)" != "array" ]; then
    echo "Error: unexpected response from the GitHub releases API (not a JSON array)." >&2
    echo "       This usually means a rate limit or auth problem — set GH_TOKEN." >&2
    exit 1
fi

if ! selected="$(printf '%s' "$releases_json" | extract | apply_policy | sort -u | cut -f2)"; then
    echo "Error: failed to compute the supported version list." >&2
    exit 1
fi

# probe-lean's source build pins the Cli dependency to a lean4-cli tag in the
# target's major.minor line (see tools/resolve-cli-rev.sh, the canonical resolver
# also used by the build workflows). Keep a Lean version only when such a
# compatible tag exists: a patch release on an already-tagged minor resolves to
# that minor's tag (e.g. v4.32.2 -> v4.32.0), but a version whose whole
# major.minor line is untagged is dropped. That still waits out the window where a
# fresh Lean minor is out but lean4-cli hasn't tagged it yet. A tag-fetch or
# resolver error is fatal — never a silent drop.
if ! cli_tags="$(fetch_cli_tags)"; then
    echo "Error: could not retrieve leanprover/lean4-cli tags." >&2
    exit 1
fi
if [ -z "$cli_tags" ]; then
    echo "Error: no leanprover/lean4-cli tags found (unexpected)." >&2
    exit 1
fi
# Reuse the single fetch above: hand the tags to the resolver via a temp file
# rather than re-invoking git ls-remote per version.
resolver="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resolve-cli-rev.sh"
cli_tags_file="$(mktemp)"
trap 'rm -f "$cli_tags_file"' EXIT
printf '%s\n' "$cli_tags" > "$cli_tags_file"
selected="$(printf '%s\n' "$selected" | while IFS= read -r v; do
    [ -n "$v" ] || continue
    rc=0
    LEAN_CLI_TAGS_FILE="$cli_tags_file" "$resolver" "$v" >/dev/null || rc=$?
    case "$rc" in
        0) printf '%s\n' "$v" ;;   # a compatible lean4-cli tag exists -> keep
        1) : ;;                     # no compatible tag -> drop this version
        *) echo "Error: could not resolve a lean4-cli tag for $v" >&2; exit 1 ;;
    esac
done)"

if [ "$JSON" = true ]; then
    printf '%s' "$selected" | jq -R -s 'split("\n") | map(select(length > 0))'
elif [ -n "$selected" ]; then
    printf '%s\n' "$selected"
fi
