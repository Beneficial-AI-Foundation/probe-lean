#!/usr/bin/env python3
"""End-to-end assertions for merged declarations (co-import proof provenance).

Run from this directory, after

    probe-lean extract . 2>extract.stderr
    probe-lean check-axioms . >check-axioms.out
    probe-lean extract . --module Merge.Good -o .verilib/module-Good.json
    probe-lean extract . --module Merge.Bad -o .verilib/module-Bad.json
    python3 check.py

`Merge.Bad` and `Merge.Good` both declare `theorem shared : True`; one proof is a
`sorry`, the other is real. Lean's importer accepts the pair and keeps ONE body
without comparing them, so in the merged environment the name `shared` no longer
identifies one project proof. `Merge.Use.caller` was built against the sorried one.
The walk must not be steered clean by whichever body survived: it follows the union
of both versions' dependencies, so `shared` reads `unverified` and both callers read
`verified`, and a warning names the merged declaration.

The atom's edges are that same union, and a `--module` run selecting either
declaring module emits `shared`, located in the selected module's file: the
importer's choice of body and owner must not decide the output either.
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


def both_bodies(atom):
    ext = atom.get("term-dependencies-external", [])
    return "probe:sorryAx" in ext and "probe:True.intro" in ext


def main():
    paths = glob.glob(".verilib/probes/lean_*.json")
    if len(paths) != 1:
        print(f"expected exactly one .verilib/probes/lean_*.json, found {len(paths)}")
        return 2
    with open(paths[0]) as fh:
        data = json.load(fh)["data"]
    selected = {}
    for m in ("Good", "Bad"):
        with open(f".verilib/module-{m}.json") as fh:
            selected[m] = json.load(fh)["data"]
    with open("extract.stderr") as fh:
        stderr = fh.read().splitlines()
    with open("check-axioms.out") as fh:
        report = fh.read().splitlines()

    print("Extract output: the merged theorem and its callers")
    check("shared is one atom", "probe:shared" in data)
    check("shared is unverified (one version's body is a sorry)",
          status(data, "probe:shared") == "unverified")
    check("caller (built against the sorried version) is verified",
          status(data, "probe:caller") == "verified")
    check("callerGood (built against the proved version) is verified too: fail closed",
          status(data, "probe:callerGood") == "verified")
    check("shared's edges are both versions' (sorryAx and True.intro)",
          both_bodies(data.get("probe:shared", {})))

    print("--module runs: either declaring module emits the merged theorem")
    for m in ("Good", "Bad"):
        shared = selected[m].get("probe:shared", {})
        check(f"--module Merge.{m}: shared is emitted, unverified",
              shared.get("verification-status") == "unverified")
        check(f"--module Merge.{m}: shared is located in Merge/{m}.lean",
              shared.get("code-module") == f"Merge.{m}"
              and shared.get("code-path") == f"Merge/{m}.lean")
        check(f"--module Merge.{m}: shared's edges are both versions'", both_bodies(shared))
        check(f"--module Merge.{m}: no caller is emitted", list(selected[m]) == ["probe:shared"])

    print("Extract stderr")
    check("the merged declaration is reported",
          any(l.startswith("Warning: 1 declaration name(s) are declared by more than one project module")
              and "shared" in l for l in stderr))
    check("no fallback: the whole project co-imported",
          not any("not imported" in l for l in stderr))
    check("no cross-boundary note (both declarers are project modules)",
          not any("by a module outside the project" in l for l in stderr))
    check("no atom was left uncovered by the walk",
          not any(l.startswith("Warning: atom ") for l in stderr))

    print("check-axioms report")
    check("shared is listed as a direct carrier", "  shared [direct]" in report)
    check("both callers are listed", "  caller" in report and "  callerGood" in report)
    check("the same warning is printed by check-axioms",
          any("declared by more than one project module" in l for l in report + stderr))

    print()
    if failures:
        print(f"merged-declaration end-to-end check: {len(failures)} assertion(s) failed:")
        for f in failures:
            print(f"  {f}")
        return 1
    print("merged-declaration end-to-end check: all assertions passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
