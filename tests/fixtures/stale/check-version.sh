#!/usr/bin/env bash
# End-to-end check of the Lean version check (R2 of issue #152).
#
# Usage: check-version.sh <probe-lean> <fixture-dir> <lean-version>
#
# A fresh copy of <fixture-dir> gets `lean-toolchain` set to <lean-version>, a
# Lean that is not the Lean of probe-lean. `extract` must fail with the R2 error,
# which names both githashes, before any build. The workspace helper checks the
# githash before it loads the workspace, so a `lakefile.lean` project must not
# fail inside the load (`unknown namespace`, `incompatible header`).
set -u

PL=$(realpath "$1")
FIX=$(realpath "$2")
VERSION=$3
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp -r "$FIX" "$WORK/p"
cd "$WORK/p" || exit 2
rm -rf .lake .verilib lake-manifest.json
echo "leanprover/lean4:$VERSION" >lean-toolchain
"$PL" extract . -o out.json >extract.out 2>extract.err
code=$?
fail=0
expect() { if "$@"; then :; else echo "  ✗ $name"; fail=1; fi; }
name="extract fails"; expect test "$code" -ne 0
name="the error is the R2 error"; expect grep -qF "uses a different Lean than probe-lean" extract.err
name="the error points to --from-project"; expect grep -qF -- "--from-project" extract.err
name="no failure inside the workspace load"
expect bash -c '! grep -qE "unknown namespace|incompatible header" extract.err'
name="nothing was built"; expect test ! -e .lake/build
name="no output file"; expect test ! -e out.json
if [ "$fail" -ne 0 ]; then cat extract.err; exit 1; fi
echo "  ✓ $(basename "$FIX") on Lean $VERSION fails with the R2 error before any build"
