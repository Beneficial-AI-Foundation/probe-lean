/-
  Environment loading for external Lean projects.
-/
import Lean
import ProbeLean.NixEnv
import ProbeLean.WorkspaceInfo

namespace ProbeLean

/-- Check if a path is a valid Lake project -/
def isLakeProject (path : System.FilePath) : IO Bool := do
  let lakefileLean := path / "lakefile.lean"
  let lakefileToml := path / "lakefile.toml"
  let hasLean ← lakefileLean.pathExists
  let hasToml ← lakefileToml.pathExists
  return hasLean || hasToml

/-- Run a command and return stdout, stderr, and exit code. `IO.Process.output`
    reads both pipes at the same time, so a child that fills the stderr pipe
    before it closes stdout does not block. -/
def runCmd (cmd : String) (args : Array String) (cwd : Option System.FilePath := none) : IO (String × String × UInt32) := do
  let out ← IO.Process.output { cmd, args, cwd }
  return (out.stdout, out.stderr, out.exitCode)

/-- Quote one argument for a POSIX shell: wrap it in single quotes and write each
    single quote inside it as `'\''`. -/
def shellQuote (s : String) : String :=
  "'" ++ s.replace "'" "'\\''" ++ "'"

/-- The `nix-shell --run` string for `lake <args>`, every argument quoted with
    `shellQuote`, so a space, a quote or a `$` in an argument reaches Lake as is. -/
def nixShellRunString (args : Array String) : String :=
  " ".intercalate ("lake" :: args.toList.map shellQuote)

/-- Run a lake command, optionally wrapping it in nix-shell / nix develop
    when the project provides a Nix environment and nix is installed. -/
def runLakeCmd (args : Array String) (cwd : Option System.FilePath := none)
    (nixMode : Option NixMode := none) : IO (String × String × UInt32) :=
  match nixMode with
  | some .flake =>
    let nixArgs := #["develop", "path:.",
      "--extra-experimental-features", "nix-command flakes",
      "--command", "lake"] ++ args
    runCmd "nix" nixArgs cwd
  | some .shell =>
    runCmd "nix-shell" #["--run", nixShellRunString args] cwd
  | none =>
    runCmd "lake" args cwd

/-- The error for a failed helper call (`queryWorkspaceInfo`, `queryOwners`). Exit
    code `helperGithashExit` means the target uses another Lean, and the
    helper's stderr then names both githashes. -/
def formatHelperFailure (command : String) (exitCode : UInt32) (stderr : String) : String :=
  if exitCode == helperGithashExit then stderr.trimAscii.toString
  else s!"Error: the Lake workspace load failed (`lake env probe-lean {command}`, \
    exit {exitCode}):\n{stderr.trimAscii}"

/-- Run the hidden `workspace-info` subcommand of this binary under `lake env` in
    the project directory (`ProbeLean/Workspace.lean`) and decode its answer. Also
    checks the githash in the answer against probe-lean's own, as a second guard. -/
def queryWorkspaceInfo (projectPath : System.FilePath) (nixMode : Option NixMode)
    : IO (Except String WorkspaceInfo) := do
  let app ← IO.appPath
  let (out, err, code) ← runLakeCmd #["env", app.toString, "workspace-info"]
    (some projectPath) nixMode
  if code != 0 then return .error (formatHelperFailure "workspace-info" code err)
  match decodeWorkspaceInfo out with
  | .error e => return .error s!"Error: {e}"
  | .ok info =>
    unless githashMatches info.leanGithash Lean.githash do
      return .error (formatGithashMismatch info.leanGithash Lean.githash)
    return .ok info

/-- Ask the helper (`workspace-owners`) for the owners of `names`. The names go
    through a temporary file outside the project, deleted after the call. The answer
    must cover every name exactly once (`checkOwnersComplete`). -/
def queryOwners (projectPath : System.FilePath) (nixMode : Option NixMode)
    (names : Array Lean.Name) : IO (Except String (Array OwnerInfo)) := do
  let app ← IO.appPath
  IO.FS.withTempFile fun h file => do
    h.putStr (encodeOwnerRequest names)
    h.flush
    let (out, err, code) ← runLakeCmd #["env", app.toString, "workspace-owners", file.toString]
      (some projectPath) nixMode
    if code != 0 then return .error (formatHelperFailure "workspace-owners" code err)
    match decodeOwners out with
    | .error e => return .error s!"Error: {e}"
    | .ok owners =>
      match checkOwnersComplete names owners with
      | .error e => return .error s!"Error: {e}"
      | .ok () => return .ok owners

/-- Convert an olean's slash-separated relative path (`.olean` suffix already
    stripped) to its module name, one atomic component per path segment. Lean
    core uses the same construction (`Lean.moduleNameOfFileName`).
    Built with `Name.mkStr` rather than `String.toName` because path segments
    are not necessarily plain identifiers. For example, the file
    `Misc/Real-EReal-ENNReal.lean` is a legal Lake module, written
    `Misc.«Real-EReal-ENNReal»`. `String.toName` mangles such segments. A
    non-identifier segment collapses the whole name to `.anonymous`, which
    `importModules` rejects outright. A digit-only segment becomes a numeric
    component, which is invalid in module names. -/
def pathToModuleName (relPath : String) : Lean.Name :=
  (relPath.splitOn "/").foldl .mkStr .anonymous

/-- Convert a module name back to the slash-separated relative path of its
    backing source file (extension not included). It is the inverse of
    `pathToModuleName`. Reads each atomic component's string directly rather
    than going through `Name.toString`, whose guillemet quoting
    (`Misc.«Real-EReal-ENNReal»`) never appears in file names. Module names
    have no numeric components (Lean's own module-path resolution rejects
    them), so a `.num` component yields `none`. -/
def moduleNameToRelPath : Lean.Name → Option String
  | .anonymous => none
  | .str .anonymous s => some s
  | .str p s => (moduleNameToRelPath p).map (· ++ "/" ++ s)
  | .num _ _ => none

end ProbeLean
