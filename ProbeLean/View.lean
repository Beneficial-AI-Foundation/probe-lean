/-
  View command: reads verify output, filters atoms, produces molecules for the web UI.
  Schema: probe-lean/view
-/
import Lean
import ProbeLean.Types
import ProbeLean.Loader
import ProbeLean.Metadata

namespace ProbeLean

open Lean

/-- Configuration for the view command -/
structure ViewConfig where
  projectPath : System.FilePath
  atomsPath : Option System.FilePath
  outputPath : Option System.FilePath
  deriving Repr

/-- Get the last dot-separated part of a name -/
def getLastNamePart (name : String) : String :=
  let parts := name.splitOn "."
  parts.getLast!

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

/-- Filter atoms for the view: not hidden, not extraction artifact, relevant, Funs.lean -/
def filterAtomsForView (atoms : Array Atom) : Array Atom :=
  atoms.filter fun atom =>
    !atom.isHidden && !atom.isExtractionArtifact && atom.isRelevant
      && atom.codePath.endsWith "Funs.lean"

/-- Generate unique keys for atoms, using short form when possible, full name when clashes occur -/
def generateUniqueKeys (atoms : Array Atom) : Array (String × Atom) := Id.run do
  let mut shortKeyCounts : List (String × Nat) := []
  for atom in atoms do
    let shortKey := s!"{atom.codePath}/{getLastNamePart atom.name}"
    match shortKeyCounts.find? (·.1 == shortKey) with
    | some _ =>
      shortKeyCounts := shortKeyCounts.map fun (k, c) => if k == shortKey then (k, c + 1) else (k, c)
    | none =>
      shortKeyCounts := (shortKey, 1) :: shortKeyCounts

  let mut result : Array (String × Atom) := #[]
  for atom in atoms do
    let shortKey := s!"{atom.codePath}/{getLastNamePart atom.name}"
    let count := shortKeyCounts.find? (·.1 == shortKey) |>.map (·.2) |>.getD 1
    let key := if count > 1 then
      s!"{atom.codePath}/{stripProbePrefix atom.name}"
    else
      shortKey
    result := result.push (key, atom)
  result

/-- Generate molecules output from filtered atoms -/
def generateMoleculesOutput (atoms : Array Atom) : MoleculesOutput :=
  let keysAndAtoms := generateUniqueKeys atoms
  { entries := keysAndAtoms.map fun (key, atom) =>
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
      (key, entry) }

/-- Run the view command -/
def runViewInProject (config : ViewConfig) : IO UInt32 := do
  let source ← collectSourceInfo config.projectPath

  let atomsPath ← match config.atomsPath with
    | some p => pure p
    | none => do
      let (path, usedFallback) ← findDefaultAtomsPath config.projectPath source
      if usedFallback then
        IO.println "NOTE: Using probes from a different version. Re-run 'probe-lean verify' for accurate results."
      pure path

  IO.println s!"Loading atoms from {atomsPath}..."

  let atoms ← match ← loadAtoms atomsPath with
    | .error msg =>
      IO.eprintln s!"Error: {msg}"
      return 1
    | .ok atoms => pure atoms

  IO.println s!"Loaded {atoms.atoms.size} atoms"

  let filtered := filterAtomsForView atoms.atoms
  IO.println s!"Filtered to {filtered.size} atoms (excluding hidden, extraction artifacts, irrelevant, non-Funs.lean)"

  let output := generateMoleculesOutput filtered
  let timestamp ← getCurrentTimestamp

  let envelope : Envelope MoleculesOutput := {
    schema := Constants.schemaView
    tool := { command := "view" }
    source := source
    timestamp := timestamp
    data := output
  }
  let json := Lean.toJson envelope
  let jsonStr := json.pretty

  let outputPath := config.outputPath.getD (buildViewsOutputPath config.projectPath)
  if let some parentDir := outputPath.parent then
    IO.FS.createDirAll parentDir
  IO.FS.writeFile outputPath jsonStr
  IO.println s!"Wrote {filtered.size} molecules to {outputPath}"

  return 0

end ProbeLean
