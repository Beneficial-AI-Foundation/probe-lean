/-
  Specify command implementation.
  Extracts specification status from atoms.json.
-/
import Lean
import ProbeLean.Types

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

/-- Load atoms.json and parse it -/
def loadAtoms (path : System.FilePath) : IO (Except String AtomsOutput) := do
  if !(← path.pathExists) then
    return .error s!"atoms.json not found at {path}. Run 'probe-lean atomize' first."
  let content ← IO.FS.readFile path
  match Json.parse content with
  | .error err => return .error s!"Failed to parse atoms.json: {err}"
  | .ok json =>
    match FromJson.fromJson? json with
    | .error err => return .error s!"Invalid atoms.json format: {err}"
    | .ok atoms => return .ok atoms

/-- Convert atoms to specs output (as JSON object keyed by name) -/
def atomsToSpecsJson (atoms : AtomsOutput) : Json :=
  let entries := atoms.atoms.map fun atom =>
    (atom.name, toJson (atomToSpecEntry atom))
  Json.mkObj entries.toList

/-- Run the specify command -/
def runSpecifyInProject (config : SpecifyConfig) : IO UInt32 := do
  -- Determine atoms.json path
  let atomsPath := config.atomsPath.getD (config.projectPath / "atoms.json")

  IO.println s!"Loading atoms from {atomsPath}..."

  -- Load atoms
  let atoms ← match ← loadAtoms atomsPath with
  | .error msg =>
    IO.eprintln s!"Error: {msg}"
    return 1
  | .ok atoms => pure atoms

  IO.println s!"Found {atoms.atoms.size} declarations"

  -- Convert to specs
  let specsJson := atomsToSpecsJson atoms

  -- Write output
  let outputPath := config.outputPath.getD (config.projectPath / "specs.json")
  IO.FS.writeFile outputPath specsJson.pretty
  IO.println s!"Wrote specs to {outputPath}"

  return 0

end ProbeLean
