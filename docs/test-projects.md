# Lean 4 Test Projects for probe-lean

Curated list of open-source Lean 4 projects suitable for testing probe-lean commands
(`atomize`, `specify`, `extract`, `pipeline`, `stubify`).

probe-lean toolchain: **v4.29.0-rc3**. Must be recompiled per target toolchain (see notes below).

## What makes a good test project

- Lean 4 Lake project (with `lakefile.lean` or `lakefile.toml`)
- Builds with `lake build`
- 3+ modules with a mix of `def`, `theorem`, `structure`, `inductive`, `class`, `instance`
- Some `sorry` usage is ideal for testing `extract`
- Smaller projects preferred for fast iteration (dalek-lean takes ~2h for `atomize`)
- Lean version close to v4.29.0-rc3 avoids compat fixes when rebuilding probe-lean

## Compatible projects (Lean v4.28--v4.29)

These projects use a Lean version within 1 minor version of probe-lean's toolchain.
Rebuilding probe-lean for these should require zero or minimal source changes.

| Project | Lean | Stars | Notes |
|---------|------|-------|-------|
| [knowsys/CertifyingDatalog](https://github.com/knowsys/CertifyingDatalog) | v4.28.0 | 7 | Certified Datalog checker. Clean structure, formal verification. No mathlib dep. |
| [Verified-zkEVM/ArkLib](https://github.com/Verified-zkEVM/ArkLib) | v4.28.0 | 167 | Formally verified SNARKs (sum-check, FRI, Merkle trees, WHIR). 1185 commits, 24 contributors. Depends on mathlib + VCV-io. |
| [Verified-zkEVM/VCV-io](https://github.com/Verified-zkEVM/VCV-io) | v4.28.0 | 67 | Formalized cryptography proofs: oracle computations, probability, Fiat-Shamir. Depends on mathlib. |
| [AeneasVerif/aeneas](https://github.com/AeneasVerif/aeneas) `tests/lean/` | v4.28.0-rc1 | 586 | Aeneas Lean test suite. 60+ targets: Hashmap, AVL, Loops, Closures, Curve25519, etc. Must clone whole repo, build from `tests/lean/`. |
| [ImperialCollegeLondon/FLT](https://github.com/ImperialCollegeLondon/FLT) | v4.28.0 | 797 | Fermat's Last Theorem formalization. Depends on mathlib. Large. |
| [argumentcomputer/ix](https://github.com/argumentcomputer/ix) | v4.28.0 | 64 | Zero-knowledge proof-carrying code platform for Lean 4. |
| [leanprover-community/mathlib4](https://github.com/leanprover-community/mathlib4) | v4.29.0-rc3 | 1.9k | Exact toolchain match. The canonical math library. 20k+ commits. Huge -- stress test only. |

## Near-compatible projects (Lean v4.26--v4.27)

Small compat fixes may be needed (e.g. `trimAscii`, `dropPrefix`).

| Project | Lean | Stars | Notes |
|---------|------|-------|-------|
| [GasStationManager/SafeVerify](https://github.com/GasStationManager/SafeVerify) | v4.27.0 | 29 | Proof verification tool. Small and focused. |
| [digama0/lean4lean](https://github.com/digama0/lean4lean) | v4.26.0 | 160 | Lean 4 kernel in Lean 4. Rich metatheory, deep dependency graph. |

## Older projects (Lean v4.22--v4.24)

Require the compat fixes we identified: `trimAscii` -> `trim`, `dropPrefix`/`dropSuffix` -> manual, `.toString` removal on String returns.

| Project | Lean | Stars | Notes |
|---------|------|-------|-------|
| [ravst/SymbolicCryptographyLean](https://github.com/ravst/SymbolicCryptographyLean) | v4.20.0-rc5 | 10 | Verified symbolic cryptography + garbled circuits. Soundness theorem. Uses VCVio fragment. CSF 2026 paper. |
| [katydid/proofs](https://github.com/katydid/proofs) | v4.22.0 | 18 | Validation algorithm proofs. Depends on mathlib. Tested successfully. |
| [Th0rgal/verity](https://github.com/Th0rgal/verity) | v4.22.0 | 32 | Smart contract verification. 431 verified theorems. |
| [verse-lab/veil](https://github.com/verse-lab/veil) | v4.24.0 | 185 | Distributed protocol verification. Classes, instances, automation. |

## Too old (Lean < v4.20)

Likely to require significant compat work. Low priority.

| Project | Lean | Stars | Notes |
|---------|------|-------|-------|
| [lenianiva/Pantograph](https://github.com/lenianiva/Pantograph) | v4.18.0 | 21 | Machine-to-machine Lean 4 interaction. |
| [optsuite/optlib](https://github.com/optsuite/optlib) | v4.13.0 | 85 | Optimization library. Math-heavy. |
| [starkware-libs/formal-proofs](https://github.com/starkware-libs/formal-proofs) | v4.13.0-rc3 | 67 | StarkWare formal proofs. |
| [AeneasVerif/icfp-tutorial](https://github.com/AeneasVerif/icfp-tutorial) | v4.11.0-rc2 | 11 | Aeneas tutorial. |
| [fraware/lean-containers](https://github.com/fraware/lean-containers) | v4.8.0 | -- | Container library. |
| [A-Stone-Olguin/cryptolib4](https://github.com/A-Stone-Olguin/cryptolib4) | nightly-2023-06-20 | 1 | Crypto library. Ancient nightly. |

## Aeneas projects (Rust -> Lean verification)

Aeneas translates Rust programs into Lean for formal verification. These are especially
relevant for `stubify` testing (Lean<->Rust mappings).

| Project | Lean | Stars | Notes |
|---------|------|-------|-------|
| [AeneasVerif/aeneas](https://github.com/AeneasVerif/aeneas) `tests/lean/` | v4.28.0-rc1 | 586 | Main test suite: Hashmap, AVL trees, Loops, Iterators, Closures, Curve25519, Traits, etc. 60+ Lean targets generated from Rust. |
| [AeneasVerif/aeneas](https://github.com/AeneasVerif/aeneas) `backends/lean/` | v4.28.0-rc1 | 586 | Base library (`Aeneas.Std`). Primitives, scalars, array/slice models. |
| [AeneasVerif/icfp-tutorial](https://github.com/AeneasVerif/icfp-tutorial) | v4.11.0-rc2 | 11 | Tutorial examples. Old toolchain. |
| [Beneficial-AI-Foundation/curve25519-dalek-lean-verify](https://github.com/Beneficial-AI-Foundation/curve25519-dalek-lean-verify) | -- | -- | Already referenced in probe-lean specs for `stubify`. Takes ~2h for `atomize`. |

## Special resources

| Resource | Notes |
|----------|-------|
| [sorrydb/sorrydb](https://github.com/sorrydb/sorrydb) | Indexes `sorry` statements across public Lean repos. Source of projects with incomplete proofs (ideal for `verify` testing). |
| [Reservoir](https://reservoir.lean-lang.org/packages) | Lean package registry. Filter by version to find compatible projects. |

## Suggested test progression

1. **CertifyingDatalog** (v4.28.0) -- closest compatible version, no mathlib, small
2. **VCV-io** (v4.28.0) -- crypto proofs, oracle computations, moderate size
3. **ArkLib** (v4.28.0) -- large crypto project, SNARKs, deep dependency graph
4. **Aeneas tests/lean** (v4.28.0-rc1) -- rich Rust->Lean content, good for stubify exploration
5. **SafeVerify** or **lean4lean** (v4.26-v4.27) -- minor compat fixes
6. **mathlib4** (v4.29.0-rc3) -- exact match, stress test at scale
7. **curve25519-dalek-lean-verify** -- stubify-specific testing (slow build)

## Test results

| Project | Lean | atomize | specify | extract | pipeline | stubify | Notes |
|---------|------|---------|---------|--------|----------|---------|-------|
| katydid/proofs | v4.22.0 | 589 atoms, 28 modules, 8s | 589 specs | 573/589 verified, 16 sorry | N/A | N/A | Depends on mathlib4. Build ~3.5min. Required probe-lean compat fixes for 4.22.0 (trimAscii, dropPrefix, toString). Default atoms.json path mismatch between atomize (.verilib/) and specify/extract (project root) -- needs `-a` flag. |
| Verified-zkEVM/ArkLib | v4.28.0 | 4024 atoms, 162 modules | 4024 specs | 3654/4024 verified, 370 sorry | 4024 enriched atoms, 3654 verified / 370 unverified | N/A | Depends on mathlib. Build ~4.5min with cache. Pipeline tested locally end-to-end. |
