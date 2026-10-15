#!/usr/bin/env python3
"""End-to-end assertions for the `assumptions` field.

Run from this directory after `lake build`:

    python3 check.py PATH/TO/probe-lean

The script runs `extract` three times, each with its own `-o` path (normal,
`--skip-verify`, `--skip-enrich`), and `check-axioms` once. Each run must exit 0.
It then checks:

- every expected atom exists, has the field, and has exactly the expected set;
- the `check-axioms` assumption section: one section, every line with its category
  and count, and the summary line;
- `--skip-verify`: no atom has the field, trusted atoms read `trusted`, no other
  atom has a status;
- `--skip-enrich`: the same sets as the normal run, clean atoms read `verified`;
- `tools/audit/check-status-consistency.py` passes on each output with the matching
  flags, and fails on two edited copies (one atom without the field, one
  `--skip-verify` atom with it).

The compiled-code rows depend on the Lean version in `lean-toolchain`: from 4.31 on
each proof adds its own `X._native.<tactic>.ax_N` axiom.
"""

import copy
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CONSISTENCY = os.path.join(HERE, "..", "..", "..", "tools", "audit", "check-status-consistency.py")
OUT = {"normal": "assumptions-normal.json", "skip-verify": "assumptions-skip-verify.json",
       "skip-enrich": "assumptions-skip-enrich.json"}
REPORT = "check-axioms.out"

failures = []


def check(name, ok):
    print(f"  {'✓' if ok else '✗'} {name}")
    if not ok:
        failures.append(name)


def lean_minor():
    with open(os.path.join(HERE, "lean-toolchain")) as fh:
        m = re.search(r"v4\.(\d+)", fh.read())
    return int(m.group(1))


NEW_NATIVE = lean_minor() >= 31
COMPILER = ["Lean.ofReduceBool", "Lean.trustCompiler"]

# atom -> (status, status-origin, assumptions)
EXPECTED = {
    "onlyS": ("transitively-verified", None, []),
    "nd": ("transitively-verified", None,
           ["nd._native.native_decide.ax_1_1"] if NEW_NATIVE else COMPILER),
    "dn": ("transitively-verified", None,
           ["dn._native.decide.ax_1_1"] if NEW_NATIVE else COMPILER),
    "bv": ("transitively-verified", None,
           ["bv._native.bv_decide.ax_1_5"] if NEW_NATIVE else COMPILER),
    "bad": ("trusted", None, ["bad"]),
    "useBad": ("transitively-verified", None, ["bad"]),
    "T": ("trusted", None, ["T"]),
    "useT": ("transitively-verified", None, ["T"]),
    "vouched": ("trusted", None, ["vouched"]),
    "useVouched": ("transitively-verified", None, ["vouched"]),
    "vouchedClean": ("trusted", None, []),
    "useVouchedClean": ("transitively-verified", None, []),
    "vouchedAx": ("trusted", None, ["bad"]),
    "n": ("trusted", None, ["n"]),
    "same": ("trusted", None, ["n"]),
    "useSame": ("transitively-verified", None, ["n"]),
    "holey": ("unverified", None, ["sorryAx"]),
    "useHoley": ("verified", "kernel-taint", ["sorryAx"]),
    "holeyDef": ("unverified", None, ["sorryAx"]),
    # The proofs name `sorryAx` (the binder type) or `holeyDef` (`rfl`), so the
    # trusted rule adds the constant's own name too.
    "stmtSorry": ("unverified", None, ["sorryAx", "stmtSorry"]),
    "stmtIndirect": ("verified", "kernel-taint", ["sorryAx", "stmtIndirect"]),
    "Box": ("verified", "kernel-taint", ["sorryAx"]),
    "mkA": ("verified", "kernel-taint", ["sorryAx"]),
    "ext_add": ("trusted", None, ["ext_add"]),
    "add_spec": ("trusted", None, ["add_spec", "ext_add"]),
    "mul": ("trusted", None, ["ext_add"]),
    "mul_spec": ("trusted", None, ["add_spec", "ext_add"]),
    "caller_spec": ("transitively-verified", None, ["add_spec", "ext_add"]),
    "ext_id": ("trusted", None, []),
    "extOpaque": ("trusted", None, ["extOpaque"]),
    "BadBox": ("verified", "kernel-taint", ["sorryAx"]),
    "EvenE": ("trusted", None, ["T"]),
    "OddE": ("trusted", None, ["T"]),
    "useD": ("transitively-verified", None, ["d"]),
    "useDepSorry": ("transitively-verified", None, ["sorryAx"]),
    "useDepVouched": ("transitively-verified", None, ["sorryAx"]),
    "useDepExt": ("transitively-verified", None, ["sorryAx"]),
    "badBoxCases": ("verified", "kernel-taint", ["sorryAx"]),
    "badMk": ("verified", "kernel-taint", ["sorryAx"]),
    # A project axiom merged with a dependency theorem: the environment keeps the
    # theorem and attributes it to the project module, and `h1` stays in its set.
    "h1": ("trusted", None, ["h1"]),
    "useH1": ("transitively-verified", None, ["h1"]),
    # A project theorem merged with a dependency axiom: the axiom version counts.
    "h2": ("transitively-verified", None, ["h2"]),
    "useH2": ("transitively-verified", None, ["h2"]),
    # Two dependency modules that swap an axiom and a theorem (`Dep.SwapA`,
    # `Dep.SwapB`): the kept theorems only call each other, the dropped axiom
    # versions keep both names in the sets.
    "useSwapA": ("transitively-verified", None, ["sa", "sb"]),
    "useSwapB": ("transitively-verified", None, ["sa", "sb"]),
    # A project axiom merged with a dependency theorem that uses `sorry`: the `sorry`
    # is outside P, so trust does not excuse it.
    "h3": ("trusted", None, ["h3", "sorryAx"]),
    "useH3": ("transitively-verified", None, ["h3", "sorryAx"]),
    # Two dependency modules that declare the same theorems, one proof of each with
    # `sorry` (`Dep.DupA`, `Dep.DupB`): every caller lists `sorryAx`, whichever version
    # Lean kept. The status walk does not enter dependencies.
    "useDd1A": ("transitively-verified", None, ["sorryAx"]),
    "useDd2A": ("transitively-verified", None, ["sorryAx"]),
    "useDd1B": ("transitively-verified", None, ["sorryAx"]),
    "useDd2B": ("transitively-verified", None, ["sorryAx"]),
}

