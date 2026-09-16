/-
  The trusted base: which project declarations `verification-status` may rest on
  without a proof.

  Soundness in probe-lean means: no `sorry` inside the project is reachable from a
  declaration except through a *trusted* declaration. Lean itself and every
  dependency package (Aeneas, Mathlib, …) are trusted wholesale — the kernel walk in
  `AxiomCheck.projectTaint` never expands a non-project constant. Inside the project,
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
    tagged `theorem X`. It shares the parent's declaration range, so a source scan of
    the `@[…]` block above that range would hand it the parent's attributes. A
    companion is never a source-visible declaration of its own and therefore can
    never carry an `@[externally_verified]` mark of its own (decision 4 of the spec:
    companions get their own status, not inherited trust). -/
def isCompanionName : Name → Bool
  | .str _ "mvcgen_spec" => true
  | _ => false

/-- Rules 1–3 of the trusted base, in precedence order:

    1. kind `axiom` — a kernel fact, applies to every project constant;
    2. `@[externally_verified]` — a human vouches for the declaration; applies only
       to a **source-visible** declaration, i.e. one with a declaration range of its
       own (`hasRange`). Constants without a range (`impl_def`, `addDecl`), internal
       auxiliaries (`_proof_N`) and generated companions cannot be tagged, so the
       caller passes `hasRange := false` for them;
    3. a non-theorem in a `*External` module — Aeneas's trust-base convention.
       Theorems there carry real proofs and get their normal status.

    Returns the `trusted-reason` string, or `none` when the declaration is not
    trusted. -/
def trustedReason (kind : DeclKind) (attributes : Array String) (moduleName : Name)
    (hasRange : Bool) : Option String :=
  if kind == .axiom then some "axiom"
  else if hasRange && attributes.contains "externally_verified" then some "externally_verified"
  else if isExternalModule moduleName && kind != .theorem then some "external"
  else none

end ProbeLean
