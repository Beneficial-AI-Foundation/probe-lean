# Schema 3.0: Lean Instantiation

Version: 3.0
Parent document: [probes/docs/envelope-rationale.md](https://github.com/Beneficial-AI-Foundation/probe/blob/main/docs/envelope-rationale.md)

This document defines the Lean-specific details for Schema 3.0 as produced by `probe-lean`: the
envelope, the code-name format, the declaration kinds, every atom field, and the contracts behind
`verification-status` and the dependency arrays. [verification-status.md](verification-status.md)
explains how the kernel walk decides each status. CLI flags and stderr output are in
[usage.md](usage.md).

## Envelope

The envelope fields (`schema`, `schema-version`, `tool`, `source`, `timestamp`, `data`) are
defined by the parent document. probe-lean registers two `schema` values:

| schema | Command | `data` holds |
|--------|---------|--------------|
| `probe-lean/extract` | `extract` | Unified atoms keyed by code-name |
| `probe-lean/viewify` | `viewify` | Molecules for the web UI keyed by `<code-path>/<name_last>` |

`source.repo` and `source.commit` are required strings. If a value is unavailable, the string is
empty.

The example below shows `extract` output with three atoms. `hashRound` is a trusted model in a
`*External` module. `check` reads `"verified"` with `"status-origin": "kernel-taint"` because its
`sorry` sits in an auxiliary constant that is not an atom. `prove` is clean. The example omits the
other atoms that the arrays name. Keys appear in descending order at every level, because
`Json.mkObj` sorts them and the printer emits them reversed (see `AtomsOutput` in
`ProbeLean/Types.lean`).

```json
{
  "tool": { "version": "0.16.0", "name": "probe-lean", "command": "extract" },
  "timestamp": "2026-03-05T14:30:00Z",
  "source": {
    "repo": "https://github.com/Verified-zkEVM/ArkLib",
    "package-version": "f6e5d4c",
    "package": "Arklib",
    "language": "lean",
    "commit": "f6e5d4c"
  },
  "schema-version": "3.0",
  "schema": "probe-lean/extract",
  "data": {
    "probe:ArkLib.SumCheck.hashRound": {
      "verification-status": "trusted",
      "type-dependencies": [],
      "trusted-reason": "external",
      "term-dependencies": [],
      "rust-source": null,
      "language": "lean",
      "kind": "def",
      "is-relevant": true,
      "is-primary-spec": false,
      "is-lean-generated": false,
      "is-in-package": true,
      "is-ignored": false,
      "is-hidden": false,
      "is-aeneas-generated": false,
      "display-name": "hashRound",
      "dependencies": [],
      "codomain-last-arg-is-bool": false,
      "codomain-is-prop": false,
      "codomain-head": "Nat",
      "code-text": { "lines-start": 10, "lines-end": 12 },
      "code-path": "ArkLib/SumCheck/HashExternal.lean",
      "code-module": "ArkLib.SumCheck.HashExternal"
    },
    "probe:ArkLib.SumCheck.Protocol.Verifier.check": {
      "verification-status": "verified",
      "type-dependencies": [],
      "term-dependencies": [],
      "status-origin": "kernel-taint",
      "rust-source": null,
      "language": "lean",
      "kind": "def",
      "is-relevant": true,
      "is-primary-spec": false,
      "is-lean-generated": false,
      "is-in-package": true,
      "is-ignored": false,
      "is-hidden": false,
      "is-aeneas-generated": false,
      "display-name": "check",
      "dependencies": [],
      "codomain-last-arg-is-bool": false,
      "codomain-is-prop": false,
      "codomain-head": "Fin",
      "code-text": { "lines-start": 70, "lines-end": 72 },
      "code-path": "ArkLib/SumCheck/Protocol.lean",
      "code-module": "ArkLib.SumCheck.Protocol"
    },
    "probe:ArkLib.SumCheck.Protocol.Prover.prove": {
      "verification-status": "transitively-verified",
      "type-dependencies": ["probe:ArkLib.SumCheck.Protocol.Prover.State"],
      "term-dependencies-external": ["probe:List.foldl"],
      "term-dependencies": [
        "probe:ArkLib.SumCheck.Protocol.Prover.computeRoundPoly",
        "probe:ArkLib.SumCheck.hashRound"
      ],
      "specs": ["probe:ArkLib.SumCheck.Protocol.Prover.prove_spec"],
      "rust-source": null,
      "primary-spec": "probe:ArkLib.SumCheck.Protocol.Prover.prove_spec",
      "language": "lean",
      "kind": "def",
      "is-relevant": true,
      "is-primary-spec": false,
      "is-lean-generated": false,
      "is-in-package": true,
      "is-ignored": false,
      "is-hidden": false,
      "is-aeneas-generated": false,
      "display-name": "prove",
      "dependencies": [
        "probe:ArkLib.SumCheck.Protocol.Prover.State",
        "probe:ArkLib.SumCheck.Protocol.Prover.computeRoundPoly",
        "probe:ArkLib.SumCheck.hashRound"
      ],
      "codomain-last-arg-is-bool": false,
      "codomain-is-prop": false,
      "codomain-head": "ArkLib.SumCheck.Protocol.Prover.State",
      "code-text": { "lines-start": 42, "lines-end": 67 },
      "code-path": "ArkLib/SumCheck/Protocol.lean",
      "code-module": "ArkLib.SumCheck.Protocol"
    }
  }
}
```

A theorem atom has the same fields with `"kind": "theorem"`. When it carries `@[primary_spec]`, it
also has `"attributes": ["primary_spec"]` and `"is-primary-spec": true`.

## Package version

`source.package-version` is always non-empty. It is an opaque identifier, not necessarily semver:

1. the `version` field of `lakefile.toml` if present (`"0.1.0"`). A `lakefile.lean` is not parsed.
2. otherwise the short git commit hash (`"a1b2c3d"`).
3. otherwise `"0.0.0"`.

The output filename has the form `lean_<package>_<version>.json`, for example
`lean_ExampleProject_0.1.0.json` or `lean_Arklib_a1b2c3d.json`.

## Code-name format

A Lean atom's code-name is `probe:` followed by the fully qualified Lean name, with private
mangling stripped (`_private.M.0.Bar.foo` becomes `probe:Bar.foo`):

- `probe:ArkLib.SumCheck.Protocol.Prover.prove`
- `probe:Mathlib.Data.Nat.Basic.succ_pos`

The code-name embeds no package or version. Lean names are unique within a project by
construction, and `source.package` tells projects apart.

## Declaration kinds (`kind`)

`kind` corresponds to the generic spec's `mode` field, in Lean-native terms.

| Value | Lean construct | Notes |
|-------|---------------|-------|
| `def` | `def` | Computable definition |
| `theorem` | `theorem` | Proven proposition (erased at runtime) |
| `abbrev` | `abbrev` | Reducible definition |
| `projection` | (auto) | Structure field or class method projection (`env.isProjectionFn`) |
| `class` | `class` | Type class |
| `structure` | `structure` | Record type |
| `inductive` | `inductive` | Inductive type |
| `instance` | `instance` | Registered in Lean's instance table: the keyword, `scoped instance`, or `attribute [instance]` in the declaring module |
| `axiom` | `axiom` | Assumed without proof. Always `"trusted"`. |
| `opaque` | `opaque` | Opaque definition (no unfolding) |
| `quot` | `Quot` | Quotient type (built-in) |

### Relationship to probe-verus

probe-verus uses the same field name with Verus's own values. Each tool keeps its language's
native declaration taxonomy:

| Concept | Verus `kind` | Lean `kind` |
|---------|-------------|-------------|
| Executable code | `exec` | `def`, `abbrev`, `projection`, `instance`, `opaque` |
| Specification | `spec` | `theorem`, `axiom` |
| Proof | `proof` | No separate kind. The proof is the body of a `theorem`. |
| Type definition | none | `class`, `structure`, `inductive`, `quot` |

## Atom fields (`probe-lean/extract`)

Every atom carries every field below unless the type says "or absent". The Source column says
where the value comes from: auto (computed from the environment), config
(`.verilib/probes/config.json`), or attribute (a Lean attribute on the declaration).

| Field | Type | Source | Description |
|-------|------|--------|-------------|
| `display-name` | string | auto | Last component of the name. |
| `kind` | string | auto | Declaration kind, see above. |
| `language` | string | auto | Always `"lean"`. |
| `dependencies` | array | auto | The union of `type-dependencies` and `term-dependencies`. See [Dependency arrays](#dependency-arrays). |
| `type-dependencies` | array | auto | `probe:` names inside the module filter that the type signature mentions. Folding never adds here. |
| `term-dependencies` | array | auto | `probe:` names inside the module filter that the body or proof mentions, plus names the fold recovers. See [Auxiliary-dependency folding](#auxiliary-dependency-folding). |
| `type-dependencies-external` | array or absent | auto | `probe:` names outside the module filter that the type mentions directly. Absent when empty. |
| `term-dependencies-external` | array or absent | auto | Same for the body or proof. |
| `code-module` | string | auto | Module containing the declaration. For a merged declaration, see [Dependency arrays](#dependency-arrays). |
| `code-path` | string | auto | Source path relative to the project root. |
| `code-text` | object or null | auto | `{ "lines-start": N, "lines-end": N }`. |
| `is-in-package` | bool | auto | Always `true`: probe-lean extracts only the project's own modules. Kept as a generic signal. |
| `is-relevant` | bool | auto / config | See [Relevance](#relevance). |
| `is-hidden` | bool | auto / config | See [Generated-code hiding](#generated-code-hiding). |
| `is-lean-generated` | bool | auto | Core-Lean output: `deriving`-generated instance clusters and structure or class projections. |
| `is-aeneas-generated` | bool | config + auto | Exists only because of Aeneas, see [Generated-code hiding](#generated-code-hiding). |
| `is-ignored` | bool | config | From the config's `is-ignored` list. Always an editorial decision. |
| `is-primary-spec` | bool | attribute | The declaration carries `@[primary_spec]`. This means tagged, not chosen, see [Specs and primary-spec](#specs-and-primary-spec). |
| `attributes` | array or absent | attribute | Lean attributes on the declaration. Absent when empty. Not evidence of trust, see [Attributes](#attributes). |
| `rust-source` | string or null | auto | Path from an Aeneas docstring's `Source: 'path'` line. probe-lean reads the declaration's own docstring first, then the docstring of its sibling `<name>_body`. |
| `specs` | array or absent | auto | Theorem atoms whose statement mentions this atom. Absent when empty. An atom is "specified" when `specs` is non-empty. |
| `primary-spec` | string or absent | auto | The primary specification theorem, see [Specs and primary-spec](#specs-and-primary-spec). |
| `verification-status` | string or absent | auto | One of the five values in [Verification status](#verification-status-and-the-trusted-base). |
| `trusted-reason` | string or absent | auto | Only when `verification-status` is `"trusted"`: `"axiom"`, `"externally_verified"` or `"external"`. A member of T whose statement rests on a project `sorry` has none. |
| `status-origin` | string or absent | auto | `"kernel-taint"` on an atom that reads `"verified"` because the walk found a reachable project `sorry`, a member of T with a tainted statement included. See [Re-deriving statuses](#re-deriving-statuses). |
| `codomain-head` | string or absent | auto | Head constant of the result type after stripping `∀`/`→` binders, if it is a constant. |
| `codomain-is-prop` | bool | auto | The result type is `Sort 0`. |
| `codomain-last-arg-is-bool` | bool | auto | The final application argument of the result type is `Bool`. |

### Dependency arrays

The module filter is every project module, or the `--module`/`--library` selection.
`dependencies` is exactly the union of `type-dependencies` and `term-dependencies`. Deduplication
uses declaration identity before private mangling is stripped. Two distinct private declarations
that print to the same name can therefore both appear. This is permitted and silent, and
`tools/audit/compare-extract.py` reports it as a diagnostic.

`type-dependencies` is exactly the signature, so `specs` and `primary-spec` derive from it. The
`*-external` arrays list Mathlib, core, other packages, and, under `--module`/`--library`, the
project's own unselected modules. They hold direct references only. An external constant reached
only through an auxiliary is not listed, and neither is one the internal-name filter drops
(`Nat.rec`, `Foo.mk`).

Several project modules can declare the same name (a merged declaration). Then all four split
arrays hold the edges of every version, see
[merged declarations](verification-status.md#merged-declarations). `code-module` is the module
that Lean's importer attributes the name to. If that module is outside the `--module`/`--library`
selection, or registers no declaration range, `code-module` is the first selected declaring module
that registers one. `code-path` and `code-text` follow `code-module`.

### Relevance

When the config has no `relevant-crate`, `is-relevant` is `true` for every atom. When it has one,
an atom without a `rust-source` reads `false`. Any other atom reads `true`
only under three conditions: its source contains the crate name, does not start with `/`, and
does not contain `/cargo/registry/`.

### Generated-code hiding

probe-lean sets `is-hidden` from the config's `is-hidden` list, and also on auto-detected
generated atoms: `deriving` clusters, projections, and `@[step]` companions. Atoms that match a
config suffix are flagged generated but not hidden.

Two kinds of atom are `is-aeneas-generated`. The first has a name that ends with a suffix in the
config's `extraction-artifact-suffixes`. The second is the companion theorem `X.mvcgen_spec` that
Aeneas's `@[step]` adds next to a tagged `theorem X`.

After transitive enrichment, `extract` clears `is-hidden` on contaminated generated atoms. A
contaminated generated atom reads `"verified"`, `"unverified"` or `"failed"`. This lets consumers
of `extract` output trace a taint through these atoms. Clean and trusted generated
atoms stay hidden. `--skip-enrich` skips this step. `viewify` drops all generated atoms
regardless.

The editorial flags (`is-hidden`, `is-lean-generated`, `is-aeneas-generated`, `is-ignored`) are a
backward-compatible convenience. In the recommended pipeline for Aeneas projects, probe-aeneas
computes them from the generic facts that probe-lean provides (`attributes`, name patterns,
`rust-source`).

### Attributes

probe-lean's own handle supplies `primary_spec`. A lexer-aware scan supplies every other name
(`step`, `progress`, `simp`). The scan reads only the `@[…]` blocks in the declaration's header. A tag
quoted in a docstring, comment, string or neighbouring declaration is not attributed.
If the header scan finds `externally_verified`, or the declaration is in the attribute's tag set
read from the environment, the array lists it. A tag attached by an `attribute` command therefore
shows here too.

A constant that shares a tagged declaration's range shows the parent's scanned tags,
`externally_verified` included. Examples are a generated companion, a `deriving` instance, and a
projection of a one-line `structure`. So this array is not evidence of trust. Read
`trusted-reason`.

### Codomain facts

The `codomain-*` fields are neutral primitives. probe-lean does not classify declarations. A
downstream tool reconstructs the codomain shape from them plus its own catalogue. The envelope
carries no `classification` object and no `source.class` field.

### Specs and primary-spec

`specs` lists the theorem atoms whose `type-dependencies` include this atom. A constant that a
theorem uses only in its proof is not something the theorem specifies. One exception exists. If a
`@[primary_spec]` theorem's statement mentions no specifiable constant, probe-lean reads the
theorem's `dependencies` instead. If that array names exactly one specifiable constant, the tag
attaches to it. With several, the tag attaches to nothing. Generated theorems are excluded. A
generated theorem tagged `@[primary_spec]` is the exception.

`primary-spec` picks one theorem from `specs`, by this precedence:

1. a theorem tagged `@[primary_spec]`.
2. a theorem with a verification-framework attribute (`@[progress]`, `@[pspec]`, `@[step]`), only
   when exactly one theorem in `specs` has one.
3. the theorem named exactly `<def>_spec`, where `<def>` is the atom's own name.
4. the only theorem in `specs`.

If several `@[primary_spec]` theorems target one atom, the tie-break is arbitrary and `extract`
prints a warning on stderr. The other tagged theorems stay in `specs` with `is-primary-spec: true`.
Signals 2 to 4 pick a theorem without tagging it, so the winner's own `is-primary-spec` can be
`false`. A tagged non-theorem reads `true`. A tagged theorem that the inference attaches to no
target (issue #104) also reads `true`. To find a target's tagged candidates, intersect its `specs`
with this flag.

## Verification status and the trusted base

A kernel walk decides `verification-status`. The build log and the emitted graph do not.
`sorry` elaborates to the `sorryAx` axiom. The walk follows the constant graph of every constant of
every built project module (the set P), atoms or not. It stops at two boundaries:

- the project boundary. Lean and every dependency package in `lake-manifest.json` are trusted
  wholesale.
- the proof of each member of the trusted base T inside the project, defined by the three rules
  below. The walk still follows the statement of a member of T.

| Status | Meaning |
|--------|---------|
| `"trusted"` | In T, and its statement does not rest on a project `sorry`. `trusted-reason` says why. |
| `"unverified"` | The declaration's own type or value names `sorryAx` (a direct carrier). For a member of T, only its type counts. |
| `"verified"` | Locally sorry-free, but an unexcused project `sorry` is reachable from it. |
| `"transitively-verified"` | No project `sorry` is reachable except through the proof of a trusted declaration ("clean modulo T"). |
| `"failed"` | Currently never produced. |

Under `--skip-enrich`, atoms that are clean modulo T read `"verified"`, and
`"transitively-verified"` never appears. Under `--skip-verify`, only the atoms that read
`"trusted"` get a status, and no atom gets `status-origin`. An atom whose name is not in P gets no status, and
`extract` prints a warning.

The trusted base, one shared rule set (`ProbeLean/Trust.lean`) in precedence order:

1. `"axiom"`: the Lean `axiom` keyword, generated `native_decide` axioms included.
2. `"externally_verified"`: the declaration is in the `externally_verified` attribute's tag set,
   read from the environment however the tag was attached. Nothing that merely shares a tagged
   declaration's source range is in the set.
3. `"external"`: a non-proof (not a theorem, and not Prop-typed) in a module whose name ends with
   `External`, trusted as a model whatever its type.

Trust excuses a declaration's proof, not its statement. The walk follows the type of a trusted
declaration and not its value. For a trusted inductive type or structure, it also follows the
constructors. A `sorry` in its proof or below it does not taint its callers. If
its statement rests on a project `sorry`, it reads `"unverified"` or `"verified"` like any other
declaration, without `trusted-reason`. See
[verification-status.md](verification-status.md#the-walk). Two more consequences a
consumer must know:

- Attribution is per kernel constant. On Lean ≤ 4.28 a `def`'s sorried proof obligation is
  abstracted into `f._proof_1`, so `f` reads `"verified"`. From 4.29 the `sorry` stays inline and
  `f` reads `"unverified"`. On every toolchain `f` is tainted.
- The walk follows kernel dependencies, not executable bodies. A `sorry` in a `partial def` body
  or in an `@[implemented_by]` target does not taint the host. A `native_decide` proof rests on a
  trusted generated axiom.

The scope and limits of each rule, module coverage, merged declarations and the cross-checks are
in [verification-status.md](verification-status.md).

### Re-deriving statuses

The emitted graph does not always show why an atom is tainted. A carrier with no declaration
range, or a `def`'s abstracted `f._proof_1`, is not an atom. A consumer that recomputes
`"transitively-verified"` from the dependency arrays (hub probe's enrichment) then promotes the
atom or its callers. So every atom from the walk's tainted branch carries
`"status-origin": "kernel-taint"`, also under `--skip-enrich`. Direct carriers read
`"unverified"` and carry no marker.

A consumer must never promote a marked atom. It must also not promote an atom that reaches a marked
atom through non-trusted dependencies. An unmarked `"verified"` atom is clean modulo T and reads
`"verified"` only because of the `--skip-enrich` cap, so a consumer can promote it. Extracts older
than probe-lean 0.16.0 have no marker and must be re-extracted, not re-enriched.

## Auxiliary-dependency folding

Lean abstracts embedded proofs and match arms into auxiliary constants (`X._proof_N`,
`X.match_N`, tactic-generated helpers). probe-lean does not emit these as atoms. Without folding,
`host → aux → lemma` leaves no trace of `lemma` (issue #99). `extract` folds the edges under such
auxiliaries into the referencing declaration. This is the authoritative statement of the
invariant. The copies in `ProbeLean/Analysis.lean` and `tools/audit/compare-extract.py` quote it:

> The fold only ever adds names to `term-dependencies`. It never adds to `type-dependencies`,
> never removes an entry from any of the four dependency arrays, never adds to the `*-external`
> arrays, and never changes the atom set.

A recovered edge always lands in `term-dependencies`, also for an auxiliary in the type. Folded
entries are indirect: `term-dependencies` holds what the body names plus what the declaration
reaches through auxiliaries. Use `dependencies` for reachability and `type-dependencies` as the
exact signature.

The fold traverses two classes of value-bearing (`def`, `theorem`, `opaque`) constants. The first
is constants that the name filter (`isInternalName`) drops. The second is project constants with
no declaration range. It does not
traverse structural members, axioms, inductives, constructors, recursors, `Quot`, or emitted atoms.
The structural-member suffixes are the literal list `autoGeneratedSuffixes` in
`ProbeLean/Analysis.lean`. A higher-index equation lemma such as `f.eq_4` matches no entry, so the
fold treats it like any other constant. A direct reference keeps its usual place: the name filter,
not the fold, decides whether it is listed.

A folded target is any project constant that survives the name filter and has a declaration
range. That is every atom plus named inductive constructors such as `Color.red`. Constructors are
never atoms, so a folded name is not always a key in `data`. Only project targets are folded. An
external constant reached only through an auxiliary is not listed anywhere, because a single
`by omega` reaches about 50 `Lean.Omega.*` constants.

`type-dependencies` never grows, so type-driven spec selection is unaffected. One fallback reads
`dependencies`: a `@[primary_spec]` theorem whose statement names no specifiable constant. A
folded edge can add a second candidate there and detach the tag.

Folding recovers edges, not nodes. It does not bear on `verification-status`, which the kernel walk
decides. It covers compiled-environment reachability only. Notation, macros, attributes and
elaboration-time instances leave no constant reference, so a zero in-degree is not a licence to
delete a declaration from the sources.

## Molecules (`probe-lean/viewify`)

`viewify` reads `extract` output. It keeps an atom when four conditions hold: the atom is not
hidden, it is neither lean- nor aeneas-generated (whatever `is-hidden` says), it is relevant, and
its `code-path` ends with `Funs.lean`. `data` is keyed by `<code-path>/<name_last>`. When two kept atoms share that key,
both use `<code-path>/<name>` instead, where `<name>` is the full name without `probe:`.

| Field | Type | Description |
|-------|------|-------------|
| `code-path` | string | The atom's `code-path` |
| `code-lines` | string or null | The atom's line range as `"start-end"` |
| `code-name` | string | The atom's code-name |
| `rust-path` | string | Always `""`. `rust-source` is not consulted. |
| `rust-lines` | object | Always `{ "lines-start": 0, "lines-end": 0 }` |
| `rust-name` | string | Always `""` |
| `spec-path` | string | The atom's own `code-path`, not its `primary-spec`'s |
| `spec-lines` | string or null | Always `null` |
| `spec-name` | string | The atom's own code-name, not its `primary-spec` |

The `rust-*` and `spec-*` fields are placeholders kept for the consumer's shape. Nothing in
`viewify` fills them from `rust-source` or `primary-spec`.
