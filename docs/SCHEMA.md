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
      "is-primary-spec": false,
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
        "probe:ArkLib.SumCheck.Protocol.Prover.prove",
        "probe:ArkLib.SumCheck.Protocol.Prover.roundPoly_degree_le"
      ],
      "type-dependencies": [
        "probe:ArkLib.SumCheck.Protocol.Prover.prove"
      ],
      "term-dependencies": [
        "probe:ArkLib.SumCheck.Protocol.Prover.prove",
        "probe:ArkLib.SumCheck.Protocol.Prover.roundPoly_degree_le"
      ],
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
      "is-primary-spec": true,
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
      "is-primary-spec": false,
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

- `lean_ExampleProject_0.1.0.json`
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
| `is-primary-spec` | bool | The declaration carries `@[primary_spec]`. *Tagged*, not *won*: a theorem the heuristic signals pick as some target's `primary-spec` reads `false` here unless it is also tagged, and a tagged non-theorem reads `true` even though it can never be a `primary-spec`. It also does not mean the tag *attached*: the attribute takes no argument, so probe-lean infers the target, and a tagged theorem whose statement names no specifiable atom and whose proof names several can appear in no target's `specs` at all while still reading `true` here (issue #104). Intersecting a target's `specs` with this flag recovers the tagged candidates for that target. |
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
| `is-primary-spec` | **AUTO** | Set from the `@[primary_spec]` attribute handle (registered by `ProbeLean.Attrs`), independently of the primary-spec signals. It records that the declaration was *tagged*, not that it *won*: a heuristic winner carries `false`, and a tagged non-theorem carries `true`. The attribute installs no kind validator, so `@[primary_spec] def foo` is accepted. |
| `attributes` | **AUTO** | Lean attributes detected on the declaration. `externally_verified` comes from the attribute's **tag set**, read from the environment (the entries the target's own `registerTagAttribute` extension stored in the olean, plus probe-lean's handle for a target that imports `ProbeLean.Attrs`), so it is present however the tag was attached — `@[…]` on the declaration or an `attribute [externally_verified] foo` command — and this is also what the trusted base reads (`trusted-reason`). `primary_spec` comes from probe-lean's handle. Every other name comes from a source scan of the `@[...]` blocks in the declaration's **header**, the only source for attributes probe-lean does not register (`step`, `progress`, `simp`, …): the file is lexed from the top so comments (docstrings included), string, raw string and interpolated string literals (their `{…}` code included), char literals and `«…»` identifiers are stripped wherever they open; the scan starts at the declaration range's first line and stops after the line that opens the declaration (`theorem x : …`, `def x :=`, …); nothing before the range is read. So a `@[…]` quoted in a docstring, a body comment, a block comment above, a string, a syntax quotation of the previous declaration or a one-line tagged neighbour is never attributed to the declaration. A constant that shares a tagged declaration's range — a generated companion (`X.mvcgen_spec`), a `deriving` instance, a projection of a one-line `structure`, an `@[ext]`-generated lemma — *shows* the tagged declaration's attributes here (deliberately: the companion of a `@[step]` axiom is that axiom's spec proxy for `primary-spec`), and so does a second command on the same line as a tagged one; none of that reaches trust. Where the scan and the tag set disagree about `externally_verified`, `extract` prints `Divergence(tag): <n> header shows @[externally_verified] naming it, but the attribute's tag set does not contain it; not trusted` or `Note(tag): <n> is tagged externally_verified by an \`attribute\` command or a macro; its header does not show the tag; trusted` on stderr. probe-lean uses known verification-framework attributes (`progress`, `pspec`, `step`) as a signal for primary-spec detection; all other attributes are raw fact data for consumers. |
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
| `dependencies` | array | `probe:`-prefixed names this declaration depends on: the **union** of `type-dependencies` and `term-dependencies`. This is an invariant, not an approximation — nothing appears here that is absent from both arrays. Deduplication is by *declaration identity*, and names are printed with private mangling stripped (`_private.M.0.Bar.foo` → `Bar.foo`), so two distinct private declarations that recover to the same user-facing name can appear twice. Note that nothing reports this per array: `extract`'s stderr warning covers duplicate **atom** names, and a colliding pair of *dependency* targets need not be emitted as atoms at all (they can be external, or constructors), in which case the duplicate is silent. `tools/audit/compare-extract.py` reports it as a diagnostic. |
| `type-dependencies` | array | `probe:`-prefixed **project** names referenced in the declaration's type signature. Exactly what the signature mentions — auxiliary folding never adds here (see [Auxiliary-dependency folding](#auxiliary-dependency-folding)), so this stays the signal `specs` / `primary-spec` are derived from. |
| `term-dependencies` | array | `probe:`-prefixed **project** names referenced in the declaration's body/proof, plus every project name the fold recovers from under a non-emitted auxiliary — including auxiliaries named in the *type* (see [Auxiliary-dependency folding](#auxiliary-dependency-folding)). Folded entries are therefore *indirect*: the array holds what the declaration reaches, not only what it literally names. For a theorem this is the proof term, so it is normally non-empty and typically much larger than `type-dependencies`. |
| `type-dependencies-external` | array or absent | `probe:`-prefixed **non-project** names (Mathlib/core) referenced **directly** in the type. Absent when empty. Lets a downstream tool reconstruct the full reachability graph, which the project-filtered `type-dependencies` omits. Auxiliary folding does not contribute here: an external constant reached only through an auxiliary is not listed (see the asymmetry note below). |
| `term-dependencies-external` | array or absent | `probe:`-prefixed **non-project** names referenced **directly** in the body/proof. Absent when empty. Same direct-only rule as `type-dependencies-external`. |
| `code-module` | string | Module name containing the declaration |
| `code-path` | string | Relative path to source file |
| `code-text` | object or null | `{ "lines-start": N, "lines-end": N }` |
| `is-in-package` | bool | Declaration belongs to the current package |
| `is-relevant` | bool | Declaration is relevant for analysis |
| `is-hidden` | bool | Hidden from UI; cleared for contaminated generated atoms after enrichment |
| `is-lean-generated` | bool | Core-Lean-generated code (deriving clusters, projections) |
| `is-aeneas-generated` | bool | Aeneas-only declarations (suffix-matched scaffolding, attribute-machinery companion theorems) |
| `is-ignored` | bool | From config's ignored list |
| `is-primary-spec` | bool | The declaration carries `@[primary_spec]`. *Tagged*, not *won* — a heuristic-chosen `primary-spec` reads `false` here, a tagged non-theorem reads `true`. |
| `attributes` | array or absent | Lean tag attributes on this declaration, from probe-lean's own attribute handles plus a scan of the `@[…]` block above the declaration's source range. Absent when empty. A constant sharing a tagged declaration's range (a generated companion `X.mvcgen_spec`, a `deriving` instance or a projection of a one-line `structure`) shows the tagged declaration's scanned tags; those never make it *trusted* (see `trusted-reason`). |
| `rust-source` | string or null | Rust source path from Aeneas docstring |
| `specs` | array or absent | Code-names of theorem atoms whose **`type-dependencies`** include this atom — that is, theorems whose *statement* mentions it. A constant a theorem only invokes in its proof is not something the theorem specifies, so it is excluded — except a theorem explicitly tagged `@[primary_spec]` whose statement mentions no specifiable constant, which falls back to its proof-term dependencies **when those name exactly one specifiable constant** (with several, the tag is ambiguous and attaches to nothing). Also excludes generated theorems — `is-lean-generated` or `is-aeneas-generated` — unless explicitly tagged `@[primary_spec]` (machine-generated companions are not user specs). Absent when empty. Whether an atom is "specified" can be inferred from `specs` being non-empty. |
| `primary-spec` | string or absent | Code-name of the primary specification theorem for this atom. Absent when none. Determined by precedence: (1) `@[primary_spec]` attribute, (2) known verification-framework attributes (`@[progress]`, `@[pspec]`, `@[step]`), (3) `_spec` suffix match, (4) sole spec inference. When several `@[primary_spec]` theorems target the same atom the pick is an arbitrary tie-break — `extract` warns on stderr, and the rejected candidates stay in `specs` with `is-primary-spec: true`. Conversely, signals 2-4 name a winner without tagging it, so `primary-spec` may point at a theorem whose own `is-primary-spec` is `false`. |
| `verification-status` | string or absent | `"transitively-verified"`, `"verified"`, `"unverified"`, `"failed"`, `"trusted"`, or absent under `--skip-verify` (trusted atoms keep `"trusted"`). Decided by a **kernel walk**, not by the build log or the emitted graph: `sorry` elaborates to the `sorryAx` axiom, and `extract` walks the constant graph of *every* constant of *every* built project module (P — regardless of `--module`/`--library`, and including constants it never emits: auxiliaries, constructors, range-less `addDecl`/`impl_def` constants), stopping at the project boundary (Lean and every dependency package are trusted wholesale) and at the trusted base T (see `trusted-reason`). `"trusted"`: in T. `"unverified"`: the declaration's own type or value names `sorryAx` (a *direct carrier*). `"verified"`: locally sorry-free, but an unexcused project `sorry` is reachable from it. `"transitively-verified"`: no project `sorry` is reachable except through a trusted declaration ("clean modulo T"); never produced under `--skip-enrich`, where such atoms read `"verified"`. `"failed"` is currently never produced. Generated companions (`X.mvcgen_spec`) receive their own status — a companion of a trusted theorem is `"transitively-verified"`, not `"trusted"`. The reverse-BFS over the emitted graph still runs as a cross-check: where it disagrees with the walk, `extract` prints `Divergence(graph): <atom> graph says clean, oracle says tainted` (or the reverse) on stderr and keeps the walk's verdict; the build log's `sorry` warnings are compared the same way (`Divergence(log): …`, trusted atoms skipped). **Kernel dependencies, not executable bodies.** The walk follows what the kernel constant references. A `partial def`'s body compiles to `X._unsafe_rec`, and the kernel constant `X` is an opaque inhabitant with no edge to it; an `@[implemented_by target]` host has no edge to `target`. So a `sorry` in a `partial def` body or in an `implemented_by` target does not taint the host: `loopy` in `partial def loopy … sorry …` reads `"transitively-verified"` while `loopy._unsafe_rec` is a direct carrier, listed `[direct] [not emitted]` by `check-axioms`, and the build-log cross-check prints `Note(log): <atom> build log says sorry; it sits in the compiled body <X._unsafe_rec> of a \`partial def\`, which the kernel constant does not reference …` instead of a divergence (an `implemented_by` target is a constant of its own and gets its own status; nothing links the host to it). `unsafe def` bodies *are* walked. If the full project module set cannot be co-imported, the walk runs over the selected modules **and every project module they import transitively** (P is the project inventory restricted to what the environment loaded), so every emitted atom's dependency closure is still inside P; the modules left out are outside that closure and only the `check-axioms` audit misses them, announced as `Warning: <n> project module(s) not imported (full import failed); …`. An atom whose Lean name is not in P is a bug signal, not "clean": it gets **no** status and `Warning: atom <name> is not a project constant the kernel walk covered; no verification-status assigned` is printed. **Merged declarations.** Lean's importer accepts two project modules restating the same theorem (same name and statement) and keeps *one* proof without comparing bodies, so after co-import that name no longer identifies one project proof. The walk fails closed for such a name: it follows the union of every version's dependencies (a `sorry` in any version makes the name `"unverified"` and every caller `"verified"`, including callers built against the proved version), no `@[externally_verified]` on it is honoured, and `Warning: <n> declaration name(s) are declared by more than one project module with the same statement, and Lean kept one proof: …` is printed. That is the pair the olean preflight can see (project/project); for a module built under the module system (`module` header) the preflight reads the `.olean.private` part the importer reads, so a `public theorem` is seen with its proof and not as the proof-less axiom of the exported level (two sorried public theorems used to merge into a trusted `"axiom"`), and a module-system olean whose split parts are missing aborts the extraction. So does a stale `.olean` with no `.lean` source that a kept module still imports: it would otherwise sit outside P and be trusted like a dependency. The exemption is per pair of modules actually read: a name a project module declares that the environment attributes to another module is exempt only when the preflight read **both** modules' versions. A restatement of a **dependency's** theorem, or a pair involving a module whose `.olean` the preflight could not read, is found after the import from the environment header — a name a project module declares that the environment attributes to another module, or that a non-project module declares too — and treated as resting on `sorry`, since the discarded body is invisible: `"unverified"` if it is emitted (the importer attributed it to the project module), otherwise `[not emitted]` in `check-axioms`; every caller `"verified"`; no trust rule applies; `Warning: <n> declaration name(s) are declared by a project module and by a module the walk cannot see into …` is printed. Remaining limitation: a name whose *every* declaring module is outside P is never examined, which is the trusted-base decision, not a gap. |
| `trusted-reason` | string or absent | Present only when `verification-status` is `"trusted"`. One shared rule set (`ProbeLean/Trust.lean`), used by this field, by the walk and by `check-axioms`, in precedence order: `"axiom"` (Lean `axiom` keyword); `"externally_verified"` (the declaration is in the attribute's **tag set** — proof discharged outside Lean — read from the environment, not from source text: `registerTagAttribute` stores the tagged names in the olean under the registering constant's name, and probe-lean finds that constant, reads the attribute name and extension name off its `initialize` body, and reads the entries; probe-lean's own handle is a second source for targets that import `ProbeLean.Attrs`. A tag is a tag, whatever syntax attached it — `@[…]` on the declaration or an after-the-fact `attribute [externally_verified] foo` command — and whatever the constant is, a range-less `impl_def` included. What is **not** in the set: anything that merely shares a tagged declaration's source range — a `deriving` instance, a projection, a generated `.mvcgen_spec` companion, a Lean-generated `instX.field` helper — and anything the source scan could be fooled by (a tag in a docstring, a comment, a string or an interpolated string, a neighbouring command on the same line, a syntax quotation). Limits, all under-trust: a tag attribute registered with an explicit `ref` other than its constant's name, through a wrapper, or as a `ParametricAttribute` is not read, and `Divergence(tag)` lines say so per declaration); `"external"` (declaration in a module whose name ends with `External`, e.g. `Pkg.FunsExternal`, that is not a **proof**: theorems, and any `def`/`opaque`/instance whose *type is a proposition* — `def admitted : False := sorry` — get their normal status there; a Prop-*valued* `def p : Prop` is a model and is trusted). A trusted declaration is a leaf of the walk: a `sorry` inside or below it does not taint its callers (a human vouched for it), and one whose *statement* names `sorryAx` directly is reported with `Warning: trusted declaration <n> names \`sorry\` directly in its statement` (a statement that reaches `sorry` only through another constant is not detected). |
| `codomain-head` | string or absent | Fully-qualified head constant of the declaration's result type (after stripping `∀`/`→` binders), if the head is a constant. Absent otherwise. A neutral fact about the declaration's shape; a downstream tool can combine it with its own catalogue to classify the codomain. |
| `codomain-is-prop` | boolean | The result type is `Sort 0` (a `Prop`). |
| `codomain-last-arg-is-bool` | boolean | The final application argument of the result type is the constant `Bool`. |

The `codomain-*` fields are neutral, domain-agnostic primitives emitted for every atom. probe-lean
does not classify declarations itself: a downstream tool reconstructs the codomain shape from these
primitives plus its own catalogue. The envelope carries no `classification` object and no
`source.class` field.

### Auxiliary-dependency folding

Lean abstracts non-atomic embedded proofs and match arms into auxiliary constants
(`X._proof_N`, `X.match_N`, tactic-generated helpers). probe-lean does not emit those as
atoms, so a dependency reached only through one of them used to leave no trace at all:
`host → aux → lemma` produced no `lemma` edge, and the reporter who trusted an in-degree of
0 to prune unreferenced declarations broke the build.

`extract` therefore folds such edges into the referencing declaration. This is the one place
the invariant is stated; everything else in the repo points here rather than restating it.
The pass is strictly **additive**:

> It only ever adds names to `term-dependencies`. It never adds to `type-dependencies`,
> never removes an entry from any of the four dependency arrays, never adds to the
> `*-external` arrays, and never changes the atom set.

**Every recovered edge lands in `term-dependencies`**, including one found under an
auxiliary named in the declaration's *type*. `type-dependencies` therefore stays exactly
what the signature syntactically mentions, so *type-driven* spec selection is unaffected:
`specs` / `primary-spec` are normally computed from `type-dependencies`, and a constant
reached only through an auxiliary's implementation is not something a statement specifies.
Since `dependencies` is the union of the two buckets, verification-status propagation still
sees every recovered edge.

That is not a blanket guarantee that `specs` cannot change. Spec selection has one fallback
that reads the union: a `@[primary_spec]`-tagged theorem whose *statement* names no
specifiable constant falls back to `dependencies`, and attaches only when that leaves
exactly one candidate. A folded term edge can add a second candidate there and detach such a
tag with `type-dependencies` byte-identical. Projects that do not rely on that fallback see
no `specs` change at all (measured: zero on curve25519-dalek-lean-verify). The fallback
exists only because `@[primary_spec]` cannot name its own target; issue #104 proposes giving
it a parameter, which removes the dependency on inference entirely.

A consequence worth stating: a folded entry in `term-dependencies` is *indirect*. The array
is no longer only "constants named in the body" — it is the direct project dependencies of
the body/proof, plus the project targets reached by expanding eligible auxiliary occurrences
in **either** the type or the body, stopping at targets. It is neither restricted to the
body nor unrestricted transitive reachability. Use `dependencies` for reachability and treat
`type-dependencies` as the exact signature signal.

What is folded **through** (traversed, contributing what it reaches):

- constants filtered from the atom set by name (`X._proof_N`, `X.match_N`, and the rest of
  `isInternalName`'s classes), and project constants with no declaration range, provided
  they are value-bearing (`def` / `theorem` / `opaque`).

What is **not** folded through:

- structural members of a type, as listed in `autoGeneratedSuffixes` — `.mk`, `.injEq`,
  `.casesOn`, `.rec`, `.recOn`, `.brecOn`, `.noConfusion`, `.noConfusionType`, `.sizeOf_spec`,
  `.inj`, `.elim`, `.below`, `.ibelow`, `.binductionOn`, `.ctorIdx`, `.toCtorIdx`, and the
  equation lemmas `.eq_1` / `.eq_2` / `.eq_3` / `.eq_def`; `ProbeLean/Analysis.lean` holds the
  authoritative list. Mapping members to their parent atom is separate work. Note the list is
  literal, not a pattern: a higher-index equation lemma (`f.eq_4`) matches no entry, so it is
  *not* excluded — it is a target if it carries a declaration range and folded through if it
  does not. Generalising the suffix would change atom emission, which is why it is a
  follow-up rather than part of the fold.
- axioms, inductives, constructors, recursors and `Quot`. An emitted project axiom or
  inductive reached *through* an auxiliary is still `.added` as a target — not folding
  through it only means the traversal does not continue past it.
- anything already emitted as an atom — traversal stops at a real dependency instead of
  flattening the graph past it.

**"Not folded through" is not "not an edge" — but it is not "edge preserved" either.** Both
halves are unchanged from before the fold, and which one applies is decided by the name
filter, not by the fold:

- a direct reference that survives `isInternalName` stays where it always was — in the
  project array if it passes the project filter, in the matching `*-external` array
  otherwise. This includes a range-less project inductive or axiom, so an edge can be listed
  even though its target is never emitted as an atom;
- a direct reference the name filter catches is omitted from **all five** dependency arrays,
  because `partitionDeps` drops internal names before the project/external split. That covers
  every structural-member suffix above and every recursor (`.rec` / `.recOn` / `.brecOn`).
  Constructors split on the same rule rather than as a class: `Color.red` is kept, `Foo.mk` is
  dropped.

A folded **target** is any project constant that survives the name filter and has a
declaration range. That is every atom, plus named inductive constructors, which are
referenced but never emitted as atoms of their own — exactly as for a *direct* edge to such
a constructor today. So a folded name is not guaranteed to be a key in `data`; the
missing-dependency reporting treats a constructor whose parent type is extracted as benign.

**Direct-vs-folded asymmetry for external constants.** Only project-internal targets are
folded. Folding external targets too would add tens of thousands of entries on a
Mathlib-backed project (a single `by omega` drags in ~50 `Lean.Omega.*` constants), so the
output is deliberately abstraction-sensitive for them: `host → anchor` appears in
`*-dependencies-external`, `host → aux → anchor` does not. This is a size tradeoff, not a
claim that external edges are uninformative. Note that "external" means *outside the
extracted project filter*, which under `--library`/`--module` restriction is not the same as
"Mathlib or core".

**What folding does not fix.** It recovers edges, not nodes, and only for the classes above.
It no longer bears on `verification-status`, which is decided by the kernel walk over every
project constant (see the `verification-status` field): a carrier folding cannot reach — a
range-less constant with no emitted target underneath it — still taints its callers through
the walk. Folding matters for the *graph* consumers read, and for the graph-BFS cross-check:
an edge the emitted graph is missing for any reason is exactly what surfaces as a
`Divergence(graph):` line on stderr.

Folding is also *compiled-environment* reachability only. Source-level rebuildability also
depends on notation, macros, attributes and elaboration-time instances that leave no
surviving constant reference, so **a zero in-degree here is still not a licence to delete a
declaration from the sources.**

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
