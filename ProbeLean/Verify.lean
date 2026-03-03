/-
  Verify command implementation.
  Checks proof completeness by detecting sorry in Lean compiler output.
-/
import Lean
import ProbeLean.Types
import ProbeLean.Environment
import ProbeLean.Analysis
import ProbeLean.Specify

namespace ProbeLean

open Lean

/-- Configuration for the verify command -/
structure VerifyConfig where
  projectPath : System.FilePath
  atomsPath : Option System.FilePath
  outputPath : Option System.FilePath
  noCache : Bool
  fromFile : Option System.FilePath
  deriving Repr

/-- A parsed sorry warning from Lean output -/
structure SorryWarning where
  filePath : String
  line : Nat
  column : Nat
  message : String
  deriving Repr, BEq

/-- Parse a single line of Lean output for sorry warnings -/
def parseSorryWarning (line : String) : Option SorryWarning := do
  -- Format: "warning: ././././TestProject.lean:42:8: declaration uses 'sorry'"
  -- Or: "⚠ [2/3] Replayed TestProject" (not a sorry warning)
  if !containsSubstring line "sorry" then none

  -- Check if it starts with "warning: " prefix
  let trimmed := line.trimAscii.toString
  if !trimmed.startsWith "warning: " then none

  let rest := (trimmed.drop 9).toString

  let parts := rest.splitOn ": "
  if parts.length < 2 then none

  let message := parts.getLast!
  let locationParts := parts.dropLast

  -- Rejoin location parts (in case path had ": " in it, unlikely but safe)
  let locationStr := String.intercalate ": " locationParts

  -- Parse location: "path/to/File.lean:42:8"
  let locParts := locationStr.splitOn ":"
  if locParts.length < 3 then none

  -- File path is all but last 2 parts (line and column)
  let filePathParts := locParts.dropLast.dropLast
  let filePath := String.intercalate ":" filePathParts

  let lineIdx := locParts.length - 2
  let colIdx := locParts.length - 1
  let lineStr := locParts[lineIdx]!
  let colStr := locParts[colIdx]!

  let lineNum ← String.toNat? lineStr
  let colNum ← String.toNat? colStr

  some {
    filePath := filePath
    line := lineNum
    column := colNum
    message := message.trimAscii.toString
  }

/-- Parse all sorry warnings from build output -/
def parseSorryWarnings (output : String) : Array SorryWarning :=
  let lines := output.splitOn "\n"
  lines.filterMap parseSorryWarning |>.toArray

/-- Normalize a file path by removing leading ./ and extracting filename -/
def normalizePathForMatch (path : String) : String :=
  -- Remove leading ./ sequences
  let cleaned := path.replace "././" ""
  -- Get just the filename for final fallback comparison
  let parts := cleaned.splitOn "/"
  parts[parts.length - 1]!

/-- Check if two file paths refer to the same file -/
def pathsMatch (path1 : String) (path2 : String) : Bool :=
  -- Direct match
  path1 == path2 ||
  -- Suffix match (handles absolute vs relative)
  path1.endsWith path2 ||
  path2.endsWith path1 ||
  -- Filename match (handles ./ prefixes)
  normalizePathForMatch path1 == normalizePathForMatch path2

/-- Check if a sorry warning falls within a declaration's line range -/
def sorryInDeclaration (warning : SorryWarning) (atom : Atom) : Bool :=
  -- Check file path matches
  if !pathsMatch warning.filePath atom.codePath then false
  else
    match atom.codeText with
    | none => false
    | some range =>
      warning.line >= range.linesStart && warning.line <= range.linesEnd

/-- Find all sorries for a given atom -/
def findSorriesForAtom (warnings : Array SorryWarning) (atom : Atom) : Array SorryInfo :=
  warnings.filterMap fun w =>
    if sorryInDeclaration w atom then
      some { line := w.line, message := w.message }
    else
      none

/-- Convert an atom and its sorries to a ProofEntry -/
def atomToProofEntry (atom : Atom) (sorries : Array SorryInfo) : ProofEntry :=
  let verified := sorries.isEmpty
  let status := if verified then VerifyStatus.success else VerifyStatus.sorries
  let codeLine := match atom.codeText with
    | some range => range.linesStart
    | none => 0
  {
    verified := verified
    status := status
    codePath := atom.codePath
    codeLine := codeLine
    sorries := sorries
  }

/-- Run lake build and capture output -/
def runLakeBuild (projectPath : System.FilePath) : IO (String × String × UInt32) := do
  runCmd "lake" #["build"] (some projectPath)

/-- Get cache directory path -/
def getCacheDir (projectPath : System.FilePath) : System.FilePath :=
  projectPath / ".lake" / "probe-lean"

