# Schema 2.0: Lean Instantiation

Version: 2.0
Date: 2026-05-22
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
    "version": "0.4.5",
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
      "is-in-package": true,
      "is-relevant": true,
      "is-hidden": false,
      "is-extraction-artifact": false,
      "is-ignored": false,
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
      "is-in-package": true,
      "is-relevant": true,
      "is-hidden": false,
      "is-extraction-artifact": false,
      "is-ignored": false,
      "attributes": ["primary_spec"],
      "rust-source": null,
      "verification-status": "verified"
    },
    "probe:Aeneas.Std.core.convert.num.FromUsizeBool": {
      "display-name": "FromUsizeBool",
      "dependencies": [],
      "type-dependencies": [],
      "term-dependencies": [],
      "code-module": "Aeneas.Std.FunsExternal",
      "code-path": "Aeneas/Std/FunsExternal.lean",
      "code-text": { "lines-start": 10, "lines-end": 12 },
      "kind": "axiom",
      "language": "lean",
      "is-in-package": true,
      "is-relevant": true,
      "is-hidden": false,
      "is-extraction-artifact": false,
      "is-ignored": false,
      "rust-source": null,
      "verification-status": "trusted",
      "trusted-reason": "axiom"
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
| probe-lean | yes | `0.4.5` |
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
| `projection` | (auto) | Structure field or class method projection (detected via `env.isProjectionFn`) |
| `class` | `class` | Type class |
| `structure` | `structure` | Record type |
| `inductive` | `inductive` | Inductive type |
| `instance` | `instance` | Type class instance |
| `axiom` | `axiom` | Axiom (assumed without proof; always `"trusted"`) |
| `opaque` | `opaque` | Opaque definition (no unfolding) |
| `quot` | `Quot` | Quotient type (built-in) |

### Relationship to Verus kinds

Both probe-lean and probe-verus use `kind` as the field name. The values differ because
they reflect each language's native declaration taxonomy:

| Concept | Verus `kind` | Lean `kind` |
|---------|-------------|-------------|
| Executable code | `exec` | `def`, `abbrev`, `projection`, `instance` |
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
| `is-in-package` | bool | Whether the declaration belongs to the current package (not an imported dependency) |
| `is-relevant` | bool | Whether the declaration is relevant for analysis (see computation rules below) |
| `is-hidden` | bool | From `.verilib/probes/config.json` `is-hidden` list |
| `is-extraction-artifact` | bool | Name ends with suffix from `extraction-artifact-suffixes` |
| `is-ignored` | bool | From `.verilib/probes/config.json` `is-ignored` list |
| `attributes` | array of strings | Lean tag attributes detected on this declaration (absent when empty) |
| `rust-source` | string or null | Rust source path from Aeneas docstring |

### Field Computation Methods

| Field | Method | Details |
|-------|--------|---------|
| `is-in-package` | **AUTO** | Always `true` for atoms emitted by probe-lean, since only declarations from the project's own modules are extracted. Provided as a generic signal for downstream tools. |
| `is-relevant` | **AUTO / CONFIG** | Defaults to `true` for all in-package declarations. When `relevant-crate` is set in `.verilib/probes/config.json`, declarations with `rust-source` are filtered to only those whose source matches the configured crate. |
| `is-hidden` | **CONFIG** | Set from the `is-hidden` name list in `.verilib/probes/config.json`. probe-lean does not auto-detect hidden declarations. |
| `is-extraction-artifact` | **CONFIG** | Set from the `extraction-artifact-suffixes` list in `.verilib/probes/config.json`. probe-lean checks if the declaration name ends with any configured suffix. |
| `is-ignored` | **CONFIG** | Set from the `is-ignored` name list in `.verilib/probes/config.json`. Always a manual editorial decision. |
| `attributes` | **AUTO** | Lean attributes detected on the declaration. Populated from two sources: (1) handle-based detection for attributes registered via `ProbeLean.Attrs` (`primary_spec`, `externally_verified`), and (2) source-level scanning of `@[...]` annotations in `.lean` files. Source scanning acts as a general fallback that works for any attribute, including those registered independently by the target project. probe-lean uses known verification-framework attributes (`progress`, `pspec`, `step`) as a signal for primary-spec detection; all other attributes are raw fact data for consumers. |
| `rust-source` | **AUTO** | Extracted from Aeneas-generated docstrings (`Source: 'path'` pattern). `null` for declarations without Aeneas docstrings. |

**Note:** The `is-hidden`, `is-extraction-artifact`, and `is-ignored` fields are set by
probe-lean from config only as a backward-compatible convenience. In the recommended
pipeline for Aeneas projects, these fields are computed by **probe-aeneas** using
Aeneas-specific heuristics applied to the generic facts (`attributes`, name patterns,
`rust-source`) that probe-lean provides.

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
| `is-in-package` | bool | Declaration belongs to the current package |
| `is-relevant` | bool | Declaration is relevant for analysis |
| `is-hidden` | bool | From config's hidden list |
| `is-extraction-artifact` | bool | From config's artifact suffixes |
| `is-ignored` | bool | From config's ignored list |
| `attributes` | array or absent | Lean tag attributes on this declaration. Absent when empty. |
| `rust-source` | string or null | Rust source path from Aeneas docstring |
| `specs` | array or absent | Code-names of theorem atoms whose dependencies include this atom. Absent when empty. Whether an atom is "specified" can be inferred from `specs` being non-empty. |
| `primary-spec` | string or absent | Code-name of the primary specification theorem for this atom. Absent when none. Determined by precedence: (1) `@[primary_spec]` attribute, (2) known verification-framework attributes (`@[progress]`, `@[pspec]`, `@[step]`), (3) `_spec` suffix match, (4) sole spec inference. |
| `verification-status` | string or absent | `"transitively-verified"`, `"verified"`, `"unverified"`, `"failed"`, `"trusted"`, or absent if skipped. A declaration is `"verified"` if its own body does not contain `sorry`; it is upgraded to `"transitively-verified"` if, additionally, all its transitive dependencies are verified or trusted (computed via reverse-BFS contamination, skippable with `--skip-enrich`). Declarations that are locally sorry-free but have at least one unverified or failed transitive dependency remain `"verified"`. Axioms, declarations carrying `@[externally_verified]`, and non-theorem declarations from `*External.lean` files (Aeneas trust base) are always `"trusted"`. Theorems in `*External.lean` without `@[externally_verified]` carry real proofs and receive their normal status from sorry detection. Declarations without source location (kernel-synthesized) are filtered from output entirely. |
| `trusted-reason` | string or absent | Present only when `verification-status` is `"trusted"`. Values: `"axiom"` (Lean `axiom` keyword), `"externally_verified"` (declaration tagged `@[externally_verified]` — proof discharged outside Lean), `"external"` (non-theorem declaration in a file ending with `External.lean`). Enables automated trust-base classification. |
| `classification` | object or absent | Security-protocol classification (absent unless the project class is `security-protocol` and the atom is classified). See *Security-protocol classification* below. |

### Security-protocol classification

For VCVio-based cryptographic projects, probe-lean classifies each declaration into a
`scheme → construction → {correctness, security}` hierarchy so a consumer can render an
accordion. This is **additive**: two optional fields appear, and only when a project class is
detected — non-class projects are byte-identical to before.

- Envelope **`source.class`** — the detected project class (currently `"security-protocol"`).
  Absent when no class is detected. Resolved by precedence: `extract --class <name>` override >
  Lake manifest (package-level VCVio dependency) > imported-module signal.
- Per-atom **`classification`** — an object, **absent** (not `null`) when the atom is unclassified:

  | field | type | meaning |
  |-------|------|---------|
  | `category` | string | `scheme`, `construction`, `correctness`, `security`, or `ambiguous` |
  | `via` | string | how it was determined — `attribute`, `type`, or `naming` (the *weakest* signal in the chain) |
  | `scheme` | string or array, or absent | code-name(s) of the scheme this atom is about — present when resolvable |
  | `construction` | string or array, or absent | code-name(s) of the construction a property is about — present when resolvable |

  `category: "ambiguous"` marks an atom recognised as a crypto *property* whose
  correctness-vs-security axis could not be decided — an equal-depth reachability tie (e.g. a
  reduction theorem referencing both a correctness assumption and a security advantage),
  conflicting `@[correctness_spec]`/`@[security_spec]` tags, or a name matching both patterns. It still carries its links; resolve it
  with an explicit tag. Link fields are **fail-closed**: a string when uniquely resolved, an array
  when genuinely ambiguous, and absent when unresolvable (links never reference non-emitted atoms,
  e.g. an imported VCVio scheme). Schemes that are not conventionally named (`*Scheme`/`*Alg`) are
  not auto-detected and must carry `@[scheme_def]`.

  Full design, signals, and the anchor catalogue:
  [docs/classification-security-protocol.md](classification-security-protocol.md).

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
6. **Renamed types**: `EnrichedAtom` → `UnifiedAtom`, `StubsOutput` → `MoleculesOutput`,
   `ProjectMetadata` → `SourceInfo`.
7. **Bug fix**: `markAtomFlags` is now correctly called in the combined pipeline (was
   previously missing from the old `pipeline` command).
8. **New per-atom fields**: `type-dependencies` and `term-dependencies` split the flat
   `dependencies` array into constants from the type signature vs the body/proof.
   The `dependencies` field is preserved as the deduplicated union for backward compatibility.
9. **Removed `specified` field**: The `specified` boolean was always `true` in Lean (all
   declarations have type signatures). Whether an atom has specifications is now inferred
   from `specs != []`, aligning with probe-verus v5.0.0 which also dropped `specified`.
10. **`SourceInfo` fields now required**: `repo` and `commit` changed from `Option String`
    to `String` (empty string when unavailable), conforming to the `probe` repository's
    JSON schema which declares these fields as required.
