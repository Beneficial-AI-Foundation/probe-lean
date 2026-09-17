#!/usr/bin/env python3
"""Bidirectional gate between an `extract` artifact and a `check-axioms` report.

Both come from the same kernel walk, so they must agree *exactly* on every emitted
atom. One-directional checks ("every `unverified` atom is a direct carrier") pass
vacuously when nothing is `unverified`; this asserts the equivalence in both
directions:

    emitted, listed `[direct]`          <=>  verification-status == "unverified"
    emitted, listed, not `[direct]`     <=>  verification-status == "verified"
    emitted, not listed                 <=>  "transitively-verified" or "trusted"
    listed without `[not emitted]`      <=>  is an atom of the artifact

An atom without a `verification-status` fails unless `--allow-missing` is given
(`--skip-verify` runs). `--skip-enrich` artifacts read `verified` where the report
predicts `transitively-verified`; pass `--no-upgrade` for those.

Usage:

    tools/audit/check-status-consistency.py ARTIFACT.json check-axioms.out
                                            [--allow-missing] [--no-upgrade]

Names: the artifact prints private declarations through `privateToUserName`; the
report prints raw `Name`s, so `_private.<module>.0.` prefixes are stripped before
matching and any name still unmatched is reported (not failed) as unresolvable.

Exit status is 0 only if every equivalence holds.
"""

import argparse
import json
import re
import sys

PREFIX = "probe:"
PRIVATE = re.compile(r"^_private\.(?:[^.]+\.)*?0\.")


def user_name(raw):
    return PRIVATE.sub("", raw)


def parse_report(path):
    """{name: (direct, emitted, stripped)} for every listed constant; `stripped` records
    that a `_private.<module>.0.` prefix was removed, so an unmatched name can still be
    told apart from a genuine inconsistency after the prefix is gone."""
    listed = {}
    with open(path) as fh:
        for line in fh:
            if not line.startswith("  "):
                continue
            parts = line.strip().split(" ")
            name = user_name(parts[0])
            flags = " ".join(parts[1:])
            listed[name] = ("[direct]" in flags, "[not emitted]" not in flags, name != parts[0])
    return listed


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("artifact")
    ap.add_argument("report")
    ap.add_argument("--allow-missing", action="store_true",
                    help="atoms without verification-status are not failures (--skip-verify)")
    ap.add_argument("--no-upgrade", action="store_true",
                    help="artifact from --skip-enrich: clean atoms read verified")
    args = ap.parse_args()

    with open(args.artifact) as fh:
        data = json.load(fh)["data"]
    listed = parse_report(args.report)

    atoms = {}
    for key, atom in data.items():
        name = key[len(PREFIX):] if key.startswith(PREFIX) else key
        atoms[name] = atom.get("verification-status")

    bad = []
    counts = {"unverified": 0, "verified": 0, "clean": 0, "trusted": 0, "missing": 0}
    for name, status in sorted(atoms.items()):
        if status is None:
            counts["missing"] += 1
            if not args.allow_missing:
                bad.append(f"{name}: no verification-status")
            continue
        entry = listed.get(name)
        if status == "trusted":
            counts["trusted"] += 1
            if entry is not None:
                bad.append(f"{name}: trusted but listed by check-axioms")
        elif status == "unverified":
            counts["unverified"] += 1
            if entry is None or not entry[0]:
                bad.append(f"{name}: unverified but not listed [direct]")
        elif status == "verified":
            counts["verified"] += 1
            if args.no_upgrade:
                if entry is not None and entry[0]:
                    bad.append(f"{name}: verified but listed [direct]")
            elif entry is None:
                bad.append(f"{name}: verified but not listed (should be transitively-verified)")
            elif entry[0]:
                bad.append(f"{name}: verified but listed [direct] (should be unverified)")
        elif status == "transitively-verified":
            counts["clean"] += 1
            if entry is not None:
                bad.append(f"{name}: transitively-verified but listed")
            if args.no_upgrade:
                bad.append(f"{name}: transitively-verified under --no-upgrade")
        else:
            bad.append(f"{name}: unexpected status {status!r}")

    unresolved = []
    for name, (direct, emitted, stripped) in sorted(listed.items()):
        if emitted and name not in atoms:
            (unresolved if stripped else bad).append(
                f"{name}: listed as emitted but not an atom of the artifact")
        if not emitted and name in atoms:
            bad.append(f"{name}: listed [not emitted] but is an atom")

    print(f"atoms {len(atoms)} | unverified {counts['unverified']} | verified {counts['verified']} "
          f"| transitively-verified {counts['clean']} | trusted {counts['trusted']} "
          f"| no status {counts['missing']} | listed {len(listed)}")
    for u in unresolved:
        print(f"unresolvable: {u}")
    if bad:
        print(f"{len(bad)} inconsistenc{'y' if len(bad) == 1 else 'ies'} between the artifact and check-axioms:")
        for b in bad:
            print(f"  {b}")
        return 1
    print("extract and check-axioms agree on every emitted atom")
    return 0


if __name__ == "__main__":
    sys.exit(main())
