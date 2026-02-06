/-
  Stubify command implementation.
  Filters atoms based on functions.json to produce stubs.json.
-/
import Lean
import ProbeLean.Types
import ProbeLean.Specify

namespace ProbeLean

open Lean

/-- Configuration for the stubify command -/
structure StubifyConfig where
  projectPath : System.FilePath
  functionsPath : Option System.FilePath
  atomsPath : Option System.FilePath
  outputPath : Option System.FilePath
  deriving Repr

/-- A function entry from functions.json -/
structure FunctionEntry where
  leanName : String
  isRelevant : Bool
  deriving Repr

/-- Parse a single function entry from JSON -/
def parseFunctionEntry (json : Json) : Except String FunctionEntry := do
  let leanName ← json.getObjValAs? String "lean_name"
  -- is_relevant defaults to true if missing
  let isRelevant := match json.getObjValAs? Bool "is_relevant" with
    | .ok b => b
    | .error _ => true
  return { leanName, isRelevant }

/-- Load functions from functions.json -/
def loadFunctions (path : System.FilePath) : IO (Except String (Array FunctionEntry)) := do
  if !(← path.pathExists) then
    return .error s!"Cannot read functions.json: {path}"

  let content ← IO.FS.readFile path
  let json ← match Json.parse content with
    | .ok j => pure j
    | .error e => return .error s!"Invalid JSON in {path}: {e}"

  -- Parse the functions array
  let functionsJson ← match json.getObjValAs? (Array Json) "functions" with
    | .ok arr => pure arr
    | .error e => return .error s!"Missing or invalid 'functions' field: {e}"

  let mut functions : Array FunctionEntry := #[]
  for fJson in functionsJson do
    match parseFunctionEntry fJson with
    | .ok entry => functions := functions.push entry
    | .error _ => pure ()  -- Skip entries without lean_name

  return .ok functions

/-- Filter atoms based on function list -/
def filterAtoms (atoms : AtomsOutput) (functions : Array FunctionEntry) : AtomsOutput :=
  -- Build a set of relevant lean names
  let relevantNames := functions
    |>.filter (·.isRelevant)
    |>.map (fun f => s!"probe:{f.leanName}")
    |>.toList

  -- Filter atoms to only those in the relevant set
  let filteredAtoms := atoms.atoms.filter fun atom =>
    relevantNames.contains atom.name

  { atoms := filteredAtoms }

/-- Run the stubify command -/
def runStubifyInProject (config : StubifyConfig) : IO UInt32 := do
  -- Determine paths
  let functionsPath := config.functionsPath.getD (config.projectPath / "functions.json")
  let atomsPath := config.atomsPath.getD (config.projectPath / "atoms.json")
  let outputPath := config.outputPath.getD (config.projectPath / "stubs.json")

  IO.println s!"Loading functions from {functionsPath}..."

  -- Load functions
  let functions ← match ← loadFunctions functionsPath with
    | .error msg =>
      IO.eprintln s!"Error: {msg}"
      return 1
    | .ok funcs => pure funcs

  let relevantCount := functions.filter (·.isRelevant) |>.size
  IO.println s!"Found {functions.size} functions ({relevantCount} relevant)"

  IO.println s!"Loading atoms from {atomsPath}..."

  -- Load atoms
  let atoms ← match ← loadAtoms atomsPath with
    | .error msg =>
      IO.eprintln s!"Error: {msg}. Run 'probe-lean atomize' first."
      return 1
    | .ok a => pure a

  IO.println s!"Found {atoms.atoms.size} atoms"

  -- Filter atoms
  let stubs := filterAtoms atoms functions

  IO.println s!"Filtered to {stubs.atoms.size} stubs"

  -- Write output
  let json := Lean.toJson stubs
  IO.FS.writeFile outputPath json.pretty
  IO.println s!"Wrote {stubs.atoms.size} stubs to {outputPath}"

  return 0

end ProbeLean
