# Classifying VCVio security-protocol projects

Cryptographic security protocols formalised in Lean on top of
[VCV-io](https://github.com/Verified-zkEVM/VCV-io) share a recurring shape: an abstract
**scheme** (a bundle of algorithms), one or more concrete **constructions** that realise it,
and **correctness** and **security** properties proved about those constructions. probe-lean
classifies the declarations of such a project into these four categories so that a downstream
consumer can present them as a `scheme → construction → {correctness, security}` hierarchy.

This document describes how that classification is performed and catalogues the symbols and
patterns it relies on. It is specific to the `security-protocol` class (projects that depend on
VCVio); other project classes are handled separately.

## The four categories

| category | What it is | Lean construct | Examples |
|---|---|---|---|
| **scheme** | the abstract interface — a bundle of operations | `structure`/`class` | `CKAScheme`, `AEADScheme`, `SymmEncAlg` |
| **construction** | a concrete instance of a scheme | `def` returning a scheme | `ddhCKA` |
| **correctness** | a functional-correctness property | `Prop`/game + the theorem proving it | `AEADScheme.Correct`, `correctnessExp`, `Pr[correctnessExp wins] = 1` |
| **security** | a security property (advantage bound) | probabilistic game + the theorem bounding advantage | `securityExp`, `securityAdvantage` |

Each classified declaration is annotated with its `category` and with `via`, recording **how**
the category was determined: `attribute`, `type`, or `naming` (defined next). A declaration
that matches none of the four categories — invariant lemmas, helper definitions, game state
records — is left unclassified (no annotation).

Classification is applied only to a project's **own** declarations — imported declarations (from
VCVio, Mathlib, …) never receive a `classification`. They may, however, be *referenced* as
anchors. Because the anchors are typically imported VCVio symbols, the classifier must read the
**full environment dependencies** of each declaration, not the project-filtered `dependencies`
array that appears in the output (which omits imported constants). In other words classification
runs inside the analysis pass over raw dependency data, **not** as a post-pass over the emitted
atoms — otherwise imported anchors such as `SecExp` would be invisible.

## How classification works

Three signals are consulted, in decreasing order of reliability. The first that applies wins,
and the signal used is recorded in `via`.

### Attributes (`via: attribute`) — authoritative

A project may tag declarations explicitly. These tags are the ground truth and override every
other signal:

| Attribute | category |
|---|---|
| `@[scheme_def]` | scheme |
| `@[construction_def]` | construction |
| `@[correctness_spec]` | correctness |
| `@[security_spec]` | security |

Tagging is optional and incremental — a single line per declaration. It is the recommended way
to pin down anything the heuristics below get wrong or cannot see.

**Registration.** Lean will not compile `@[scheme_def]` (etc.) unless the attribute is
*registered* by some module the project imports. These attributes are registered in
probe-lean's attribute module (`ProbeLean.Attrs`), following the same pattern as `@[primary_spec]`,
so a project that wants to tag its declarations imports that module (taking a dependency on
probe-lean) and adds the tags. probe-lean then detects the tags directly from the built project —
handle-based from the environment, with a source scan of `@[…]` annotations as a fallback — and
never edits the project.

So in an **unattended verilib run, attributes only apply to projects that have already adopted
them**; for every other project, classification falls back to the *type* and *naming* signals.

If a declaration carries **conflicting tags** (e.g. both `@[correctness_spec]` and
`@[security_spec]`), or a tag whose category is incompatible with its kind (e.g. `@[scheme_def]`
on a `theorem`), the classifier emits a diagnostic and leaves the declaration unclassified rather
than guessing.

### Framework types (`via: type`) — structural inference

When no attribute is present, probe-lean infers the category from the Lean type structure. All
conditions below are in addition to the precondition in *How classification works* (own
declaration only).

#### Scheme

> A **scheme** is the *syntactic interface of a cryptographic primitive* — a `structure`/`class`
modelling a tuple of algorithms.

