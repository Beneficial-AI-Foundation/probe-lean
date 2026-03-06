/-
  Atomize command implementation.
-/
import Lean
import ProbeLean.Types
import ProbeLean.Environment
import ProbeLean.Analysis
import ProbeLean.Metadata

namespace ProbeLean

open Lean

/-- Load user config from .verilib/config.json -/
def loadUserConfig (projectPath : System.FilePath) : IO (Option Lean.Json) := do
  let configPath := projectPath / ".verilib" / "config.json"
  if !(← configPath.pathExists) then
    return none
  let content ← IO.FS.readFile configPath
  match Lean.Json.parse content with
  | .error _ => return none
  | .ok json =>
    match json.getObjVal? "user" with
    | .error _ => return none
    | .ok userObj => return some userObj

/-- Load the is-hidden list from .verilib/config.json -/
def loadIsHiddenList (userConfig : Option Lean.Json) : Array String :=
  match userConfig with
  | none => #[]
  | some userObj =>
    match userObj.getObjValAs? (Array String) "is-hidden" with
    | .error _ => #[]
    | .ok arr => arr

/-- Load the extraction-artifact-suffixes list from .verilib/config.json -/
def loadExtractionArtifactSuffixes (userConfig : Option Lean.Json) : Array String :=
  match userConfig with
  | none => #[]
  | some userObj =>
    match userObj.getObjValAs? (Array String) "extraction-artifact-suffixes" with
    | .error _ => #[]
    | .ok arr => arr

/-- Load the is-ignored list from .verilib/config.json -/
def loadIsIgnoredList (userConfig : Option Lean.Json) : Array String :=
  match userConfig with
  | none => #[]
  | some userObj =>
    match userObj.getObjValAs? (Array String) "is-ignored" with
    | .error _ => #[]
    | .ok arr => arr

/-- Load the relevant-crate from .verilib/config.json -/
def loadRelevantCrate (userConfig : Option Lean.Json) : String :=
  match userConfig with
  | none => ""
  | some userObj =>
    match userObj.getObjValAs? String "relevant-crate" with
    | .error _ => ""
    | .ok crate => crate

/-- Strip "probe:" prefix from an atom name -/
def stripProbePrefix (name : String) : String :=
  if name.startsWith "probe:" then (name.drop 6).toString else name

/-- Check if a name ends with any of the given suffixes -/
def hasAnySuffix (name : String) (suffixes : Array String) : Bool :=
  suffixes.any fun suffix => name.endsWith suffix

/-- Set isHidden, isExtractionArtifact, and isIgnored fields on atoms based on config -/
def markAtomFlags (atoms : Array Atom) (hiddenList : Array String) (artifactSuffixes : Array String) (ignoredList : Array String) : Array Atom :=
  atoms.map fun atom =>
    let nameWithoutPrefix := stripProbePrefix atom.name
    let isHidden := hiddenList.contains nameWithoutPrefix
    let isExtractionArtifact := hasAnySuffix nameWithoutPrefix artifactSuffixes
    let isIgnored := ignoredList.contains nameWithoutPrefix
    { atom with isHidden := isHidden, isExtractionArtifact := isExtractionArtifact, isIgnored := isIgnored }

/-- Configuration for the atomize command -/
structure AtomizeConfig where
  projectPath : System.FilePath
  outputPath : Option System.FilePath
  moduleFilter : Option String
  deriving Repr

