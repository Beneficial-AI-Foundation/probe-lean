/-
  Shared loading functions for probe-lean output files.
  Handles both bare-dict (Schema 1.x) and enveloped (Schema 4.0) formats.
-/
import Lean
import ProbeLean.Types

namespace ProbeLean

open Lean

/-- Extract the atom data from JSON, unwrapping the Schema 4.0 envelope if present. -/
def unwrapEnvelope (json : Json) : Json :=
  match json.getObjVal? "schema", json.getObjVal? "data" with
  | .ok (.str _), .ok data => data
  | _, _ => json

/-- Load atoms from a JSON file, handling both bare-dict and enveloped formats. -/
def loadAtoms (path : System.FilePath) : IO (Except String AtomsOutput) := do
  if !(← path.pathExists) then
    return .error s!"Atoms file not found at {path}. Run 'probe-lean extract' first."
  let content ← IO.FS.readFile path
  match Json.parse content with
  | .error err => return .error s!"Failed to parse atoms file: {err}"
  | .ok json =>
    let data := unwrapEnvelope json
    match FromJson.fromJson? data with
    | .error err => return .error s!"Invalid atoms file format: {err}"
    | .ok atoms => return .ok atoms

end ProbeLean