There is **no *type* signal for schemes.** Schemes are project-defined and vary too much to infer
reliably from the type structure — they share no common VCVio base (e.g. `CKAScheme`, `AEADScheme`
`extend` nothing), and "a structure that bundles operations" also matches adversaries, oracle
handlers, and operation-bundling classes. So a scheme is recognised only by an explicit
`@[scheme_def]` attribute, or by the **naming** fallback (below). Schemes that are not named
conventionally (e.g. PQXDH's `AEAD`/`KEM`/`KDF`/`Sig`, KVAC's `AlgebraicMAC`) are **not**
auto-detected and must carry `@[scheme_def]`.

#### Construction

- **kind** is `def` (or an `abbrev`/`instance` producing a `class`-style scheme).
- its **return-type head** (the head symbol of the type after stripping binders) is a scheme —
  either a project-own structure already classified as a scheme, or a VCVio scheme from the
  catalogue below. e.g. `ddhCKA : … → CKAScheme …` has return-type head `CKAScheme`.
- this signal can **over-match**: generic builders, adapters, and test fixtures that also return a
  scheme are caught too. Return-head recovery is also approximate — it must see through reducible
  `abbrev`s, `instance` resolution, and class inference. Such cases are best pinned with
  `@[construction_def]`.

#### Correctness

- a `theorem`, or a `Prop`/game `def`.
- its **statement reaches a correctness anchor** (below). Matching starts from the declaration's
  **type-dependencies** (the statement), *not* its proof/body — so a proof that merely *uses* a
  correctness lemma does not make an unrelated theorem "correctness". From the statement the walk
  descends into the bodies of *game/experiment definitions* only, because a headline theorem names
  the game rather than the anchor (e.g. `Pr[= true | correctnessExp ddhCKA] = 1` names
  `correctnessExp`, whose body in turn reaches the anchor).

#### Security

- a `theorem`, or a game `def`.
- its **statement reaches a security anchor** (below), by the same type-dependency-rooted,
  descend-into-games walk as correctness.

**Walk semantics (both):** the walk is **bounded** — a fixed maximum depth plus a visited-set;
cycles and the bound both terminate it, leaving the atom *unclassified* rather than hanging.
"Nearest anchor wins" means the smallest number of hops; **a tie is left unclassified**. In
particular, when a statement reaches *both* a correctness and a security anchor (e.g.
`correctness_implies_security`), neither dominates and the atom is left unclassified — resolve
such cases with `@[correctness_spec]` / `@[security_spec]`.

### Naming conventions (`via: naming`) — last-resort fallback

Used only when neither an attribute nor a type signal applies. Matches the declaration's **own
name** against conventional patterns (no dependency walking).

#### Scheme

- **own name** matches `*Scheme` or `*Alg` (suffix).
- **guard 1**: kind is `structure` or `class` — a `def`/lemma merely *named* `…Scheme` is not a
  scheme (a `def` returning a scheme is a *construction*; the scheme is the interface *type*, not
  a value).
- **guard 2**: not Mathlib algebra — `AlgHom`, `AlgEquiv`, `BialgHom`, `AddMonoidAlgebra`,
  `Algebra`, `Subalgebra`, `BoolAlg`, … all contain `Alg` but are not schemes.
- this is the weakest scheme signal and is easily superseded by `@[scheme_def]`.

> The `Alg` exclusion is needed precisely *because* the scheme naming signal keys on `*Alg`
(VCVio schemes are named `SymmEncAlg`, `MacAlg`, …), which collides lexically with Mathlib's
algebra hierarchy. Other Mathlib names (`Finset`, `Matrix`, `Polynomial`, …) do not match
`*Scheme`/`*Alg`, so they never trigger this rule — and imported Mathlib is excluded anyway by
the own-declarations-only filter. The `Alg` guard is the backstop for projects that vendor or
redefine algebra-named structures in their *own* package.

#### Construction

- **Not applicable** — there is no reliable naming convention for constructions; they are
  detected only by the *type* signal (return-type head). A construction is therefore never
  classified `via: naming`.

#### Correctness

- **own name** matches `…_correct…`, `…Correct`, `…Complete`, or `correctnessExp`.
- **guard**: kind is `theorem` or a `Prop`/game `def` — not a `structure`, `class`, `inductive`,
  `instance`, or `axiom` (a data structure merely *named* `…Correct` is not a correctness
  property). Note Lean `lemma`s are emitted as kind `theorem`, so they are covered.

#### Security