/-- Resolve a potentially relative path against a base directory -/
def resolvePath (basePath : System.FilePath) (path : System.FilePath) : IO System.FilePath := do
  let pathStr := path.toString
  -- Check if path is relative (starts with . or doesn't start with /)
  if pathStr.startsWith "/" then
    return path
  else
    -- Resolve relative to basePath
    let resolved := basePath / path
    -- Try to normalize it
    if ← resolved.pathExists then
      return resolved
    else
      return resolved

/-- Run analysis via lake env to get correct search paths -/
def runAnalysisViaLakeEnv (projectPath : System.FilePath) (modules : Array Name) (crate : String) : IO (Except String (Array Atom)) := do
  -- Get absolute project path
  let absProjectPath ← IO.FS.realPath projectPath

  -- Initialize Lean
  Lean.initSearchPath (← Lean.findSysroot)

  -- Get LEAN_PATH from the target project
  let (leanPathOut, _, exitCode) ← runCmd "lake" #["env", "printenv", "LEAN_PATH"] (some absProjectPath)
  if exitCode != 0 then
    return .error "Failed to get LEAN_PATH from target project"

  let leanPath := leanPathOut.trimAscii.toString

  -- Set up search path with project's paths, resolving relative paths
  let paths := leanPath.splitOn ":"
  let mut searchPaths : Array System.FilePath := #[]
  for p in paths do
    let resolved ← resolvePath absProjectPath p
    searchPaths := searchPaths.push resolved

  Lean.searchPathRef.set searchPaths.toList

  -- Import all project modules
  let imports := modules.map fun m => { module := m : Import }

  IO.println s!"Importing {imports.size} modules..."

  let env ← try
    importModules imports {} 0
  catch e =>
    return .error s!"Failed to import modules: {e}"

  IO.println "Extracting declarations..."

  -- Get project declarations
  let decls := getProjectDecls env modules

  IO.println s!"Found {decls.size} declarations"

  -- Convert to atoms
  let mut atoms : Array Atom := #[]
  for decl in decls do
    let atom ← declInfoToAtom env projectPath modules crate decl
    atoms := atoms.push atom

  return .ok atoms

/-- Run the atomize command within the context of the target project -/
def runAtomizeInProject (config : AtomizeConfig) : IO UInt32 := do
  -- Validate project path
  if !(← isLakeProject config.projectPath) then
    IO.eprintln s!"Error: Not a Lake project (missing lakefile.lean or lakefile.toml): {config.projectPath}"
    return 1

  -- Build the project first (and cache output for later verify)
  IO.println s!"Building project at {config.projectPath}..."
  match ← buildProject config.projectPath with
  | .error msg =>
    IO.eprintln msg
    return 1
  | .ok buildOutput =>
    saveCache config.projectPath buildOutput

  IO.println "Getting project modules..."
  -- Get the list of project modules
  let modules ← match ← getProjectModules config.projectPath with
  | .error msg =>
    IO.eprintln msg
    return 1
  | .ok mods => pure mods

  if modules.isEmpty then
    IO.eprintln "Warning: No modules found in project"
    return 1

  IO.println s!"Found {modules.size} modules"

  -- Apply module filter if specified
  let filteredModules := match config.moduleFilter with
    | some filter =>
      let filterName := String.toName filter
      modules.filter fun m =>
        m == filterName || m.toString.startsWith (filter ++ ".")
    | none => modules

  IO.println s!"Analyzing {filteredModules.size} modules..."

  -- Load config to get crate name for relevance detection
  let userConfig ← loadUserConfig config.projectPath
  let crate := loadRelevantCrate userConfig

  -- Use lake env to run analysis with correct environment
  let analysisResult ← runAnalysisViaLakeEnv config.projectPath filteredModules crate

  match analysisResult with
  | .error msg =>
    IO.eprintln s!"Analysis failed: {msg}"
    return 1
  | .ok atoms =>
    -- Mark atoms with is-hidden, is-extraction-artifact, and is-ignored flags from config
    let hiddenList := loadIsHiddenList userConfig
    let artifactSuffixes := loadExtractionArtifactSuffixes userConfig
    let ignoredList := loadIsIgnoredList userConfig
    let atoms := markAtomFlags atoms hiddenList artifactSuffixes ignoredList

    let output : AtomsOutput := { atoms := atoms }
    let pm ← gatherMetadata config.projectPath
    let envelope := wrapInEnvelopeWith "probe-lean/atoms" "atomize" (Lean.toJson output) pm
    let jsonStr := envelope.pretty

    let outputPath := config.outputPath.getD (getDefaultOutputPath config.projectPath pm "")
    if let some parentDir := outputPath.parent then
      IO.FS.createDirAll parentDir
    IO.FS.writeFile outputPath jsonStr
    IO.println s!"Wrote {atoms.size} atoms to {outputPath}"
    return 0

end ProbeLean
