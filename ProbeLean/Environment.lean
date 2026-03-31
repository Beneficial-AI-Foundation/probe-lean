/-
  Environment loading for external Lean projects.
-/
import Lean

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
    Skips dot-directories (.lake/, .git/, etc.) to avoid walking dependency
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

/-- Check if cache is valid: cache file exists, build output directory exists,
    config files (lean-toolchain, lakefile) haven't changed, and no .lean source
    is newer than the cache. -/
def isCacheValid (projectPath : System.FilePath) : IO Bool := do
  let (outputCache, _) := getCacheFiles projectPath
  if !(← outputCache.pathExists) then return false
  let buildLibLean := projectPath / ".lake" / "build" / "lib" / "lean"
  let buildLib := projectPath / ".lake" / "build" / "lib"
  if !(← buildLibLean.pathExists) && !(← buildLib.pathExists) then return false
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

/-- Recursively collect .olean files and convert to module names -/
partial def collectOleanFiles (basePath : System.FilePath) (currentPath : System.FilePath) : IO (Array Lean.Name) := do
  let mut result : Array Lean.Name := #[]
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
      let moduleName := relPath.replace "/" "."
      result := result.push (String.toName moduleName)
  return result

/-- Get the list of modules in the project by parsing lake output -/
def getProjectModules (projectPath : System.FilePath) : IO (Except String (Array Lean.Name)) := do
  -- Use lake to print the environment and extract LEAN_PATH
  let (stdout, stderr, exitCode) ← runCmd "lake" #["env", "printenv", "LEAN_PATH"] projectPath
  if exitCode != 0 then
    return .error s!"Failed to get LEAN_PATH:\n{stderr}"

  -- Parse the LEAN_PATH to find olean directories
  let _leanPath := stdout.trimAscii

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

  -- Collect all .olean files from the project's build directory
  let mut modules : Array Lean.Name := #[]

  if ← projectBuildPath.pathExists then
    let oleans ← collectOleanFiles projectBuildPath projectBuildPath
    for olean in oleans do
      modules := modules.push olean

  return .ok modules

/-- Information about a loaded project -/
structure ProjectInfo where
  path : System.FilePath
  modules : Array Lean.Name

end ProbeLean
