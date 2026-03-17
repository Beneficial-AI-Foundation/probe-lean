# Schema 2.0: Lean Instantiation

Version: 2.0
Date: 2026-03-07
Parent document: [probes/docs/envelope-rationale.md](https://github.com/Beneficial-AI-Foundation/probe/blob/main/docs/envelope-rationale.md)

This document defines the Lean-specific details for Schema 2.0 as produced by `probe-lean`.
It instantiates the generic envelope and atom schema from the parent document with Lean
declaration kinds, code-name URIs, versioning, and field mappings.

## Envelope Example

A complete probe-lean extract output with the Schema 2.0 envelope:

```json
{
  "schema": "probe-lean/extract",
  "schema-version": "2.0",
  "tool": {
    "name": "probe-lean",
    "version": "0.1.0",
    "command": "extract"
  },
  "source": {
    "repo": "https://github.com/Verified-zkEVM/ArkLib",
    "commit": "f6e5d4c",
    "language": "lean",
    "package": "Arklib",
    "package-version": "f6e5d4c"
  },
  "timestamp": "2026-03-05T14:30:00Z",
  "data": {
    "probe:ArkLib.SumCheck.Protocol.Prover.prove": {
      "display-name": "prove",
      "dependencies": [
        "probe:ArkLib.SumCheck.Protocol.Prover.computeRoundPoly",
        "probe:ArkLib.SumCheck.Protocol.Verifier.verify"
      ],
      "type-dependencies": [
        "probe:ArkLib.SumCheck.Protocol.Verifier.verify"
      ],
      "term-dependencies": [
        "probe:ArkLib.SumCheck.Protocol.Prover.computeRoundPoly",
        "probe:ArkLib.SumCheck.Protocol.Verifier.verify"
      ],
      "code-module": "ArkLib.SumCheck.Protocol",
      "code-path": "ArkLib/SumCheck/Protocol.lean",
      "code-text": { "lines-start": 42, "lines-end": 67 },
      "kind": "def",
      "language": "lean",
      "is-hidden": false,
      "is-extraction-artifact": false,
      "is-ignored": false,
      "is-relevant": true,
      "rust-source": null,
      "specs": ["probe:ArkLib.SumCheck.Protocol.Prover.prove_spec"],
      "primary-spec": "probe:ArkLib.SumCheck.Protocol.Prover.prove_spec",
      "verification-status": "verified"
    },
    "probe:ArkLib.SumCheck.Protocol.Prover.prove_spec": {
      "display-name": "prove_spec",
      "dependencies": [
        "probe:ArkLib.SumCheck.Protocol.Prover.prove"
      ],
      "type-dependencies": [
        "probe:ArkLib.SumCheck.Protocol.Prover.prove"
      ],
      "term-dependencies": [],
      "code-module": "ArkLib.SumCheck.Protocol",
      "code-path": "ArkLib/SumCheck/Protocol.lean",
      "code-text": { "lines-start": 70, "lines-end": 85 },
      "kind": "theorem",
      "language": "lean",
      "is-hidden": false,
      "is-extraction-artifact": false,
      "is-ignored": false,
      "is-relevant": true,
      "rust-source": null,
      "verification-status": "verified"
    }
  }
}
```

## Schema Values

probe-lean registers the following `schema` values:

| schema | Command | Description |
|--------|---------|-------------|
| `probe-lean/extract` | `extract` | Unified atoms with verification status and specs |
| `probe-lean/viewify` | `viewify` | Filtered molecules for the web UI |

## CLI Commands

probe-lean exposes two commands:

- **`extract`**: The primary command. Combines atom extraction, specs computation,
  and sorry detection into a single pass. Outputs unified atoms to `.verilib/probes/`.
- **`viewify`**: Reads extract output, filters atoms (not hidden, not extraction artifact,
  is relevant, code-path ends with `Funs.lean`), and outputs molecules to `.verilib/views/`.

## Package Versioning for Lean

Lean's Lake build system has an optional `version` field in `lakefile.toml`/`lakefile.lean`.
Unlike Rust's Cargo (where every crate must have a semver version), most Lean projects do
not declare a version.

Surveyed projects:

| Project | Has `version`? | Value |
|---------|---------------|-------|
| probe-lean | yes | `0.1.0` |
| curve25519-dalek-lean-verify | yes | `0.1.0` |
| ArkLib | no | -- |
| katydid-proofs | no | -- |
| VCV-io | no | -- |

**Strategy:**

1. Read `version` from `lakefile.toml` if present.
2. Otherwise, use the short git commit hash.
3. Fall back to `"0.0.0"` if neither is available.

This means `source.package-version` is always non-empty, but consumers should treat it
as an opaque identifier and not assume semver.

Examples:

- Versioned: `"package-version": "0.1.0"`
- Unversioned: `"package-version": "a1b2c3d"`

The probe filename convention uses underscores for filesystem safety:

- `lean_Curve25519Dalek_0.1.0.json`
- `lean_Arklib_a1b2c3d.json`

## Code-Name URI Format

Lean atoms use the `probe:` prefix followed by the fully qualified Lean name:

```
probe:<FullyQualifiedName>
```

Examples:

- `probe:ArkLib.SumCheck.Protocol.Prover.prove`
- `probe:Mathlib.Data.Nat.Basic.succ_pos`
- `probe:RegexDeriv.Language.Semantics.derive_correct`

### Differences from Rust code-names

Rust code-names embed the crate name and version in the URI:
`probe:curve25519-dalek/4.1.3/scalar/Scalar#Add<&Scalar>#add()`

Lean code-names currently use the bare fully qualified name without package or version.
This is because:

- Lean's namespace hierarchy already encodes the package/library prefix
  (e.g., `Mathlib.Data.Nat` is unambiguously from Mathlib).
- Lean projects do not reliably have semver versions to embed.

**Open question:** Should Lean code-names be extended to include the package name and
version for cross-project uniqueness? e.g.,
`lean:Arklib/a1b2c3d/ArkLib.SumCheck.Protocol.Prover.prove`

For now, the `probe:` prefix with the fully qualified name is sufficient because:

- Within a single project, Lean names are unique by construction.
- Across projects, the envelope's `source.package` disambiguates.
- In merged files, the per-atom `language` field distinguishes Lean atoms from Rust atoms.

If cross-project atom references become needed (e.g., one project depending on Mathlib
atoms), the code-name format can be extended in a minor schema version bump.

## Declaration Kinds (`kind` field)

The `kind` field classifies the Lean declaration. This corresponds to the `mode` field in
the generic interchange spec, using Lean-native terminology.

| Value | Lean construct | Notes |
|-------|---------------|-------|
| `def` | `def` | Computable definition |
| `theorem` | `theorem` | Proven proposition (erased at runtime) |
| `abbrev` | `abbrev` | Abbreviation (reducible definition) |
| `class` | `class` | Type class |
| `structure` | `structure` | Record type |
| `inductive` | `inductive` | Inductive type |
| `instance` | `instance` | Type class instance |
| `axiom` | `axiom` | Axiom (trusted, no proof) |
| `opaque` | `opaque` | Opaque definition (no unfolding) |
| `quot` | `Quot` | Quotient type (built-in) |

### Relationship to Verus kinds

Both probe-lean and probe-verus use `kind` as the field name. The values differ because
they reflect each language's native declaration taxonomy:

| Concept | Verus `kind` | Lean `kind` |
|---------|-------------|-------------|
| Executable code | `exec` | `def`, `abbrev`, `instance` |
| Specification | `spec` | `theorem`, `axiom` |
| Proof | `proof` | (implicit in `theorem` -- the proof *is* the body) |
| Type definition | -- | `class`, `structure`, `inductive` |

Lean does not have a separate "proof" kind because proofs are the bodies of `theorem`
declarations, not standalone units. This is a fundamental difference from Verus where
`proof` and `spec` are syntactically distinct modes.

## Lean-Specific Atom Fields

In addition to the core fields defined by the interchange spec, probe-lean atoms include:

| Field | Type | Description |
|-------|------|-------------|
| `kind` | string | Declaration kind (see table above). Same field name used by probe-verus. |
| `is-hidden` | bool | From `.verilib/probes/config.json` `is-hidden` list |
| `is-extraction-artifact` | bool | Name ends with suffix from `extraction-artifact-suffixes` |
| `is-ignored` | bool | From `.verilib/probes/config.json` `is-ignored` list |
| `is-relevant` | bool | Rust source is from the target crate (Aeneas projects only) |
| `rust-source` | string or null | Rust source path from Aeneas docstring |

The `is-*` fields and `rust-source` are specific to the Aeneas (Rust-to-Lean transpiler)
workflow. They are optional extensions per the interchange spec's rules: consumers that
do not recognize them must ignore them.

## Output Types

### `probe-lean/extract` (unified atoms)

Produced by the `extract` command (`tool.command: "extract"`). Dictionary keyed by code-name.
Each value contains all atom fields plus verification status and specs:

| Field | Type | Description |
|-------|------|-------------|
| `display-name` | string | Last component of the name |
| `kind` | string | Declaration kind |
| `language` | string | Always `"lean"` |
| `dependencies` | array | `probe:`-prefixed names this declaration depends on (union of type + term) |
| `type-dependencies` | array | `probe:`-prefixed names referenced in the declaration's type signature |
| `term-dependencies` | array | `probe:`-prefixed names referenced in the declaration's body/proof |
| `code-module` | string | Module name containing the declaration |
| `code-path` | string | Relative path to source file |
| `code-text` | object or null | `{ "lines-start": N, "lines-end": N }` |
| `is-hidden` | bool | From config's hidden list |
| `is-extraction-artifact` | bool | From config's artifact suffixes |
| `is-ignored` | bool | From config's ignored list |
| `is-relevant` | bool | Rust source is from the target crate |
| `rust-source` | string or null | Rust source path from Aeneas docstring |
| `specs` | array or absent | Code-names of theorem atoms whose dependencies include this atom. Absent when empty. Whether an atom is "specified" can be inferred from `specs` being non-empty. |
| `primary-spec` | string or absent | Code-name of the primary specification theorem for this atom. Absent when none. Set by `@[primary_spec]` attribute, or inferred when `<name>_spec` exists in `specs`. |
| `verification-status` | string or absent | `"verified"`, `"unverified"`, `"failed"`, or absent if skipped |

### `probe-lean/viewify` (molecules)

Produced by the `viewify` command (`tool.command: "viewify"`). Dictionary keyed by
`<code-path>/<name_last>` (or full name on collision). Each value:

| Field | Type | Description |
|-------|------|-------------|
| `code-path` | string or null | Source file path |
| `code-lines` | string or null | Line range as string |
| `code-name` | string | Atom name with `probe:` prefix |
| `rust-path` | string | Rust source path (empty for pure Lean) |
| `rust-lines` | object | `{ "lines-start": N, "lines-end": N }` |
| `rust-name` | string | Rust function name (empty for pure Lean) |
| `spec-path` | string or null | Specification file path |
| `spec-lines` | string or null | Specification line range |
| `spec-name` | string or null | Specification atom name |

## Changes from Schema 1.x

The only consumer is `verilib-cli`, which we control. No backward compatibility period is
needed -- probe-lean and verilib-cli are updated in lockstep.

Key changes:

1. **Top-level structure**: The bare dictionary becomes nested under a `data` key inside
   the envelope.
2. **New per-atom field**: `language: "lean"` is added for merged-file compatibility.
3. **Output path**: Default output moves from `.verilib/atoms.json` to
   `.verilib/probes/lean_<package>_<version>.json`.
4. **CLI simplification**: The five old commands (`atomize`, `specify`, `verify`, `pipeline`,
   `stubify`) are replaced by two: `extract` (combined pipeline) and `viewify` (filtered output).
5. **Schema identifiers**: Changed from per-step schemas (`probe-lean/atoms`, `probe-lean/specs`,
   etc.) to per-command schemas (`probe-lean/extract`, `probe-lean/viewify`).
6. **Renamed types**: `EnrichedAtom` → `UnifiedAtom`, `StubsOutput` → `MoleculesOutput`.
7. **Bug fix**: `markAtomFlags` is now correctly called in the combined pipeline (was
   previously missing from the old `pipeline` command).
8. **New per-atom fields**: `type-dependencies` and `term-dependencies` split the flat
   `dependencies` array into constants from the type signature vs the body/proof.
   The `dependencies` field is preserved as the deduplicated union for backward compatibility.
9. **Removed `specified` field**: The `specified` boolean was always `true` in Lean (all
   declarations have type signatures). Whether an atom has specifications is now inferred
   from `specs != []`, aligning with probe-verus v5.0.0 which also dropped `specified`.
