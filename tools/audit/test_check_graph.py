#!/usr/bin/env python3
"""Tests for tools/audit/check-graph.py. Run from the probe-lean root:
    python3 tools/audit/test_check_graph.py

Uses only the standard library. Each case is a small hand-written artifact.
"""
import contextlib
import importlib.util
import io
import json
import os
import sys
import tempfile
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "check_graph", Path(__file__).resolve().parent / "check-graph.py")
cg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cg)

PASS = 0
FAIL = 0


def assert_eq(name, expected, actual):
    global PASS, FAIL
    if expected == actual:
        print(f"  PASS: {name}")
        PASS += 1
    else:
        print(f"  FAIL: {name} (expected {expected!r}, got {actual!r})")
        FAIL += 1


def atom(status=None, deps=(), kind="theorem", tainted=False):
    a = {"kind": kind, "dependencies": list(deps)}
    if status is not None:
        a["verification-status"] = status
    if tainted:
        a["status-origin"] = "kernel-taint"
    return a


def tainted(deps=()):
    """A `verified` atom the kernel walk found tainted."""
    return atom("verified", deps, tainted=True)


def clean(deps=()):
    return atom("transitively-verified", deps)


def envelope(atoms, version="0.16.0", name="probe-lean"):
    """`atoms` in the envelope that `extract` writes."""
    return {"schema": "probe-lean/extract", "tool": {"name": name, "version": version},
            "data": atoms}


def divs(atoms):
    lines, _ = cg.run(envelope(atoms))
    return [l for l in lines if l.startswith("Divergence(graph):")]


def missing(atoms, report=None):
    lines, _ = cg.run(envelope(atoms), report)
    return [l for l in lines if l.startswith("Warning: dependency")]


def note(atoms):
    lines, _ = cg.run(envelope(atoms))
    return [l for l in lines if l.startswith("Note:")]


def says_clean(key):
    return f"Divergence(graph): {key} graph says clean, oracle says tainted"


def says_tainted(key):
    return f"Divergence(graph): {key} graph says tainted, oracle says clean"


def main_exit(atoms, *flags, raw=None):
    """(exit code, stdout, stderr) of `main` on `atoms`, enveloped, written to a temp
    file. `raw` is written as it is instead."""
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as fh:
        fh.write(raw if raw is not None else json.dumps(envelope(atoms)))
        path = fh.name
    out, err = io.StringIO(), io.StringIO()
    try:
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = cg.main([path, *flags])
    finally:
        os.unlink(path)
    return code, out.getvalue(), err.getvalue()


def test_divergences():
    print("Divergences")
    assert_eq("tainted atom with the seed edge: no divergence",
              [], divs({"U": atom("unverified"), "T": tainted(["U"])}))
    assert_eq("failed seed taints its caller",
              [], divs({"F": atom("failed"), "T": tainted(["F"])}))
    assert_eq("tainted atom without the seed edge: graph says clean",
              [says_clean("T")], divs({"U": atom("unverified"), "T": tainted()}))
    assert_eq("clean atom that reaches a seed: graph says tainted",
              [says_tainted("C")], divs({"U": atom("unverified"), "C": clean(["U"])}))
    assert_eq("tainted atom that is not a seed passes taint on",
              [], divs({"U": atom("unverified"), "T": tainted(["U"]), "T2": tainted(["T"])}))
    assert_eq("clean verified without marker (--skip-enrich) reached: graph says tainted",
              [says_tainted("V")], divs({"U": atom("unverified"), "V": atom("verified", ["U"])}))
    assert_eq("clean verified without marker not reached: no divergence",
              [], divs({"V": atom("verified")}))
    assert_eq("seeds and trusted atoms get no divergence line",
              [], divs({"U": atom("unverified", ["X"]), "X": atom("trusted")}))


def test_graph_shapes():
    print("Graph shapes")
    assert_eq("trusted atom on the path blocks taint",
              [says_clean("T")],
              divs({"U": atom("unverified"), "Tr": atom("trusted", ["U"]), "T": tainted(["Tr"])}))
    assert_eq("chain of three edges",
              [], divs({"U": atom("unverified"), "A": tainted(["U"]), "B": tainted(["A"]),
                        "C": tainted(["B"])}))
    assert_eq("diamond",
              [], divs({"U": atom("unverified"), "L": tainted(["U"]), "R": tainted(["U"]),
                        "Top": tainted(["L", "R"])}))
    assert_eq("cycle with a seed",
              [], divs({"U": atom("unverified"), "A": tainted(["B", "U"]), "B": tainted(["A"])}))
    assert_eq("cycle without a seed terminates",
              [], divs({"A": clean(["B"]), "B": clean(["A"])}))
    assert_eq("self-edge",
              [], divs({"A": clean(["A"]), "U": atom("unverified", ["U"])}))


def test_missing_dependencies():
    print("Missing dependencies")
    assert_eq("sorted and without duplicates",
              ['Warning: dependency "a" not found in atom map',
               'Warning: dependency "b" not found in atom map'],
              missing({"X": clean(["b", "a", "b"]), "Y": clean(["a"])}))
    for kind in ("inductive", "structure", "class"):
        atoms = {"Foo": atom("trusted", kind=kind), "X": clean(["Foo.mk"])}
        assert_eq(f"member of {kind}: no warning", [], missing(atoms))
        assert_eq(f"member of {kind}: counted",
                  ["Note: 1 reference(s) to constructors/fields of extracted types"], note(atoms))
    assert_eq("missing parent: warning",
              ['Warning: dependency "Gone.mk" not found in atom map'],
              missing({"X": clean(["Gone.mk"])}))
    assert_eq("parent of another kind: warning",
              ['Warning: dependency "f.aux" not found in atom map'],
              missing({"f": atom("transitively-verified", kind="def"), "X": clean(["f.aux"])}))
    assert_eq("no Note line without type members", [], note({"X": clean(["a"])}))


