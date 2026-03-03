/-
  Stubify command implementation.
  Generates stubs.json from functions.json.
-/
import Lean
import ProbeLean.Types

namespace ProbeLean

open Lean

/-- Configuration for the stubify command -/
structure StubifyConfig where
  projectPath : System.FilePath
  functionsPath : Option System.FilePath
  outputPath : Option System.FilePath
  deriving Repr

/-- A function entry from functions.json -/
structure FunctionEntry where
  leanName : String
  isRelevant : Bool
  source : String
  lines : String
  rustName : String
  specFile : Option String
  deriving Repr

/-- Parse a single function entry from JSON -/
def parseFunctionEntry (json : Json) : Except String FunctionEntry := do
  let leanName ← json.getObjValAs? String "lean_name"
  -- is_relevant defaults to true if missing
  let isRelevant := match json.getObjValAs? Bool "is_relevant" with
    | .ok b => b
    | .error _ => true
  let source := match json.getObjValAs? String "source" with
    | .ok s => s
    | .error _ => ""
  let lines := match json.getObjValAs? String "lines" with
    | .ok l => l
    | .error _ => ""
  let rustName := match json.getObjValAs? String "rust_name" with
    | .ok r => r
    | .error _ => ""
  let specFile := match json.getObjValAs? String "spec_file" with
    | .ok s => if s.isEmpty then none else some s
    | .error _ => none
  return { leanName, isRelevant, source, lines, rustName, specFile }

/-- Get the last dot-separated part of a name -/
def getLastNamePart (name : String) : String :=
  let parts := name.splitOn "."
  parts.getLast!

/-- Get the second-to-last dot-separated part of a name -/
def getSecondLastNamePart (name : String) : String :=
  let parts := name.splitOn "."
  if parts.length < 2 then ""
  else parts[parts.length - 2]!

/-- Strip leading 'L' from line number string if present -/
def stripLinePrefix (s : String) : String :=
  if s.startsWith "L" then (s.drop 1).toString else s

/-- Safely convert string to Nat, returning 0 on failure -/
def safeToNat (s : String) : Nat :=
  s.toNat?.getD 0

/-- Parse lines string "L230-L238" or "230-238" into CodeTextInfo -/
def parseLines (lines : String) : CodeTextInfo :=
  if lines.isEmpty then { linesStart := 0, linesEnd := 0 }
  else
    let parts := lines.splitOn "-"
    match parts with
    | [start, end_] =>
      { linesStart := safeToNat (stripLinePrefix start),
        linesEnd := safeToNat (stripLinePrefix end_) }
    | [single] =>
      let n := safeToNat (stripLinePrefix single)
      { linesStart := n, linesEnd := n }
    | _ => { linesStart := 0, linesEnd := 0 }

/-- Generate stub key with optional clash resolution -/
def generateStubKey (source : String) (leanName : String) (hasClash : Bool) : String :=
  let lastPart := getLastNamePart leanName
  if hasClash then
    let secondPart := getSecondLastNamePart leanName
    s!"{source}/{lastPart}#{secondPart}"
  else
    s!"{source}/{lastPart}"

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

/-- Create a StubEntry from a FunctionEntry -/
def functionToStubEntry (func : FunctionEntry) : StubEntry :=
  let rustLines := parseLines func.lines
  let codePath := func.specFile
  let codeName := func.specFile.map fun _ => s!"probe:{func.leanName}_spec"
  {
    leanPath := none
    leanLines := none
    leanName := s!"probe:{func.leanName}"
    rustPath := func.source
    rustLines := rustLines
    rustName := func.rustName
    codePath := codePath
    codeLines := none
    codeName := codeName
  }

/-- Detect clashes: functions with same source/lastPart combination -/
def detectClashes (functions : Array FunctionEntry) : List String := Id.run do
  -- Group by source/lastPart
  let keys := functions.map fun f => (f.source, getLastNamePart f.leanName)
  let mut seen : List (String × String) := []
  let mut clashes : List String := []
  for key in keys do
    if seen.contains key then
      let clashKey := s!"{key.1}/{key.2}"
      if !clashes.contains clashKey then
        clashes := clashKey :: clashes
    seen := key :: seen
  clashes

/-- Generate stubs output as JSON object keyed by stub keys -/
def generateStubsJson (functions : Array FunctionEntry) : Lean.Json :=
  let clashKeys := detectClashes functions
  let entries := functions.map fun f =>
    let baseKey := s!"{f.source}/{getLastNamePart f.leanName}"
    let hasClash := clashKeys.contains baseKey
    let key := generateStubKey f.source f.leanName hasClash
    let entry := functionToStubEntry f
    (key, Lean.toJson entry)
  Lean.Json.mkObj entries.toList

/-- Run the stubify command -/
def runStubifyInProject (config : StubifyConfig) : IO UInt32 := do
  -- Determine paths
  let functionsPath := config.functionsPath.getD (config.projectPath / "functions.json")
  let outputPath := config.outputPath.getD (config.projectPath / ".verilib" / "stubs.json")

  IO.println s!"Loading functions from {functionsPath}..."

  -- Load functions
  let functions ← match ← loadFunctions functionsPath with
    | .error msg =>
      IO.eprintln s!"Error: {msg}"
      return 1
    | .ok funcs => pure funcs

  -- Filter to only relevant functions
  let relevantFunctions := functions.filter (·.isRelevant)
  IO.println s!"Found {functions.size} functions ({relevantFunctions.size} relevant)"

  -- Generate stubs JSON
  let json := generateStubsJson relevantFunctions
  IO.FS.createDirAll outputPath.parent.get!
  IO.FS.writeFile outputPath json.pretty
  IO.println s!"Wrote {relevantFunctions.size} stubs to {outputPath}"

  return 0

end ProbeLean
