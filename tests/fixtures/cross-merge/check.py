#!/usr/bin/env python3
"""End-to-end assertions for a declaration merged across the project boundary.

Run from this directory, after

    lake build
    probe-lean extract . 2>extract.stderr
    probe-lean check-axioms . >check-axioms.out
    python3 check.py

`CrossMerge.Restate` restates the dependency theorem `Dep.Shared.shared` (same name
and statement) with a `sorry`. Lean's importer tolerates the pair and keeps ONE body
without comparing them; it attributes the name to the module imported first — the
dependency, loaded through `CrossMerge.Other` — and keeps the body imported last —
the project's sorried one. The name is therefore outside P (blocked, "trusted
wholesale") while carrying the project's `sorry`, and `CrossMerge.Use.caller` would
read clean. The olean preflight reads project modules only and cannot see this; the
post-import scan of the environment header must flag `shared`, treat it as resting on
`sorry`, and taint both callers.
"""

import glob
import json
import sys

failures = []


def check(name, ok):
    print(f"  {'✓' if ok else '✗'} {name}")
    if not ok:
        failures.append(name)


def status(data, atom):
    return data.get(atom, {}).get("verification-status")


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

    print("Extract output: the callers of the cross-merged theorem")
    check("caller (built against the sorried version) is verified",
          status(data, "probe:caller") == "verified")
    check("viaDep (built against the dependency's proved version) is verified too: fail closed",
          status(data, "probe:viaDep") == "verified")
    check("nothing reads transitively-verified",
          all(a.get("verification-status") != "transitively-verified" for a in data.values()))
    check("every atom has a status", all("verification-status" in a for a in data.values()))

    print("Extract stderr")
    check("the cross-merged declaration is reported",
          any(l.startswith("Warning: 1 declaration name(s) are declared by a project module and by a module the walk cannot see into")
              and "shared" in l for l in stderr))
    check("no project/project merge warning (the preflight cannot see this pair)",
          not any("declared by more than one project module" in l for l in stderr))
    check("no fallback: the whole project co-imported",
          not any("not imported" in l for l in stderr))
    check("no atom was left uncovered by the walk",
          not any(l.startswith("Warning: atom ") for l in stderr))

    print("check-axioms report")
    check("shared is listed as a direct carrier",
          any(l.startswith("  shared [direct]") for l in report))
    check("both callers are listed", "  caller" in report and "  viaDep" in report)
    check("the same warning is printed by check-axioms",
          any("cannot see into" in l for l in report + stderr))

    print()
    if failures:
        print(f"cross-merge end-to-end check: {len(failures)} assertion(s) failed:")
        for f in failures:
            print(f"  {f}")
        return 1
    print("cross-merge end-to-end check: all assertions passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