def test_drop_regression():
    print("Drop regression (T -> I -> U)")
    assert_eq("I present: no divergence",
              [], divs({"U": atom("unverified"), "I": tainted(["U"]), "T": tainted(["I"])}))
    atoms = {"U": atom("unverified"), "T": tainted(["I"])}
    assert_eq("I missing: T graph says clean", [says_clean("T")], divs(atoms))
    assert_eq("I missing: I reported",
              ['Warning: dependency "I" not found in atom map'], missing(atoms))


def test_input_output():
    print("Input and output")
    bare = {"U": atom("unverified"), "T": tainted()}
    two = {"X": clean(["a", "b"])}
    assert_eq("--report 1 prints one warning", 1, len(missing(two, 1)))
    assert_eq("--report 0 prints no warning", 0, len(missing(two, 0)))
    code, out, _ = main_exit(two, "--report", "0")
    assert_eq("--report 0 keeps the summary and exit 0",
              (0, "Graph check: 0 atom(s) where the emitted graph disagrees with the kernel walk\n"),
              (code, out))
    assert_eq("--report -1 exits 2", 2, main_exit(two, "--report", "-1")[0])
    assert_eq("divergence without the flag exits 0", 0, main_exit(bare)[0])
    code, out, _ = main_exit(bare, "--fail-on-divergence")
    assert_eq("divergence with --fail-on-divergence exits 1", 1, code)
    assert_eq("summary counts the divergences",
              "Graph check: 1 atom(s) where the emitted graph disagrees with the kernel walk",
              out.splitlines()[-1])
    assert_eq("no divergence with the flag exits 0",
              0, main_exit({"U": atom("unverified")}, "--fail-on-divergence")[0])
    assert_eq("empty artifact: zero summary, exit 0",
              (0, "Graph check: 0 atom(s) where the emitted graph disagrees with the kernel walk\n"),
              main_exit({})[:2])
    code, _, err = main_exit(None, raw=json.dumps(envelope(bare, version="0.15.2")))
    assert_eq("artifact before 0.16.0 exits 2 and names the version",
              (2, True), (code, "0.15.2" in err))
    # A 0.15 tainted atom reads "verified" without the marker. Read as clean, the
    # missing carrier would go unreported, so input without a version is rejected.
    old_data = {"T": atom("verified", ["missingCarrier"])}
    for name, raw in (("bare dict", old_data),
                      ("envelope without tool", {"schema": "s", "data": old_data}),
                      ("envelope from another tool", envelope(old_data, "0.1.0", "other-tool"))):
        code, out, err = main_exit(None, raw=json.dumps(raw))
        assert_eq(f"{name} exits 2 with one message", (2, "", 1),
                  (code, out, len(err.splitlines())))
    code, out, _ = main_exit({"U": atom("unverified"), "N": atom(None, ["U"])})
    assert_eq("atom without status: warning, exit 0",
              (0, "Warning: 1 atom(s) without verification-status "
                  "(not covered by the kernel walk), skipped"),
              (code, out.splitlines()[0]))
    assert_eq("atom without status passes no taint",
              [says_clean("T")],
              divs({"U": atom("unverified"), "N": atom(None, ["U"]), "T": tainted(["N"])}))


def test_invalid_input():
    print("Invalid input (exit 2)")
    cases = {
        "invalid JSON": dict(raw="{"),
        "top level not an object": dict(raw="[]"),
        "data not an object": dict(raw=json.dumps(envelope([]))),
        "atom not an object": dict(doc={"A": 1}),
        "dependencies not a list": dict(doc={"A": {"dependencies": "x"}}),
        "dependency not a string": dict(doc={"A": {"dependencies": [1]}}),
        "unknown status": dict(doc={"A": {"verification-status": "proved"}}),
        "list status": dict(doc={"A": {"verification-status": []}}),
        "object status": dict(doc={"A": {"verification-status": {}}}),
        "unknown status-origin": dict(doc={"A": {"verification-status": "verified",
                                                 "status-origin": "log"}}),
        "status-origin on a non-verified atom": dict(
            doc={"A": {"verification-status": "unverified", "status-origin": "kernel-taint"}}),
        "kind not a string": dict(doc={"A": {"verification-status": "trusted", "kind": 3}}),
        "R5: --skip-verify shape": dict(doc={"A": atom("trusted"), "B": atom(None)}),
        "R5: no status at all": dict(doc={"B": atom(None)}),
    }
    for name, c in cases.items():
        code, out, err = main_exit(c.get("doc"), raw=c.get("raw"))
        assert_eq(name, (2, "", 1), (code, out, len(err.splitlines())))
    code, _, err = main_exit({"A": atom("trusted"), "B": atom(None)})
    assert_eq("R5 message",
              "check-graph: no atom has a kernel-walk status (an artifact from --skip-verify?)",
              err.strip())
    assert_eq("only trusted atoms, all with status: accepted",
              0, main_exit({"A": atom("trusted")})[0])
    with contextlib.redirect_stderr(io.StringIO()) as err:
        code = cg.main(["/nonexistent/artifact.json"])
    assert_eq("missing file exits 2 with one message", (2, 1), (code, len(err.getvalue().splitlines())))


def main():
    test_divergences()
    test_graph_shapes()
    test_missing_dependencies()
    test_drop_regression()
    test_input_output()
    test_invalid_input()
    print(f"\n{PASS} passed, {FAIL} failed")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
