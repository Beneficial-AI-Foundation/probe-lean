#!/usr/bin/env bash
# End-to-end check of Lake's artifact cache (R8 of issue #152).
#
# Usage: check-cache.sh <probe-lean> [restore]
#
# Two fresh copies of this fixture share one artifact cache. The first copy is
# built. In the second copy the build is a cache hit, and without a restore Lake
# keeps the .olean files out of .lake/build, so `extract` must fail with the R8
# error. With `restore` (Lean 4.31 or later), LAKE_RESTORE_ARTIFACTS=true is set
# and `extract` must succeed and analyze every module.
set -u

PL=$(realpath "$1")
MODE=${2:-}
SRC=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
for c in first second; do
  cp -r "$SRC" "$WORK/$c"
  rm -rf "$WORK/$c/.lake" "$WORK/$c/.verilib" "$WORK/$c/lake-manifest.json"
done
export LAKE_ARTIFACT_CACHE=true
export LAKE_CACHE_DIR="$WORK/cache"
if [ "$MODE" = restore ]; then export LAKE_RESTORE_ARTIFACTS=true; fi

(cd "$WORK/first" && lake build Core:leanArts >build.log 2>&1) \
  || { cat "$WORK/first/build.log"; exit 1; }
cd "$WORK/second" || exit 2
"$PL" extract . -o out.json >extract.out 2>extract.err
code=$?
if [ "$MODE" = restore ]; then
  if [ "$code" -ne 0 ]; then
    echo "  ✗ extract failed with LAKE_RESTORE_ARTIFACTS=true"; cat extract.err; exit 1
  fi
  n=$(python3 -c 'import json; print(len(json.load(open("out.json"))["data"]))')
  grep -q "Analyzing 4 of 4 project modules" extract.out \
    || { echo "  ✗ not every module was analyzed"; cat extract.out; exit 1; }
  echo "  ✓ extract succeeds with LAKE_RESTORE_ARTIFACTS=true ($n atoms, 4 modules)"
else
  if [ "$code" -eq 0 ]; then
    echo "  ✗ extract succeeded although the cache kept the .olean files out of .lake/build"; exit 1
  fi
  grep -qF "have no .olean in .lake/build/lib/lean" extract.err \
    && grep -qF "LAKE_RESTORE_ARTIFACTS=true" extract.err \
    || { echo "  ✗ the error is not the R8 error"; cat extract.err; exit 1; }
  echo "  ✓ extract fails with the R8 error on a cache hit without restore"
fi
