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

/-- Read the target project's lean-toolchain file and return its contents (trimmed),
    or `none` if the file doesn't exist or can't be read. -/
def readToolchain (projectPath : System.FilePath) : IO (Option String) := do
  let path := projectPath / "lean-toolchain"
  if !(← path.pathExists) then return none
  let contents ← IO.FS.readFile path
  return some contents.trimAscii.toString

/-- Extract the version tag from a lean-toolchain string.
    `"leanprover/lean4:v4.28.0-rc1"` → `"v4.28.0-rc1"`, bare `"v4.28.0"` passes through. -/
def parseToolchainVersion (tc : String) : String :=
  let trimmed := tc.trimAscii.toString
  match trimmed.splitOn ":" with
  | [_, version] => version
  | _ => trimmed

/-- Load probes config from .verilib/probes/config.json -/
def loadUserConfig (projectPath : System.FilePath) : IO (Option Lean.Json) := do
  let configPath := projectPath / ".verilib" / "probes" / "config.json"
  if !(← configPath.pathExists) then
    return none
  let content ← IO.FS.readFile configPath
  match Lean.Json.parse content with
  | .error _ => return none
  | .ok json => return some json

/-- Load the is-hidden list from .verilib/probes/config.json -/
def loadIsHiddenList (userConfig : Option Lean.Json) : Array String :=
  match userConfig with
  | none => #[]
  | some userObj =>
    match userObj.getObjValAs? (Array String) "is-hidden" with
    | .error _ => #[]
    | .ok arr => arr

/-- Load the extraction-artifact-suffixes list from .verilib/probes/config.json -/
def loadExtractionArtifactSuffixes (userConfig : Option Lean.Json) : Array String :=
  match userConfig with
  | none => #[]
  | some userObj =>
    match userObj.getObjValAs? (Array String) "extraction-artifact-suffixes" with
    | .error _ => #[]
    | .ok arr => arr

/-- Load the is-ignored list from .verilib/probes/config.json -/
def loadIsIgnoredList (userConfig : Option Lean.Json) : Array String :=
  match userConfig with
  | none => #[]
  | some userObj =>
    match userObj.getObjValAs? (Array String) "is-ignored" with
    | .error _ => #[]
    | .ok arr => arr

/-- Load the relevant-crate from .verilib/probes/config.json -/
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

/-- Attributes from verification frameworks that indicate a theorem is a
    primary specification. Used as a signal in primary-spec detection.
    Precedence: @[primary_spec] > known-attribute > _spec suffix > sole-spec. -/
def primarySpecAttributes : List String :=
  ["progress", "pspec", "step"]

/-- Check if an atom carries any of the known primary-spec attributes. -/
def hasKnownSpecAttribute (attrs : Array String) : Bool :=
  primarySpecAttributes.any fun a => attrs.contains a

/-- Compute reverse edges: for each theorem atom, add its name to the `specs`
    list of every non-theorem dependency. Also propagate `primarySpec` using
    a multi-signal precedence chain:
    1. `@[primary_spec]` attribute (always wins)
    2. Known verification-framework attributes (`primarySpecAttributes`)
    3. `_spec` suffix naming convention
    4. Sole-spec inference (exactly one spec) -/
def computeSpecs (atoms : Array Atom) : Array Atom :=
  let kindMap : Lean.RBMap String DeclKind compare :=
    atoms.foldl (init := .empty) fun m a => m.insert a.name a.kind
  let attrsMap : Lean.RBMap String (Array String) compare :=
    atoms.foldl (init := .empty) fun m a => m.insert a.name a.attributes
  let specsMap : Lean.RBMap String (Array String) compare :=
    atoms.foldl (init := .empty) fun m a =>
      if a.kind == DeclKind.theorem then
        a.dependencies.foldl (init := m) fun m dep =>
          match kindMap.find? dep with
          | some k =>
            if k == DeclKind.theorem then m
            else
              let cur := (m.find? dep).getD #[]
              m.insert dep (cur.push a.name)
          | none => m
      else m
  -- Signal 0: @[primary_spec] attribute (always wins)
  let attrPrimarySpecMap : Lean.RBMap String String compare :=
    atoms.foldl (init := .empty) fun m a =>
      if a.kind == DeclKind.theorem && a.isPrimarySpec then
        a.dependencies.foldl (init := m) fun m dep =>
          match kindMap.find? dep with
          | some k =>
            if k == DeclKind.theorem then m
            else m.insert dep a.name
          | none => m
      else m
  -- Signals 1-3: known-attribute > _spec suffix > sole-spec
  let primarySpecMap :=
    atoms.foldl (init := attrPrimarySpecMap) fun m a =>
      if a.kind == DeclKind.theorem then m
      else
        match m.find? a.name with
        | some _ => m
        | none =>
          match specsMap.find? a.name with
          | some specs =>
            -- Signal 1: known-attribute boost
            let knownAttrMatches := specs.filter fun s =>
              match attrsMap.find? s with
              | some attrs => hasKnownSpecAttribute attrs
              | none => false
            if knownAttrMatches.size == 1 then m.insert a.name knownAttrMatches[0]!
            else
              -- Signal 2: _spec suffix
              let candidate := a.name ++ "_spec"
              if specs.contains candidate then m.insert a.name candidate
              else
                -- Signal 3: sole spec
                if specs.size == 1 then m.insert a.name specs[0]!
                else m
          | none => m
  atoms.map fun a =>
    let a := match specsMap.find? a.name with
      | some specs => { a with specs := specs.qsort (· < ·) }
      | none => a
    match primarySpecMap.find? a.name with
    | some ps => { a with primarySpec := some ps }
    | none => a

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

