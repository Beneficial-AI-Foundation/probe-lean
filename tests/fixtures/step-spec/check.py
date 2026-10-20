#!/usr/bin/env python3
"""End-to-end assertions for the step-program primary-spec rules (#129, #132, #133).

Run from this directory after `lake build`:

    python3 check.py PATH/TO/probe-lean [OUT]

The script runs `extract . -o OUT` (default `step-spec.json`). The run must exit 0.
It then checks the `primary-spec` of each target in `Step/Funs.lean` and the
`attributes` of the `@[local step]` theorem. Run it with an older probe-lean and a
separate OUT to see which assertions the change fixes.
"""

import json
import subprocess
import sys

# target -> expected primary spec, with the deciding rule
EXPECTED = {
    "Fx.Ns.mont_mul": "Props.mont_mul.spec",  # rule 4
    "Step.invert": "Step.invert_correct",  # rule 2, to_edwards_spec is about to_edwards
    "Step.to_edwards": "Step.to_edwards_spec",  # rule 2
    "Step.lfactor": "Step.lfactor_spec",  # rule 3, part1_spec is about part1 (#129)
    "Step.part1": "Step.part1_spec",  # rule 2
    "Step.chi_row": "Step.chi_row_correct",  # rule 2, @[local step] (#133)
    "Step.append": "Step.append.spec",  # rule 3, <T>.spec
    "Step.hkdf": None,  # the axiom companion is about to_slice, to_vec_spec about to_vec
    "Step.to_slice": "Step.to_slice_spec.mvcgen_spec",  # rule 2, the axiom companion
}

failures = []


def check(name, ok):
    print(f"  {'✓' if ok else '✗'} {name}")
    if not ok:
        failures.append(name)


def main():
    if len(sys.argv) not in (2, 3):
        print(__doc__)
        return 2
    binary = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) == 3 else "step-spec.json"
    run = subprocess.run([binary, "extract", ".", "-o", out], capture_output=True, text=True)
    if run.returncode != 0:
        sys.stderr.write(run.stderr)
        print(f"extract exited with {run.returncode}")
        return 2
    with open(out) as fh:
        data = json.load(fh)["data"]

    print("Primary spec from the step program")
    for target, spec in EXPECTED.items():
        atom = data.get(f"probe:{target}", {})
        got = atom.get("primary-spec")
        want = None if spec is None else f"probe:{spec}"
        check(f"{target} -> {spec} (got {got})", got == want)
    attrs = data.get("probe:Step.chi_row_correct", {}).get("attributes", [])
    check(f"@[local step] is recorded as step, not local (got {attrs})",
          "step" in attrs and "local" not in attrs)

    if failures:
        print(f"{len(failures)} check(s) failed")
        return 1
    print("All step-spec checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
