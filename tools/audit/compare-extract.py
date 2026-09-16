#!/usr/bin/env python3
"""Invariant gate for the auxiliary-dependency fold (issue #99).

Compares two `probe-lean extract` artifacts — one from before the fold, one from
after — and asserts the governing invariant:

    The fold only ever *adds* names to `term-dependencies`. It never adds to
    `type-dependencies`, never removes an entry from any of the four dependency
    arrays, never adds to the `*-external` arrays, and never changes the atom
    set.

What matters here is the invariants, not the edge counts: recovering the *wrong*
565 edges would pass any numeric test. Pass `--oracle` (output of
`tools/audit/Audit6.lean` on the same project, commit and module filter) to
additionally require that the added edges are exactly the ones an independent
traversal predicts.

This is a manual recipe, not a CI gate — it needs a built target project. Two
limits worth knowing when reading its output:

- field values are compared *normalized*: absent, `null` and `[]` are all read as
  `[]`, so this checks value identity, not field presence;
- **private-name collisions are outside what it can verify.** The artifact prints
  names through `privateToUserName`, so two distinct declarations can serialize
  identically. This script only ever sees the printed form, which costs it two
  things: a repeated name is reported as a diagnostic rather than checked (see
  the `collisions` note below), and the added-edge diff below is a set difference
  over printed strings, whereas `Audit6.lean` subtracts direct dependencies by
  raw `Name` and renders afterwards. On a colliding pair the two disagree — the
  oracle can predict an edge this diff cannot see — and `--oracle` then reports a
  spurious "predicted but not added". Verifying those cases needs identity in the
  artifact, which it does not carry.

Usage:

    tools/audit/compare-extract.py BEFORE.json AFTER.json [--oracle oracle.tsv]
                                   [--report N]

Exit status is 0 only if every invariant holds.
"""

import argparse
import json
import sys
from collections import Counter, defaultdict

DEP_FIELDS = [
    "dependencies",
    "type-dependencies",
    "term-dependencies",
    "type-dependencies-external",
    "term-dependencies-external",
]
BUCKETS = {"type": "type-dependencies", "term": "term-dependencies"}
PREFIX = "probe:"


def load(path):
    with open(path) as fh:
        return json.load(fh)["data"]


def deps(atom, field):
    return atom.get(field) or []