/-- Get cache file paths -/
def getCacheFiles (projectPath : System.FilePath) : System.FilePath × System.FilePath :=
  let cacheDir := getCacheDir projectPath
  (cacheDir / "build_output.txt", cacheDir / "build_config.json")

/-- Recursively check if any .lean file is newer than cache -/
partial def checkFilesNewerThan (dir : System.FilePath) (cacheTime : IO.FS.SystemTime) : IO Bool := do
  let entries ← dir.readDir
  for entry in entries do
    let path := entry.path
    if ← path.isDir then
      if ← checkFilesNewerThan path cacheTime then return true
    else if path.extension == some "lean" then
      let fileMeta ← path.metadata
      if fileMeta.modified > cacheTime then return true
  return false

/-- Check if cache is valid (exists and newer than any .lean file) -/
def isCacheValid (projectPath : System.FilePath) : IO Bool := do
  let (outputCache, _) := getCacheFiles projectPath
  if !(← outputCache.pathExists) then return false

  -- Get cache modification time
  let cacheMeta ← outputCache.metadata
  let cacheTime := cacheMeta.modified

  -- Check if any .lean file is newer
  let hasNewerFile ← checkFilesNewerThan projectPath cacheTime
  return !hasNewerFile

/-- Save build output to cache -/
def saveCache (projectPath : System.FilePath) (output : String) : IO Unit := do
  let cacheDir := getCacheDir projectPath
  IO.FS.createDirAll cacheDir
  let (outputCache, _) := getCacheFiles projectPath
  IO.FS.writeFile outputCache output

/-- Load build output from cache -/
def loadCache (projectPath : System.FilePath) : IO (Option String) := do
  let (outputCache, _) := getCacheFiles projectPath
  if ← outputCache.pathExists then
    some <$> IO.FS.readFile outputCache
  else
    return none

/-- Convert atoms to proofs output (as JSON object keyed by name) -/
def atomsToProofsJson (atoms : AtomsOutput) (warnings : Array SorryWarning) : Json :=
  let entries := atoms.atoms.map fun atom =>
    let sorries := findSorriesForAtom warnings atom
    (atom.name, toJson (atomToProofEntry atom sorries))
  Json.mkObj entries.toList

/-- Run the verify command -/
def runVerifyInProject (config : VerifyConfig) : IO UInt32 := do
  -- Determine atoms.json path
  let atomsPath := config.atomsPath.getD (config.projectPath / ".verilib" / "atoms.json")

  IO.println s!"Loading atoms from {atomsPath}..."

  -- Load atoms
  let atoms ← match ← loadAtoms atomsPath with
  | .error msg =>
    IO.eprintln s!"Error: {msg}"
    return 1
  | .ok atoms => pure atoms

  IO.println s!"Found {atoms.atoms.size} declarations"

  -- Get build output
  let buildOutput ← if let some fromFile := config.fromFile then
    -- Use provided file
    IO.println s!"Reading build output from {fromFile}..."
    IO.FS.readFile fromFile
  else if !config.noCache then
    -- Try cache first
    if ← isCacheValid config.projectPath then
      IO.println "Using cached build output..."
      match ← loadCache config.projectPath with
      | some output => pure output
      | none =>
        IO.println "Cache invalid, rebuilding..."
        let (stdout, stderr, _) ← runLakeBuild config.projectPath
        let output := stdout ++ "\n" ++ stderr
        saveCache config.projectPath output
        pure output
    else
      IO.println "Building project..."
      let (stdout, stderr, _) ← runLakeBuild config.projectPath
      let output := stdout ++ "\n" ++ stderr
      saveCache config.projectPath output
      pure output
  else
    -- No cache
    IO.println "Building project..."
    let (stdout, stderr, _) ← runLakeBuild config.projectPath
    pure (stdout ++ "\n" ++ stderr)

  -- Parse sorry warnings
  let warnings := parseSorryWarnings buildOutput
  IO.println s!"Found {warnings.size} sorry warnings"

  -- Convert to proofs
  let proofsJson := atomsToProofsJson atoms warnings

  -- Count verified vs unverified
  let verified := atoms.atoms.filter fun atom =>
    (findSorriesForAtom warnings atom).isEmpty
  IO.println s!"Verified: {verified.size}/{atoms.atoms.size} declarations"

  -- Write output
  let outputPath := config.outputPath.getD (config.projectPath / ".verilib" / "proofs.json")
  IO.FS.createDirAll outputPath.parent.get!
  IO.FS.writeFile outputPath proofsJson.pretty
  IO.println s!"Wrote proofs to {outputPath}"

  return 0

end ProbeLean
