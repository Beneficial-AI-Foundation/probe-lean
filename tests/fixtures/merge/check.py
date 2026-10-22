#!/usr/bin/env python3
"""End-to-end assertions for merged declarations (co-import proof provenance).

Run from this directory, after

    probe-lean extract . 2>extract.stderr
    probe-lean check-axioms . >check-axioms.out
    probe-lean extract . --module Merge.Good -o .verilib/module-Good.json
    probe-lean extract . --module Merge.Bad -o .verilib/module-Bad.json
    probe-lean extract . --module Merge.FixAdd -o .verilib/module-FixAdd.json \
        2>.verilib/module-FixAdd.stderr
    probe-lean extract . --module Merge.FixRestate -o .verilib/module-FixRestate.json
    python3 check.py

`check.py` runs `tools/audit/check-graph.py` on the `--module Merge.FixAdd` artifact.

`Merge.Bad` and `Merge.Good` both declare `theorem shared : True`; one proof is a
`sorry`, the other is real. Lean's importer accepts the pair and keeps ONE body
without comparing them, so in the merged environment the name `shared` no longer
identifies one project proof. `Merge.Use.caller` was built against the sorried one.
The walk must not be steered clean by whichever body survived: it follows the union
of both versions' dependencies, so `shared` reads `unverified` and both callers read
`verified`, and a warning names the merged declaration.

The atom's edges are that same union. A `--module` run imports only the closure of
the selected modules, so it loads one version of `shared`: `--module Merge.Good`
reports the proved version (the `True.intro` edge only), `--module Merge.Bad` the
sorried one (the `sorryAx` edge only). Each locates `shared` in the selected
module's file.

`Merge.Fix.mutual` (issue #135) is merged the same way. `Merge.FixAdd` adds it with no
declaration range and owns it, `Merge.FixRestate` states it in source. `extract`
drops the direct edge to a generated `partial_fixpoint` body, but this name is an
emitted atom, so its callers keep the edge. In `--module Merge.FixAdd` it is not
emitted, but no `partial_fixpoint` block made it, so `fixCallerAdd` keeps the edge too.
"""

import glob
import json
import subprocess
import sys
from pathlib import Path

