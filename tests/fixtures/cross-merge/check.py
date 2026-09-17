#!/usr/bin/env python3
"""End-to-end assertions for declarations merged across the project boundary.

Run from this directory, after

    lake build
    probe-lean extract . 2>extract.stderr
    probe-lean check-axioms . >check-axioms.out
    python3 check.py

Four project theorems restate a theorem of the `dep` path dependency with the same name
and statement; Lean's importer keeps ONE body per name without comparing them. In both
import orders (dependency wins the name / project wins the name) and for both project
bodies (sorried / proved) the walk must follow the *project's* version, which the
environment header keeps even when the lookup map kept the dependency's:

    name      project body   who wins the name   body the env keeps   expected
    shared    sorry          dependency          project's (sorry)    callers verified
    shared2   proof          dependency          project's (proof)    callers transitively-verified
    shared3   proof          project             dependency's         shared3 + caller transitively-verified
    shared4   sorry          project             dependency's (proof) shared4 unverified, caller verified

`shared4` is the sharp case: the environment shows a clean body under a project name.
"""

import glob
import json
import sys

failures = []

NOTE = "Note: 4 declaration name(s) are declared by a project module and by a module outside the project"


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

    print("Dependency wins the name, project body sorried (shared)")
    check("caller (built against the sorried version) is verified",
          status(data, "probe:caller") == "verified")
    check("viaDep (built against the dependency's proved version) is verified too: the name is one",
          status(data, "probe:viaDep") == "verified")
    check("shared is not an atom (the dependency owns the name)", "probe:shared" not in data)

    print("Dependency wins the name, project body proved (shared2)")
    check("callerGood is transitively-verified", status(data, "probe:callerGood") == "transitively-verified")
    check("viaDep2 is transitively-verified", status(data, "probe:viaDep2") == "transitively-verified")
    check("shared2 is not an atom", "probe:shared2" not in data)

    print("Project wins the name, project body proved (shared3)")
    check("shared3 is an atom and transitively-verified, not trusted",
          status(data, "probe:shared3") == "transitively-verified")
    check("callerFirst is transitively-verified", status(data, "probe:callerFirst") == "transitively-verified")

    print("Project wins the name, project body sorried, environment holds the dependency's proof (shared4)")
    check("shared4 is unverified (the header's copy of the project body is walked)",
          status(data, "probe:shared4") == "unverified")
    check("callerBad is verified", status(data, "probe:callerBad") == "verified")

    check("every atom has a status", all("verification-status" in a for a in data.values()))

    print("Extract stderr")
    check("the note names all four cross-boundary declarations",
          any(l.startswith(NOTE) and all(n in l for n in ("shared", "shared2", "shared3", "shared4"))
              for l in stderr))
    check("no project/project merge warning (these are cross-boundary pairs)",
          not any("declared by more than one project module" in l for l in stderr))
    check("no fallback: the whole project co-imported",
          not any("not imported" in l for l in stderr))
    check("no atom was left uncovered by the walk",
          not any(l.startswith("Warning: atom ") for l in stderr))

    print("check-axioms report")
    check("shared is listed as a direct carrier that is not emitted",
          "  shared [direct] [not emitted]" in report)
    check("shared4 is listed as an emitted direct carrier", "  shared4 [direct]" in report)
    check("the tainted callers are listed",
          all(f"  {c}" in report for c in ("caller", "viaDep", "callerBad")))
    check("the clean names are not listed",
          not any(l.startswith(f"  {c}") for l in report
                  for c in ("shared2", "shared3", "callerGood", "callerFirst", "viaDep2")))
    check("the same note is printed by check-axioms",
          any(l.startswith(NOTE) for l in report + stderr))

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
