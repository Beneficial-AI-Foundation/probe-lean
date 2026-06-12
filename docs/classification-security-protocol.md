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

Each classified declaration is annotated with its `category`, with `via` — recording **how** the
category was determined: `attribute`, `type`, or `naming` (defined next) — and, where resolvable,
with explicit **links** to the construction and scheme it is about (see *Output schema*). A
declaration that matches none of the four categories — invariant lemmas, helper definitions, game
state records — is left unclassified (no annotation).

Classification is applied only to a project's **own** declarations — imported declarations (from
VCVio, Mathlib, …) never receive a `classification`. They may, however, be *referenced* as
anchors. Because the anchors are typically imported VCVio symbols, the classifier must read the
**full environment dependencies** of each declaration, not the project-filtered `dependencies`
array that appears in the output (which omits imported constants). In other words classification
runs inside the analysis pass over raw dependency data, **not** as a post-pass over the emitted
atoms — otherwise imported anchors such as `SecExp` would be invisible.

## How classification works

For each declaration, three signals are consulted in decreasing order of reliability; the first
that applies wins, and the signal used is recorded in `via`.

Classification runs as a **staged pipeline**, because later categories depend on earlier ones:

1. **schemes** — needed before constructions can be detected;
2. **constructions** — detected by their return type being a scheme;
3. **property definitions** — games, correctness predicates, advantage definitions. Project-own
   property definitions classified in this stage are **promoted into the anchor set** (see the
   promotion rule under *Correctness/Security* below);
4. **theorems** — classified by walking their statements to the nearest anchor (catalogued or
   promoted).

The staging only fixes *when* each kind of declaration is classified — it does **not** force every
theorem through a game: a theorem may reach a predicate anchor (`…Correct`) or an advantage
definition directly, or be classified purely by attribute/naming with no anchor at all.

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
*registered* by some module the project imports. These attributes belong in
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

- a `theorem`, or a property-shaped `def` — a predicate (`Prop`-valued), a game (monadic-`Bool`
  return-type head), or an advantage definition (real-/`ℝ≥0∞`-valued).
- its **statement reaches a correctness anchor**. Matching starts from the declaration's
  **type-dependencies** (the statement), *not* its proof/body — so a proof that merely *uses* a
  correctness lemma does not make an unrelated theorem "correctness".

#### Security

- a `theorem`, or a property-shaped `def` (predicate, game, or advantage definition — as above).
- its **statement reaches a security anchor**, by the same type-dependency-rooted walk as
  correctness.

#### Anchors, the promotion rule, and the walk (both categories)

**The anchor set = the catalogued VCVio anchors (below) ∪ promoted project-local property
definitions.** The catalogued VCVio anchors alone are *not* enough: empirically, project games
are hand-rolled — e.g. secure-messaging's `correctnessExp`/`securityExp` are plain
`ProbComp Bool` definitions built from `simulateQ` and project-local oracles, whose bodies never
reference `SecExp`, `CorrectExp`, or any catalogued advantage. A walk that only targets VCVio
anchors therefore dead-ends and classifies almost nothing.

**Promotion rule:** when the *property-definitions* stage of the pipeline classifies a
project-own game, predicate, or advantage definition as correctness/security — by any of the
three signals (attribute, type, or naming; e.g. `correctnessExp` matches the `*correct*` naming
pattern) — that definition is **added to the anchor set, in memory, for the remainder of the
run**. A theorem whose statement reaches a promoted anchor counts as
reaching an anchor of that category. No external file or configuration is involved; the anchor
set is rebuilt from the catalogue + the project's own classified definitions on every run.

To keep the result independent of declaration order, the property-definitions stage runs as two
sub-passes: first the **anchor-independent signals** (attribute and naming) classify and promote;
then the **type signal** classifies the remaining property definitions against the anchor set,
**iterated to a fixed point** (a newly classified definition is promoted and may classify
further ones). The anchor set only grows, so the fixed point is the same whatever order
declarations are visited in; iteration is bounded by the number of declarations.

**Provenance (weakest-tier inheritance):** a theorem classified through a *promoted* anchor
inherits the **weakest signal in its chain** as its `via` — e.g. a theorem anchored on
`correctnessExp` (itself classified `via: naming`) is emitted with `via: naming`, not
`via: type`. This keeps the provenance honest: the walk was structural, but the anchor underneath
was a naming inference, and a false-positive anchor name would otherwise confidently mislabel
every theorem above it as structurally classified. A theorem anchored on a *catalogued VCVio*
anchor keeps `via: type` (nothing heuristic in its chain), and an anchor pinned with an attribute
upgrades the whole chain (theorems above it are then genuinely `via: type`).