CHECK_GRAPH = Path(__file__).resolve().parents[3] / "tools" / "audit" / "check-graph.py"

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
    selected = {}
    for m in ("Good", "Bad", "FixAdd", "FixRestate"):
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
    check("callerSub (submodule of Merge.Good) is verified", status(data, "probe:callerSub") == "verified")
    check("privCaller (private) is an atom under its user-facing name, verified",
          status(data, "probe:privCaller") == "verified" and "probe:_private.Merge.Use.0.privCaller" not in data)
    check("shared's edges are both versions' (sorryAx and True.intro)",
          both_bodies(data.get("probe:shared", {})))

    print("--module runs: either declaring module emits the merged theorem")
    # A --module run imports only the closure of the selected modules, so the
    # environment holds one version of `shared`, and the run reports that version.
    for m, st, edge in (("Good", "transitively-verified", "probe:True.intro"),
                        ("Bad", "unverified", "probe:sorryAx")):
        shared = selected[m].get("probe:shared", {})
        check(f"--module Merge.{m}: shared is emitted, {st}",
              shared.get("verification-status") == st)
        check(f"--module Merge.{m}: shared is located in Merge/{m}.lean",
              shared.get("code-module") == f"Merge.{m}"
              and shared.get("code-path") == f"Merge/{m}.lean")
        ext = shared.get("term-dependencies-external", [])
        check(f"--module Merge.{m}: shared's edges are the loaded version's only",
              edge in ext and not both_bodies(shared))
    check("--module Merge.Bad: nothing but shared is emitted", list(selected["Bad"]) == ["probe:shared"])
    # `Merge.Good.Sub` is selected by the `Merge.Good` prefix; `Merge.Bad`, which owns
    # `shared` in the environment, is not. The emitted `shared` must still be the
    # caller's project dependency, not an external one.
    check("--module Merge.Good: shared and the submodule's caller are emitted",
          sorted(selected["Good"]) == ["probe:callerSub", "probe:shared"])
    sub = selected["Good"].get("probe:callerSub", {})
    check("--module Merge.Good: callerSub's edge to the emitted shared is a project edge",
          "probe:shared" in sub.get("term-dependencies", [])
          and "probe:shared" in sub.get("dependencies", [])
          and "probe:shared" not in sub.get("term-dependencies-external", []))
    check("--module Merge.Good: callerSub is transitively-verified (only the proved version is loaded)",
          sub.get("verification-status") == "transitively-verified")

    print("Merged .mutual name: an emitted atom, so its edges stay")
    fix = "probe:Merge.Fix.mutual"
    check("Merge.Fix.mutual is an atom located in Merge/FixRestate.lean",
          data.get(fix, {}).get("code-path") == "Merge/FixRestate.lean")
    for caller in ("probe:fixCaller", "probe:fixCallerSub", "probe:fixCallerAdd"):
        check(f"{caller} lists Merge.Fix.mutual",
              fix in data.get(caller, {}).get("term-dependencies", [])
              and fix in data.get(caller, {}).get("dependencies", []))
    restate = selected["FixRestate"]
    check("--module Merge.FixRestate: Merge.Fix.mutual is emitted from Merge/FixRestate.lean",
          restate.get(fix, {}).get("code-path") == "Merge/FixRestate.lean")
    check("--module Merge.FixRestate: fixCallerSub lists Merge.Fix.mutual as a project edge",
          fix in restate.get("probe:fixCallerSub", {}).get("term-dependencies", []))
    check("--module Merge.FixAdd: Merge.Fix.mutual is not an atom (no range there)",
          fix not in selected["FixAdd"])
    add_caller = selected["FixAdd"].get("probe:fixCallerAdd", {})
    check("--module Merge.FixAdd: fixCallerAdd keeps its edge to Merge.Fix.mutual "
          "(no partial_fixpoint block made it)",
          fix in add_caller.get("term-dependencies", [])
          and fix in add_caller.get("dependencies", []))
    with open(".verilib/module-FixAdd.stderr") as fh:
        add_stderr = fh.read().splitlines()
    check("--module Merge.FixAdd: extract prints no atom-map warning (check-graph.py does)",
          not any(old_cross_check_line(l) for l in add_stderr))
    add_graph = subprocess.run([sys.executable, str(CHECK_GRAPH), ".verilib/module-FixAdd.json"],
                               capture_output=True, text=True)
    check("--module Merge.FixAdd: check-graph.py reports the dangling edge to Merge.Fix.mutual",
          add_graph.returncode == 0 and
          f'Warning: dependency "{fix}" not found in atom map' in add_graph.stdout.splitlines())

    print("Assumptions of an axiom/theorem pair")
    for name in ("pairAx", "callerAx"):
        a = data.get(f"probe:{name}", {})
        check(f"{name} has assumptions [\"pairAx\"]",
              "assumptions" in a and a["assumptions"] == ["pairAx"])

    print("Extract stderr")
    check("no graph or build-log cross-check line (extract no longer prints them)",
          not any(old_cross_check_line(l) for l in stderr))
    check("the merged declarations are reported",
          any(l.startswith("Warning: 3 declaration name(s) are declared by more than one project module")
              and "shared" in l and "Merge.Fix.mutual" in l and "pairAx" in l for l in stderr))
    check("no fallback: the whole project co-imported",
          not any("not imported" in l for l in stderr))
    check("no cross-boundary note (both declarers are project modules)",
          not any("by a module outside the project" in l for l in stderr))
    check("no atom was left uncovered by the walk",
          not any(l.startswith("Warning: atom ") for l in stderr))

    print("check-axioms report")
    check("shared is listed as a direct carrier", "  shared [direct]" in report)
    check("both callers are listed", "  caller" in report and "  callerGood" in report)
    check("the private caller is listed under its raw name, as emitted",
          "  _private.Merge.Use.0.privCaller" in report)
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
