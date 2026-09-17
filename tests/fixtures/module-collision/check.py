#!/usr/bin/env python3
"""End-to-end assertions for the import fallback over module-system modules.

Run from this directory, after

    probe-lean extract . -m ModColl.Main 2>extract.stderr
    probe-lean check-axioms . -m ModColl.Main >check-axioms.out
    python3 check.py

The `collision` fixture with `module` headers. `ModColl.A` and `ModColl.B` both export
`public def dup`, so the full project cannot be co-imported and `extract --module
ModColl.Main` falls back to the selection. Getting here at all is the point: the
fallback preflights `ModColl.Main` and `ModColl.Common` three times in one process (all
modules, the selection, the imported set), and reading a module-system module's split
olean parts with separate `readModuleData` calls segfaulted on the second read. The
status assertions are the collision fixture's: `Common.bad` is loaded transitively, is in
P, and taints `Main.thm`.
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

    print("Extract output under the import fallback (module system)")
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
        print(f"module-system import-fallback end-to-end check: {len(failures)} assertion(s) failed:")
        for f in failures:
            print(f"  {f}")
        return 1
    print("module-system import-fallback end-to-end check: all assertions passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
