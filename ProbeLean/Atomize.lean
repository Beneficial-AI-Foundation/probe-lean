/-
  Atomize: core logic for extracting dependency graph atoms from a Lean environment.
  Not a CLI command - used by Verify.lean.
-/
import Lean
import ProbeLean.Types
import ProbeLean.Environment
import ProbeLean.Analysis

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

/-- Resolve a potentially relative path against a base directory -/
def resolvePath (basePath : System.FilePath) (path : System.FilePath) : IO System.FilePath := do
  let pathStr := path.toString
  if pathStr.startsWith "/" then
    return path
  else
    let resolved := basePath / path
    if ← resolved.pathExists then
      return resolved
    else
      return resolved

/-- Run analysis via lake env to get correct search paths -/
def runAnalysisViaLakeEnv (projectPath : System.FilePath) (modules : Array Name) (crate : String) : IO (Except String (Array Atom)) := do
  let absProjectPath ← IO.FS.realPath projectPath

  Lean.initSearchPath (← Lean.findSysroot)

  let (leanPathOut, _, exitCode) ← runCmd "lake" #["env", "printenv", "LEAN_PATH"] (some absProjectPath)
  if exitCode != 0 then
    return .error "Failed to get LEAN_PATH from target project"

  let leanPath := leanPathOut.trimAscii.toString

  let paths := leanPath.splitOn ":"
  let mut searchPaths : Array System.FilePath := #[]
  for p in paths do
    let resolved ← resolvePath absProjectPath p
    searchPaths := searchPaths.push resolved

  Lean.searchPathRef.set searchPaths.toList

  let imports := modules.map fun m => { module := m : Import }

  IO.println s!"Importing {imports.size} modules..."

  let env ← try
    importModules imports {} 0
  catch e =>
    return .error s!"Failed to import modules: {e}"

  IO.println "Extracting declarations..."

  let decls := getProjectDecls env modules

  IO.println s!"Found {decls.size} declarations"

  let mut atoms : Array Atom := #[]
  for decl in decls do
    let atom ← declInfoToAtom env projectPath modules crate decl
    atoms := atoms.push atom

  return .ok atoms

end ProbeLean
