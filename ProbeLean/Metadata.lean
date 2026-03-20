/-
  Schema 2.0 metadata gathering and output path construction.
  Reads git info and lakefile to populate envelope fields.
  Callers construct typed `Envelope α` directly rather than using generic wrappers.
-/
import Lean
import ProbeLean.Types
import ProbeLean.Environment

namespace ProbeLean

open Lean

/-- Run a command and return trimmed stdout, or a fallback on failure. -/
private def runCmdOrDefault (cmd : String) (args : Array String)
    (cwd : Option System.FilePath) (default : String) : IO String := do
  try
    let (stdout, _, exitCode) ← runCmd cmd args cwd
    if exitCode == 0 then return stdout.trimAscii.toString
    else return default
  catch _ => return default

def getGitCommit (projectPath : System.FilePath) : IO String :=
  runCmdOrDefault "git" #["rev-parse", "HEAD"] (some projectPath) ""

def getGitRemoteUrl (projectPath : System.FilePath) : IO String :=
  runCmdOrDefault "git" #["remote", "get-url", "origin"] (some projectPath) ""

def getCurrentTimestamp : IO String :=
  runCmdOrDefault "date" #["-u", "+%Y-%m-%dT%H:%M:%SZ"] none "1970-01-01T00:00:00Z"

/-- Parse `name = "value"` from a TOML line. -/
def parsePackageNameFromToml (content : String) : Option String := do
  for line in content.splitOn "\n" do
    let trimmed := line.trimAscii.toString
    if trimmed.startsWith "[" then break
    if trimmed.startsWith "name" then
      let parts := trimmed.splitOn "="
      if parts.length >= 2 then
        let valuePart := (String.intercalate "=" (parts.drop 1)).trimAscii.toString
        if valuePart.startsWith "\"" && valuePart.endsWith "\"" then
          let stripped := valuePart.drop 1
          return (stripped.dropEnd 1).toString
  none

/-- Parse `version = "value"` from a TOML line. -/
def parsePackageVersionFromToml (content : String) : Option String := do
  for line in content.splitOn "\n" do
    let trimmed := line.trimAscii.toString
    if trimmed.startsWith "[" then break
    if trimmed.startsWith "version" then
      let parts := trimmed.splitOn "="
      if parts.length >= 2 then
        let valuePart := (String.intercalate "=" (parts.drop 1)).trimAscii.toString
        if valuePart.startsWith "\"" && valuePart.endsWith "\"" then
          let stripped := valuePart.drop 1
          return (stripped.dropEnd 1).toString
  none

/-- Extract all `[[lean_lib]]` library names from a lakefile.toml string. -/
def parseLeanLibsFromToml (content : String) : Array String := Id.run do
  let mut result : Array String := #[]
  let mut inLeanLib := false
  for line in content.splitOn "\n" do
    let trimmed := line.trimAscii.toString
    if trimmed.startsWith "[[" || trimmed.startsWith "[" then
      inLeanLib := trimmed.replace " " "" |>.startsWith "[[lean_lib]]"
    else if inLeanLib && trimmed.startsWith "name" then
      let parts := trimmed.splitOn "="
      if parts.length >= 2 then
        let valuePart := (String.intercalate "=" (parts.drop 1)).trimAscii.toString
        if valuePart.startsWith "\"" && valuePart.endsWith "\"" then
          let stripped := valuePart.drop 1
          result := result.push (stripped.dropEnd 1).toString
  result

/-- Parse `defaultTargets = ["Lib1", "Lib2"]` from a lakefile.toml string. -/
def parseDefaultTargetsFromToml (content : String) : Array String := Id.run do
  let mut result : Array String := #[]
  for line in content.splitOn "\n" do
    let trimmed := line.trimAscii.toString
    if trimmed.startsWith "[" then break
    if trimmed.startsWith "defaultTargets" then
      let parts := trimmed.splitOn "="
      if parts.length >= 2 then
        let valuePart := (String.intercalate "=" (parts.drop 1)).trimAscii.toString
        if valuePart.startsWith "[" && valuePart.endsWith "]" then
          let inner := ((valuePart.drop 1).dropEnd 1).toString
          for entry in inner.splitOn "," do
            let e := entry.trimAscii.toString
            if e.startsWith "\"" && e.endsWith "\"" then
              result := result.push ((e.drop 1).dropEnd 1).toString
  result

/-- Read build targets from a project's lakefile.toml.
    Prefers `defaultTargets` when present; falls back to all `[[lean_lib]]` names.
    Returns an empty array if the file doesn't exist or has no targets. -/
def getLeanLibs (projectPath : System.FilePath) : IO (Array String) := do
  let tomlPath := projectPath / "lakefile.toml"
  if ← tomlPath.pathExists then
    let content ← IO.FS.readFile tomlPath
    let defaults := parseDefaultTargetsFromToml content
    if !defaults.isEmpty then return defaults
    return parseLeanLibsFromToml content
  return #[]

