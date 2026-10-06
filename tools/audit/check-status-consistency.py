#!/usr/bin/env python3
"""Bidirectional gate between an `extract` artifact and a `check-axioms` report.

Both come from the same kernel walk, so they must agree *exactly* on every emitted
atom. One-directional checks ("every `unverified` atom is a direct carrier") pass
vacuously when nothing is `unverified`; this asserts the equivalence in both
directions:

    emitted, listed `[direct]`          <=>  verification-status == "unverified"
    emitted, listed, not `[direct]`     <=>  verification-status == "verified"
    emitted, not listed                 <=>  "transitively-verified" or "trusted"
    emitted, listed, not `[direct]`     <=>  status-origin == "kernel-taint"
    listed without `[not emitted]`      <=>  is an atom of the artifact

An atom without a `verification-status` fails unless `--allow-missing` is given
(`--skip-verify` runs). `--skip-enrich` artifacts read `verified` where the report
predicts `transitively-verified`; pass `--no-upgrade` for those. The
`status-origin` equivalence holds in both modes: the marker distinguishes a tainted
`verified` from a capped clean one.

Usage:

    tools/audit/check-status-consistency.py ARTIFACT.json check-axioms.out
                                            [--allow-missing] [--no-upgrade]

Names: the artifact prints private declarations through `privateToUserName`; the
report prints raw `Name`s, so `_private.<module>.0.` prefixes are stripped before
matching (`user_name`, the same normalisation). A listed name marked emitted that is
still not an atom after that is a failure like any other: the stripping is exact, so
there is no residual class of "unresolvable" names, and treating one as such let
the gate pass while an emitted private atom was missing from the artifact. The
message says when a prefix was stripped so the raw name can be found in the report.

The report must contain the tainted header, followed by exactly as many lines as
its count says; otherwise the gate fails.

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


TAINTED_HEADER = re.compile(r"^(?P<count>\d+) constant\(s\) rest on an unexcused project sorry:$")

# A listed line is the raw name followed by the optional flags, in the order
# `formatTaintedLine` prints them. The flags are matched from the end rather than
# the line split on spaces: an escaped Lean identifier (`«bad name»`) may contain
# spaces, and splitting truncated it to `«bad` — a false inconsistency.
TAINTED_LINE = re.compile(r"^(?P<raw>.*?)(?P<direct> \[direct\])?(?P<not_emitted> \[not emitted\])?$")


def parse_report(path):
    """({name: (direct, emitted, raw)}, problems). The map has every listed tainted
    constant, keyed by the user-facing name; `raw` is the name as the report printed
    it, which differs from the key only for a private declaration.

    Only the indented lines under the tainted header are read: the report goes on to
    list the trusted base (`N trusted constant(s) (T):`) with the same indentation.
    `problems` is non-empty if the header is missing or the number of lines under it
    differs from its count: an empty or cut report must not pass as "nothing tainted"."""
    listed = {}
    in_tainted = False
    expected = None
    seen = 0
    with open(path) as fh:
        for line in fh:
            header = TAINTED_HEADER.match(line.rstrip("\n"))
            if header:
                in_tainted = True
                expected = int(header.group("count"))
                continue
            if not line.startswith("  "):
                in_tainted = False
                continue
            if not in_tainted:
                continue
            seen += 1
            m = TAINTED_LINE.match(line.strip())
            raw = m.group("raw")
            listed[user_name(raw)] = (m.group("direct") is not None,
                                      m.group("not_emitted") is None, raw)
    problems = []
    if expected is None:
        problems.append("report: no tainted header (`N constant(s) rest on an unexcused project sorry:`)")
    elif seen != expected:
        problems.append(f"report: tainted header says {expected} constant(s), {seen} line(s) listed")
    return listed, problems


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
    listed, report_problems = parse_report(args.report)

    atoms = {}
    origins = {}
    for key, atom in data.items():
        name = key[len(PREFIX):] if key.startswith(PREFIX) else key
        atoms[name] = atom.get("verification-status")
        origins[name] = atom.get("status-origin")

    bad = list(report_problems)
    counts = {"unverified": 0, "verified": 0, "clean": 0, "trusted": 0, "missing": 0}
    for name, status in sorted(atoms.items()):
        if status is None:
            counts["missing"] += 1
            if not args.allow_missing:
                bad.append(f"{name}: no verification-status")
            if origins[name] is not None:
                bad.append(f"{name}: status-origin {origins[name]!r} without a verification-status")
            continue
        entry = listed.get(name)
        tainted = entry is not None and not entry[0]
        origin = origins[name]
        if tainted and origin != "kernel-taint":
            bad.append(f"{name}: listed, not [direct], but status-origin is {origin!r}")
        elif not tainted and origin is not None:
            bad.append(f"{name}: status-origin {origin!r} but not a tainted non-direct constant")
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

    for name, (direct, emitted, raw) in sorted(listed.items()):
        private = f" (private, listed as {raw})" if raw != name else ""
        if emitted and name not in atoms:
            bad.append(f"{name}: listed as emitted but not an atom of the artifact{private}")
        if not emitted and name in atoms:
            bad.append(f"{name}: listed [not emitted] but is an atom{private}")

    print(f"atoms {len(atoms)} | unverified {counts['unverified']} | verified {counts['verified']} "
          f"| transitively-verified {counts['clean']} | trusted {counts['trusted']} "
          f"| no status {counts['missing']} | listed {len(listed)}")
    if bad:
        print(f"{len(bad)} inconsistenc{'y' if len(bad) == 1 else 'ies'} between the artifact and check-axioms:")
        for b in bad:
            print(f"  {b}")
        return 1
    print("extract and check-axioms agree on every emitted atom")
    return 0


if __name__ == "__main__":
    sys.exit(main())
