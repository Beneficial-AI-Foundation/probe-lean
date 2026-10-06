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
| `compare-extract.py` | Diffs a before and after `extract` artifact and asserts the fold invariants in `docs/schema.md`. `--oracle` also checks the added edges against `Audit6.lean`. `--status-policy taint` allows the 0.14 to 0.15 status moves, and `--exec-hosts NAME,...` excuses executable-body hosts. `--report N` sets how many example violations it prints per check (default 10). |
| `check-status-consistency.py` | Checks that an artifact and a `check-axioms` report agree on every emitted atom in both directions: `unverified`, `verified`, clean, and `status-origin: "kernel-taint"`. It fails on an empty or cut report. CI runs it on the fixtures. Use `--allow-missing` for `--skip-verify` artifacts and `--no-upgrade` for `--skip-enrich` artifacts. |

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
- Private-name collisions are outside what the recipe can check. Artifacts print names through `privateToUserName`, so two declarations can print as one string. `Audit6.lean` works on raw `Name`s, so `--oracle` can report a false "predicted but not added". `compare-extract.py` therefore reports a repeated name as a diagnostic and does not fail on it.

The baseline numbers measured on curve25519-dalek-lean-verify for issue #99 are in the description of [PR #100](https://github.com/Beneficial-AI-Foundation/probe-lean/pull/100).
