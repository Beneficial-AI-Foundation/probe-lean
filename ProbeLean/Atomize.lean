/-
  Atomize command implementation.
-/
import Lean
import ProbeLean.Types
import ProbeLean.Environment
import ProbeLean.Analysis

namespace ProbeLean

open Lean

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
def runAnalysisViaLakeEnv (projectPath : System.FilePath) (modules : Array Name) : IO (Except String (Array Atom)) := do
  -- Get absolute project path
  let absProjectPath ← IO.FS.realPath projectPath

  -- Initialize Lean
  Lean.initSearchPath (← Lean.findSysroot)

  -- Get LEAN_PATH from the target project
  let (leanPathOut, _, exitCode) ← runCmd "lake" #["env", "printenv", "LEAN_PATH"] (some absProjectPath)
  if exitCode != 0 then
    return .error "Failed to get LEAN_PATH from target project"

  let leanPath := leanPathOut.trim

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
    let atom ← declInfoToAtom env projectPath modules decl
    atoms := atoms.push atom

  return .ok atoms

/-- Run the atomize command within the context of the target project -/
def runAtomizeInProject (config : AtomizeConfig) : IO UInt32 := do
  -- Validate project path
  if !(← isLakeProject config.projectPath) then
    IO.eprintln s!"Error: Not a Lake project (missing lakefile.lean or lakefile.toml): {config.projectPath}"
    return 1

  -- Build the project first
  IO.println s!"Building project at {config.projectPath}..."
  match ← buildProject config.projectPath with
  | .error msg =>
    IO.eprintln msg
    return 1
  | .ok () => pure ()

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

  -- Use lake env to run analysis with correct environment
  let analysisResult ← runAnalysisViaLakeEnv config.projectPath filteredModules

  match analysisResult with
  | .error msg =>
    IO.eprintln s!"Analysis failed: {msg}"
    return 1
  | .ok atoms =>
    -- Write output
    let output : AtomsOutput := { atoms := atoms }
    let json := Lean.toJson output
    let jsonStr := json.pretty

    let outputPath := config.outputPath.getD (config.projectPath / "atoms.json")
    IO.FS.writeFile outputPath jsonStr
    IO.println s!"Wrote {atoms.size} atoms to {outputPath}"
    return 0

end ProbeLean
