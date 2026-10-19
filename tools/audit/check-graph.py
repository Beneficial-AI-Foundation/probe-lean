#!/usr/bin/env python3
"""Graph check of an `extract` artifact: does the emitted `dependencies` graph
explain every status the kernel walk stamped?

The kernel walk decides `verification-status`. This script re-derives taint from the
emitted graph alone and prints every atom where the two disagree. A disagreement
means that the graph lacks a node or an edge on the path to a `sorry` (issues #99
and #135 were such bugs). Up to 0.20.0, `extract` ran this check itself and printed
the same lines on stderr.

The rule, ported from `enrichTransitiveVerification`:

    seeds        atoms that read "unverified" or "failed"
    propagation  from a dependency to its callers, through atoms that read
                 "verified" or "transitively-verified"
    blockers     "trusted" atoms, atoms without a status, missing dependencies

The kernel walk's verdict, from the artifact:

    tainted  "verified" with status-origin "kernel-taint"
    clean    "transitively-verified", or "verified" without status-origin
             (the --skip-enrich cap)

    tainted, not reached by the BFS:  graph says clean, oracle says tainted
    clean, reached by the BFS:        graph says tainted, oracle says clean

Output, on stdout:

    Warning: dependency "<name>" not found in atom map     (one per missing name)
    Note: N reference(s) to constructors/fields of extracted types
    Divergence(graph): <atom> graph says ..., oracle says ...
    Graph check: K atom(s) where the emitted graph disagrees with the kernel walk

A missing name `Foo.Bar` whose parent `Foo` is an `inductive`, `structure` or
`class` atom is a type member. It goes into the `Note:` count, not a warning.

Exit status: 0 when the report is printed, 1 when there is a divergence and
`--fail-on-divergence` is given, 2 on invalid input. Exit 0 means that the emitted
graph and the kernel walk agree on every atom with a status. It does not prove that
every edge was emitted: a missing edge that does not change taint is invisible, and
missing dependencies never fail the run.

Limits:

- Artifacts from probe-lean 0.16.0 on. Older ones have no `status-origin` marker,
  and the script rejects them. A bare-dict artifact has no version and is accepted.
- If `extract` printed the duplicate-name warning, the artifact keeps one of the
  colliding atoms. The report then lacks the other atom and its edges.
- A `--skip-verify` artifact has no kernel-walk status, and the script rejects it.

Usage:

    tools/audit/check-graph.py ARTIFACT.json [--fail-on-divergence] [--report N]
"""

import argparse
import json
import sys
from collections import deque

STATUSES = {"verified", "unverified", "failed", "trusted", "transitively-verified"}
SEEDS = {"unverified", "failed"}
PASSES = {"verified", "transitively-verified"}
TYPE_KINDS = {"inductive", "structure", "class"}
MIN_VERSION = (0, 16, 0)


class InputError(Exception):
    pass


def parse_version(text):
    """(major, minor, patch) of a version string, or None if it is not one."""
    parts = text.split("-")[0].split(".")
    if len(parts) != 3 or not all(p.isdigit() for p in parts):
        return None
    return tuple(int(p) for p in parts)


def unwrap(doc):
    """The atom map of a bare-dict or enveloped artifact, as `Loader.lean` reads it:
    an envelope has a string `schema` and a `data` field. Rejects an envelope from
    probe-lean before 0.16.0."""
    if not isinstance(doc, dict):
        raise InputError("top level is not a JSON object")
    if not (isinstance(doc.get("schema"), str) and "data" in doc):
        return doc
    tool = doc.get("tool")
    if isinstance(tool, dict) and tool.get("name") == "probe-lean":
        version = tool.get("version")
        parsed = parse_version(version) if isinstance(version, str) else None
        if parsed is None:
            raise InputError(f"tool.version is {version!r}, not a version")
        if parsed < MIN_VERSION:
            raise InputError(f"artifact from probe-lean {version}: the graph check needs "
                             "0.16.0 or later (status-origin marker)")
    data = doc["data"]
    if not isinstance(data, dict):
        raise InputError("data is not a JSON object")
    return data


