/-
  Specify command implementation.
  Extracts specification status from atoms.json.
-/
import Lean
import ProbeLean.Types
import ProbeLean.Loader
import ProbeLean.Metadata

namespace ProbeLean

open Lean

/-- Configuration for the specify command -/
structure SpecifyConfig where
  projectPath : System.FilePath
  atomsPath : Option System.FilePath
  outputPath : Option System.FilePath
  deriving Repr

/-- Determine if a declaration kind is always considered specified -/
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

/-- Run the specify command -/
def runSpecifyInProject (config : SpecifyConfig) : IO UInt32 := do
  let atomsPath := config.atomsPath.getD (config.projectPath / ".verilib" / "atoms.json")

  IO.println s!"Loading atoms from {atomsPath}..."

  let atoms ← match ← loadAtoms atomsPath with
  | .error msg =>
    IO.eprintln s!"Error: {msg}"
    return 1
  | .ok atoms => pure atoms

  IO.println s!"Found {atoms.atoms.size} declarations"

  let output := atomsToSpecsOutput atoms
  let envelope ← wrapInEnvelope "probe-lean/specs" "specify" (Lean.toJson output) config.projectPath
  let jsonStr := envelope.pretty

  let outputPath := config.outputPath.getD (config.projectPath / ".verilib" / "specs.json")
  IO.FS.createDirAll outputPath.parent.get!
  IO.FS.writeFile outputPath jsonStr
  IO.println s!"Wrote specs to {outputPath}"

  return 0

end ProbeLean
