/-
  What probe-lean knows about verification frameworks, for primary-spec detection.

  Aeneas accepts a `@[step]` theorem only in the shape
  `∀ xs, H1 → ... → Hk → S T (f a1 ... an) P`, where `S` is a spec statement
  registered with `#register_spec_info` and the program `f a1 ... an` is the argument
  at the statement's program index. The `step` tactic indexes the theorem under `f`,
  its step program head. `stepProgramHeadOf` reads that head from the theorem's kernel
  type. probe-lean does not read the Aeneas `stepMap` from the olean, because
  `@[local step]` and `@[scoped step]` registrations never reach the olean, and the
  type gives the same head for them.

  Aeneas checks only the statement constant and its arity, not that the program
  starts with a constant. A generic lemma `∀ p, WP.spec p P` is a valid `@[step]`
  theorem, and its program head is `none`.

  For a `@[step]` declaration `X`, Aeneas also generates a companion `X.mvcgen_spec`:
  `X` applied to its binders and wrapped into mvcgen's `Triple (f args) ⌜True⌝ post`.
  Its program is the program of `X`. probe-lean keeps the companion of an axiom as the
  axiom's spec source, so `companionParentHead` gives it the head of `X`.
-/
import Lean

namespace ProbeLean

open Lean

/-- Attributes from verification frameworks that mark a theorem as a primary
    specification candidate (rule 2 of the primary-spec precedence, see
    `computeSpecs`). `progress` is a deprecated Aeneas alias of `step`, and `pspec`
    is its older name. -/
def primarySpecAttributes : List String :=
  ["progress", "pspec", "step"]

/-- Check if an atom carries any of the known primary-spec attributes. -/
def hasKnownSpecAttribute (attrs : Array String) : Bool :=
  primarySpecAttributes.any fun a => attrs.contains a

/-- Spec statements that Aeneas's `step` accepts: (constant, arity, program index).
    Mirrors `#register_spec_info` in Aeneas `Std/WP.lean` (`b059c34a`). -/
def stepSpecStatements : List (Name × Nat × Nat) :=
  [(`Aeneas.Std.WP.spec, 3, 1), (`Aeneas.Std.WP.dspec, 3, 1)]

/-- Strip `let` binders (zeta, by instantiating the body with the value) and
    metadata from the front of `e`. -/
private partial def stripLets : Expr → Expr
  | .mdata _ e => stripLets e
  | .letE _ _ value body _ => stripLets (body.instantiate1 value)
  | e => e

/-- Strip leading `∀`/`→` binders, `let` binders and metadata, in any order. The
    result can contain loose bvars. Only its application spine is inspected. -/
private partial def stripToResult : Expr → Expr
  | .forallE _ _ body _ => stripToResult body
  | .mdata _ e => stripToResult e
  | .letE _ _ value body _ => stripToResult (body.instantiate1 value)
  | e => e

/-- The step program head of a theorem type: the head constant of the program in a
    statement `S T (f a1 ... an) P` with `S` in `stepSpecStatements`, after the leading
    binders. `none` if the statement is not such an application with the listed arity,
    or if the program does not start with a constant (a generic lemma). The primed
    `Expr` helpers look through metadata anywhere in an application spine, also around
    a partial application. A `let` in the program is instantiated, as Aeneas does
    before it indexes the theorem. -/
def stepProgramHeadOf (type : Expr) : Option Name := do
  let stmt := stripToResult type
  let .const c _ := stmt.getAppFn' | none
  let (_, arity, idx) ← stepSpecStatements.find? (·.1 == c)
  guard (stmt.getAppNumArgs' == arity)
  match (stripLets (stmt.getArg!' idx)).getAppFn' with
  | .const f _ => some f
  | _ => none

/-- The step program head of the axiom parent `X` of a companion `X.mvcgen_spec`, if
    any. Aeneas builds the companion by applying `X` to its binders, so its program is
    the program of `X`. probe-lean keeps the companion of an axiom as the axiom's spec
    source. Its own statement is in mvcgen's `Triple` form and has no head. A companion
    of a theorem is generated and never a spec source, so it gets `none` here. -/
def companionParentHead (env : Environment) : Name → Option Name
  | .str parent "mvcgen_spec" =>
    match env.find? parent with
    | some (.axiomInfo a) => stepProgramHeadOf a.type
    | _ => none
  | _ => none

end ProbeLean
