# Schema 3.0: Lean Instantiation

Version: 3.0
Date: 2026-08-03
Parent document: [probes/docs/envelope-rationale.md](https://github.com/Beneficial-AI-Foundation/probe/blob/main/docs/envelope-rationale.md)

This document defines the Lean-specific details for Schema 3.0 as produced by `probe-lean`: the
envelope, the code-name format, the declaration kinds, every atom field, and the contracts behind
the two fields that need one (`verification-status` and the dependency arrays). Two companion
documents hold the audit-level detail: [verification-status.md](verification-status.md) and
[auxiliary-folding.md](auxiliary-folding.md). CLI flags and stderr output are in
[USAGE.md](USAGE.md). Historical notes (Schema 1.x changes, the versioning survey, the Verus kind
comparison) are archived in [archive/schema-3.0-migration-notes.md](archive/schema-3.0-migration-notes.md).

## Envelope

The envelope fields (`schema`, `schema-version`, `tool`, `source`, `timestamp`, `data`) are
defined by the parent document. probe-lean registers two `schema` values:

| schema | Command | `data` holds |
|--------|---------|--------------|
| `probe-lean/extract` | `extract` | Unified atoms keyed by code-name |
| `probe-lean/viewify` | `viewify` | Molecules for the web UI keyed by `<code-path>/<name_last>` |

`source.repo` and `source.commit` are required strings (empty when unavailable). Example `extract`
output with one definition and one trusted axiom; a theorem atom has the same fields with
`"kind": "theorem"` and, when tagged, `"attributes": ["primary_spec"]` and `"is-primary-spec": true`:

```json
{
  "schema": "probe-lean/extract",
  "schema-version": "3.0",
  "tool": { "name": "probe-lean", "version": "0.15.0", "command": "extract" },
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
      "kind": "def",
      "language": "lean",
      "dependencies": [
        "probe:ArkLib.SumCheck.Protocol.Prover.computeRoundPoly",
        "probe:ArkLib.SumCheck.Protocol.Verifier.verify"
      ],
      "type-dependencies": ["probe:ArkLib.SumCheck.Protocol.Verifier.verify"],
      "term-dependencies": [
        "probe:ArkLib.SumCheck.Protocol.Prover.computeRoundPoly",
        "probe:ArkLib.SumCheck.Protocol.Verifier.verify"
      ],
      "code-module": "ArkLib.SumCheck.Protocol",
      "code-path": "ArkLib/SumCheck/Protocol.lean",
      "code-text": { "lines-start": 42, "lines-end": 67 },
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
      "verification-status": "transitively-verified",
      "codomain-head": "ArkLib.SumCheck.Protocol.Prover.State",
      "codomain-is-prop": false,
      "codomain-last-arg-is-bool": false
    },
    "probe:Aeneas.Std.core.convert.num.FromUsizeBool": {
      "display-name": "FromUsizeBool",
      "kind": "axiom",
      "language": "lean",
      "dependencies": [],
      "type-dependencies": [],
      "term-dependencies": [],
      "code-module": "Aeneas.Std.FunsExternal",
      "code-path": "Aeneas/Std/FunsExternal.lean",
      "code-text": { "lines-start": 10, "lines-end": 12 },
      "is-in-package": true,
      "is-relevant": true,
      "is-hidden": false,
      "is-lean-generated": false,
      "is-aeneas-generated": false,
      "is-ignored": false,
      "is-primary-spec": false,
      "rust-source": null,
      "verification-status": "trusted",
      "trusted-reason": "axiom",
      "codomain-is-prop": false,
      "codomain-last-arg-is-bool": false
    }
  }
}
```

## Package version

`source.package-version` is always non-empty but is an opaque identifier, not necessarily semver:

1. the `version` field of `lakefile.toml` if present (`"0.1.0"`; a `lakefile.lean` is not parsed);
2. otherwise the short git commit hash (`"a1b2c3d"`);
3. otherwise `"0.0.0"`.

The output filename uses underscores: `lean_<package>_<version>.json`, e.g.
`lean_ExampleProject_0.1.0.json` or `lean_Arklib_a1b2c3d.json`.

## Code-name format

A Lean atom's code-name is `probe:` followed by the fully qualified Lean name, with private
mangling stripped (`_private.M.0.Bar.foo` → `probe:Bar.foo`):

- `probe:ArkLib.SumCheck.Protocol.Prover.prove`
- `probe:Mathlib.Data.Nat.Basic.succ_pos`

No package or version is embedded: within a project Lean names are unique by construction, and
across projects `source.package` disambiguates.

## Declaration kinds (`kind`)

`kind` corresponds to the generic spec's `mode` field, in Lean-native terms. probe-verus uses the
same field name with Verus's own values.

| Value | Lean construct | Notes |
|-------|---------------|-------|
| `def` | `def` | Computable definition |
| `theorem` | `theorem` | Proven proposition (erased at runtime) |
| `abbrev` | `abbrev` | Reducible definition |
| `projection` | (auto) | Structure field or class method projection (`env.isProjectionFn`) |
| `class` | `class` | Type class |
| `structure` | `structure` | Record type |
| `inductive` | `inductive` | Inductive type |
| `instance` | `instance` | Detected by name: the last component starts with `inst`, Lean's auto-naming. A user-named instance is emitted as `def`; a `def instFoo` as `instance`. |
| `axiom` | `axiom` | Assumed without proof; always `"trusted"` |
| `opaque` | `opaque` | Opaque definition (no unfolding) |
| `quot` | `Quot` | Quotient type (built-in) |

## Atom fields (`probe-lean/extract`)

Every atom carries every field below unless marked "or absent". The Source column says where the
value comes from: **auto** (computed from the environment), **config** (`.verilib/probes/config.json`),
or **attribute** (a Lean attribute on the declaration).

| Field | Type | Source | Description |
|-------|------|--------|-------------|
| `display-name` | string | auto | Last component of the name. |
| `kind` | string | auto | Declaration kind, see above. |
| `language` | string | auto | Always `"lean"`. |
| `dependencies` | array | auto | `probe:`-prefixed **project** names: the exact **union** of `type-dependencies` and `term-dependencies`. Deduplication is by declaration identity before private mangling is stripped, so two distinct private declarations that print to the same name can appear twice; this is permitted and silent (`tools/audit/compare-extract.py` reports it as a diagnostic). |
| `type-dependencies` | array | auto | Project names the declaration's type signature mentions. Exactly the signature; auxiliary folding never adds here, so this is the signal `specs`/`primary-spec` derive from. |
| `term-dependencies` | array | auto | Project names the body/proof mentions, plus every project name the fold recovers from under a non-emitted auxiliary, auxiliaries named in the *type* included. Folded entries are therefore indirect: what the declaration reaches, not only what it names. See [Auxiliary-dependency folding](#auxiliary-dependency-folding). |
| `type-dependencies-external` | array or absent | auto | **Non-project** names (Mathlib, core) the type mentions **directly**. Absent when empty. Lets a downstream tool extend the graph past the project boundary by direct edges; an external reached only through an auxiliary, or one the internal-name filter drops (`Nat.rec`, `Foo.mk`), is not listed. Folding never contributes here. |
| `term-dependencies-external` | array or absent | auto | Same for the body/proof. |
| `code-module` | string | auto | Module containing the declaration. |
| `code-path` | string | auto | Source path relative to the project root. |
| `code-text` | object or null | auto | `{ "lines-start": N, "lines-end": N }`. |
| `is-in-package` | bool | auto | Always `true`: only the project's own modules are extracted. Kept as a generic signal. |
| `is-relevant` | bool | auto / config | `true` for every atom when the config has no `relevant-crate`. When it has one: `false` for atoms without a `rust-source`, and for the rest `true` only if the source contains the crate name, does not start with `/`, and does not contain `/cargo/registry/`. |
| `is-hidden` | bool | auto / config | From the config's `is-hidden` list, or auto-set for auto-detected generated atoms (deriving clusters, projections, `@[step]` companions; config-suffix-matched scaffolding is flagged generated but not hidden). After transitive enrichment it is **cleared** on *contaminated* generated atoms (`verified` but not `transitively-verified`, or `unverified`/`failed`) so consumers reading `extract` output surface them for tracing; clean and trusted generated atoms stay hidden. `viewify` drops all generated atoms regardless. Not cleared under `--skip-enrich`. |
| `is-lean-generated` | bool | auto | Core-Lean output: `deriving`-generated instance clusters and structure/class projections. |
| `is-aeneas-generated` | bool | config + auto | Exists only because of Aeneas: name ends with a suffix in the config's `extraction-artifact-suffixes`, or is the attribute-machinery companion theorem `X.mvcgen_spec` that Aeneas's `@[step]` adds next to a tagged `theorem X`. |
| `is-ignored` | bool | config | From the config's `is-ignored` list. Always an editorial decision. |
| `is-primary-spec` | bool | attribute | The declaration carries `@[primary_spec]`. *Tagged*, not *won*: a heuristic-chosen `primary-spec` reads `false`, a tagged non-theorem reads `true`, and a tagged theorem the inference could not attach to any target (issue #104) still reads `true`. Intersecting a target's `specs` with this flag recovers its tagged candidates. |
| `attributes` | array or absent | attribute | Lean attributes on the declaration, absent when empty. `primary_spec` comes from probe-lean's handle; every other name (`step`, `progress`, `simp`, …) from a lexer-aware scan of the `@[…]` blocks in the declaration's header only, so a tag quoted in a docstring, comment, string or neighbouring declaration is not attributed. `externally_verified` is listed when the header scan finds it **or** the declaration is in the attribute's tag set read from the environment (so a tag attached by an `attribute` command shows here too). A constant sharing a tagged declaration's range (a generated companion, a `deriving` instance, a projection of a one-line `structure`) *shows* the parent's scanned tags, `externally_verified` included, so this array is **not** evidence of trust: read `trusted-reason`. |
| `rust-source` | string or null | auto | Path from an Aeneas docstring's `Source: 'path'` line, read from the declaration's own docstring or, failing that, from its sibling `<name>_body` declaration's. |
| `specs` | array or absent | auto | Theorem atoms whose **`type-dependencies`** include this atom, i.e. whose *statement* mentions it. A constant a theorem only uses in its proof is not something it specifies, with one exception: a `@[primary_spec]` theorem whose statement mentions no specifiable constant falls back to its proof-term dependencies when those name exactly one specifiable constant (several: the tag attaches to nothing). Generated theorems are excluded unless tagged `@[primary_spec]`. Absent when empty; "specified" means `specs` is non-empty. |
| `primary-spec` | string or absent | auto | The primary specification theorem, by precedence: (1) `@[primary_spec]`, (2) a verification-framework attribute (`@[progress]`, `@[pspec]`, `@[step]`), (3) `_spec` suffix match, (4) sole spec. Several `@[primary_spec]` theorems on one target: arbitrary tie-break, stderr warning, losers stay in `specs` with `is-primary-spec: true`. Signals 2–4 pick a theorem without tagging it, so the winner's own `is-primary-spec` may be `false`. |
| `verification-status` | string or absent | auto | One of the five values in [Verification status](#verification-status-and-the-trusted-base). Absent under `--skip-verify`, except trusted atoms keep `"trusted"`. |
| `trusted-reason` | string or absent | auto | Only when `verification-status` is `"trusted"`: `"axiom"`, `"externally_verified"` or `"external"`, see below. |
| `codomain-head` | string or absent | auto | Head constant of the result type after stripping `∀`/`→` binders, if it is a constant. |
| `codomain-is-prop` | bool | auto | The result type is `Sort 0`. |
| `codomain-last-arg-is-bool` | bool | auto | The final application argument of the result type is `Bool`. |

The `codomain-*` fields are neutral primitives. probe-lean does not classify declarations; a
downstream tool reconstructs the codomain shape from them plus its own catalogue. The envelope
carries no `classification` object and no `source.class` field.

The editorial flags (`is-hidden`, `is-lean-generated`, `is-aeneas-generated`, `is-ignored`) are a
backward-compatible convenience. In the recommended pipeline for Aeneas projects,
**probe-aeneas** computes them from the generic facts probe-lean provides (`attributes`, name
patterns, `rust-source`).

## Verification status and the trusted base

`verification-status` is decided by a **kernel walk**, not by the build log or the emitted graph.
`sorry` elaborates to the `sorryAx` axiom, and the walk follows the constant graph of every
constant of every built project module, atoms or not. It stops at two boundaries:

- **the project boundary**: Lean and every dependency package in `lake-manifest.json` are trusted
  wholesale;
- **the trusted base T** inside the project, defined by the three rules below.

| Status | Meaning |
|--------|---------|
| `"trusted"` | In T; `trusted-reason` says why. |
| `"unverified"` | The declaration's own type or value names `sorryAx` (a *direct carrier*). |
| `"verified"` | Locally sorry-free, but an unexcused project `sorry` is reachable from it. |
| `"transitively-verified"` | No project `sorry` is reachable except through a trusted declaration ("clean modulo T"). Never produced under `--skip-enrich`, where such atoms read `"verified"`. |
| `"failed"` | Currently never produced. |

The trusted base, one shared rule set (`ProbeLean/Trust.lean`) in precedence order:

1. **`"axiom"`**: the Lean `axiom` keyword, generated `native_decide` axioms included.
2. **`"externally_verified"`**: the declaration is in the `externally_verified` attribute's tag
   set, read from the environment however the tag was attached. Nothing that merely shares a
   tagged declaration's source range is in the set.
3. **`"external"`**: a non-proof (not a theorem, and not Prop-typed) in a module whose name ends
   with `External`, trusted as a model whatever its type.

A trusted declaration is a leaf: a `sorry` inside or below it does not taint its callers. Two
consequences a consumer must know:

- **Attribution is per kernel constant.** On Lean ≤ 4.28 a `def`'s sorried proof obligation is
  abstracted into `f._proof_1`, so `f` reads `"verified"`; from 4.29 the `sorry` stays inline and
  `f` reads `"unverified"`. On every toolchain `f` is tainted.
- **Kernel dependencies, not executable bodies.** A `sorry` in a `partial def` body or in an
  `@[implemented_by]` target does not taint the host, and a `native_decide` proof rests on a
  trusted generated axiom.

Everything else (cross-checks, module coverage, merged declarations, the exact scope of each rule
and its limits) is in [verification-status.md](verification-status.md).

## Auxiliary-dependency folding

Lean abstracts embedded proofs and match arms into auxiliary constants (`X._proof_N`,
`X.match_N`) that probe-lean does not emit as atoms. `extract` folds the edges underneath them into
the referencing declaration. This is the authoritative statement of the invariant; the copies in
`ProbeLean/Analysis.lean` and `tools/audit/compare-extract.py` quote it:

> The fold only ever adds names to `term-dependencies`. It never adds to `type-dependencies`,
> never removes an entry from any of the four dependency arrays, never adds to the `*-external`
> arrays, and never changes the atom set.

The four arrays are `type-dependencies`, `term-dependencies` and their `*-external` twins;
`dependencies` is the derived union, so it grows with `term-dependencies`.

Every recovered edge lands in `term-dependencies`, including one found under an auxiliary named in
the declaration's *type*, so `type-dependencies` stays exactly what the signature mentions and
type-driven spec selection is unaffected. Only project-internal targets are folded: an external
constant reached only through an auxiliary is not listed anywhere (a size tradeoff, since a single
`by omega` reaches ~50 `Lean.Omega.*` constants). Folding recovers edges, not nodes, and does not
bear on `verification-status`. A zero in-degree in this output is still not a licence to delete a
declaration from the sources.

What is and is not folded through, what a folded target is, and the one way `specs` can change are
in [auxiliary-folding.md](auxiliary-folding.md).

## Molecules (`probe-lean/viewify`)

`viewify` reads `extract` output and keeps atoms that are not hidden, not lean- or
aeneas-generated (dropped regardless of `is-hidden`), relevant, and whose `code-path` ends with
`Funs.lean`. `data` is keyed by `<code-path>/<name_last>`, or by the full name on collision:

| Field | Type | Description |
|-------|------|-------------|
| `code-path` | string or null | The atom's `code-path` |
| `code-lines` | string or null | The atom's line range as `"start-end"` |
| `code-name` | string | The atom's code-name |
| `rust-path` | string | Always `""`; `rust-source` is not consulted |
| `rust-lines` | object | Always `{ "lines-start": 0, "lines-end": 0 }` |
| `rust-name` | string | Always `""` |
| `spec-path` | string or null | The atom's own `code-path`, not its `primary-spec`'s |
| `spec-lines` | string or null | Always `null` |
| `spec-name` | string or null | The atom's own code-name, not its `primary-spec` |

The `rust-*` and `spec-*` fields are placeholders kept for the consumer's shape; nothing in
`viewify` fills them from `rust-source` or `primary-spec`.