**Descent gate:** a headline theorem may name an intermediate definition rather than an anchor.
The walk descends into the bodies of **game-shaped definitions only** — operationally, a `def`
whose return-type head (after stripping binders) is a monadic `Bool` computation (e.g.
`ProbComp Bool`, `OracleComp _ Bool`). This gate is purely structural, so it involves no
circularity with classification; it exists for unconventionally-named intermediate games. Note
that advantage definitions need no descent shape: they are typically anchors *themselves*
(promoted via the `*advantage*` naming pattern), so the walk ends at them rather than stepping
through them.

**Walk semantics:** the walk is **bounded** — a fixed maximum depth plus a visited-set; cycles
and the bound both terminate it, leaving the atom *unclassified* rather than hanging. "Nearest
anchor wins" means the smallest number of hops; **a tie is left unclassified**. In particular,
when a statement reaches *both* a correctness and a security anchor at equal distance (e.g.
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

- **own name** contains `correct` or `complete` (case-insensitive substring — `*correct*` /
  `*complete*`).
- **guard**: kind is `theorem` or a property-shaped `def` (predicate, game, or advantage
  definition) — not a `structure`, `class`, `inductive`, `instance`, or `axiom` (a data structure
  merely *named* `…Correct` is not a correctness property). Note Lean `lemma`s are emitted as
  kind `theorem`, so they are covered.

#### Security

- **own name** contains `secur` or `advantage` (case-insensitive substring — `*secur*` /
  `*advantage*`), or ends with `Adv` (suffix; the bare substring `adv` would over-match words
  like "advance").
- **guard**: kind is `theorem` or a property-shaped `def` (predicate, game, or advantage
  definition — this explicitly admits numeric `…Advantage` defs, which are the anchors the
  promotion rule depends on) — not a `structure`, `class`, `inductive`, `instance`, or `axiom`
  (a data record merely *named* `…Advantage` is not a security property).

Patterns are deliberately loose **substrings** rather than anchored affixes: real corpus names
defeat affix patterns — the flagship theorems are named bare `correctness`
(`CKA/FromDDH/Correctness.lean`, no underscore, no capital) and
`security_reduces_to_ind_cpa_exists` (starts with "security", so `…_secur…` never matches). The
kind guards and the attribute override carry the precision burden.

## Built-in anchor and type catalogue

probe-lean ships with the stable **VCVio** symbols below baked in, so the *type* signal works on a
VCVio project with no project-specific setup. These are VCVio symbols only — a project's *own*
property definitions (e.g. secure-messaging's `correctnessExp`, `securityExp`, `ckaSecuritySpec`)
are **not** in this catalogue; they enter the anchor set via the **promotion rule** above, once
classified by attribute, type, or naming. This is why the examples elsewhere use lowercase
project-local names like `correctnessExp` while the tables below list the VCVio anchors
(`CorrectExp`, `SecExp`, …).

To avoid collisions, catalogued anchors are matched by **fully-qualified name** — *not* by bare
last component. Names like `advantage`, `Correct`, and `Complete` are far too generic to match on
the last component alone (they would hit unrelated project-local declarations). The reachability
walk looks for a dependency whose fully-qualified name is one of the catalogued VCVio symbols, or
a promoted project-local anchor.

The tables below display the **final name component for readability only**; the implementation
catalogue stores the fully-qualified names (the symbols live in the namespaces of their defining
structures, e.g. `SymmEncAlg.Complete`, `AsymmEncAlg.Correct`, `PRFScheme.prfAdvantage`). The
exact fully-qualified enumeration is fixed during implementation against the targeted VCVio
version — and policed thereafter by the drift diagnostic below.

**Drift diagnostic:** the catalogue names live in probe-lean while VCVio evolves independently, so
renames upstream silently break individual anchors (this has already happened:
`preimageFindingAdvantage` was renamed to `programmedPreimageAdvantage`). At classification start,
probe-lean therefore **resolves every catalogued fully-qualified name against the loaded
environment and emits a warning for each unresolved anchor** — converting silent drift into a
visible diagnostic. The warning is informational, not an error: which names exist depends on the
VCVio version the target project builds against. The catalogue should be re-verified against
current VCVio whenever it is edited.

### VCVio correctness anchors

| Symbol | Kind |
|---|---|
| `Correct`, `Complete` | `def … : Prop` (predicate form) |
| `CorrectExp`, `CompleteExp` | `def … : m Bool` (game form) |

### VCVio security anchors

| Symbol | Kind |
|---|---|
| `SecExp`, `SecurityExp`, `SecurityGame` | `structure` (experiment) |
| `advantage`, `bindingAdvantage`, `hidingAdvantage`, `owfAdvantage`, `prfAdvantage`, `prgAdvantage`, `tdpAdvantage`, `programmedPreimageAdvantage`, `collisionFindingAdvantage`, `ddhDistAdvantage`, `ddhGuessAdvantage` | `def` (advantage) |

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

## Class detection

A project is treated as `security-protocol` when it **imports VCVio**, detected from the built
environment's import graph (with the Lake manifest as a fallback signal — less robust against
vendoring and renames). Detection is automatic: probe-lean runs unattended in the verilib
backend, so no flag or configuration is required. An optional `--class` override may be offered
for manual runs, but verilib never depends on it. When no class is detected, the classification
stages do not run and the output carries no class fields.

## Output schema

Classification is additive to the existing extract output: existing fields are unchanged, and
two new fields are introduced:

- envelope **`source.class`** — the detected project class, `"security-protocol"` here. Absent
  when no class is detected.
- per-atom **`classification`** — an object, **absent** (not `null`) when the atom is
  unclassified, with the fields:

  | field | meaning | when present |
  |---|---|---|
  | `category` | `scheme` / `construction` / `correctness` / `security` | always |
  | `via` | the **weakest signal in the classification chain**: `attribute` / `type` / `naming` — a theorem anchored on a promoted anchor inherits that anchor's tier (see *Provenance* above) | always |
  | `scheme` | code-name of the scheme this atom is about | when resolvable (see below) |
  | `construction` | code-name of the construction this property is about | correctness/security atoms, when resolvable |

**Explicit hierarchy links.** The accordion join is emitted by probe-lean, not left to a
consumer-side dependency walk — flat `dependencies` are referenced constants with no application
structure, so a consumer cannot tell a property's *subject* from its *ingredients*. The common
counterexample is a reduction bound, the normal shape of a security theorem: a statement like
`distAdvantage (etmAEAD se prf) adv ≤ prfAdvantage prf + …` references several schemes (the AEAD
under proof as subject, the PRF/SE assumptions as ingredients), and a naive walk would nest it
under all of them. probe-lean resolves the join while it still has the information:

- **construction atom** → `scheme` = the scheme it instantiates (its return-type head).
- **correctness/security atom** → `construction` = the **unique classified construction among the
  statement's dependencies** (assumption schemes typically enter as bound variables, not
  construction constants, so the subject construction is usually the only one); `scheme` = that
  construction's scheme.