/-- Get package name and version from lakefile.toml / lakefile.lean / lake-manifest.json.
    Falls back to directory name for name and short git commit for version. -/
def getPackageInfo (projectPath : System.FilePath) (commit : String) : IO (String × String) := do
  let mut name := ""
  let mut version := ""

  let tomlPath := projectPath / "lakefile.toml"
  if ← tomlPath.pathExists then
    let content ← IO.FS.readFile tomlPath
    if let some n := parsePackageNameFromToml content then
      name := n
    if let some v := parsePackageVersionFromToml content then
      version := v

  if name.isEmpty then
    let manifestPath := projectPath / "lake-manifest.json"
    if ← manifestPath.pathExists then
      let content ← IO.FS.readFile manifestPath
      if let .ok json := Json.parse content then
        if let .ok n := json.getObjValAs? String "name" then
          name := n.replace "«" "" |>.replace "»" ""

  if name.isEmpty then
    name := (projectPath.fileName.getD "unknown-package")

  if version.isEmpty then
    if commit.length >= 7 then
      version := (commit.take 7).toString
    else
      version := "0.0.0"

  return (name, version)

/-- Collect all source metadata into a SourceInfo.
    Returns non-optional strings (empty when unavailable) to conform to the
    probe repo JSON schema which declares repo/commit as required fields. -/
def collectSourceInfo (projectPath : System.FilePath) : IO SourceInfo := do
  let repo ← getGitRemoteUrl projectPath
  let commit ← getGitCommit projectPath
  let (pkgName, pkgVersion) ← getPackageInfo projectPath commit
  return {
    repo := repo
    commit := commit
    language := "lean"
    package := pkgName
    packageVersion := pkgVersion
  }

/-- Generate output filename: `lean_<package>_<version>.json`
    Replaces dashes with underscores in the package name. -/
def generateOutputFilename (source : SourceInfo) : String :=
  let safePackage := source.package.replace "-" "_"
  s!"lean_{safePackage}_{source.packageVersion}.json"

/-- Build path to probes output: `.verilib/probes/lean_<pkg>_<ver>.json` -/
def buildProbesOutputPath (projectPath : System.FilePath) (source : SourceInfo) : System.FilePath :=
  projectPath / Constants.verilibDir / Constants.probesDir / generateOutputFilename source

/-- Build path to views output: `.verilib/views/molecules_all.json` -/
def buildViewsOutputPath (projectPath : System.FilePath) : System.FilePath :=
  projectPath / Constants.verilibDir / Constants.viewsDir / "molecules_all.json"

/-- Check if a filename matches the probes file pattern `lean_<prefix>*.json`.
    Only prefix+suffix are checked because each output type now lives in its own
    directory (probes/, views/, maps/), so there are no sibling files to confuse. -/
def isAtomsFileName (name : String) (pkgNamePrefix : String) : Bool :=
  name.startsWith pkgNamePrefix && name.endsWith ".json"

/-- Find the default probes input path. Tries the exact computed path first;
    if it doesn't exist, searches .verilib/probes/ for a matching file
    (picking the most recently modified one). Emits a warning when falling back.
    Returns `(path, usedFallback)`. -/
def findDefaultAtomsPath (projectPath : System.FilePath) (source : SourceInfo)
    : IO (System.FilePath × Bool) := do
  let exactPath := buildProbesOutputPath projectPath source
  if ← exactPath.pathExists then return (exactPath, false)
  let probesDir := projectPath / Constants.verilibDir / Constants.probesDir
  if !(← probesDir.pathExists) then
    IO.eprintln s!"Warning: probes file not found at {exactPath} and {probesDir} does not exist"
    return (exactPath, false)
  let entries ← probesDir.readDir
  let namePrefix := s!"lean_{source.package.replace "-" "_"}_"
  let mut candidates : Array (System.FilePath × IO.FS.SystemTime) := #[]
  for entry in entries do
    if isAtomsFileName entry.fileName namePrefix then
      try
        let fileMeta ← entry.path.metadata
        candidates := candidates.push (entry.path, fileMeta.modified)
      catch _ => pure ()
  if candidates.isEmpty then
    IO.eprintln s!"Warning: probes file not found at {exactPath} and no alternatives found in {probesDir}"
    return (exactPath, false)
  let sorted := candidates.qsort fun (_, t1) (_, t2) => t1 > t2
  match sorted[0]? with
  | some (chosen, _) =>
    IO.eprintln s!"Warning: exact probes path {exactPath} not found; using {chosen} (from a different version)"
    return (chosen, true)
  | none =>
    IO.eprintln s!"Warning: probes file not found at {exactPath} and no alternatives found in {probesDir}"
    return (exactPath, false)

end ProbeLean
