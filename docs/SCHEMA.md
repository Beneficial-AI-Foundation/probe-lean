# Schema 3.0: Lean Instantiation

Version: 3.0
Date: 2026-08-03
Parent document: [probes/docs/envelope-rationale.md](https://github.com/Beneficial-AI-Foundation/probe/blob/main/docs/envelope-rationale.md)

This document defines the Lean-specific details for Schema 3.0 as produced by `probe-lean`.
It instantiates the generic envelope and atom schema from the parent document with Lean
declaration kinds, code-name URIs, versioning, and field mappings.

## Envelope Example

A complete probe-lean extract output with the Schema 3.0 envelope:

```json
{
  "schema": "probe-lean/extract",
  "schema-version": "3.0",
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
      "is-lean-generated": false,
      "is-aeneas-generated": false,
      "is-ignored": false,
      "rust-source": null,
      "specs": ["probe:ArkLib.SumCheck.Protocol.Prover.prove_spec"],
      "primary-spec": "probe:ArkLib.SumCheck.Protocol.Prover.prove_spec",
      "verification-status": "verified",
      "codomain-head": "ArkLib.SumCheck.Protocol.Prover.State",
      "codomain-is-prop": false,
      "codomain-last-arg-is-bool": false
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
      "is-lean-generated": false,
      "is-aeneas-generated": false,
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
      "is-lean-generated": false,
      "is-aeneas-generated": false,
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
- **`viewify`**: Reads extract output, filters atoms (not hidden, and never lean-generated
  or aeneas-generated — dropped regardless of `is-hidden` — is relevant, code-path ends with
  `Funs.lean`), and outputs molecules to `.verilib/views/`. Consumers that instead read the
  `extract` output directly (e.g. the web UI) honor `is-hidden` and so surface contaminated
  generated atoms once enrichment clears their `is-hidden` (see below).

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
| `is-hidden` | bool | From `.verilib/probes/config.json` `is-hidden` list. Cleared after transitive enrichment for *contaminated* generated atoms (lean- or aeneas-generated) — locally verified but not `transitively-verified`, or `unverified`/`failed` — so consumers that read `extract` output directly (e.g. the web UI) surface them for tracing; `transitively-verified` and `trusted` generated atoms stay hidden. `viewify` omits all generated atoms regardless of this flag. |
| `is-lean-generated` | bool | Core-Lean-generated code: `deriving`-generated instance clusters and structure/class projections |
| `is-aeneas-generated` | bool | Declarations that exist only because of Aeneas: name ends with a suffix from the `extraction-artifact-suffixes` config (source scaffolding), or an attribute-machinery companion theorem (e.g. the `X.mvcgen_spec` that Aeneas's `@[step]` adds next to a tagged `theorem X`) |
| `is-ignored` | bool | From `.verilib/probes/config.json` `is-ignored` list |
| `attributes` | array of strings | Lean tag attributes detected on this declaration (absent when empty) |
| `rust-source` | string or null | Rust source path from Aeneas docstring |

### Field Computation Methods

| Field | Method | Details |
|-------|--------|---------|
| `is-in-package` | **AUTO** | Always `true` for atoms emitted by probe-lean, since only declarations from the project's own modules are extracted. Provided as a generic signal for downstream tools. |
| `is-relevant` | **AUTO / CONFIG** | Defaults to `true` for all in-package declarations. When `relevant-crate` is set in `.verilib/probes/config.json`, declarations with `rust-source` are filtered to only those whose source matches the configured crate. |
| `is-hidden` | **AUTO / CONFIG** | Set from the `is-hidden` name list in `.verilib/probes/config.json`, OR auto-set for *auto-detected* generated atoms (deriving clusters, projections, `@[step]` companions; config-suffix-matched scaffolding is flagged generated but not auto-hidden). After transitive enrichment (skipped under `--skip-enrich`), `is-hidden` is cleared on *contaminated* generated atoms — lean- or aeneas-generated, locally verified but not `transitively-verified`, or `unverified`/`failed`; `transitively-verified` and `trusted` generated atoms stay hidden. Clearing surfaces them only to consumers reading `extract` output directly (e.g. the web UI); `viewify` omits all generated atoms regardless. |
| `is-lean-generated` | **AUTO** | Auto-detected for `deriving`-generated instance clusters and structure/class projections. |
| `is-aeneas-generated` | **CONFIG + AUTO** | Set from the `extraction-artifact-suffixes` list in `.verilib/probes/config.json` (declaration name ends with a configured suffix), and auto-detected for `@[step]`'s attribute-machinery companion theorems (`X.mvcgen_spec`). |
| `is-ignored` | **CONFIG** | Set from the `is-ignored` name list in `.verilib/probes/config.json`. Always a manual editorial decision. |
| `attributes` | **AUTO** | Lean attributes detected on the declaration. Populated from two sources: (1) handle-based detection for attributes registered via `ProbeLean.Attrs` (`primary_spec`, `externally_verified`), and (2) source-level scanning of `@[...]` annotations in `.lean` files. Source scanning acts as a general fallback that works for any attribute, including those registered independently by the target project. probe-lean uses known verification-framework attributes (`progress`, `pspec`, `step`) as a signal for primary-spec detection; all other attributes are raw fact data for consumers. |
| `rust-source` | **AUTO** | Extracted from Aeneas-generated docstrings (`Source: 'path'` pattern). `null` for declarations without Aeneas docstrings. |

**Note:** The `is-hidden`, `is-lean-generated`, `is-aeneas-generated`, and `is-ignored` fields are set by
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
| `type-dependencies` | array | `probe:`-prefixed **project** names referenced in the declaration's type signature |
| `term-dependencies` | array | `probe:`-prefixed **project** names referenced in the declaration's body/proof |
| `type-dependencies-external` | array or absent | `probe:`-prefixed **non-project** names (Mathlib/core) referenced in the type. Absent when empty. Lets a downstream tool reconstruct the full reachability graph, which the project-filtered `type-dependencies` omits. |
| `term-dependencies-external` | array or absent | `probe:`-prefixed **non-project** names referenced in the body/proof. Absent when empty. |
| `code-module` | string | Module name containing the declaration |
| `code-path` | string | Relative path to source file |
| `code-text` | object or null | `{ "lines-start": N, "lines-end": N }` |
| `is-in-package` | bool | Declaration belongs to the current package |
| `is-relevant` | bool | Declaration is relevant for analysis |
| `is-hidden` | bool | Hidden from UI; cleared for contaminated generated atoms after enrichment |
| `is-lean-generated` | bool | Core-Lean-generated code (deriving clusters, projections) |
| `is-aeneas-generated` | bool | Aeneas-only declarations (suffix-matched scaffolding, attribute-machinery companion theorems) |
| `is-ignored` | bool | From config's ignored list |
| `attributes` | array or absent | Lean tag attributes on this declaration. Absent when empty. |
| `rust-source` | string or null | Rust source path from Aeneas docstring |
| `specs` | array or absent | Code-names of theorem atoms whose dependencies include this atom, excluding generated theorems — `is-lean-generated` or `is-aeneas-generated` — unless explicitly tagged `@[primary_spec]` (machine-generated companions are not user specs). Absent when empty. Whether an atom is "specified" can be inferred from `specs` being non-empty. |
| `primary-spec` | string or absent | Code-name of the primary specification theorem for this atom. Absent when none. Determined by precedence: (1) `@[primary_spec]` attribute, (2) known verification-framework attributes (`@[progress]`, `@[pspec]`, `@[step]`), (3) `_spec` suffix match, (4) sole spec inference. |
| `verification-status` | string or absent | `"transitively-verified"`, `"verified"`, `"unverified"`, `"failed"`, `"trusted"`, or absent if skipped. A declaration is `"verified"` if its own body does not contain `sorry`; it is upgraded to `"transitively-verified"` if, additionally, all its transitive dependencies are verified or trusted (computed via reverse-BFS contamination, skippable with `--skip-enrich`). Declarations that are locally sorry-free but have at least one unverified or failed transitive dependency remain `"verified"`. Axioms, declarations carrying `@[externally_verified]`, and non-theorem declarations from `*External.lean` files (Aeneas trust base) are always `"trusted"`. Theorems in `*External.lean` without `@[externally_verified]` carry real proofs and receive their normal status from sorry detection. Declarations without source location (kernel-synthesized) are filtered from output entirely. |
| `trusted-reason` | string or absent | Present only when `verification-status` is `"trusted"`. Values: `"axiom"` (Lean `axiom` keyword), `"externally_verified"` (declaration tagged `@[externally_verified]` — proof discharged outside Lean), `"external"` (non-theorem declaration in a file ending with `External.lean`). Enables automated trust-base classification. |
| `codomain-head` | string or absent | Fully-qualified head constant of the declaration's result type (after stripping `∀`/`→` binders), if the head is a constant. Absent otherwise. A neutral fact about the declaration's shape; a downstream tool can combine it with its own catalogue to classify the codomain. |
| `codomain-is-prop` | boolean | The result type is `Sort 0` (a `Prop`). |
| `codomain-last-arg-is-bool` | boolean | The final application argument of the result type is the constant `Bool`. |

The `codomain-*` fields are neutral, domain-agnostic primitives emitted for every atom. probe-lean
does not classify declarations itself: a downstream tool reconstructs the codomain shape from these
primitives plus its own catalogue. The envelope carries no `classification` object and no
`source.class` field.

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
