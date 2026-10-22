#!/usr/bin/env python3
"""End-to-end assertions for a deleted module that a target module imports.

Run from this directory, after

    lake build
    probe-lean extract . 2>extract.stderr          # succeeds; thm is verified
    rm Orph/Dep.lean
    probe-lean extract . -o .verilib/after.json 2>extract2.stderr     # must fail
    probe-lean check-axioms . >check-axioms2.out 2>check-axioms2.err   # must fail
    git checkout -- Orph/Dep.lean
    python3 check.py

`Orph.Main` imports `Orph.Dep`, whose `bad` is a `sorry`. After `Orph/Dep.lean` is
deleted, its `.olean` stays in the build directory. probe-lean builds the targets on
every run, so `lake build` fails and names the missing file, and both commands fail
before the import. Without the build, importing `Orph.Main` would load the stale
`Orph.Dep.olean`, and `thm` would rest on a module that has no source.
"""

import glob
import json
import os
import sys

failures = []


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
    check("extract failed in the build, which names Orph/Dep.lean",
          "Lake build failed" in stderr2 and "Orph/Dep.lean" in stderr2)
    check("no output file was written", not os.path.exists(".verilib/after.json"))

    print("check-axioms (Orph/Dep.lean deleted)")
    check("check-axioms failed in the build, which names Orph/Dep.lean",
          "Lake build failed" in axerr2 and "Orph/Dep.lean" in axerr2)

    print()
    if failures:
        print(f"deleted-module end-to-end check: {len(failures)} assertion(s) failed:")
        for f in failures:
            print(f"  {f}")
        return 1
    print("deleted-module end-to-end check: all assertions passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
