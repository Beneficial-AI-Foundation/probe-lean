#!/usr/bin/env python3
"""End-to-end assertions for the import fallback of the kernel taint walk.

Run from this directory, after

    probe-lean extract . -m Coll.Main 2>extract.stderr
    probe-lean check-axioms . -m Coll.Main >check-axioms.out
    python3 check.py

The fixture has four modules. `Coll.A` and `Coll.B` both declare `dup`, so the
full project cannot be co-imported and `extract --module Coll.Main` falls back to
importing the selection. `Coll.Main` imports `Coll.Common`, whose `bad` is a
`sorry`; Lean loads `Coll.Common` transitively. P must contain it: building P from
the *selected* list left `bad` outside P — blocked, hence clean — and `thm` read
`transitively-verified`. The two modules genuinely left out are `Coll.A` and
`Coll.B`, which nothing selected imports.
"""

import glob
import json
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
    with open("extract.stderr") as fh:
        stderr = fh.read().splitlines()
    with open("check-axioms.out") as fh:
        report = fh.read().splitlines()

    print("Extract output under the import fallback")
    check("thm is an atom", "probe:thm" in data)
    check("thm is verified (rests on the transitively loaded sorry)",
          data.get("probe:thm", {}).get("verification-status") == "verified")
    check("bad is not an atom (its module is not selected)", "probe:bad" not in data)

    print("Extract stderr")
    check("fallback warning names the two modules outside the import closure",
          any(l.startswith("Warning: 2 project module(s) not imported (full import failed)")
              for l in stderr))
    check("no atom was left uncovered by the walk",
          not any(l.startswith("Warning: atom ") for l in stderr))
    # `bad` is not an atom (its module is not selected), so the emitted graph cannot
    # see the edge and the graph-BFS reports `thm` clean; the walk sees it. That
    # disagreement is exactly what the divergence line exists for.
    check("the graph-BFS disagreement on thm is printed",
          "Divergence(graph): probe:thm graph says clean, oracle says tainted" in stderr)

    print("check-axioms report")
    check("bad is listed as a direct carrier that is not emitted",
          "  bad [direct] [not emitted]" in report)
    check("thm is listed", "  thm" in report)
    check("the summary counts the two loaded modules",
          any(l.startswith("Project constants:") and " in 2 module(s)" in l for l in report))

    print()
    if failures:
        print(f"import-fallback end-to-end check: {len(failures)} assertion(s) failed:")
        for f in failures:
            print(f"  {f}")
        return 1
    print("import-fallback end-to-end check: all assertions passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
