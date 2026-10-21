#!/usr/bin/env python3
"""End-to-end assertions for colliding module-system modules outside the import
closure.

Run from this directory, after

    lake build
    probe-lean extract . -m ModColl.Main 2>extract.stderr
    probe-lean check-axioms . -m ModColl.Main >check-axioms.out
    probe-lean extract . -o .verilib/full.json 2>extract-full.stderr   # must fail
    python3 check.py

`check.py` runs `tools/audit/check-graph.py` on the artifact itself.

The `collision` fixture with `module` headers. `ModColl.A` and `ModColl.B` both export
`public def dup`. `extract -m ModColl.Main` imports the closure of `ModColl.Main` only,
so the pair is never loaded, `Common.bad` is in P and taints `Main.thm`. At the
exported level (the base `.olean` the preflight reads) a non-exposed `public def` is an
axiom, and the preflight tolerates two same-type axioms. So the run without `-m` passes
the preflight and fails at the import (`environment already contains 'dup'`), with a
message that names both modules. The fixture is also the regression test for the
segfault on repeated reads of module-system headers in one process.
"""
import glob
import json
import os
import subprocess
import sys
from pathlib import Path

PREFIX = "ModColl"
TITLE = "module-system collision"
FULL_MESSAGE = "environment already contains 'dup'"

CHECK_GRAPH = Path(__file__).resolve().parents[3] / "tools" / "audit" / "check-graph.py"

failures = []


def check(name, ok):
    print(f"  {'✓' if ok else '✗'} {name}")
    if not ok:
        failures.append(name)


def old_cross_check_line(line):
    """A line of the cross-checks that `extract` printed up to 0.20.0 (issue #141)."""
    return (line.startswith(("Divergence(graph):", "Divergence(log):", "Note(log):",
                             "Graph cross-check:"))
            or "not found in atom map" in line)


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
    with open("extract-full.stderr") as fh:
        full = fh.read()
    graph = subprocess.run([sys.executable, str(CHECK_GRAPH), paths[0]],
                           capture_output=True, text=True)

    print(f"Extract output with -m {PREFIX}.Main")
    check("thm is an atom", "probe:thm" in data)
    check("thm is verified (rests on the transitively loaded sorry)",
          data.get("probe:thm", {}).get("verification-status") == "verified")
    check("bad is not an atom (its module is not selected)", "probe:bad" not in data)

    print("Extract stderr")
    check("no graph or build-log cross-check line (extract no longer prints them)",
          not any(old_cross_check_line(l) for l in stderr))
    check("no import fallback message (the closure of the import set imports)",
          not any("full import failed" in l for l in stderr))
    check("the import loads the two modules of the closure",
          any("(2 project modules in the closure)" in l for l in stderr + report))
    check("no atom was left uncovered by the walk",
          not any(l.startswith("Warning: atom ") for l in stderr))

    print("check-graph.py report")
    check("check-graph.py exits 0", graph.returncode == 0)
    # `bad` is not an atom (its module is not selected), so the emitted graph cannot
    # see the edge and the graph-BFS reports `thm` clean; the walk sees it.
    check("the graph-BFS disagreement on thm is printed",
          "Divergence(graph): probe:thm graph says clean, oracle says tainted"
          in graph.stdout.splitlines())

    print("check-axioms report")
    check("bad is listed as a direct carrier that is not emitted",
          "  bad [direct] [not emitted]" in report)
    check("thm is listed", "  thm" in report)
    check(f"the summary counts the two loaded modules ({PREFIX}.A and {PREFIX}.B are not loaded)",
          any(l.startswith("Project constants:") and " in 2 module(s)" in l for l in report))

    print("Extract without -m (every module of the library)")
    check("the run failed with the collision message", FULL_MESSAGE in full)
    check(f"the message names {PREFIX}.A and {PREFIX}.B",
          f"{PREFIX}.A, {PREFIX}.B" in full)
    check("the message suggests --module", "--module" in full)
    check("no output file was written", not os.path.exists(".verilib/full.json"))

    print()
    if failures:
        print(f"{TITLE} end-to-end check: {len(failures)} assertion(s) failed:")
        for f in failures:
            print(f"  {f}")
        return 1
    print(f"{TITLE} end-to-end check: all assertions passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
