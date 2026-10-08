# Spec relationships

This document states the rules that decide the `specs` and `primary-spec` fields of
`probe-lean extract`, and the reasons for each decision. [schema.md](schema.md) defines the
fields themselves.

A spec relationship connects two atoms. The spec target is the atom that the spec describes, for
example a function. The spec source is the declaration that describes it, for example a theorem
about the function. The target's `specs` lists its sources. Its `primary-spec` names one of them.

## Terms

- Proof: a constant whose type is a proposition (`Meta.isProp` on the kernel type is true).
  Every `theorem` is a proof. So are `def admitted : False := sorry`, an instance of a
  Prop-valued class, and the projection `Bundle.pos : (b : Bundle) → 0 < b.val`.
- Predicate: a constant that is not a proof and whose result type, after all binders, is `Prop`.
  This is the `codomain-is-prop` fact. Examples: `def IsValid (x : T) : Prop`,
  `def P : Prop := True`.
- Type former: a constant that is not a proof and whose result type, after all binders, is
  `Sort u` with `u` other than zero, for example `Type`. Examples: `abbrev Score : Type := Nat`,
  `def Grid (n : Nat) : Type := Fin n → Nat`.
- Data constant: a constant that is neither a proof, nor a predicate, nor a type former.
- Generated theorem: a theorem atom flagged `is-lean-generated` or `is-aeneas-generated`. See
  [schema.md](schema.md), section "Generated-code hiding".

## Spec targets

A spec target is a constant with computational behavior that a theorem can describe. It has two
properties:

1. Its `kind` is `def`, `abbrev`, `instance`, `opaque` or `axiom`.
2. It is a data constant.

No other atom is a spec target, so no other atom has `specs` or `primary-spec`. This excludes
types (`structure`, `class`, `inductive`, `quot`), projections, theorems, every proof, every
predicate and every type former.

| Atom | Kind | Target |
|------|------|--------|
| `def needsPos (n : Nat) [IsPos n] : Nat` | `def` (data) | yes |
| Aeneas `axiom f : U32 → Result U32` | `axiom` (data) | yes |
| `instance : Add T` | `instance` (data) | yes |
| `structure Bundle` | `structure` | no |
| `Bundle.val` | `projection` (data) | no |
| `axiom ax : 0 < 1` | `axiom` (proof) | no |
| `def admitted : False := sorry` | `def` (proof) | no |
| `def IsValid (x : T) : Prop` | `def` (predicate) | no |
| `abbrev Score : Type := Nat` | `abbrev` (type former) | no |
| `def Grid (n : Nat) : Type := Fin n → Nat` | `def` (type former) | no |

Decisions (issue #130):

- Predicates are not targets. A predicate is specification vocabulary, like a Verus `spec fn`.
  The theorems that name only a predicate are mostly unfolding lemmas. In
  curve25519-dalek-lean-verify, 11 predicates received specs before this rule, and
  `montgomery.valid_ladder_state` had the wrong `primary-spec`.
- Projections and types are not targets. Their specs are dropped, not moved to another atom (for
  example, from `Bundle.val` to a constructor). The theorems that name only a projection are
  mostly structure lemmas such as `ext`. The `@[primary_spec]` fallback in "Spec sources" is the
  one exception: if a tagged theorem's statement names no target, its tag can attach to a
  function that its proof uses.
- Type formers are not targets. A type alias plays the role of a structure: theorems mention it
  because they are about its values. In curve25519-dalek-lean-verify, 10 type formers received
  specs before this rule, for example `Edwards.CurveField` (275), `FieldElement51` (219) and
  `Montgomery.CurveField` (126). The type family `window.LookupTable` lost its 4 specs too.
- If `Meta.isProp` cannot decide a constant's type (an elaboration error, a heartbeat or
  recursion limit), `extract` prints a warning on stderr and treats the constant as a proof, so
  it is not a target. This fails closed, like the proof test of the External-module trust rule
  ([verification-status.md](verification-status.md)).

Known limitation: the predicate and type-former tests read the syntax of the result type. They
do not unfold aliases or reduce the result type (for example a `let` or a function
application in the type). So a constant whose result type is an alias of `Prop` stays a target, for
example `def HiddenPredicate (n : Nat) : Proposition` with `abbrev Proposition : Type := Prop`, or
a constant of type `Set α`. An alias of `Type` stays a target too. The `aux-fold` fixture records
the `HiddenPredicate` case.

## Spec sources

`specs` lists the theorem atoms whose `type-dependencies` include the target. A theorem specifies
what its statement is about. A constant that the theorem uses only in its proof (a helper lemma,
a definition it unfolds) is not something the theorem specifies.

Generated theorems are not spec sources. A generated theorem tagged `@[primary_spec]` is the
exception: the tag is a human decision about that theorem.

The projection of a Prop-valued field or class parent is not a spec source either. Lean compiles
it as a theorem, but its kind is `projection` (#115). Its statement only restates the field.

One exception reads the proof. If a `@[primary_spec]` theorem's statement names no spec target,
probe-lean reads the theorem's `dependencies` instead. If that array names exactly one spec
target, the tag attaches to it. With several, the tag attaches to nothing.

Known limitations:

- Axioms are not spec sources. Aeneas pairs a data axiom `f` (an external function) with a Prop
  axiom `f_spec` tagged `@[step]`. The `@[step]` attribute generates a theorem
  `f_spec.mvcgen_spec` that restates `f_spec`. probe-lean does not flag the companion of an
  axiom parent as generated, so the companion is the spec of `f`. Without it, `f` has no spec.
  The companion is not human-written.
- probe-lean detects generated theorems by name shape only. Theorems that other attributes add,
  for example `X.onCurve_iff` from Mathlib's `@[mk_iff]`, are spec sources.

## Primary spec

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