- **Scheme-level properties carry `scheme` without `construction`.** Property *definitions*
  (games, predicates, advantage definitions) are generic over constructions — `correctnessExp`
  takes *any* `CKAScheme` — so they resolve no construction; their subject is the scheme itself.
  They link to the **unique classified scheme among their statement's dependencies**. Likewise, a
  theorem that resolves no construction but reaches a promoted anchor (e.g. a generic lemma about
  `securityExp`) inherits that anchor's `scheme`. This distinguishes scheme-level properties from
  true orphans.
- **Fail-closed:** a link field is **absent** when unresolvable (zero candidates — orphans stay
  visibly orphaned, never fabricated).
- **JSON types:** each link field is a **string** when uniquely resolved and an **array of
  strings** when genuinely ambiguous (two or more candidate constructions). With an ambiguous
  construction set, `scheme` is the union of those constructions' schemes — again a string if
  that union is a singleton, an array otherwise.
- **Links always reference emitted atoms.** When a construction's return-type head is an
  *imported* VCVio scheme (which is never emitted as an atom), its `scheme` link is **absent**
  rather than a dangling name — consistent with fail-closed (see *Reliability and limitations*).

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
    "probe:SecureMessaging.CKA.Defs.correctnessExp": {
      "display-name": "correctnessExp",
      "kind": "def",
      "verification-status": "verified",
      "classification": {
        "category": "correctness", "via": "naming",
        "scheme": "probe:SecureMessaging.CKA.Defs.CKAScheme"
      }
    },
    "probe:SecureMessaging.CKA.FromDDH.Construction.ddhCKA": {
      "display-name": "ddhCKA",
      "kind": "def",
      "dependencies": ["probe:SecureMessaging.CKA.Defs.CKAScheme"],
      "verification-status": "transitively-verified",
      "classification": {
        "category": "construction", "via": "type",
        "scheme": "probe:SecureMessaging.CKA.Defs.CKAScheme"
      }
    },
    "probe:SecureMessaging.CKA.FromDDH.Correctness.correctness": {
      "display-name": "correctness",
      "kind": "theorem",
      "dependencies": [
        "probe:SecureMessaging.CKA.Defs.correctnessExp",
        "probe:SecureMessaging.CKA.FromDDH.Construction.ddhCKA"
      ],
      "verification-status": "verified",
      "classification": {
        "category": "correctness", "via": "naming",
        "construction": "probe:SecureMessaging.CKA.FromDDH.Construction.ddhCKA",
        "scheme": "probe:SecureMessaging.CKA.Defs.CKAScheme"
      }
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

Reading the example: `correctnessExp` is a project-own game classified by naming and **promoted to
an anchor** — generic over constructions, so it carries a `scheme` link only (scheme-level). The
`correctness` theorem is classified structurally by reaching it, but inherits the anchor's weaker
tier (`via: naming`), and carries explicit links to its construction and scheme.
`security_reduces_to_ind_cpa_exists` resolves no unique construction, so its link fields are
**absent** — a visible orphan, nested nowhere rather than somewhere wrong. `reachableInv_init`
carries no `classification` key at all — an unclassified helper lemma.

### Building the accordion from the links

Every classified atom carries its **full path** — a property links to both its construction and
its scheme directly, so a consumer never chases chains or computes anything transitive. Assembling
the `scheme → construction → {correctness, security}` view is a single linear pass with a
group-by:

```
for each atom with a classification:
  category == scheme         → create a root
  category == construction   → place under its `scheme`
  correctness / security     → place under its `construction`;
                               if only `scheme` is present, place at scheme level;
                               if neither, list as unattached
```

The link-presence pattern encodes the placement directly:

| links present | placement |
|---|---|
| `construction` + `scheme` | property proved of a specific construction |
| `scheme` only | scheme-level property (the games/predicates defining the property; generic lemmas) |
| `construction` only | property of a construction whose scheme is not an emitted atom (e.g. imported VCVio scheme) — a construction-rooted subtree |
| neither | unattached (orphan) — rendered as a bare leaf, never force-nested |

A scheme atom is always a root; a construction roots its own subtree exactly when its `scheme`
link is absent; a property is a bare leaf exactly when both links are absent. Nothing is ever
fabricated to force a tree shape — an untagged project may legitimately render as bare property
leaves (naming catches its theorems but not its schemes), and the view assembles into trees as the
project adopts the attributes.

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
  is an imported VCVio symbol — never classified, never emitted as an atom. The construction's
  `scheme` link is therefore **absent** (links always reference emitted atoms), and the accordion
  has a construction with no scheme above it to nest under. The surveyed projects define their own
  schemes, so this does not arise in practice, but the verilib contract should decide how to
  render such a case.
- **Correctness vs security** at the theorem level relies on reaching the right anchor;
  stepping-stone lemmas that pass through a game can be tagged by reachability, so the walk is
  bounded and prefers the nearest anchor. `@[correctness_spec]` / `@[security_spec]` resolve any
  remaining ambiguity.
- **Promoted anchors inherit naming risk.** Most project anchors enter the anchor set via the
  naming pattern, so a false-positive anchor name would mislabel every theorem anchored on it.
  Weakest-tier inheritance makes this visible — such theorems carry `via: naming`, so consumers
  can discount or badge them — and an attribute on the anchor definition upgrades the whole
  chain at once.
- When VCVio renames or moves a baked-in symbol, the *type* signal for that symbol silently
  stops matching until the catalogue is updated. The **resolve-at-start drift diagnostic**
  (under *Built-in anchor and type catalogue*) turns this into a per-run warning; diagnostics
  should additionally log which anchors matched, so both drift and over-matching are visible.
- **Link-field resolution is heuristic.** The "unique classified construction among the
  statement's dependencies" rule resolves the common shapes (direct properties; reduction bounds
  whose assumption schemes enter as bound variables), but a statement referencing several
  classified constructions yields an array, and a fully generic statement yields no link.
  Application-position analysis of the elaborated statement (which argument slot the construction
  occupies) is a possible refinement if validation shows the simple rule resolves too little.

### Future signals

- **Docstrings and Verso labels.** Project documentation (declaration docstrings, Verso blueprint
  labels such as `:::theorem "…_security" (lean := …)`) could serve as an additional
  classification signal — a possible fourth `via: docs` value. Deferred to a separate issue.

### Open decisions

- **Schema docs.** `docs/SCHEMA.md` and the test suite must be updated to declare `source.class`
  and the per-atom `classification` object (including the link fields) as optional fields when
  this is implemented.