# The expected values below were taken on Lean 4.28.0-rc1 (`NEW_NATIVE` false),
# Lean 4.33.0 and Lean 4.35.0 (`NEW_NATIVE` true, 4.35.0 is the `test-newest` toolchain). Lean generates other
# constants on other versions, so after a toolchain bump compare these values first.
#
# The check-axioms section: (name, category, count), sorted by name. The counts
# include project constants that are not atoms: the constructor `Box.a`, the
# generated constants of the inductives (`BadBox.casesOn` names the trusted
# recursor `BadBox.rec`), and the auxiliary constants of the compiled-code proofs.
COMMON = [
    # From Lean 4.35 on, the generated `BadBox.recOn` refers to `BadBox.casesOn`, not
    # to `BadBox.rec`, so `BadBox.casesOn` is in one more set.
    ("BadBox.casesOn", "trusted (external)", 2 if lean_minor() >= 35 else 1),
    ("BadBox.recOn", "trusted (external)", 1),
    ("T", "universe-typed", 44),
    ("add_spec", "trusted (externally_verified)", 3),
    ("bad", "project axiom", 3),
    ("d", "dependency axiom", 1),
    ("extOpaque", "trusted (external)", 1),
    ("ext_add", "trusted (external)", 5),
    ("h1", "project axiom", 2),
    ("h2", "project axiom", 2),
    ("h3", "project axiom", 2),
    ("n", "project axiom", 3),
    ("sa", "dependency axiom", 2),
    ("sb", "dependency axiom", 2),
    ("sorryAx", "sorry", 43),
    ("stmtIndirect", "trusted (externally_verified)", 1),
    ("stmtSorry", "trusted (externally_verified)", 1),
    ("vouched", "trusted (externally_verified)", 2),
]
if NEW_NATIVE:
    NATIVE = [
        ("bv._native.bv_decide.ax_1_5", "bv_decide", 2),
        ("dn._native.decide.ax_1_1", "native_decide", 2),
        ("nd._native.native_decide.ax_1_1", "native_decide", 2),
    ]
else:
    NATIVE = [
        ("Lean.ofReduceBool", "native_decide", 6),
        ("Lean.trustCompiler", "native_decide", 6),
    ]
SECTION = sorted(COMMON + NATIVE)


def run(cmd, stdout=None):
    print(f"$ {' '.join(cmd)}")
    proc = subprocess.run(cmd, stdout=stdout, stderr=subprocess.PIPE, text=True)
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr)
    return proc.returncode


def load(path):
    with open(path) as fh:
        return json.load(fh)["data"]


def atom(data, name):
    return data.get("probe:" + name)


def source_lines(a):
    with open(os.path.join(HERE, a["code-path"])) as fh:
        lines = fh.read().splitlines()
    span = a["code-text"]
    return "\n".join(lines[span["lines-start"] - 1:span["lines-end"]])


def check_normal(data):
    print("Expected atoms, statuses and sets")
    for name, (status, origin, sets) in EXPECTED.items():
        a = atom(data, name)
        if a is None:
            check(f"{name}: atom exists", False)
            continue
        if "assumptions" not in a:
            check(f"{name}: has the assumptions field", False)
            continue
        got = (a.get("verification-status"), a.get("status-origin"), a["assumptions"])
        check(f"{name}: {status}{' + ' + origin if origin else ''}, {sets}", got == (status, origin, sets))
    print("The trusted inductives form one kernel cycle")
    even, odd = atom(data, "EvenE"), atom(data, "OddE")
    if even is None or odd is None:
        check("EvenE and OddE exist", False)
    else:
        # The emitted `dependencies` of an inductive do not list its constructor
        # fields, so the cycle is shown from the constructors in the source.
        check("EvenE names OddE and OddE names EvenE in their constructors",
              "OddE" in source_lines(even) and "EvenE" in source_lines(odd))