- **own name** matches `*Advantage`, `*Adv`, `…_secur…`, or `securityExp…`.
- **guard**: kind is `theorem` or a `Prop`/game `def` — not a `structure`, `class`, `inductive`,
  `instance`, or `axiom` (a data record merely *named* `…Advantage` is not a security property).

## Built-in anchor and type catalogue

probe-lean ships with the stable **VCVio** symbols below baked in, so the *type* signal works on a
VCVio project with no project-specific setup. These are VCVio symbols only — a project's *own*
property definitions (e.g. secure-messaging's `correctnessExp`, `securityExp`, `ckaSecuritySpec`)
are **not** in this catalogue; they are reached either transitively (a project game whose body
reaches a catalogued VCVio anchor) or, failing that, by the *naming* fallback / attributes. This
is why the examples elsewhere use lowercase project-local names like `correctnessExp` while the
tables below list the VCVio anchors (`CorrectExp`, `SecExp`, …).

To avoid collisions, catalogued anchors are matched by **fully-qualified name** (or VCVio module
prefix) — *not* by bare last component. Names like `advantage`, `Correct`, and `Complete` are far
too generic to match on the last component alone (they would hit unrelated project-local
declarations). The reachability walk looks for a dependency whose fully-qualified name is one of
the catalogued VCVio symbols.

### VCVio correctness anchors

| Symbol | Kind |
|---|---|
| `Correct`, `Complete` | `def … : Prop` (predicate form) |
| `CorrectExp`, `CompleteExp` | `def … : m Bool` (game form) |

### VCVio security anchors

| Symbol | Kind |
|---|---|
| `SecExp`, `SecurityExp`, `SecurityGame` | `structure` (experiment) |
| `advantage`, `bindingAdvantage`, `hidingAdvantage`, `owfAdvantage`, `prfAdvantage`, `prgAdvantage`, `tdpAdvantage`, `preimageFindingAdvantage`, `ddhDistAdvantage`, `ddhGuessAdvantage` | `def` (advantage) |

### VCVio scheme anchors

Algorithm-bundling interfaces defined in VCVio's `CryptoFoundations/`: `SymmEncAlg`,
`AsymmEncAlg`, `MacAlg`, `KEMScheme`, `DEMScheme`, `SignatureAlg`, `PRFScheme`, `PRGScheme`,
`CommitmentScheme`, `SigmaProtocol`, `IdenSchemeWithAbort`, `TrapdoorPermutation`,
`PreimageSampleableFunction`, `GenerableRelation`.

This list has a **single role: construction detection.** It is the set of VCVio scheme types that
count as a valid **construction return-type head** — so a `def` returning one of them directly
(e.g. `def myEnc : AsymmEncAlg … := …`) is recognised as a construction, alongside `def`s
returning a project's own scheme. Matching is by exact name on the return-type head, so it cannot
over-match.

> **NOTE:** It is **not** a scheme-*classification* input: these symbols are imported and are never classified
as scheme atoms themselves (only project-own declarations are classified — schemes via
`@[scheme_def]` or the naming fallback). In practice protocol projects define and return their
**own** schemes, so this catalogue only matters when a construction returns a VCVio scheme
directly.

## Output schema

Classification is additive to the existing extract output: existing fields are unchanged, and
two new fields are introduced:

- envelope **`source.class`** — the detected project class, `"security-protocol"` here. Absent
  when no class is detected.
- per-atom **`classification`** — an object `{ "category": …, "via": … }` where `category` is one
  of `scheme` / `construction` / `correctness` / `security` and `via` is `attribute` / `type` /
  `naming`. **Absent** (not `null`) when the atom is unclassified.

No existing field changes; `verification-status` and the rest are emitted as before. When no
class is detected, neither field appears and the output is unchanged. (Lean keyword note: the
envelope field is `sourceClass` in code, serialised to the JSON key `class`.)

```json
{
  "schema": "probe-lean/extract",
  "source": {
    "repo": "https://github.com/Beneficial-AI-Foundation/secure-messaging",
    "language": "lean",
    "package": "SecureMessaging",
    "class": "security-protocol"
  },
  "data": {
    "probe:SecureMessaging.CKA.Defs.CKAScheme": {
      "display-name": "CKAScheme",
      "kind": "structure",
      "verification-status": "verified",
      "classification": { "category": "scheme", "via": "attribute" }
    },
    "probe:SecureMessaging.CKA.FromDDH.Construction.ddhCKA": {
      "display-name": "ddhCKA",
      "kind": "def",
      "dependencies": ["probe:SecureMessaging.CKA.Defs.CKAScheme"],
      "verification-status": "transitively-verified",
      "classification": { "category": "construction", "via": "type" }
    },
    "probe:SecureMessaging.CKA.FromDDH.Correctness.correctness": {
      "display-name": "correctness",
      "kind": "theorem",
      "dependencies": [
        "probe:SecureMessaging.CKA.Defs.correctnessExp",
        "probe:SecureMessaging.CKA.FromDDH.Construction.ddhCKA"
      ],
      "verification-status": "verified",
      "classification": { "category": "correctness", "via": "attribute" }
    },
    "probe:SecureMessaging.CKA.FromKEM.Security.security_reduces_to_ind_cpa_exists": {
      "display-name": "security_reduces_to_ind_cpa_exists",
      "kind": "theorem",
      "dependencies": ["probe:SecureMessaging.CKA.Defs.securityExp"],
      "verification-status": "unverified",
      "classification": { "category": "security", "via": "naming" }
    },
    "probe:SecureMessaging.CKA.FromDDH.Correctness.reachableInv_init": {
      "display-name": "reachableInv_init",
      "kind": "theorem",
      "verification-status": "verified"
    }
  }
}
```

(`reachableInv_init` carries no `classification` key — an unclassified helper lemma.)

A consumer reconstructs the `scheme → construction → {correctness, security}` hierarchy by walking
the existing `dependencies` edges: a correctness/security atom links to its construction, and the
construction to the scheme it returns. 

**Caveat:** `dependencies` are referenced constants, not
application edges, so this relies on the property's *statement* actually naming its construction —
which it usually does (the construction appears as an argument), but is not guaranteed. A property
that is generic over constructions, or that names only a game and not the construction, cannot be
linked from dependencies alone. If validation shows this is common, probe-lean may need to emit
**explicit** construction/scheme links rather than leaving the join to the consumer's graph walk
(tracked as an open question for the verilib contract).

## Reliability and limitations

- **Schemes** are auto-detected only by the naming convention (`*Scheme`/`*Alg`, with the
  structure-kind and Mathlib-algebra guards). Schemes named otherwise — PQXDH's `AEAD`/`KEM`/
  `KDF`/`Sig`, KVAC's `AlgebraicMAC` — are **not** auto-detected and must carry `@[scheme_def]`.
  This is a deliberate trade-off: schemes vary too much to infer from the type structure without
  over-matching, so the contract is "tag the schemes that aren't conventionally named."
- **Constructions** depend on schemes being identified first — a construction is detected by its
  return type being a scheme. If a scheme is missed, its constructions are missed too.
- If a construction returns a **VCVio scheme directly** (rather than a project-own scheme), the
  construction itself is still classified (it's a project-own `def`), but the **returned scheme**
  is an imported VCVio symbol — so that scheme is never classified and isn't emitted as an atom at
  all. The accordion would then have a construction with no scheme atom above it to nest under.
  The surveyed projects define their own schemes, so this does not arise in practice, but the
  verilib contract should decide how to render such a case.
- **Correctness vs security** at the theorem level relies on reaching the right anchor;
  stepping-stone lemmas that pass through a game can be tagged by reachability, so the walk is
  bounded and prefers the nearest anchor. `@[correctness_spec]` / `@[security_spec]` resolve any
  remaining ambiguity.
- When VCVio renames or moves a baked-in symbol, the *type* signal for that symbol silently
  stops matching until the catalogue is updated; diagnostics should log which anchors matched so
  drift is visible.

### Open decisions

- **Hierarchy join.** Whether the `property → construction → scheme` join is left to the
  consumer's dependency walk or emitted as explicit links (see the caveat under *Output schema*).
- **Schema docs.** `docs/SCHEMA.md` and the test suite must be updated to declare `source.class`
  and the per-atom `classification` object as optional fields when this is implemented.
