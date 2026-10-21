/-
  The pure rules of the build and import selection: which Lake targets to build,
  the arguments of `lake build`, the `--module` filter, the ownership check of the
  project modules, and the emitted set. No `Lake` import: the inputs come from the
  workspace helper (`ProbeLean/WorkspaceInfo.lean`).

  The rule behind the ownership check: if a `lean_lib` of the workspace owns an
  imported module, Lake records the import in the importer's trace. Otherwise Lake
  takes the module's `.olean` from `LEAN_PATH` without a check. So when a
  `lean_lib` of the root package owns every project module that the import loads,
  the target build checked all of them in this run.
-/
import Lean
import ProbeLean.WorkspaceInfo

namespace ProbeLean

open Lean

/-- A Lake target that probe-lean builds: a `lean_lib`, or a `lean_exe` given by its
    name and its root module. -/
inductive Target where
  | lib (name : Name)
  | exe (name root : Name)
  deriving BEq, Repr, Inhabited

/-- Lake's parser for a target name on the command line
    (`Lake.stringToLegalOrSimpleName`, `Lake/Util/Name.lean`): a string that does not
    parse as a name becomes one atomic component. Copied, because this module does
    not import `Lake`. -/
def stringToLegalOrSimpleName (s : String) : Name :=
  if s.toName.isAnonymous then Name.mkSimple s else s.toName

/-- The names of `--library`: comma-separated, each trimmed and parsed as Lake parses
    a target name. -/
def parseLibraryArg (s : String) : Array Name :=
  ((s.splitOn ",").map (·.trimAscii.toString)).filter (!·.isEmpty)
    |>.map stringToLegalOrSimpleName |>.toArray

/-- The targets of the run and the default targets that were skipped, in the order
    of R4: `--library`, `--all-libraries`, `defaultTargets`, every `lean_lib`. An
    empty `defaultTargets` means every `lean_lib`. A default target that is neither a
    `lean_lib` nor a `lean_exe` (a custom `target`, an `extern_lib`) is skipped. An
    empty result is an error, because `lake build` without arguments builds the
    default targets, custom targets and executables included. -/
