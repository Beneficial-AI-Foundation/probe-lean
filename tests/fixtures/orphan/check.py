#!/usr/bin/env python3
"""End-to-end assertions for the stale-orphan abort.

Run from this directory, after

    lake build
    probe-lean extract . 2>extract.stderr          # succeeds; thm is verified
    rm Orph/Dep.lean
    probe-lean extract . 2>extract2.stderr         # must fail
    probe-lean check-axioms . >check-axioms2.out 2>check-axioms2.err   # must fail
    git checkout -- Orph/Dep.lean
    python3 check.py

`Orph.Main` imports `Orph.Dep`, whose `bad` is a `sorry`. After `Orph/Dep.lean` is
deleted, the build cache is still valid (nothing is newer than it), so `lake build` is
skipped; discovery drops `Orph.Dep` as an orphan; importing `Orph.Main` loads the stale
`Orph.Dep.olean` anyway. Without the post-import check `Orph.Dep` would sit outside P,
blocked, and `thm` would read `transitively-verified`. Both commands must abort instead.
"""

import glob
import json
import sys

failures = []

STALE = "1 stale module(s) with no .lean source were imported by a live module: Orph.Dep."


def check(name, ok):
    print(f"  {'✓' if ok else '✗'} {name}")
    if not ok:
        failures.append(name)


def main():
    paths = glob.glob(".verilib/probes/lean_*.json")
    if len(paths) != 1:
        print(f"expected exactly one .verilib/probes/lean_*.json, found {len(paths)}")
        return 2
    with open(paths[0]) as fh:
        data = json.load(fh)["data"]
    with open("extract2.stderr") as fh:
        stderr2 = fh.read()
    with open("check-axioms2.err") as fh:
        axerr2 = fh.read()

    print("First extract (source present)")
    check("thm is verified (rests on the project sorry)",
          data.get("probe:thm", {}).get("verification-status") == "verified")
    check("bad is an atom and unverified",
          data.get("probe:bad", {}).get("verification-status") == "unverified")

    print("Second extract (Orph/Dep.lean deleted)")
    check("extract aborted through the import path naming the stale module",
          f"Analysis failed: {STALE}" in stderr2)
    check("the remedy is stated", "Run `lake clean` in the target project and rebuild." in stderr2)
    check("no Divergence line was printed (nothing was stamped)",
          "Divergence(" not in stderr2)

    print("check-axioms (Orph/Dep.lean deleted)")
    check("check-axioms aborted naming the stale module", f"Import failed: {STALE}" in axerr2)

    print()
    if failures:
        print(f"stale-orphan end-to-end check: {len(failures)} assertion(s) failed:")
        for f in failures:
            print(f"  {f}")
        return 1
    print("stale-orphan end-to-end check: all assertions passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
