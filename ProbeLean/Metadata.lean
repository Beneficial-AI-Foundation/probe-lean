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
  runCmdOrDefault "date" #["-u", "+%Y-%m-%dT%H:%M:%SZ"] none ""

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
def getPackageNameAndVersion (projectPath : System.FilePath) : IO (String × String) := do
  let mut name := ""
  let mut version := ""

  let tomlPath := projectPath / "lakefile.toml"
  if ← tomlPath.pathExists then
    let content ← IO.FS.readFile tomlPath
    for line in content.splitOn "\n" do
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
    let commit ← getGitCommit projectPath
    if commit.length >= 7 then
      version := (commit.take 7).toString
    else
      version := "unknown"

  return (name, version)

/-- Wrap a JSON payload in a Schema 2.0 envelope. -/
def wrapInEnvelope (schema command : String) (data : Json) (projectPath : System.FilePath) : IO Json := do
  let commit ← getGitCommit projectPath
  let repo ← getGitRemoteUrl projectPath
  let timestamp ← getTimestamp
  let (pkgName, pkgVersion) ← getPackageNameAndVersion projectPath

  let tool : ToolInfo := {
    name := "probe-lean"
    version := probeVersion
    command := command
  }
  let source : SourceInfo := {
    repo := repo
    commit := commit
    language := "lean"
    package := pkgName
    packageVersion := pkgVersion
  }

  return Json.mkObj [
    ("schema", toJson schema),
    ("schema-version", toJson "2.0"),
    ("tool", toJson tool),
    ("source", toJson source),
    ("timestamp", toJson timestamp),
    ("data", data)
  ]

end ProbeLean
