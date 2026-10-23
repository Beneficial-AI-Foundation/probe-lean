#!/usr/bin/env python3
"""End-to-end assertions for private declarations with one user-facing name
(issue #88).

Run from this directory, after

    lake build
    probe-lean extract . 2>extract.stderr
    python3 check.py

`PrivColl.A`, `PrivColl.B` and the module-system module `PrivColl.E` each define a
private `aux`. `PrivColl.D` has a private `pub`, `PrivColl.C` a public `pub`.
`PrivColl.F` has a private protected and a public protected declaration. Every
code-name is `probe:` followed by the raw Lean name, so each declaration is its own
atom and every edge points to the declaration of its own module. Probe-lean 0.23.0
and earlier published `probe:aux` and `probe:pub` once each and fail here.
"""
import glob
import json
import sys

PRIVATE = "probe:_private."

AUX_A = "probe:_private.PrivColl.A.0.aux"
AUX_B = "probe:_private.PrivColl.B.0.aux"
AUX_E = "probe:_private.PrivColl.E.0.aux"
PUB_D = "probe:_private.PrivColl.D.0.pub"
FOO_BAR = "probe:_private.PrivColl.F.0.Foo.bar"

# Code-name → (code-module, is private, is protected).
EXPECTED = {
    AUX_A: ("PrivColl.A", True, False),
    AUX_B: ("PrivColl.B", True, False),
    AUX_E: ("PrivColl.E", True, False),
    PUB_D: ("PrivColl.D", True, False),
    FOO_BAR: ("PrivColl.F", True, True),
    "probe:Foo.baz": ("PrivColl.F", False, True),
    "probe:pub": ("PrivColl.C", False, False),
    "probe:useA": ("PrivColl.A", False, False),
    "probe:useB": ("PrivColl.B", False, False),
    "probe:useE": ("PrivColl.E", False, False),
    "probe:usePub": ("PrivColl.D", False, False),
}

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
        stderr = fh.read()

    def field(name, key):
        return data.get(name, {}).get(key)

    print("Atom set")
    check(f"{len(EXPECTED)} atoms, one per declaration", len(data) == len(EXPECTED))
    check("every expected code-name is an atom", all(n in data for n in EXPECTED))
    check("each atom has the code-module of its declaration",
          all(field(n, "code-module") == m for n, (m, _, _) in EXPECTED.items()))
    check("a code-name starts with probe:_private. exactly when the declaration is private",
          all(n.startswith(PRIVATE) == p for n, (_, p, _) in EXPECTED.items()))
    check("is-protected is correct on every atom",
          all(field(n, "is-protected") is pr for n, (_, _, pr) in EXPECTED.items()))
    check("public pub is probe:pub, the private one keeps its prefix",
          "probe:pub" in data and PUB_D in data)

    print("Edges")
    check("useA depends on the aux of A", field("probe:useA", "dependencies") == [AUX_A])
    check("useB depends on the aux of B", field("probe:useB", "dependencies") == [AUX_B])
    check("useE depends on the aux of E", field("probe:useE", "dependencies") == [AUX_E])
    check("usePub depends on the private pub", field("probe:usePub", "dependencies") == [PUB_D])

    print("Statuses")
    for name in (AUX_A, "probe:useA"):
        check(f"{name} is not clean and rests on sorryAx",
              field(name, "verification-status") != "transitively-verified"
              and "sorryAx" in (field(name, "assumptions") or []))
    for name in (AUX_B, "probe:useB"):
        check(f"{name} is transitively-verified with empty assumptions",
              field(name, "verification-status") == "transitively-verified"
              and field(name, "assumptions") == [])

    print("Extract stderr")
    check("no duplicate-name warning", "duplicate atom name" not in stderr)

    if failures:
        print(f"{len(failures)} check(s) failed")
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