def strip(name):
    return name[len(PREFIX):] if name.startswith(PREFIX) else name


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("before")
    ap.add_argument("after")
    ap.add_argument("--oracle", help="TSV from tools/audit/Audit6.lean")
    ap.add_argument("--report", type=int, default=10,
                    help="how many example violations to print per check")
    ap.add_argument("--status-policy", choices=("fold", "taint"), default="fold",
                    help="which verification-status moves are legitimate: `fold` "
                         "(default) allows only transitively-verified -> verified, "
                         "the one move adding edges can cause; `taint` is for the "
                         "0.14 -> 0.15 comparison, where status comes from the "
                         "kernel walk: it additionally allows trusted -> "
                         "transitively-verified (generated companions no longer "
                         "inherit their parent's tag) and reports every move by kind")
    args = ap.parse_args()

    before, after = load(args.before), load(args.after)
    failures = []
    notes = []

    def fail(check, violations):
        """Record a failed check. Takes the FULL violation list — truncation is a
        printing concern. Passing a pre-truncated list made `--report 0` slice
        every list to empty and turned the whole gate into a no-op."""
        violations = list(violations)
        if violations:
            failures.append((check, violations))

    # --- atom set unchanged -------------------------------------------------
    fail("atoms removed", sorted(set(before) - set(after)))
    fail("atoms added", sorted(set(after) - set(before)))
    common = sorted(set(before) & set(after))

    # --- nothing removed from any dependency array --------------------------
    for field in DEP_FIELDS:
        removed = []
        for name in common:
            lost = set(deps(before[name], field)) - set(deps(after[name], field))
            if lost:
                removed.append(f"{name}: {sorted(lost)[:5]}")
        fail(f"entries removed from {field}", removed)

    # --- the arrays the fold must not touch at all ---------------------------
    # `type-dependencies` belongs here, not merely in the "nothing removed"
    # loop: every recovered edge is routed to `term-dependencies` so that
    # type-driven `specs` selection cannot move, and that is the one invariant
    # this gate previously could not catch — an artifact pair whose only change
    # was a type-bucket addition printed "All invariants hold." and exited 0.
    for field in ("type-dependencies",
                  "type-dependencies-external", "term-dependencies-external"):
        changed = [f"{name}: {sorted(set(deps(after[name], field)) - set(deps(before[name], field)))[:5]}"
                   for name in common
                   if deps(before[name], field) != deps(after[name], field)]
        fail(f"{field} changed", changed)

    # --- `dependencies` is the deduplicated union of the two buckets --------
    # Checked on the *after* artifact: the fold replaces the old independent
    # derivation of `dependencies`, so a future divergence between the union and
    # whatever produced it must fail here rather than silently drop entries.
    bad_union = []
    for name in common:
        a = after[name]
        union = set(deps(a, "type-dependencies")) | set(deps(a, "term-dependencies"))
        listed = deps(a, "dependencies")
        if sorted(union) != sorted(set(listed)):
            bad_union.append(name)
    fail("dependencies is not the union of type+term", bad_union)

    # Deduplication is by *declaration identity* (raw `Lean.Name`), but the
    # artifact prints names through `privateToUserName`, so two private
    # declarations that recover to one user-facing name serialize identically.
    #
    # Reported, NOT failed. `docs/SCHEMA.md` permits this duplicate, so failing
    # on it rejected artifacts the fold had not touched at all: a before/after
    # pair that differed in nothing still exited 1 whenever either side carried a
    # collision, making the recipe unusable on such a project. Nor is "fail only
    # on new ones" right — an additive fold can legitimately reach a second,
    # distinct declaration whose printed name already occurs. Since the artifact
    # prints names only, this script cannot tell that case from a real double
    # entry, so it surfaces the ambiguity and leaves the judgement to the reader.
    # Multiplicity is tracked per (atom, field, name) so a second collision
    # inside an already-duplicated field is not masked by the first.
    def collisions(data):
        out = Counter()
        for name in common:
            for field in DEP_FIELDS:
                counts = Counter(deps(data[name], field))
                for value, n in counts.items():
                    if n > 1:
                        out[(name, field, value)] = n
        return out

    dup_before, dup_after = collisions(before), collisions(after)
    if dup_after:
        # Counted as distinct (atom, field, name) sites, not as occurrences: a
        # name appearing 3x is one site, and "2 sites" is readable where "5
        # occurrences" is not. `Counter` subtraction still catches a site whose
        # multiplicity merely *grew*.
        new_sites = dup_after - dup_before
        notes.append(
            f"repeated serialized dependency names (private-name collisions, "
            f"permitted by docs/SCHEMA.md — not an invariant): "
            f"{len(dup_before)} site(s) before, {len(dup_after)} after"
            + (f", {len(new_sites)} newly repeated — CHECK THESE" if new_sites else ""))
        for (atom, field, value), n in sorted(new_sites.items())[:args.report]:
            notes.append(f"  newly repeated: {atom}/{field} -> {value} (x{n})")

    # --- sorted output (P14) ------------------------------------------------
    # Only *regressions* are failures. Some arrays are already unsorted with
    # respect to the emitted strings, because probe-lean sorts by the raw
    # `Name` (`_private.M.0.Bar.foo`) while the artifact shows the recovered
    # user-facing name (`Bar.foo`) — deterministic, but not lexicographic in the
    # printed form. That is pre-existing and unrelated to folding.
    def unsorted_fields(data):
        out = set()
        for name in common:
            for field in DEP_FIELDS:
                values = deps(data[name], field)
                if values != sorted(values):
                    out.add(f"{name}/{field}")
        return out

    notes.append(f"arrays unsorted in printed form (pre-existing, see above): "
                 f"{len(unsorted_fields(before))} before, "
                 f"{len(unsorted_fields(after))} after")

    # The check that *is* an invariant, and does not depend on reconstructing
    # probe-lean's sort key: an additive merge re-sorted with the same
    # comparator leaves the old array as a **subsequence** of the new one. This
    # subsumes "nothing removed" and adds "relative order preserved".
    not_subseq = []
    for name in common:
        for field in DEP_FIELDS:
            old, new = deps(before[name], field), deps(after[name], field)
            it = iter(new)
            if not all(any(x == y for y in it) for x in old):
                not_subseq.append(f"{name}/{field}")
    fail("old dependency array is not a subsequence of the new one", not_subseq)

    # --- what the fold actually added ---------------------------------------
    added = defaultdict(set)   # (atom, bucket) -> targets
    for name in common:
        for bucket, field in BUCKETS.items():
            gained = set(deps(after[name], field)) - set(deps(before[name], field))
            if gained:
                added[(strip(name), bucket)] = {strip(t) for t in gained}
    edge_count = sum(len(v) for v in added.values())
    atoms_touched = len({k[0] for k in added})
    notes.append(f"added {edge_count} edge(s) across {atoms_touched} atom(s)")
    by_bucket = defaultdict(int)
    for (_, bucket), targets in added.items():
        by_bucket[bucket] += len(targets)
    notes.append(f"by bucket: " + ", ".join(
        f"{b}={by_bucket.get(b, 0)}" for b in sorted(BUCKETS)))

    # In-edges recovered, and atoms that were invisible before (in-degree 0 over
    # the emitted graph) and are referenced after. This is the reporter's case.
    def indegree(data):
        deg = defaultdict(int)
        for name, atom in data.items():
            for dep in deps(atom, "dependencies"):
                if dep != name:
                    deg[dep] += 1
        return deg

    deg_before, deg_after = indegree(before), indegree(after)
    rescued = sorted(name for name in common
                     if deg_before.get(name, 0) == 0 and deg_after.get(name, 0) > 0)
    notes.append(f"in-degree 0 -> >0: {len(rescued)}")

    # Status changes. Under the `fold` policy the fold can only ever *add* edges,
    # so the only legitimate move is a downgrade away from `transitively-verified`.
    # Under `taint` (the kernel-walk comparison) a `trusted` companion may also
    # rise to `transitively-verified`; every move is counted by kind so the
    # golden numbers can be checked against the expected delta.
    allowed = {("transitively-verified", "verified")}
    if args.status_policy == "taint":
        allowed.add(("trusted", "transitively-verified"))
    bad_status = []
    moves = Counter()
    for name in common:
        b, a = before[name].get("verification-status"), after[name].get("verification-status")
        if b == a:
            continue
        moves[(b, a)] += 1
        if (b, a) not in allowed:
            bad_status.append(f"{name}: {b} -> {a}")
    for (b, a), n in sorted(moves.items(), key=lambda kv: str(kv[0])):
        notes.append(f"{b} -> {a}: {n}")
    if not moves:
        notes.append("verification-status: no moves")
    fail(f"verification-status moved in a direction the `{args.status_policy}` policy forbids",
         bad_status)
    if args.status_policy == "taint":
        attr_changes = [f"{name}: {deps(before[name], 'attributes')} -> {deps(after[name], 'attributes')}"
                        for name in common
                        if deps(before[name], "attributes") != deps(after[name], "attributes")]
        notes.append(f"attributes changed: {len(attr_changes)}")
        for line in attr_changes[:args.report]:
            notes.append(f"  {line}")

    # --- specs / primary-spec blast radius ----------------------------------
    # Not an invariant: `computeSpecs`' `@[primary_spec]` fallback walks the
    # union `dependencies`, so a folded term edge legitimately can attach or
    # detach a spec. Reported in full so the change is a recorded decision
    # rather than a surprise.
    spec_diff = []
    for name in common:
        if before[name].get("primary-spec") != after[name].get("primary-spec"):
            spec_diff.append(f"{name}/primary-spec: "
                             f"{before[name].get('primary-spec')} -> "
                             f"{after[name].get('primary-spec')}")
        # Set delta, not the whole array: a widely-depended-on atom can carry
        # hundreds of specs and the diff is unreadable printed in full.
        gained = set(deps(after[name], "specs")) - set(deps(before[name], "specs"))
        lost = set(deps(before[name], "specs")) - set(deps(after[name], "specs"))
        if gained or lost:
            spec_diff.append(f"{name}/specs: +{sorted(gained)} -{sorted(lost)}")
    notes.append(f"specs/primary-spec field changes: {len(spec_diff)}")

    # --- oracle agreement ---------------------------------------------------
    if args.oracle:
        expected = defaultdict(set)
        with open(args.oracle) as fh:
            for line in fh:
                line = line.rstrip("\n")
                if not line:
                    continue
                atom, bucket, target = line.split("\t")
                expected[(atom, bucket)].add(target)
        missing, extra = [], []
        for key in sorted(set(expected) | set(added)):
            exp, got = expected.get(key, set()), added.get(key, set())
            if exp - got:
                missing.append(f"{key[0]}/{key[1]}: {sorted(exp - got)[:5]}")
            if got - exp:
                extra.append(f"{key[0]}/{key[1]}: {sorted(got - exp)[:5]}")
        notes.append(f"oracle expects {sum(len(v) for v in expected.values())} edge(s)")
        fail("oracle edge predicted but not added", missing)
        fail("edge added but not predicted by the oracle", extra)

    for note in notes:
        print(f"  {note}")
    if spec_diff:
        print("  specs/primary-spec diff:")
        for line in spec_diff[:args.report]:
            print(f"    {line}")
    if rescued:
        print("  sample of atoms rescued from in-degree 0:")
        for name in rescued[:args.report]:
            print(f"    {name}")

    if not failures:
        print("\nAll invariants hold.")
        return 0
    print(f"\n{len(failures)} invariant check(s) FAILED:")
    for check, violations in failures:
        print(f"  ✗ {check} ({len(violations)})")
        shown = violations[:args.report] if args.report > 0 else []
        for violation in shown:
            print(f"      {violation}")
        hidden = len(violations) - len(shown)
        if hidden:
            print(f"      ({hidden} not shown; raise --report)")
    return 1


if __name__ == "__main__":
    sys.exit(main())
