/-
  Shared loading functions for probe-lean output files.
  Handles both bare-dict (Schema 1.x) and enveloped (Schema 2.0) formats.
-/
import Lean
import ProbeLean.Types

namespace ProbeLean

open Lean

/-- Extract the atom data from JSON, unwrapping the Schema 2.0 envelope if present. -/
def unwrapEnvelope (json : Json) : Json :=
  match json.getObjVal? "schema", json.getObjVal? "data" with
  | .ok (.str _), .ok data => data
  | _, _ => json

/-- Load atoms.json, handling both bare-dict and enveloped formats. -/
def loadAtoms (path : System.FilePath) : IO (Except String AtomsOutput) := do
  if !(← path.pathExists) then
    return .error s!"atoms.json not found at {path}. Run 'probe-lean atomize' first."
  let content ← IO.FS.readFile path
  match Json.parse content with
  | .error err => return .error s!"Failed to parse atoms.json: {err}"
  | .ok json =>
    let data := unwrapEnvelope json
    match FromJson.fromJson? data with
    | .error err => return .error s!"Invalid atoms.json format: {err}"
    | .ok atoms => return .ok atoms

/-- Load atoms.json and return filtered atoms for stubify (not hidden, not extraction artifact,
    is relevant, code-path ends with Funs.lean). -/
def loadFilteredAtoms (path : System.FilePath) : IO (Except String (Array Atom)) := do
  match ← loadAtoms path with
  | .error e => return .error e
  | .ok atomsOutput =>
    let filtered := atomsOutput.atoms.filter fun atom =>
      !atom.isHidden && !atom.isExtractionArtifact && atom.isRelevant
        && atom.codePath.endsWith "Funs.lean"
    return .ok filtered

end ProbeLean
