/-
  The workspace helper: two hidden subcommands that read the target project with
  Lake's own `loadWorkspace`. probe-lean runs them as
  `lake env <probe-lean> workspace-info` and
  `lake env <probe-lean> workspace-owners <file>` (`queryWorkspaceInfo`,
  `queryOwners`), in the project directory and in the Nix mode of the run. So the
  load sees the same Lean, Lake and environment as `lake build`, and probe-lean does
  not parse the lakefile itself. The output types and decoders are in
  `ProbeLean/WorkspaceInfo.lean`.
-/
import Lake
import Lake.Load
import ProbeLean.WorkspaceInfo

namespace ProbeLean

open Lean Lake

/-- Find the Lean and Lake installs, check that the target's Lean is the Lean of
    probe-lean, then load the workspace in the current directory. The check comes
    before the load: a helper built for another Lean fails inside `loadWorkspace` on
    a `lakefile.lean` project, so a check after the load never runs. On a failure,
    the result is the exit code: `helperGithashExit` for a different Lean, 1 for
    anything else. Messages go to stderr. -/
def loadRootWorkspace : IO (Except UInt32 (Workspace × String)) := do
  let (elan?, some lean, some lake) ← findInstall?
    | IO.eprintln "workspace helper: could not find the Lean and Lake installs"
      return .error 1
  let gh ← IO.Process.output
    { cmd := (lean.sysroot / "bin" / "lean").toString, args := #["--githash"] }
  if gh.exitCode != 0 then
    IO.eprintln s!"workspace helper: `lean --githash` failed:\n{gh.stderr}"
    return .error 1
  let githash := gh.stdout.trimAscii.toString
  unless githashMatches githash Lean.githash do
    IO.eprintln (formatGithashMismatch githash Lean.githash)
    return .error helperGithashExit
  let env ← match ← (Env.compute lake lean elan?).toBaseIO with
    | .ok e => pure e
    | .error e =>
      IO.eprintln s!"workspace helper: could not compute the Lake environment: {e}"
      return .error 1
  let (ws?, log) ← (loadWorkspace { lakeEnv := env, wsDir := "." }).captureLog
  let some ws := ws?
    | IO.eprintln s!"workspace helper: Lake could not load the workspace:\n{log.toString}"
      return .error 1
  return .ok (ws, githash)

/-- The `workspace-info` subcommand: print one `WorkspaceInfo` JSON line. -/
def runWorkspaceInfo : IO UInt32 := do
  let (ws, githash) ← match ← loadRootWorkspace with
    | .error code => return code
    | .ok r => pure r
  let root := ws.root
  let mut libs : Array LibInfo := #[]
  for lib in root.leanLibs do
    -- `getModuleArray` reads the directories of the library's globs, and throws if
    -- one is missing. Only a target library with an error fails the run
    -- (`chooseTargets`), as `lake build` of the other libraries does not read them.
    let entry : LibInfo ← try
        pure { name := lib.name, modules := (← lib.getModuleArray).map (·.name) }
      catch e => pure { name := lib.name, modules := #[], error := some (toString e) }
    libs := libs.push entry
  let exes := root.leanExes.map fun exe => ({ name := exe.name, root := exe.root.name } : ExeInfo)
  let info : WorkspaceInfo := {
    leanGithash := githash
    leanPath := (← IO.getEnv "LEAN_PATH").getD ""
    leanLibDir := root.leanLibDir.toString
    defaultTargets := root.defaultTargets
    libs, exes }
  IO.println (toJson info).compress
  return 0

/-- The `workspace-owners` subcommand. `file` holds one name per line
    (`encodeOwnerRequest`). Print one `OwnerInfo` JSON line per name. -/
def runWorkspaceOwners (file : System.FilePath) : IO UInt32 := do
  let names ← match decodeOwnerRequest (← IO.FS.readFile file) with
    | .ok ns => pure ns
    | .error e =>
      IO.eprintln s!"workspace helper: could not read {file}: {e}"
      return 1
  let (ws, _) ← match ← loadRootWorkspace with
    | .error code => return code
    | .ok r => pure r
  for n in names do
    let lib := (ws.root.findModule? n).map (·.lib.name)
    let exe := (ws.root.leanExes.find? (·.root.name == n)).map (·.name)
    IO.println (toJson ({ module := n, lib, exe } : OwnerInfo)).compress
  return 0

/-- Run a helper subcommand if `args` names one. `main` calls this before the CLI
    parser, so the subcommands do not show in `--help`. -/
def runWorkspaceHelper? : List String → Option (IO UInt32)
  | ["workspace-info"] => some runWorkspaceInfo
  | ["workspace-owners", file] => some (runWorkspaceOwners file)
  | _ => none

end ProbeLean
