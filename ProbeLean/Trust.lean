/-
  The trusted base: which project declarations `verification-status` may rest on
  without a proof.

  Soundness in probe-lean means: no `sorry` inside the project is reachable from a
  declaration except through a *trusted* declaration. Lean itself and every
  dependency package (Aeneas, Mathlib, …) are trusted wholesale — the kernel walk in
  `AxiomCheck.projectTaint` never expands a non-project constant, except a name a
  project module declares that the environment attributes to a dependency (a
  cross-boundary merge, walked from the project's own bodies; `Taint.runProjectTaint`).
  Inside the project,
  three rules decide trust, and this module is the **only** place they are written
  down: the atom's `trusted-reason`, the taint walk's blocked set, and the
  `check-axioms` report all call `trustedReason`, so they cannot drift.
-/
import Lean
import ProbeLean.Types

namespace ProbeLean

open Lean

/-- Rule 3's module test: the module name ends with `External` (the `*External.lean`
    convention of Aeneas targets, e.g. `Curve25519Dalek.FunsExternal`). Keyed on the
    module name rather than the source path so it also fires when the path lookup
    fails. -/
def isExternalModule (moduleName : Name) : Bool :=
  -- The last component decides; testing it directly avoids printing the name,
  -- which matters when this runs over every project constant.
  match moduleName with
  | .str _ s => s.endsWith "External"
  | _ => false

/-- `X.mvcgen_spec` — the companion theorem Aeneas's `@[step]` generates next to a
    tagged `theorem X`. It shares the parent's declaration range, so it passes
    `isSourceVisible` and a header scan hands it the parent's `@[…]` attributes; nothing
    in the source is its own. Two consumers share this name test so they cannot
    disagree about what a companion is: `generatedCompanionTheoremNames` flags it
    `is-aeneas-generated`, and `tagAudit` leaves it out of the scan-only side, since a
    parent's `@[externally_verified]` showing on it is expected. Trust is not decided
    here: a companion gets its own status (spec decision 4), and an explicit
    `attribute [externally_verified] X.mvcgen_spec` command would put it in the tag set
    like any constant. -/
def isCompanionName : Name → Bool
  | .str _ "mvcgen_spec" => true
  | _ => false

/-- Rules 1–3 of the trusted base, in precedence order:

    1. kind `axiom` — a kernel fact, applies to every project constant;
    2. `@[externally_verified]` — a human vouches for the declaration. `externallyVerified`
       is membership in the attribute's **tag set**, read from the environment: the
       entries the target's own `registerTagAttribute` extension stored in the olean
       (`TagSet.externallyVerifiedTagSet`) plus probe-lean's own handle
       (`Taint.externallyVerifiedNames`). A tag is a tag, whatever syntax attached it —
       `@[…]` on the declaration or an `attribute [externally_verified] foo` command —
       and whatever the constant is: a range-less `impl_def`, a companion, an instance
       a macro tagged on purpose. What the set does **not** contain: anything that
       merely shares a tagged declaration's source range — a `deriving` instance, a
       projection, a generated `.mvcgen_spec` companion, an `instX.field` helper.
       Those were exactly the false-trust paths of the source scan, which no longer
       feeds trust;
    3. a non-proof in a `*External` module — Aeneas's trust-base convention for
       hand-written models of external functions and types. `isProof` is true for every
       `theorem` and for any other declaration whose type is a proposition (`def
       admitted : False := sorry`, an `opaque` of Prop type); those carry proofs and get
       their normal status.

    Returns the `trusted-reason` string, or `none` when the declaration is not
    trusted. -/
def trustedReason (kind : DeclKind) (externallyVerified : Bool) (moduleName : Name)
    (isProof : Bool) : Option String :=
  if kind == .axiom then some "axiom"
  else if externallyVerified then some "externally_verified"
  else if isExternalModule moduleName && !isProof then some "external"
  else none

end ProbeLean
