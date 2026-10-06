/-
  Environment loading for external Lean projects.
-/
import Lean
import ProbeLean.NixEnv

namespace ProbeLean

/-- Check if a path is a valid Lake project -/
def isLakeProject (path : System.FilePath) : IO Bool := do
  let lakefileLean := path / "lakefile.lean"
  let lakefileToml := path / "lakefile.toml"
  let hasLean ← lakefileLean.pathExists
  let hasToml ← lakefileToml.pathExists
  return hasLean || hasToml

/-- Run a command and return stdout, stderr, and exit code -/
def runCmd (cmd : String) (args : Array String) (cwd : Option System.FilePath := none) : IO (String × String × UInt32) := do
  let proc ← IO.Process.spawn {
    cmd := cmd
    args := args
    cwd := cwd
    stdout := .piped
    stderr := .piped
  }
  let stdout ← proc.stdout.readToEnd
  let stderr ← proc.stderr.readToEnd
  let exitCode ← proc.wait
  return (stdout, stderr, exitCode)

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
    let cmdStr := " ".intercalate (["lake"] ++ args.toList)
    runCmd "nix-shell" #["--run", cmdStr] cwd
  | none =>
    runCmd "lake" args cwd

/-- Build the target project using lake, returning combined stdout+stderr on success -/
def buildProject (projectPath : System.FilePath) : IO (Except String String) := do
  let (stdout, stderr, exitCode) ← runCmd "lake" #["build"] projectPath
  if exitCode != 0 then
    return .error s!"Lake build failed:\n{stderr}"
  return .ok (stdout ++ "\n" ++ stderr)

/-- Get cache directory path -/
def getCacheDir (projectPath : System.FilePath) : System.FilePath :=
  projectPath / ".lake" / "probe-lean"

/-- Get cache file paths -/
def getCacheFiles (projectPath : System.FilePath) : System.FilePath × System.FilePath :=
  let cacheDir := getCacheDir projectPath
  (cacheDir / "build_output.txt", cacheDir / "build_config.json")

/-- Recursively check if any .lean file is newer than cache.
    Skips dot-directories (such as .lake/ and .git/) to avoid walking dependency
    sources and build artifacts. -/
partial def checkFilesNewerThan (dir : System.FilePath) (cacheTime : IO.FS.SystemTime) : IO Bool := do
  let entries ← dir.readDir
  for entry in entries do
    let path := entry.path
    if ← path.isDir then
      if !entry.fileName.startsWith "." then
        if ← checkFilesNewerThan path cacheTime then return true
    else if path.extension == some "lean" then
      let fileMeta ← path.metadata
      if fileMeta.modified > cacheTime then return true
  return false

/-- Recursively check whether `dir` contains at least one `.olean` file.
    Short-circuits on the first hit. Used by `isCacheValid` to detect
    `lake clean` having removed build artifacts while leaving the directory
    tree (or cache file) in place. -/
partial def hasAnyOlean (dir : System.FilePath) : IO Bool := do
  let entries ← dir.readDir
  for entry in entries do
    let path := entry.path
    if ← path.isDir then
      if ← hasAnyOlean path then return true
    else if path.extension == some "olean" then
      return true
  return false

/-- Check if cache is valid. The cache file must exist, and the build output
    directory must contain at least one `.olean`. No config file (lean-toolchain,
    lakefile) and no .lean source can be newer than the cache. -/
def isCacheValid (projectPath : System.FilePath) : IO Bool := do
  let (outputCache, _) := getCacheFiles projectPath
  if !(← outputCache.pathExists) then return false
  let buildLibLean := projectPath / ".lake" / "build" / "lib" / "lean"
  let buildLib := projectPath / ".lake" / "build" / "lib"
  let buildDir ←
    if ← buildLibLean.pathExists then pure (some buildLibLean)
    else if ← buildLib.pathExists then pure (some buildLib)
    else pure none
  match buildDir with
  | none => return false
  | some d => unless ← hasAnyOlean d do return false
  let cacheMeta ← outputCache.metadata
  let cacheTime := cacheMeta.modified
  let configFiles := #[
    projectPath / "lean-toolchain",
    projectPath / "lakefile.toml",
    projectPath / "lakefile.lean"
  ]
  for cf in configFiles do
    if ← cf.pathExists then
      let cfMeta ← cf.metadata
      if cfMeta.modified > cacheTime then return false
  let hasNewerFile ← checkFilesNewerThan projectPath cacheTime
  return !hasNewerFile

/-- Save build output to cache -/
def saveCache (projectPath : System.FilePath) (output : String) : IO Unit := do
  let cacheDir := getCacheDir projectPath
  IO.FS.createDirAll cacheDir
  let (outputCache, _) := getCacheFiles projectPath
  IO.FS.writeFile outputCache output

/-- Load build output from cache -/
def loadCache (projectPath : System.FilePath) : IO (Option String) := do
  let (outputCache, _) := getCacheFiles projectPath
  if ← outputCache.pathExists then
    some <$> IO.FS.readFile outputCache
  else
    return none

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

/-- Recursively collect .olean files. For each file, return its module name and
    its path relative to `basePath`, slash-separated and with the `.olean`
    suffix stripped (for example `"A/B/C"`). The relative path is kept so callers can
    reconstruct the backing source location under a library's `srcDir`. -/
