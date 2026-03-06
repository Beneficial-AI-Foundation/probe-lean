/-
  Schema 2.0 metadata gathering and envelope construction.
  Reads git info and lakefile to populate the envelope fields.
-/
import Lean
import ProbeLean.Types
import ProbeLean.Environment

namespace ProbeLean

open Lean

def probeVersion : String := "0.1.0"

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

def getTimestamp : IO String :=
  runCmdOrDefault "date" #["-u", "+%Y-%m-%dT%H:%M:%SZ"] none "1970-01-01T00:00:00Z"

/-- Try to extract `name = "value"` from a TOML line. -/
private def extractTomlString (line : String) (key : String) : Option String := do
  let trimmed := line.trimAscii.toString
  if !trimmed.startsWith key then none
  else
    let rest := (trimmed.drop key.length).toString.trimAscii.toString
    if !rest.startsWith "=" then none
    else
      let afterEq := (rest.drop 1).toString.trimAscii.toString
      if afterEq.startsWith "\"" && afterEq.endsWith "\"" then
        let stripped := (afterEq.drop 1).toString
        some (stripped.take (stripped.length - 1)).toString
      else none

/-- Read package name and version from lakefile.toml via string matching.
    Falls back to lake-manifest.json for name, and short git commit for version. -/
def getPackageNameAndVersion (projectPath : System.FilePath) (commit : String) : IO (String × String) := do
  let mut name := ""
  let mut version := ""

  let tomlPath := projectPath / "lakefile.toml"
  if ← tomlPath.pathExists then
    let content ← IO.FS.readFile tomlPath
    for line in content.splitOn "\n" do
      let trimmed := line.trimAscii.toString
      if trimmed.startsWith "[" then break
      if name.isEmpty then
        if let some v := extractTomlString line "name" then
          name := v
      if version.isEmpty then
        if let some v := extractTomlString line "version" then
          version := v

  if name.isEmpty then
    let manifestPath := projectPath / "lake-manifest.json"
    if ← manifestPath.pathExists then
      let content ← IO.FS.readFile manifestPath
      if let .ok json := Json.parse content then
        if let .ok n := json.getObjValAs? String "name" then
          name := n.replace "«" "" |>.replace "»" ""

  if version.isEmpty then
    if commit.length >= 7 then
      version := (commit.take 7).toString
    else
      version := "unknown"

  return (name, version)

/-- Gathered metadata for the project, used by both envelope wrapping and output path generation. -/
structure ProjectMetadata where
  commit : String
  repo : String
  timestamp : String
  pkgName : String
  pkgVersion : String
  deriving Repr

/-- Gather all project metadata in one pass (git info, package name/version, timestamp). -/
def gatherMetadata (projectPath : System.FilePath) : IO ProjectMetadata := do
  let commit ← getGitCommit projectPath
  let repo ← getGitRemoteUrl projectPath
  let timestamp ← getTimestamp
  let (pkgName, pkgVersion) ← getPackageNameAndVersion projectPath commit
  return { commit, repo, timestamp, pkgName, pkgVersion }

/-- Compute the default output path for a probe-lean command.
    Format: `.verilib/probes/lean_<pkg>_<ver><suffix>.json`
    Pass `suffix = ""` for atoms, `"_specs"` for specs, etc. -/
def getDefaultOutputPath (projectPath : System.FilePath) (pm : ProjectMetadata) (suffix : String)
    : System.FilePath :=
  let filename := s!"lean_{pm.pkgName}_{pm.pkgVersion}{suffix}.json"
  projectPath / ".verilib" / "probes" / filename

/-- Check if a filename matches the atoms file pattern `lean_<pkg>_<version>.json`.
    Uses positive matching: the version portion (between prefix and `.json`) must be
    non-empty and contain no underscores (git hashes are hex-only, semver uses
    dots/hyphens), which distinguishes atoms files from derived outputs like
    `lean_<pkg>_<ver>_specs.json`. -/
def isAtomsFileName (name : String) (pkgNamePrefix : String) : Bool :=
  name.startsWith pkgNamePrefix && name.endsWith ".json" &&
    let afterPrefix := (name.drop pkgNamePrefix.length).toString
    let versionPart := (afterPrefix.take (afterPrefix.length - ".json".length)).toString
    !versionPart.isEmpty && (versionPart.splitOn "_").length == 1

/-- Find the default atoms input path. Tries the exact computed path first;
    if it doesn't exist, searches .verilib/probes/ for a matching atoms file
    (picking the most recently modified one). Emits a warning when falling back.
    This handles the case where the git commit changed between atomize and
    downstream commands (specify/verify/stubify). -/
def findDefaultAtomsPath (projectPath : System.FilePath) (pm : ProjectMetadata)
    : IO System.FilePath := do
  let exactPath := getDefaultOutputPath projectPath pm ""
  if ← exactPath.pathExists then return exactPath
  let probesDir := projectPath / ".verilib" / "probes"
  if !(← probesDir.pathExists) then
    IO.eprintln s!"Warning: atoms file not found at {exactPath} and {probesDir} does not exist"
    return exactPath
  let entries ← probesDir.readDir
  let namePrefix := s!"lean_{pm.pkgName}_"
  let mut candidates : Array (System.FilePath × IO.FS.SystemTime) := #[]
  for entry in entries do
    if isAtomsFileName entry.fileName namePrefix then
      try
        let fileMeta ← entry.path.metadata
        candidates := candidates.push (entry.path, fileMeta.modified)
      catch _ => pure ()
  if candidates.isEmpty then
    IO.eprintln s!"Warning: atoms file not found at {exactPath} and no alternatives found in {probesDir}"
    return exactPath
  let sorted := candidates.qsort fun (_, t1) (_, t2) => t1 > t2
  let chosen := sorted[0]!.1
  IO.eprintln s!"Warning: exact atoms path {exactPath} not found; using {chosen} (from a different version)"
  return chosen

/-- Wrap a JSON payload in a Schema 2.0 envelope using pre-gathered metadata. -/
def wrapInEnvelopeWith (schema command : String) (data : Json) (pm : ProjectMetadata) : Json :=
  let tool : ToolInfo := {
    name := "probe-lean"
    version := probeVersion
    command := command
  }
  let source : SourceInfo := {
    repo := pm.repo
    commit := pm.commit
    language := "lean"
    package := pm.pkgName
    packageVersion := pm.pkgVersion
  }
  Json.mkObj [
    ("schema", toJson schema),
    ("schema-version", toJson "2.0"),
    ("tool", toJson tool),
    ("source", toJson source),
    ("timestamp", toJson pm.timestamp),
    ("data", data)
  ]

/-- Wrap a JSON payload in a Schema 2.0 envelope (convenience that gathers metadata). -/
def wrapInEnvelope (schema command : String) (data : Json) (projectPath : System.FilePath) : IO Json := do
  let pm ← gatherMetadata projectPath
  return wrapInEnvelopeWith schema command data pm

end ProbeLean