def validate(atoms):
    """Check every field the script reads. Raises InputError on the first problem."""
    for key, atom in atoms.items():
        if not isinstance(atom, dict):
            raise InputError(f"{key}: atom is not a JSON object")
        deps = atom.get("dependencies", [])
        if not isinstance(deps, list) or not all(isinstance(d, str) for d in deps):
            raise InputError(f"{key}: dependencies is not a list of strings")
        status = atom.get("verification-status")
        if status is not None and status not in STATUSES:
            raise InputError(f"{key}: unknown verification-status {status!r}")
        if "status-origin" in atom:
            origin = atom["status-origin"]
            if origin != "kernel-taint":
                raise InputError(f"{key}: unknown status-origin {origin!r}")
            if status != "verified":
                raise InputError(f"{key}: status-origin on an atom that reads {status!r}")
        if "kind" in atom and not isinstance(atom["kind"], str):
            raise InputError(f"{key}: kind is not a string")
    with_status = [a["verification-status"] for a in atoms.values()
                   if a.get("verification-status") is not None]
    if len(with_status) < len(atoms) and all(s == "trusted" for s in with_status):
        raise InputError("no atom has a kernel-walk status (an artifact from --skip-verify?)")


def missing_dependencies(atoms):
    """(orphans, type_member_count): the sorted dependency names that are not atoms,
    without type members, and the number of type members (`partitionMissingDeps`)."""
    missing = sorted({d for a in atoms.values() for d in a.get("dependencies", [])
                      if d not in atoms})
    type_defs = {k for k, a in atoms.items() if a.get("kind") in TYPE_KINDS}
    orphans = []
    members = 0
    for dep in missing:
        parent = dep.rsplit(".", 1)[0] if "." in dep else None
        if parent is not None and parent in type_defs:
            members += 1
        else:
            orphans.append(dep)
    return orphans, members


def reached(atoms):
    """The atoms the reverse BFS reaches from the seeds through passing atoms."""
    callers = {}
    for key, atom in atoms.items():
        for dep in atom.get("dependencies", []):
            callers.setdefault(dep, []).append(key)
    marked = set()
    queue = deque(k for k, a in atoms.items() if a.get("verification-status") in SEEDS)
    while queue:
        node = queue.popleft()
        for caller in callers.get(node, []):
            if caller not in marked and atoms[caller].get("verification-status") in PASSES:
                marked.add(caller)
                queue.append(caller)
    return marked


def divergences(atoms, marked):
    out = []
    for key in sorted(atoms):
        atom = atoms[key]
        status = atom.get("verification-status")
        tainted = status == "verified" and atom.get("status-origin") == "kernel-taint"
        clean = status == "transitively-verified" or (
            status == "verified" and "status-origin" not in atom)
        if tainted and key not in marked:
            out.append(f"Divergence(graph): {key} graph says clean, oracle says tainted")
        elif clean and key in marked:
            out.append(f"Divergence(graph): {key} graph says tainted, oracle says clean")
    return out


def run(doc, report=None):
    """(lines, divergence_count) for a parsed artifact. Raises InputError."""
    atoms = unwrap(doc)
    validate(atoms)
    lines = []
    statusless = sum(1 for a in atoms.values() if a.get("verification-status") is None)
    if statusless:
        lines.append(f"Warning: {statusless} atom(s) without verification-status "
                     "(not covered by the kernel walk), skipped")
    orphans, members = missing_dependencies(atoms)
    for dep in orphans if report is None else orphans[:report]:
        lines.append(f'Warning: dependency "{dep}" not found in atom map')
    if members:
        lines.append(f"Note: {members} reference(s) to constructors/fields of extracted types")
    divs = divergences(atoms, reached(atoms))
    lines.extend(divs)
    lines.append(f"Graph check: {len(divs)} atom(s) where the emitted graph disagrees "
                 "with the kernel walk")
    return lines, len(divs)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("artifact")
    ap.add_argument("--fail-on-divergence", action="store_true",
                    help="exit 1 if the graph and the kernel walk disagree on an atom")
    ap.add_argument("--report", type=int, metavar="N",
                    help="print at most N missing-dependency warnings (default: all)")
    args = ap.parse_args(argv)
    try:
        if args.report is not None and args.report < 0:
            raise InputError(f"--report {args.report}: must not be negative")
        try:
            with open(args.artifact) as fh:
                doc = json.load(fh)
        except OSError as e:
            raise InputError(f"cannot read {args.artifact}: {e.strerror}")
        except json.JSONDecodeError as e:
            raise InputError(f"{args.artifact}: invalid JSON: {e}")
        lines, count = run(doc, args.report)
    except InputError as e:
        print(f"check-graph: {e}", file=sys.stderr)
        return 2
    for line in lines:
        print(line)
    return 1 if args.fail_on_divergence and count else 0


if __name__ == "__main__":
    sys.exit(main())
