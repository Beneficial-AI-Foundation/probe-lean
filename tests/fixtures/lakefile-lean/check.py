#!/usr/bin/env python3
"""End-to-end assertions for a `lakefile.lean` project (issue #123).

Run from a fresh copy of this directory (no `.lake`), after

    probe-lean extract . -o out.json 2>extract.stderr
    python3 check.py

The package has `srcDir := "src"`, the library `Lib` has its own `srcDir`, the
library `«a.b»` needs `«»` quotes, and the default executable `«my-exe»` has root
`Main`. probe-lean must build all three default targets, emit the atoms of both
libraries and of `Main`, and not link the executable.
"""

import json
import os
import sys

failures = []


def check(name, ok):
    print(f"  {'✓' if ok else '✗'} {name}")
    if not ok:
        failures.append(name)


def main():
    with open("out.json") as fh:
        data = json.load(fh)["data"]
    print("lakefile.lean project")
    check("inner_thm (lib with its own srcDir) is emitted", "probe:inner_thm" in data)
    check("dotted_thm (lib «a.b») is emitted", "probe:dotted_thm" in data)
    check("main_thm (executable root) is emitted", "probe:main_thm" in data)
    check("inner_thm is transitively-verified",
          data.get("probe:inner_thm", {}).get("verification-status") == "transitively-verified")
    check("the executable was not linked", not os.path.exists(".lake/build/bin"))
    print()
    if failures:
        print(f"lakefile-lean end-to-end check: {len(failures)} assertion(s) failed:")
        for f in failures:
            print(f"  {f}")
        return 1
    print("lakefile-lean end-to-end check: all assertions passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
