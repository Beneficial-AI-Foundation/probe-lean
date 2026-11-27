#!/usr/bin/env python3
"""End-to-end assertions for the step-program primary-spec rules (#129, #132, #133).

Run from this directory after `lake build`:

    python3 check.py PATH/TO/probe-lean [OUT]

The script runs `extract . -o OUT` (default `step-spec.json`). The run must exit 0.
It then checks the `primary-spec` of each target in `Step/Funs.lean` and the
`attributes` of the `@[local step]` theorem. For `Step/Marker.lean` it checks the
primary-spec docstring marker: `is-primary-spec`, the winners and the collision
warning. Run it with an older probe-lean and a
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
    "Step.one": "Step.one_spec",  # rule 3, program head is some
    # Step/Marker.lean: the primary-spec docstring marker
    "Marker.double": "Marker.double_correct",  # rule 1 by marker, over rule 3
    "Marker.square": "Marker.square_spec",  # plain comments and primary-specs do not mark
    "Marker.triple": "Marker.triple_ax.mvcgen_spec",  # marker added with add_decl_doc
    "Marker.half": "Marker.half_both",  # tagged and marked counts once, over rule 3
}

# Marker.twice has two marked theorems, Marker.quad one tagged and one marked:
# the winner is arbitrary, and each target gets a collision warning.
COLLISIONS = {
    "Marker.twice": {"probe:Marker.twice_a", "probe:Marker.twice_b"},
    "Marker.quad": {"probe:Marker.quad_tagged", "probe:Marker.quad_marked"},
}

# atom -> expected is-primary-spec
MARKED = {
    "Marker.double_correct": True,
    "Marker.double_spec": False,
    "Marker.square_spec": False,
    "Marker.square_bound": False,  # plain comments
    "Marker.square_aux": False,  # primary-specs
    "Marker.twice_a": True,
    "Marker.twice_b": True,
    "Marker.quad_tagged": True,
    "Marker.quad_marked": True,
    "Marker.half_both": True,
    "Marker.half_spec": False,
    "Marker.marked_def": True,  # a marked non-theorem
    "Marker.triple_ax": True,
    "Marker.triple_ax.mvcgen_spec": True,  # add_decl_doc
    "Marker.triple_spec": False,
    "Marker.double": False,  # the module docstring marks nothing
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
        key = f"probe:{target}"
        if key not in data:
            check(f"{target} is in the output", False)
            continue
        got = data[key].get("primary-spec")
        want = None if spec is None else f"probe:{spec}"
        check(f"{target} -> {spec} (got {got})", got == want)
    attrs = data.get("probe:Step.chi_row_correct", {}).get("attributes", [])
    check(f"@[local step] is recorded as step, not local (got {attrs})",
          "step" in attrs and "local" not in attrs)

    print("Primary spec from the docstring marker")
    for atom, want in MARKED.items():
        got = data.get(f"probe:{atom}", {}).get("is-primary-spec")
        check(f"{atom} is-primary-spec = {want} (got {got})", got is want)
    attrs = data.get("probe:Marker.double_correct", {}).get("attributes", [])
    check(f"the marker adds no attribute (got {attrs})", "primary_spec" not in attrs)
    attrs = data.get("probe:Marker.quad_tagged", {}).get("attributes", [])
    check(f"the stub tag is recorded as primary_spec (got {attrs})", "primary_spec" in attrs)
    warnings = [l for l in run.stderr.splitlines() if l.startswith("Warning:")]
    for target, candidates in COLLISIONS.items():
        got = data.get(f"probe:{target}", {}).get("primary-spec")
        check(f"{target} -> one of {sorted(candidates)} (got {got})", got in candidates)
        hits = [w for w in warnings if f"probe:{target} " in w]
        check(f"one collision warning for {target} (got {hits})", len(hits) == 1)
    check(f"no other collision warning (got {warnings})", len(warnings) == len(COLLISIONS))

    if failures:
        print(f"{len(failures)} check(s) failed")
        return 1
    print("All step-spec checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
