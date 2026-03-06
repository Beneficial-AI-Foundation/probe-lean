# Schema 2.0: Lean Instantiation

Version: draft
Date: 2026-03-05
Parent document: [probes/docs/envelope-rationale.md](https://github.com/Beneficial-AI-Foundation/probe/blob/main/docs/envelope-rationale.md)

This document defines the Lean-specific details for Schema 2.0 as produced by `probe-lean`.
It instantiates the generic envelope and atom schema from the parent document with Lean
declaration kinds, code-name URIs, versioning, and field mappings.

## Envelope Example

A complete probe-lean atoms output with the Schema 2.0 envelope:

```json
{
  "schema": "probe-lean/atoms",
  "schema-version": "2.0",
  "tool": {
    "name": "probe-lean",
    "version": "1.0.0",
    "command": "atomize"
  },
  "source": {
    "repo": "https://github.com/Verified-zkEVM/ArkLib",
    "commit": "f6e5d4c3b2a19876543210abcdef",
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
      "code-module": "ArkLib.SumCheck.Protocol",
      "code-path": "ArkLib/SumCheck/Protocol.lean",
      "code-text": { "lines-start": 42, "lines-end": 67 },
      "kind": "def",
      "language": "lean"
    }
  }
}
```

## Schema Values

probe-lean registers the following `schema` values:

| schema | Description |
|--------|-------------|
| `probe-lean/atoms` | Lean call graph atoms (dependency graph) |
| `probe-lean/specs` | Lean specification status |
| `probe-lean/proofs` | Lean verification results (sorry detection) |
| `probe-lean/enriched-atoms` | Atoms + specs + proofs combined (produced by `pipeline`) |
| `probe-lean/stubs` | Lean stub entries for Aeneas bridge (produced by `stubify`) |

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

1. Read `version` from `lakefile.toml` or `lakefile.lean` if present.
2. Otherwise, use the 7-character short git commit hash.

This means `source.package-version` is always non-empty, but consumers should treat it
as an opaque identifier and not assume semver.

Examples:

- Versioned: `"package-version": "0.1.0"`
- Unversioned: `"package-version": "a1b2c3d"`

The probe filename convention follows the same pattern:

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
| `is-hidden` | bool | From `.verilib/config.json` `user.is-hidden` list |
| `is-extraction-artifact` | bool | Name ends with suffix from `user.extraction-artifact-suffixes` |
| `is-ignored` | bool | From `.verilib/config.json` `user.is-ignored` list |
| `is-relevant` | bool | Rust source is from the target crate (Aeneas projects only) |
| `rust-source` | string or null | Rust source path from Aeneas docstring |

The `is-*` fields and `rust-source` are specific to the Aeneas (Rust-to-Lean transpiler)
workflow. They are optional extensions per the interchange spec's rules: consumers that
do not recognize them must ignore them.

## Output Types

### `probe-lean/atoms` (atoms output)

Dictionary keyed by code-name. Each value contains all core fields plus Lean-specific
extensions.

### `probe-lean/specs` (specification status)

Dictionary keyed by code-name. Each value:

| Field | Type | Description |
|-------|------|-------------|
| `specified` | bool | Whether the declaration has a type signature (always true for theorems) |
| `code-path` | string | Relative path to source file |
| `spec-text` | object or null | `{ "lines-start": N, "lines-end": N }` |

### `probe-lean/proofs` (verification results)

Dictionary keyed by code-name. Each value:

| Field | Type | Description |
|-------|------|-------------|
| `verified` | bool | No `sorry` in this declaration |
| `status` | string | `"success"`, `"sorries"`, or `"failure"` |
| `code-path` | string | Relative path to source file |
| `code-line` | number | Line number of declaration |
| `sorries` | array | Sorry locations (only if status is `"sorries"`) |

Each entry in `sorries`:

| Field | Type | Description |
|-------|------|-------------|
| `line` | number | Source line of the sorry |
| `message` | string | Compiler message |

### `probe-lean/enriched-atoms` (pipeline output)

Produced by the `pipeline` command (`tool.command: "pipeline"`). Dictionary keyed by
code-name. Each value contains all atom fields plus:

| Field | Type | Description |
|-------|------|-------------|
| `verification-status` | string or absent | `"verified"`, `"unverified"`, `"failed"`, or absent if skipped |
| `specified` | bool or absent | From specs output |

## Changes from Schema 1.x

The only consumer is `verilib-cli`, which we control. No backward compatibility period is
needed -- probe-lean and verilib-cli are updated in lockstep.

Key changes:

1. **Top-level structure**: The bare dictionary becomes nested under a `data` key inside
   the envelope.
2. **New per-atom field**: `language: "lean"` is added for merged-file compatibility.
3. **Output path**: Default output moves from `.verilib/atoms.json` to
   `.verilib/probes/lean_<package>_<version>.json`.
