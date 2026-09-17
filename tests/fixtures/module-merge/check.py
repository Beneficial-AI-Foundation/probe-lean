#!/usr/bin/env python3
"""End-to-end assertions for merged declarations under the module system.

Run from this directory, after

    lake build
    probe-lean extract . 2>extract.stderr
    probe-lean check-axioms . >check-axioms.out
    python3 check.py

`ModMerge.Bad` and `ModMerge.Good` are `module` files that both export `public
theorem shared : True`; one proof is a `sorry`. A module-system module's base
`.olean` is the *exported* level, where a `public theorem` is represented as an
axiom without its proof. The co-import preflight used to read only that part, so it
saw two same-type axioms, filed the name as merged, and the merged-trust rule
returned "axiom" — two theorems, one of them `sorry`, trusted. The preflight now
reads the `.olean.private` part the importer reads, so `shared` is a theorem with
its proof in both versions: `unverified`, never trusted, both callers `verified`.
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

    print("Extract output: the merged public theorem and its callers")
    check("shared is one atom", "probe:shared" in data)
    check("shared is a theorem, not an axiom (the private part was read)",
          data.get("probe:shared", {}).get("kind") == "theorem")
    check("shared is unverified (one version's body is a sorry)",
          status(data, "probe:shared") == "unverified")
    check("shared is not trusted", "trusted-reason" not in data.get("probe:shared", {}))
    check("caller (built against the sorried version) is verified",
          status(data, "probe:caller") == "verified")
    check("callerGood (built against the proved version) is verified too: fail closed",
          status(data, "probe:callerGood") == "verified")

    print("Extract stderr")
    check("the merged declaration is reported",
          any(l.startswith("Warning: 1 declaration name(s) are declared by more than one project module")
              and "shared" in l for l in stderr))
    check("no cross-merge warning (both versions were read, so the pair is covered)",
          not any("cannot see into" in l for l in stderr))
    check("no fallback: the whole project co-imported",
          not any("not imported" in l for l in stderr))
    check("no atom was left uncovered by the walk",
          not any(l.startswith("Warning: atom ") for l in stderr))

    print("check-axioms report")
    check("shared is listed as a direct carrier", "  shared [direct]" in report)
    check("both callers are listed", "  caller" in report and "  callerGood" in report)
    check("nothing is trusted",
          any(l.startswith("Project constants:") and "| trusted: 0 |" in l for l in report))

    print()
    if failures:
        print(f"module-system merge end-to-end check: {len(failures)} assertion(s) failed:")
        for f in failures:
            print(f"  {f}")
        return 1
    print("module-system merge end-to-end check: all assertions passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
