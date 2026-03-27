#!/usr/bin/env bash
# Generate ProbeLean/Version.lean from the version in lakefile.toml.
# Run this after bumping the version in lakefile.toml.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."

VERSION=$(grep '^version' "$REPO_ROOT/lakefile.toml" | sed 's/version = "\(.*\)"/\1/' | head -1)

if [ -z "$VERSION" ]; then
    echo "Error: could not extract version from lakefile.toml" >&2
    exit 1
fi

cat > "$REPO_ROOT/ProbeLean/Version.lean" <<EOF
-- Generated from lakefile.toml by tools/gen-version.sh — do not edit manually.
namespace ProbeLean

def version : String := "$VERSION"

end ProbeLean
EOF

echo "Generated ProbeLean/Version.lean with version $VERSION"