HEADER = re.compile(r"^(\d+) assumption name\(s\) in the sets of project constants:$")
LINE = re.compile(r"^  (.*) \[(.*)\] (\d+)$")
ORDER = ["sorry", "bv_decide", "native_decide", "universe-typed", "project axiom",
         "dependency axiom", "trusted"]


def check_report(lines):
    print("The check-axioms assumption section")
    starts = [i for i, l in enumerate(lines) if HEADER.match(l)]
    check("exactly one assumption section", len(starts) == 1)
    if len(starts) != 1:
        return
    start = starts[0]
    count = int(HEADER.match(lines[start]).group(1))
    body = []
    for l in lines[start + 1:start + 1 + count]:
        m = LINE.match(l)
        body.append((m.group(1), m.group(2), int(m.group(3))) if m else ("?", l, -1))
    check(f"header count {count} equals the expected {len(SECTION)} names", count == len(SECTION))
    for exp, got in zip(SECTION, body):
        check(f"line {exp[0]} [{exp[1]}] {exp[2]}", exp == got)
    for got in body[len(SECTION):]:
        check(f"unexpected line {got}", False)
    cats = [c for _, c, _ in SECTION]
    key = lambda c: "trusted" if c.startswith("trusted (") else c
    summary = "Assumptions by category: " + " | ".join(
        f"{k} {sum(1 for c in cats if key(c) == k)}" for k in ORDER)
    check(f"summary line: {summary}", lines[start + 1 + count:start + 2 + count] == [summary])


def check_skip_verify(normal, data):
    print("--skip-verify")
    check("no atom has the field", all("assumptions" not in a for a in data.values()))
    trusted = {k for k, a in normal.items() if a.get("trusted-reason")}
    check("trusted atoms read trusted",
          all(data[k].get("verification-status") == "trusted" for k in trusted))
    check("no other atom has a status",
          all("verification-status" not in a for k, a in data.items() if k not in trusted))


def check_skip_enrich(normal, data):
    print("--skip-enrich")
    check("the same sets as the normal run",
          all(data[k].get("assumptions") == a.get("assumptions") for k, a in normal.items()))
    clean = [k for k, a in normal.items() if a.get("verification-status") == "transitively-verified"]
    check("clean atoms read verified",
          all(data[k].get("verification-status") == "verified" for k in clean))


def consistency(artifact, *flags):
    proc = subprocess.run([sys.executable, CONSISTENCY, artifact, REPORT, *flags],
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    return proc.returncode, proc.stdout


def check_consistency(normal, skip_verify):
    print("check-status-consistency.py")
    for path, flags in ((OUT["normal"], []), (OUT["skip-enrich"], ["--no-upgrade"]),
                        (OUT["skip-verify"], ["--allow-missing"])):
        code, out = consistency(path, *flags)
        check(f"passes on {path} {' '.join(flags)}".rstrip(), code == 0)
        if code != 0:
            print(out)
    without = copy.deepcopy(normal)
    del without["probe:useBad"]["assumptions"]
    with_field = copy.deepcopy(skip_verify)
    with_field["probe:vouched"]["assumptions"] = ["vouched"]
    for path, data, flags, message in (
            ("assumptions-negative-missing.json", without, [], "useBad: no assumptions field"),
            ("assumptions-negative-present.json", with_field, ["--allow-missing"],
             "vouched: assumptions present under --allow-missing")):
        with open(path, "w") as fh:
            json.dump({"data": data}, fh)
        code, out = consistency(path, *flags)
        check(f"fails on {path} with `{message}`", code != 0 and message in out)


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    probe = sys.argv[1]
    os.chdir(HERE)
    for path in list(OUT.values()) + [REPORT, "assumptions-negative-missing.json",
                                      "assumptions-negative-present.json"]:
        if os.path.exists(path):
            os.remove(path)
    print("Runs")
    check("extract exits 0", run([probe, "extract", ".", "-o", OUT["normal"]],
                                 stdout=subprocess.DEVNULL) == 0)
    check("extract --skip-verify exits 0",
          run([probe, "extract", ".", "--skip-verify", "-o", OUT["skip-verify"]],
              stdout=subprocess.DEVNULL) == 0)
    check("extract --skip-enrich exits 0",
          run([probe, "extract", ".", "--skip-enrich", "-o", OUT["skip-enrich"]],
              stdout=subprocess.DEVNULL) == 0)
    with open(REPORT, "w") as fh:
        check("check-axioms exits 0", run([probe, "check-axioms", "."], stdout=fh) == 0)
    if failures:
        return 1
    normal, skip_verify, skip_enrich = (load(OUT[k]) for k in ("normal", "skip-verify", "skip-enrich"))
    with open(REPORT) as fh:
        report = fh.read().splitlines()
    check_normal(normal)
    check_report(report)
    check_skip_verify(normal, skip_verify)
    check_skip_enrich(normal, skip_enrich)
    check_consistency(normal, skip_verify)
    print(f"{len(failures)} failure(s)" if failures else "all assumption checks pass")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