partial def collectOleanFiles (basePath : System.FilePath) (currentPath : System.FilePath) : IO (Array (Lean.Name × String)) := do
  let mut result : Array (Lean.Name × String) := #[]
  let entries ← currentPath.readDir
  for entry in entries do
    let path := entry.path
    if ← path.isDir then
      let subResult ← collectOleanFiles basePath path
      result := result ++ subResult
    else if path.extension == some "olean" then
      -- Convert path to module name
      let relPath := (path.toString.dropPrefix basePath.toString).toString
      let relPath := (relPath.dropPrefix "/").toString
      let relPath := (relPath.dropSuffix ".olean").toString
      result := result.push (pathToModuleName relPath, relPath)
  return result

/-- Partition collected olean modules into (source-backed, orphan), where a
    module with relative path `A/B/C` is source-backed iff `<root>/A/B/C.lean`
    exists under some `root` in `sourceRoots`. An empty `sourceRoots` defaults to
    `#["."]`. A module is an orphan only when *no* root has its source. A live
    module under a `srcDir` that is missing from `sourceRoots` is therefore
    dropped as an orphan.
    Kept entries retain their `(name, relPath)` tuple so callers never have to
    re-join names with paths after the fact. -/
def partitionBySource (projectPath : System.FilePath) (sourceRoots : Array String)
    (oleans : Array (Lean.Name × String)) : IO (Array (Lean.Name × String) × Array Lean.Name) := do
  let roots := if sourceRoots.isEmpty then #["."] else sourceRoots
  let mut kept : Array (Lean.Name × String) := #[]
  let mut orphans : Array Lean.Name := #[]
  for (name, relPath) in oleans do
    let mut hasSource := false
    for root in roots do
      let rootDir : System.FilePath := if root == "." then projectPath else projectPath / root
      let srcFile : System.FilePath := ⟨rootDir.toString ++ "/" ++ relPath ++ ".lean"⟩
      if ← srcFile.pathExists then
        hasSource := true
        break
    if hasSource then
      kept := kept.push (name, relPath)
    else
      orphans := orphans.push name
  return (kept, orphans)

/-- A project module paired with the `.olean` it was discovered from. Discovery
    sets the pairing once, and every filter keeps it. So a module name is never
    matched with the wrong olean. The preflight co-importability check reads the
    olean by this path. -/
structure ProjectModule where
  name      : Lean.Name
  oleanPath : System.FilePath
  deriving Inhabited

/-- The project's own modules. These are the `.olean` files under its build
    directory (`.lake/build/lib[/lean]`) that still have a backing `.lean` source.
    Each is paired with the olean it was discovered from (`ProjectModule`).

    Lake never garbage-collects oleans. After a file is renamed or deleted, the stale
    "orphan" olean stays on disk. Importing it next to the module that replaced it makes
    `importModules` abort with `environment already contains '...'`. A module `A/B/C` is
    source-backed when `<root>/A/B/C.lean` exists under some root in `sourceRoots`. The
    caller supplies `"."` plus every library `srcDir` declared in `lakefile.toml`. A
    module is dropped only when *no* root has its source, and dropped orphans are
    printed. A `lakefile.lean` is not parsed, so a live module under a custom `srcDir`
    declared there is dropped and printed as an orphan. The `lake env` call checks that
    the Lake environment is usable before scanning.

    Returns the kept modules and the dropped orphan names, both sorted. A kept module can
    still import a dropped orphan, and then `importModules` loads it anyway. A loaded
    module outside the inventory sits outside P and is trusted like a dependency
    package. So the caller compares the orphans with the imported module set after the
    import (`Atomize.loadedOrphans`) and aborts. -/
def getProjectModules (projectPath : System.FilePath)
    (nixMode : Option NixMode := none) (sourceRoots : Array String := #["."])
    : IO (Except String (Array ProjectModule × Array Lean.Name)) := do
  let (_, stderr, exitCode) ← runLakeCmd #["env", "printenv", "LEAN_PATH"] projectPath nixMode
  if exitCode != 0 then
    return .error s!"Failed to get LEAN_PATH:\n{stderr}"

  -- Find the project's build directory
  -- Some projects use .lake/build/lib/lean, others use .lake/build/lib directly
  let buildLibPath := projectPath / ".lake" / "build" / "lib"
  let buildLibLeanPath := buildLibPath / "lean"

  -- Prefer .lake/build/lib/lean if it exists (standard Lake structure)
  let projectBuildPath ← do
    if ← buildLibLeanPath.pathExists then
      pure buildLibLeanPath
    else
      pure buildLibPath

  -- Collect all .olean files, then keep only those with a backing source.
  -- Records are built straight from the kept (name, relPath) tuples, so name
  -- and olean path can never be paired up wrong.
  let mut modules : Array ProjectModule := #[]
  let mut orphans : Array Lean.Name := #[]

  if ← projectBuildPath.pathExists then
    let oleans ← collectOleanFiles projectBuildPath projectBuildPath
    let (kept, dropped) ← partitionBySource projectPath sourceRoots oleans
    orphans := dropped
    for (name, relPath) in kept do
      modules := modules.push { name, oleanPath := projectBuildPath / (relPath ++ ".olean") }

  let sortedOrphans := orphans.qsort fun a b => a.toString < b.toString
  if !sortedOrphans.isEmpty then
    IO.println s!"Ignoring {sortedOrphans.size} orphan module(s) with no backing .lean source (stale build artifacts):"
    for o in sortedOrphans do
      IO.println s!"  - {o}"

  -- Sort for deterministic import order (P14)
  let sortedModules := modules.qsort fun a b => a.name.toString < b.name.toString
  return .ok (sortedModules, sortedOrphans)

/-- Information about a loaded project -/
structure ProjectInfo where
  path : System.FilePath
  modules : Array Lean.Name

end ProbeLean