/-- Run analysis via lake env to get correct search paths.
    Returns the atoms together with the effective project class (`none` when no
    class is detected). The class is resolved here — where both the environment
    and the project path are available — so a later classifier pass can gate on
    it. Precedence: `classOverride` (from `--class`) > `lake-manifest.json`
    (package-level) > imported-module signal. -/
def runAnalysisViaLakeEnv (projectPath : System.FilePath) (modules : Array Name) (crate : String)
    (nixMode : Option NixMode := none) (classOverride : Option String := none)
    : IO (Except String (Array Atom × Option String)) := do
  let absProjectPath ← IO.FS.realPath projectPath

  Lean.initSearchPath (← Lean.findSysroot)

  let probeLeanPaths ← findProbeLeanLib

  let (leanPathOut, _, exitCode) ← runLakeCmd #["env", "printenv", "LEAN_PATH"] (some absProjectPath) nixMode
  if exitCode != 0 then
    return .error "Failed to get LEAN_PATH from target project"

  let leanPath := leanPathOut.trimAscii.toString

  let paths := leanPath.splitOn ":"
  let mut searchPaths : Array System.FilePath := #[]
  for p in paths do
    let resolved ← resolvePath absProjectPath p
    searchPaths := searchPaths.push resolved

  Lean.searchPathRef.set (searchPaths.toList ++ probeLeanPaths)

  let imports := modules.map fun m => { module := m : Import }

  IO.println s!"Importing {imports.size} modules..."

  let env ← try
    importModules imports {} 0
  catch e =>
    let msg := toString e
    if containsSubstring msg "incompatible header" then
      let targetTC ← readToolchain projectPath
      let probeLeanVersion := Lean.versionString
      let hint := match targetTC with
        | some tc =>
          let targetVersion := (parseToolchainVersion tc).dropPrefix "v" |>.toString
          if targetVersion == probeLeanVersion then
            s!"\n\nStale .olean files: probe-lean and the target project both use Lean {probeLeanVersion},\n" ++
            "but the build artifacts were compiled by a different Lean version.\n" ++
            s!"Fix: run `lake clean` in the target project, then re-run extract."
          else
            s!"\n\nToolchain mismatch: probe-lean was built with Lean {probeLeanVersion}, " ++
            s!"but the target project uses {tc}.\n" ++
            "The .olean binary format is not compatible across Lean versions.\n" ++
            "Fix: install probe-lean for the target's Lean version, or update the target project."
        | none => s!"\n\nThis may be a toolchain mismatch. probe-lean was built with Lean {probeLeanVersion}.\n" ++
            "Ensure the target project uses the same Lean version, or update probe-lean to match."
      return .error s!"Failed to import modules: {msg}{hint}"
    return .error s!"Failed to import modules: {msg}"

  IO.println "Extracting declarations..."

  let decls := getProjectDecls env modules

  IO.println s!"Found {decls.size} declarations"

  -- Effective class: --class override > manifest (package-level) > imported modules.
  let manifestClass ← detectClassFromManifest projectPath
  let detectedClass := classOverride.orElse fun () =>
    manifestClass.orElse fun () => detectClass env
  match detectedClass with
  | some c => IO.println s!"Project class: {c}"
  | none => pure ()

  let fileCache : FileCache ← IO.mkRef {}
  let mut atoms : Array Atom := #[]
  for decl in decls do
    let atom ← declInfoToAtom env projectPath modules crate fileCache decl
    atoms := atoms.push atom

  return .ok (atoms, detectedClass)

end ProbeLean
