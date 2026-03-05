/-
  Stubify command implementation.
  Generates stubs.json from atoms.json, filtering out hidden and extraction artifact atoms.
-/
import Lean
import ProbeLean.Types
import ProbeLean.Atomize

namespace ProbeLean

open Lean

/-- Configuration for the stubify command -/
structure StubifyConfig where
  projectPath : System.FilePath
  atomsPath : Option System.FilePath
  outputPath : Option System.FilePath
  deriving Repr

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

/-- Load atoms from atoms.json and return filtered atoms (not hidden, not extraction artifact) -/
def loadFilteredAtoms (path : System.FilePath) : IO (Except String (Array Atom)) := do
  if !(← path.pathExists) then
    return .error s!"Cannot read atoms.json: {path}"

  let content ← IO.FS.readFile path
  match Json.parse content with
  | .error e => return .error s!"Invalid JSON in {path}: {e}"
  | .ok json =>
    match Lean.fromJson? json (α := AtomsOutput) with
    | .error e => return .error s!"Failed to parse atoms: {e}"
    | .ok atomsOutput =>
      -- Filter to atoms that are NOT hidden AND NOT extraction artifacts AND is relevant AND code-path ends with "Funs.lean"
      let filteredAtoms := atomsOutput.atoms.filter fun atom =>
        !atom.isHidden && !atom.isExtractionArtifact && atom.isRelevant && atom.codePath.endsWith "Funs.lean"
      return .ok filteredAtoms

/-- Generate unique keys for atoms, using short form when possible, full name when clashes occur -/
def generateUniqueKeys (atoms : Array Atom) : Array (String × Atom) := Id.run do
  -- First pass: count occurrences of each short key
  let mut shortKeyCounts : List (String × Nat) := []
  for atom in atoms do
    let shortKey := s!"{atom.codePath}/{getLastNamePart atom.name}"
    match shortKeyCounts.find? (·.1 == shortKey) with
    | some _ =>
      shortKeyCounts := shortKeyCounts.map fun (k, c) => if k == shortKey then (k, c + 1) else (k, c)
    | none =>
      shortKeyCounts := (shortKey, 1) :: shortKeyCounts

  -- Second pass: assign keys, using full name for clashes
  let mut result : Array (String × Atom) := #[]
  for atom in atoms do
    let shortKey := s!"{atom.codePath}/{getLastNamePart atom.name}"
    let count := shortKeyCounts.find? (·.1 == shortKey) |>.map (·.2) |>.getD 1
    let key := if count > 1 then
      -- Use full atom name (without probe: prefix) for uniqueness
      s!"{atom.codePath}/{stripProbePrefix atom.name}"
    else
      shortKey
    result := result.push (key, atom)
  result

/-- Generate stubs output as JSON object keyed by stub keys -/
def generateStubsJsonFromAtoms (atoms : Array Atom) : Lean.Json :=
  let keysAndAtoms := generateUniqueKeys atoms
  let entries := keysAndAtoms.map fun (key, atom) =>
    let entry : StubEntry := {
      codePath := some atom.codePath
      codeLines := atom.codeText.map fun ct => s!"{ct.linesStart}-{ct.linesEnd}"
      codeName := atom.name
      rustPath := ""
      rustLines := { linesStart := 0, linesEnd := 0 }
      rustName := ""
      specPath := some atom.codePath
      specLines := none
      specName := some atom.name
    }
    (key, Lean.toJson entry)
  Lean.Json.mkObj entries.toList

/-- Run the stubify command -/
def runStubifyInProject (config : StubifyConfig) : IO UInt32 := do
  -- Determine paths
  let atomsPath := config.atomsPath.getD (config.projectPath / ".verilib" / "atoms.json")
  let outputPath := config.outputPath.getD (config.projectPath / ".verilib" / "stubs.json")

  IO.println s!"Loading atoms from {atomsPath}..."

  -- Load and filter atoms
  let atoms ← match ← loadFilteredAtoms atomsPath with
    | .error msg =>
      IO.eprintln s!"Error: {msg}"
      return 1
    | .ok atoms => pure atoms

  IO.println s!"Found {atoms.size} atoms (excluding hidden, extraction artifacts, and irrelevant)"

  -- Generate stubs JSON
  let json := generateStubsJsonFromAtoms atoms
  IO.FS.createDirAll outputPath.parent.get!
  IO.FS.writeFile outputPath json.pretty
  IO.println s!"Wrote {atoms.size} stubs to {outputPath}"

  return 0

end ProbeLean
