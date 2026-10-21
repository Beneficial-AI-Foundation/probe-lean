/-
  The import closure of the import set, read from the `.olean` headers before the
  import. probe-lean resolves each import with Lean's own `SearchPath.findWithExt`
  on the search path that the import uses, so the walk loads what `importModules`
  loads. A module is a project module when its `.olean` is in the build directory
  (`.lake/build/lib/lean` of the project). The project modules of the closure are
  P, the domain of the taint walk.
-/
import Lean
import ProbeLean.Environment
import ProbeLean.Coimport

namespace ProbeLean

open Lean

/-- Locate probe-lean's own .olean files so the interpreter can resolve
    ProbeLean modules at runtime (required by `supportInterpreter`). Checks:
    1. Lake build layout:       `<bin>/../lib/lean/`
    2. Versioned installed layout: `<bin>/../lib/probe-lean-v<version>/`
    3. Legacy installed layout:  `<bin>/../lib/probe-lean/` -/
def findProbeLeanLib : IO (List System.FilePath) := do
  let appPath ← IO.appPath
  let binDir := appPath.parent.getD "."
  let lakeBuildLib := binDir / ".." / "lib" / "lean"
  let versionedLib := binDir / ".." / "lib" / s!"probe-lean-v{Lean.versionString}"
  let installedLib := binDir / ".." / "lib" / "probe-lean"
  let mut paths : List System.FilePath := []
  if ← installedLib.pathExists then paths := installedLib :: paths
  if ← versionedLib.pathExists then paths := versionedLib :: paths
  if ← lakeBuildLib.pathExists then paths := lakeBuildLib :: paths
  return paths

/-- The search path of the closure walk and of the import: the entries of
    `LEAN_PATH` from the workspace helper, then probe-lean's own library paths. A
    relative entry is resolved against the project directory, and an entry that
    exists is replaced by its real path, so the build directory test of
    `isInBuildDir` is a plain prefix test. -/
def resolveSearchPath (projectReal : System.FilePath) (leanPath : String)
    : IO SearchPath := do
  let mut out : Array System.FilePath := #[]
  for e in System.SearchPath.parse leanPath do
    if e.toString.isEmpty then continue
    let p := if e.isAbsolute then e else projectReal / e
    out := out.push (← if ← p.pathExists then IO.FS.realPath p else pure p)
  return out.toList ++ (← findProbeLeanLib)

/-- Whether `path` is inside the build directory `buildDir` (both real paths). -/
def isInBuildDir (buildDir path : System.FilePath) : Bool :=
  path.toString.startsWith (buildDir.toString ++ "/")

/-- The modules of `importSet` whose `.olean` is not in the build directory. -/
def missingOleans (buildDir : System.FilePath) (importSet : Array Name) : IO (Array Name) :=
  importSet.filterM fun m => return !(← (modToFilePath buildDir m "olean").pathExists)

/-- The error for `missingOleans`. -/
def formatMissingOleans (names : Array Name) : String :=
  s!"Error: after the build, {names.size} target module(s) have no .olean in \
    .lake/build/lib/lean: {", ".intercalate (names.map toString).toList}.\n\
    Lake's artifact cache can keep the .olean out of .lake/build. Set \
    LAKE_RESTORE_ARTIFACTS=true (Lean 4.31 or later) or restoreAllArtifacts = true \
    in the lakefile, then run probe-lean again."

/-- The closure walk. Starting from `roots`, `step` returns `none` for a module whose
    imports are not followed (a dependency module), `some a` for a project module
    with the imports `importsOf a`, or an error. Each module is visited once. The
    result holds the `some` answers in visit order. An error stops the walk, and the
    message names the module's importer. -/
def closureWalk [Monad m] (roots : Array Name) (importsOf : α → Array Name)
    (step : Name → m (Except String (Option α))) : m (Except String (Array α)) := do
  let mut seen : Std.HashSet Name := {}
  let mut stack : Array (Name × Option Name) := roots.reverse.map (·, none)
  let mut out : Array α := #[]
  repeat
    let some (n, importer) := stack.back? | break
    stack := stack.pop
    if seen.contains n then continue
    seen := seen.insert n
    match ← step n with
    | .error e =>
      let by_ := match importer with
        | some i => s!"imported by {i}"
        | none => "a target module"
      return .error s!"{e} ({n}, {by_})"
    | .ok none => pure ()
    | .ok (some a) =>
      out := out.push a
      for i in (importsOf a).reverse do
        unless seen.contains i do
          stack := stack.push (i, some n)
  return .ok out

/-- The modules of `importSet` that are not in `headers`. -/
def targetsOutsideProject (importSet : Array Name) (headers : Array ProjectHeader) : Array Name :=
  let p := Std.HashSet.ofArray (headers.map (·.name))
  importSet.filter (!p.contains ·)

/-- The error for `targetsOutsideProject`. -/
def formatTargetsOutsideProject (buildDir : System.FilePath) (names : Array Name) : String :=
  s!"Error: {names.size} target module(s) do not resolve to an .olean in the build \
    directory {buildDir}: {", ".intercalate (names.map toString).toList}.\n\
    The search path resolves them elsewhere, for example to a dependency with a \
    directory of the same root name."

/-- The headers of the project modules in the closure of `importSet`, sorted by
    name. Fails closed: an import that does not resolve, a project `.olean` that does
    not exist, a header that cannot be read and a module of `importSet` that resolves
    outside the build directory each fail the run. -/
def computeClosure (buildDir : System.FilePath) (sp : SearchPath) (importSet : Array Name)
    : IO (Except String (Array ProjectHeader)) := do
  let step (n : Name) : IO (Except String (Option ProjectHeader)) := do
    match ← sp.findWithExt "olean" n with
    | none => return .error "no .olean on the search path"
    | some path =>
      if !isInBuildDir buildDir path then return .ok none
      if !(← path.pathExists) then return .error s!"{path} does not exist"
      return (← readHeader n path).map some
  match ← closureWalk importSet (·.imports) step with
  | .error e => return .error s!"Error: the import closure cannot be read: {e}"
  | .ok hs =>
    let outside := targetsOutsideProject importSet hs
    if !outside.isEmpty then return .error (formatTargetsOutsideProject buildDir outside)
    return .ok (hs.qsort fun a b => a.name.toString < b.name.toString)

/-- The modules that some header in `headers` imports. -/
def importedNames (headers : Array ProjectHeader) : Std.HashSet Name :=
  headers.foldl (init := {}) fun s h => h.imports.foldl (init := s) fun s i => s.insert i

/-- What `prepareProject` hands to the pipeline. -/
structure PreparedProject where
  /-- The target modules, narrowed by `--module`: what the run imports. -/
  importSet : Array Name
  /-- The headers of P, the project modules of the closure, sorted by name. -/
  headers : Array ProjectHeader
  /-- The modules whose atoms the run reports (`emittedSet`). -/
  emitted : Array Name
  /-- The search path of the closure walk, set again for the import. -/
  searchPath : SearchPath
  /-- `.lake/build/lib/lean` of the project, a real path. -/
  buildDir : System.FilePath
  nixMode : Option NixMode

/-- The names of P. -/
def PreparedProject.projectModules (pp : PreparedProject) : Array Name :=
  pp.headers.map (·.name)

end ProbeLean
