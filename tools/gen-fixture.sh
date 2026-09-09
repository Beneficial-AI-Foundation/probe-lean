#!/usr/bin/env bash
# Regenerate the committed example extract artifact in examples/.
#
# The fixture is real probe-lean output (written through the same Envelope and
# UnifiedAtomsOutput serializers as `extract`), so it must be regenerated
# whenever the output format changes — a new atom field, a renamed key, a
# changed envelope shape, or a version bump. CI runs this and fails if the
# committed file differs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."

cd "$REPO_ROOT"

lake build gen-fixture
.lake/build/bin/gen-fixture "$@"
