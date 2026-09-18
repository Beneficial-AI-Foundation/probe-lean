# Schema 3.0 migration notes (archived)

Historical material moved out of [docs/SCHEMA.md](../SCHEMA.md) on 2026-09-18. Nothing here is
needed to read a current `extract` artifact.

## Package version survey (2026-03)

Lean's Lake build system has an optional `version` field in `lakefile.toml`/`lakefile.lean`.
Unlike Rust's Cargo (where every crate must have a semver version), most Lean projects do not
declare a version. Projects surveyed when the `package-version` strategy was chosen:

| Project | Has `version`? | Value |
|---------|---------------|-------|
| probe-lean | yes | `0.4.5` |
| curve25519-dalek-lean-verify | yes | `0.1.0` |
| ArkLib | no | -- |
| katydid-proofs | no | -- |
| VCV-io | no | -- |

## Code-name format: open question

Rust code-names embed the crate name and version in the URI:
`probe:curve25519-dalek/4.1.3/scalar/Scalar#Add<&Scalar>#add()`

Lean code-names use the bare fully qualified name without package or version, because Lean's
namespace hierarchy already encodes the package/library prefix and Lean projects do not reliably
have semver versions to embed.

Should Lean code-names be extended to include the package name and version for cross-project
uniqueness, e.g. `lean:Arklib/a1b2c3d/ArkLib.SumCheck.Protocol.Prover.prove`? For now the
`probe:` prefix with the fully qualified name is sufficient: within a single project Lean names
are unique by construction, across projects the envelope's `source.package` disambiguates, and in
merged files the per-atom `language` field distinguishes Lean atoms from Rust atoms. If
cross-project atom references become needed, the format can be extended in a minor schema version
bump.

## Relationship to Verus kinds

Both probe-lean and probe-verus use `kind` as the field name. The values differ because they
reflect each language's native declaration taxonomy:

| Concept | Verus `kind` | Lean `kind` |
|---------|-------------|-------------|
| Executable code | `exec` | `def`, `abbrev`, `projection`, `instance` |
| Specification | `spec` | `theorem`, `axiom` |
| Proof | `proof` | (implicit in `theorem`: the proof *is* the body) |
| Type definition | -- | `class`, `structure`, `inductive` |

Lean does not have a separate "proof" kind because proofs are the bodies of `theorem`
declarations, not standalone units.

## Changes from Schema 1.x

The only consumer is `verilib-cli`, which we control. No backward compatibility period is needed;
probe-lean and verilib-cli are updated in lockstep.

1. **Top-level structure**: The bare dictionary becomes nested under a `data` key inside the
   envelope.
2. **New per-atom field**: `language: "lean"` is added for merged-file compatibility.
3. **Output path**: Default output moves from `.verilib/atoms.json` to
   `.verilib/probes/lean_<package>_<version>.json`.
4. **CLI simplification**: The five old commands (`atomize`, `specify`, `verify`, `pipeline`,
   `stubify`) are replaced by two: `extract` (combined pipeline) and `viewify` (filtered output).
5. **Schema identifiers**: Changed from per-step schemas (`probe-lean/atoms`, `probe-lean/specs`,
   etc.) to per-command schemas (`probe-lean/extract`, `probe-lean/viewify`).
6. **Renamed types**: `EnrichedAtom` → `UnifiedAtom`, `StubsOutput` → `MoleculesOutput`,
   `ProjectMetadata` → `SourceInfo`.
7. **Bug fix**: `markAtomFlags` is now correctly called in the combined pipeline (was previously
   missing from the old `pipeline` command).
8. **New per-atom fields**: `type-dependencies` and `term-dependencies` split the flat
   `dependencies` array into constants from the type signature vs the body/proof. The
   `dependencies` field is preserved as the deduplicated union for backward compatibility.
9. **Removed `specified` field**: The `specified` boolean was always `true` in Lean (all
   declarations have type signatures). Whether an atom has specifications is now inferred from
   `specs != []`, aligning with probe-verus v5.0.0 which also dropped `specified`.
10. **`SourceInfo` fields now required**: `repo` and `commit` changed from `Option String` to
    `String` (empty string when unavailable), conforming to the `probe` repository's JSON schema
    which declares these fields as required.
