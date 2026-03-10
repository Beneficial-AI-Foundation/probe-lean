/-
  Specify: core logic for extracting specification status from atoms.
  Not a CLI command - used by Verify.lean.
-/
import Lean
import ProbeLean.Types

namespace ProbeLean

open Lean

/-- Determine if a declaration kind is always considered specified.
    In Lean, all declaration kinds have type signatures serving as specs. -/
def isAlwaysSpecified (kind : DeclKind) : Bool :=
  match kind with
  | .theorem => true
  | .class => true
  | .structure => true
  | .inductive => true
  | .instance => true
  | .axiom => true
  | .def => true
  | .abbrev => true
  | .opaque => true
  | .quot => true

/-- Convert an Atom to a SpecEntry -/
def atomToSpecEntry (atom : Atom) : SpecEntry :=
  {
    specified := isAlwaysSpecified atom.kind
    codePath := atom.codePath
    specText := atom.codeText
  }

/-- Convert atoms to a typed SpecsOutput -/
def atomsToSpecsOutput (atoms : AtomsOutput) : SpecsOutput :=
  { entries := atoms.atoms.map fun atom => (atom.name, atomToSpecEntry atom) }

end ProbeLean
