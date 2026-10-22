# Audit scripts

Measurement and gate scripts for probe-lean's output. The Lean scripts were written for [issue #99](https://github.com/Beneficial-AI-Foundation/probe-lean/issues/99) (dependency edges hidden under auxiliary constants). The Python scripts compare and check `extract` artifacts. All of them run on any target project.

They live in lowercase `tools/`, outside probe-lean's build (`Tools/` is a `lean_lib`). They run under the target project's toolchain, because only the Lean version that wrote a project's `.olean` files can read them. The Lean scripts re-implement probe-lean's predicates instead of importing them, so a bug in probe-lean's code does not hide in its own oracle.

## Running them

From the target project, under the target's toolchain:

```bash
cd <target-project>
env -u LEAN_PATH bash -lc 'source ~/.elan/env; \
  lake env lean --run <probe-lean>/tools/audit/Audit.lean <ModulePrefix>...'
```

`<ModulePrefix>...` is the project-module filter, the same set `extract` analyzes (for example `Curve25519Dalek`). Most Lean scripts take a few minutes, mostly to import the `.olean` closure. `Audit6.lean` takes more than ten minutes on curve25519-dalek-lean-verify because it has no cross-root memo. It is not hung.

## What each script measures

`Audit.lean` to `Audit5.lean` fold every filtered class, structural members included. They measure the size of the problem, not the shipped behaviour. They date from before 0.15.0. Where they talk about `verification-status`, they mean the old graph contamination. Since 0.15.0 the status comes from the kernel walk (see `docs/verification-status.md`).

| Script | Question it answers |
|---|---|
| `Audit.lean` | How many emitted atoms reference an auxiliary, how many project edges hide under one, and how many atoms gain in-edges. |
| `Audit2.lean` | Pre-0.15 historical. Runs `sorry` contamination over the emitted graph and over the aux-folded graph and reports the atoms whose graph-derived status differs. |
| `Audit3.lean` | What fraction of non-theorem declarations carry an embedded proof, per corpus (core, Batteries, Mathlib, Aeneas, the project). Counts a host by whether it references a `_proof_N`. |
| `Audit4.lean` | Histogram by auxiliary shape (`_proof_N`, `match_N`, `.mk`, `.injEq`, ...) of the edges each shape hides. |
| `Audit5.lean` | Whether the hidden auxiliaries sit in a declaration's type or its body. The shipped fold sends type-position finds to `term-dependencies` (see `docs/schema.md`, "Auxiliary-dependency folding"). |
| `Audit6.lean` | Oracle for the shipped fold. Prints, per atom and bucket, the targets the fold must add, as `<atom>\t(type\|term)\t<target>` TSV. It uses a hand-written classification and no cross-root cache. |
| `compare-extract.py` | Diffs a before and after `extract` artifact and asserts the fold invariants in `docs/schema.md`. `--oracle` also checks the added edges against `Audit6.lean`. `--status-policy taint` allows the 0.14 to 0.15 status moves, and `--exec-hosts NAME,...` excuses executable-body hosts. `--report N` sets how many example violations it prints per check (default 10). It reports the names added to or removed from `assumptions` per atom as a note, not a failure. |
| `check-graph.py` | Checks that the emitted `dependencies` graph explains every status: a reverse BFS from the `unverified` and `failed` atoms through `verified` and `transitively-verified` ones, compared with the kernel walk (`verified` with `status-origin: "kernel-taint"` is tainted). Prints a `Divergence(graph)` line per disagreeing atom, a `Warning:` line per dependency that is not an atom, and a `Note:` count of type members. `extract` printed the same lines on stderr up to 0.20.0. `--fail-on-divergence` exits 1 on a divergence. Without it, the script exits 0 also on a divergence. With it, exit 0 means that the graph and the walk agree on every atom with a status, not that every edge was emitted. `--report N` limits the warnings. Reads enveloped artifacts from 0.16.0 on, and rejects input without a probe-lean version and `--skip-verify` artifacts. If `extract` printed the duplicate-name warning, the report lacks the colliding atoms. Run it on every re-extract of a downstream target. `test_check_graph.py` tests it in CI. |
| `check-status-consistency.py` | Checks that an artifact and a `check-axioms` report agree on every emitted atom in both directions: `unverified`, `verified`, clean, and `status-origin: "kernel-taint"`. It fails on an empty report or a cut list of tainted constants. It does not read the assumption section: `tests/fixtures/assumptions/check.py` compares that section for the fixture. It also checks `assumptions`: every atom with a status has an array of strings, sorted by string and without duplicates, an atom without a status has no field, and an atom that reads `unverified`, or `verified` with `status-origin: "kernel-taint"`, has `sorryAx` in it. CI runs it on the fixtures. Use `--no-upgrade` for `--skip-enrich` artifacts. Use `--allow-missing` for `--skip-verify` artifacts: atoms without a status are then accepted, and an atom with `assumptions` is a failure. |

## The verification recipe

```bash
# 1. before/after artifacts, same project, same module filter
<baseline-probe-lean> extract <target>   # keep the artifact
<new-probe-lean>      extract <target>   # keep the artifact

# 2. the oracle, on the same project state
cd <target>
env -u LEAN_PATH bash -lc 'source ~/.elan/env; \
  lake env lean --run <probe-lean>/tools/audit/Audit6.lean <ModulePrefix>...' \
  > /tmp/oracle.tsv

# 3. the gate
<probe-lean>/tools/audit/compare-extract.py before.json after.json \
  --oracle /tmp/oracle.tsv
```

The invariants and the oracle agreement are the result, not the edge counts. This recipe is manual, not a CI gate, because it needs a built target project. CI covers the fold with the unit suite and the `tests/fixtures/aux-fold` end-to-end step.

Limits:

- `compare-extract.py` compares normalized values. To it, absent, `null` and `[]` are the same.
- Oracle agreement shows that two implementations agree on one reading of the contract. It does not show that the contract is right.
- Versions before 0.24.0 print private names without their `_private.<module>.0.` prefix. Compare two artifacts of the same name format. `--oracle` needs artifacts from 0.24.0 on, because `Audit6.lean` prints the prefix.
- Two different raw names can print as one string (`«#foo.bar»` and `«#foo».bar`). `compare-extract.py` reports a repeated name as a diagnostic and does not fail on it.

The baseline numbers measured on curve25519-dalek-lean-verify for issue #99 are in the description of [PR #100](https://github.com/Beneficial-AI-Foundation/probe-lean/pull/100).