def chooseTargets (info : WorkspaceInfo) (libraries : Option (Array Name)) (allLibs : Bool)
    : Except String (Array Target × Array Name) := do
  let libNames := info.libs.map (·.name)
  let allLibTargets := libNames.map Target.lib
  let (targets, skipped) ← match libraries, allLibs with
    | some _, true => throw "Error: --all-libraries and --library cannot be used together."
    | some ls, false => do
      for l in ls do
        if libNames.contains l then continue
        if info.exes.any (·.name == l) then
          throw s!"Error: --library {l}: {l} is a lean_exe, not a lean_lib. \
            --library takes lean_lib names."
        throw s!"Error: --library {l}: no lean_lib of that name. \
          The lean_lib targets are: {", ".intercalate (libNames.map toString).toList}"
      pure (ls.map Target.lib, #[])
    | none, true => pure (allLibTargets, #[])
    | none, false =>
      if info.defaultTargets.isEmpty then pure (allLibTargets, #[])
      else
        pure <| info.defaultTargets.foldl (init := (#[], #[])) fun (ts, sk) d =>
          if libNames.contains d then (ts.push (.lib d), sk)
          else match info.exes.find? (·.name == d) with
            | some e => (ts.push (.exe e.name e.root), sk)
            | none => (ts, sk.push d)
  if targets.isEmpty then
    let note := if skipped.isEmpty then ""
      else s!" Skipped default targets: {", ".intercalate (skipped.map toString).toList}."
    throw s!"Error: no lean_lib or lean_exe target was found.{note}"
  return (targets, skipped)

/-- The arguments of `lake build`: `<lib>:leanArts` for a library, so the build does
    not depend on its `defaultFacets`, and `+<root>` for an executable, so it is not
    linked. `Name.toString` adds `«»` where Lean needs them. `targets` is never
    empty (`chooseTargets`). -/
def buildArgs (targets : Array Target) : Array String :=
  #["build"] ++ targets.map fun
    | .lib n => s!"{n}:leanArts"
    | .exe _ root => s!"+{root}"

/-- The target module list: the modules of the target libraries, then the roots of
    the target executables, without repeats. -/
def targetModules (info : WorkspaceInfo) (targets : Array Target) : Array Name := Id.run do
  let mut out : Array Name := #[]
  let mut seen : Std.HashSet Name := {}
  for t in targets do
    let mods := match t with
      | .lib n => ((info.libs.find? (fun (l : LibInfo) => l.name == n)).map LibInfo.modules).getD #[]
      | .exe _ root => #[root]
    for m in mods do
      unless seen.contains m do
        seen := seen.insert m
        out := out.push m
  return out

/-- Drop `.` components from a path, as `normalize` keeps them. -/
private def dropDotComponents (p : System.FilePath) : String :=
  let parts := (p.normalize.toString.splitOn "/").filter (· != ".")
  "/".intercalate parts

/-- R6: the build directory `leanLibDir` (as Lake stores it, usually relative) must
    be `.lake/build/lib/lean` of the project. `projectReal` is the real path of the
    project directory. The build directory itself need not exist. -/
def checkLeanLibDir (projectReal : System.FilePath) (leanLibDir : String) : Except String Unit :=
  let dir : System.FilePath :=
    if leanLibDir.startsWith "/" then leanLibDir else projectReal / leanLibDir
  let expected := projectReal / ".lake" / "build" / "lib" / "lean"
  if dropDotComponents dir == dropDotComponents expected then .ok ()
  else .error s!"Error: the build directory of the project is {leanLibDir}, not \
    .lake/build/lib/lean. probe-lean does not support a custom buildDir or leanLibDir."

/-- R12: parse the `--module` prefix as a module name. `String.toName` returns
    `.anonymous` for a string that does not parse, and `.anonymous` is a prefix of
    every name, so it is an error. -/
def parseModulePrefix (s : String) : Except String Name :=
  let n := s.trimAscii.toString.toName
  if n.isAnonymous then .error s!"Error: --module {s}: not a module name."
  else .ok n

/-- R12: the modules of `mods` whose name is `pre` or starts with `pre.`, compared as
    `Name` components. -/
def filterModulePrefix (mods : Array Name) (pre : Name) : Array Name :=
  mods.filter pre.isPrefixOf

/-- The error for a `--module` prefix that keeps no target module. -/
def formatEmptyModuleFilter (pre : Name) (targetCount : Nat) : String :=
  s!"Error: --module {pre} matches none of the {targetCount} target module(s). \
    --module filters the modules of the targets. For a module of another lean_lib, \
    name that library with --library."

/-- Why the ownership check (R11) rejects a project module. -/
inductive Rejection where
  /-- Only a `lean_exe` owns the module, and another project module imports it. -/
  | exeImported
  /-- A `lean_lib` and a `lean_exe` both own the module. -/
  | libAndExe
  /-- No `lean_lib` of the root package owns the module, and no `lean_exe`. -/
  | unowned
  /-- Only a `lean_exe` owns the module, it is not a target, and no project module
      imports it. The closure starts at the targets, so this is a bug. -/
  | internal
  deriving BEq, Repr, Inhabited

/-- R11: classify each project module by its owners. `targetExeRoots` are the roots
    of the target executables, `imported` says whether a module of P imports the
    module. Returns the rejected modules with their reason, in the order of `p`. -/
def classifyOwnership (p : Array Name) (owners : Array OwnerInfo) (targetExeRoots : Array Name)
    (imported : Name → Bool) : Array (Name × Rejection) :=
  let byName : Std.HashMap Name OwnerInfo :=
    owners.foldl (init := {}) fun m o => m.insert o.module o
  p.filterMap fun m =>
    let o := byName.getD m { module := m }
    match o.lib, o.exe with
    | some _, none => none
    | some _, some _ => some (m, .libAndExe)
    | none, none => some (m, .unowned)
    | none, some _ =>
      if imported m then some (m, .exeImported)
      else if targetExeRoots.contains m then none
      else some (m, .internal)

/-- The reason line of one rejection. -/
def Rejection.reason : Rejection → String
  | .exeImported => "only a lean_exe owns this module, and another project module imports it. \
      Lake does not record imports of an executable root in the importer's trace, so it does \
      not recheck the module, and a fresh clone does not build this layout. \
      Move the module into a lean_lib."
  | .libAndExe => "the name is both a lean_lib module and a lean_exe root. A library build \
      and an executable build write the same .olean, so the name is ambiguous."
  | .unowned => "no lean_lib of the root package owns this module, so Lake did not check \
      its .olean in this run. Its source can be deleted, or its [[lean_lib]] entry removed."
  | .internal => "internal error: an executable root that is not a target and that no \
      module imports is in the import closure. Please report this."

/-- One message for every rejected module (R11). -/
def formatRejections (rs : Array (Name × Rejection)) : String :=
  let lines := rs.toList.map fun (m, r) => s!"  {m}: {r.reason}"
  s!"Error: {rs.size} module(s) in the import closure fail the ownership check:\n" ++
    "\n".intercalate lines

/-- R15: the modules whose atoms the run reports. With `--module`, the import set.
    Else with `--library`, the modules of P whose `lean_lib` owner is a named
    library. Else every module of P. -/
def emittedSet (importSet p : Array Name) (owners : Array OwnerInfo)
    (modulePrefix? : Option Name) (libraries? : Option (Array Name)) : Array Name :=
  match modulePrefix?, libraries? with
  | some _, _ => importSet
  | none, some libs =>
    let libOf : Std.HashMap Name Name :=
      owners.foldl (init := {}) fun m o => match o.lib with
        | some l => m.insert o.module l
        | none => m
    p.filter fun m => match libOf[m]? with
      | some l => libs.contains l
      | none => false
  | none, none => p

end ProbeLean
