/-
  Atomize: core logic for extracting dependency graph atoms from a Lean environment.
  Not a CLI command - used by Verify.lean.
-/
import Lean
import ProbeLean.Types
import ProbeLean.Environment
import ProbeLean.Coimport
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

/-- Load the extraction-artifact-suffixes list from .verilib/probes/config.json.
    Reads the `extraction-artifact-suffixes` config key for backward compatibility
    but now feeds the `is-aeneas-generated` field. -/
def loadAeneasGeneratedSuffixes (userConfig : Option Lean.Json) : Array String :=
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

/-- Set isHidden, isAeneasGenerated, and isIgnored fields on atoms based on config -/
def markAtomFlags (atoms : Array Atom) (hiddenList : Array String) (aeneasGeneratedSuffixes : Array String) (ignoredList : Array String) : Array Atom :=
  atoms.map fun atom =>
    let nameWithoutPrefix := stripProbePrefix atom.name
    -- OR with any flag already set (e.g. auto-detected generated code), so config
    -- adds to rather than overwrites automatic detection.
    let isHidden := atom.isHidden || hiddenList.contains nameWithoutPrefix
    let isAeneasGenerated := atom.isAeneasGenerated || hasAnySuffix nameWithoutPrefix aeneasGeneratedSuffixes
    let isIgnored := atom.isIgnored || ignoredList.contains nameWithoutPrefix
    { atom with isHidden := isHidden, isAeneasGenerated := isAeneasGenerated, isIgnored := isIgnored }

/-- Attributes from verification frameworks that indicate a theorem is a
    primary specification. Used as a signal in primary-spec detection.
    Precedence: @[primary_spec] > known-attribute > _spec suffix > sole-spec. -/
def primarySpecAttributes : List String :=
  ["progress", "pspec", "step"]

/-- Check if an atom carries any of the known primary-spec attributes. -/
def hasKnownSpecAttribute (attrs : Array String) : Bool :=
  primarySpecAttributes.any fun a => attrs.contains a

/-- Compute reverse edges: for each theorem atom, add its name to the `specs`
    list of every non-theorem **type** dependency. Also propagate `primarySpec`
    using a multi-signal precedence chain:
    1. `@[primary_spec]` attribute (always wins)
    2. Known verification-framework attributes (`primarySpecAttributes`)
    3. `_spec` suffix naming convention
    4. Sole-spec inference (exactly one spec)

    Only `typeDependencies` are walked, not the union `dependencies`: a theorem
    specifies what its *statement* is about. A constant a proof merely happens to
    invoke — a helper lemma, a definition it unfolds — is not something the
    theorem specifies, and admitting those edges would put a spurious spec on
    most definitions in the project and defeat primary-spec detection, whose
    known-attribute and sole-spec signals both require exactly one candidate.

    Fallback for explicit tags: a theorem carrying `@[primary_spec]` whose
    *statement* names no specifiable constant (an abstract statement whose
    specified function enters only via the proof term) falls back to the union
    `dependencies` — provided that leaves exactly one candidate — so the
    user's explicit override can still attach. With several candidates the
    tag is ambiguous (it marks the theorem, not a target) and attaches to
    nothing, like an untagged abstract theorem. The `specs` map and the
    `@[primary_spec]` map share one target set (`specTargets`), so `primary-spec`
    never points outside `specs`.

    Generated theorems (attribute-macro companions like `X.mvcgen_spec`,
    whatever their origin flag) are not user specs: they enter neither the
    `specs` lists nor the heuristic primary-spec candidate pool (signals 2-4).
    Without this, a generated companion sits next to its parent spec on every
    dependency and defeats signals 2 and 4, which require exactly one
    candidate. The explicit `@[primary_spec]` tag is the user's escape hatch:
    it wins signal 1 as usual, and a tagged generated theorem also re-enters
    the `specs` lists, so `primary-spec` never points outside `specs`. -/
def computeSpecs (atoms : Array Atom) : Array Atom :=
  let kindMap : Lean.RBMap String DeclKind compare :=
    atoms.foldl (init := .empty) fun m a => m.insert a.name a.kind
  let attrsMap : Lean.RBMap String (Array String) compare :=
    atoms.foldl (init := .empty) fun m a => m.insert a.name a.attributes
  let isGeneratedTheorem : Atom → Bool := fun a =>
    (a.isLeanGenerated || a.isAeneasGenerated) && !a.isPrimarySpec
  -- A non-theorem constant a spec can attach to (theorems and unknown names are
  -- never spec targets).
  let isSpecifiable : String → Bool := fun dep =>
    match kindMap.find? dep with
    | some k => k != DeclKind.theorem
    | none   => false
  -- The constants a theorem is a spec *of*: normally those named in its statement
  -- (`typeDependencies`). Fallback: an explicitly `@[primary_spec]`-tagged theorem
  -- whose statement names no specifiable constant walks the union `dependencies`
  -- so the tag can still attach — but only when that leaves exactly one
  -- candidate. The tag marks the theorem, not its target, so with several
  -- proof-invoked definitions there is nothing to disambiguate by: attaching
  -- to all of them would spray `primary-spec` onto every helper the proof
  -- touches. Ambiguous tags attach to nothing, like untagged abstract
  -- theorems. Order preserved (inputs are name-sorted, P14).
  let specTargets : Atom → Array String := fun a =>
    let typeTargets := a.typeDependencies.filter isSpecifiable
    if !typeTargets.isEmpty || !a.isPrimarySpec then typeTargets
    else
      let unionTargets := a.dependencies.filter isSpecifiable
      if unionTargets.size == 1 then unionTargets else #[]
  let specsMap : Lean.RBMap String (Array String) compare :=
    atoms.foldl (init := .empty) fun m a =>
      if a.kind == DeclKind.theorem && !isGeneratedTheorem a then
        (specTargets a).foldl (init := m) fun m dep =>
          let cur := (m.find? dep).getD #[]
          m.insert dep (cur.push a.name)
      else m
  -- Signal 0: @[primary_spec] attribute (always wins). Deliberately NOT
  -- filtered by isLeanGenerated: the explicit tag is the user's escape hatch,
  -- including for a false positive of the generated-companion detection.
  let attrPrimarySpecMap : Lean.RBMap String String compare :=
    atoms.foldl (init := .empty) fun m a =>
      if a.kind == DeclKind.theorem && a.isPrimarySpec then
        (specTargets a).foldl (init := m) fun m dep =>
          m.insert dep a.name
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

/-- Import the target project's built modules into a single `Environment`, with the
    same LEAN_PATH / search-path setup and co-import preflight the analysis uses.
    Shared by `runAnalysisViaLakeEnv` and the `check-axioms` command so both see the
    exact same environment. -/
def importProjectEnv (projectPath : System.FilePath) (modules : Array ProjectModule)
    (nixMode : Option NixMode := none) : IO (Except String Environment) := do
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

  -- Preflight: abort with an actionable diagnostic if the modules cannot
  -- coexist in one environment, instead of paying for the import and
  -- surfacing a raw kernel error.
  let (collisions, skippedPreflight) ← detectCoimportCollisions modules

  if !collisions.isEmpty then
    return .error (formatCoimportError collisions skippedPreflight)

  let moduleNames := modules.map (·.name)
  let imports := moduleNames.map fun m => { module := m : Import }

  IO.println s!"Importing {imports.size} modules..."

  try
    -- The import level is pinned: `.private` loads all olean data, theorem
    -- proofs included. The exported level can present module-system theorems
    -- without their proofs, which the pipeline downstream would read as empty
    -- term-dependencies and status propagation would silently trust — the
    -- same failure shape as the `ConstantInfo.value?` default that emptied
    -- theorem proof edges. `.private` is the current upstream default; it is
    -- spelled out so a future default change cannot regress soundness.
    return .ok (← importModules imports {} 0 (level := OLeanLevel.private))
  catch e =>
    let msg := toString e
    if containsSubstring msg "already contains" then
      -- Two imported modules declare the same name, and the preflight above
      -- found no collision among the scanned project modules. The duplicate
      -- therefore involves something the scan cannot see: a dependency
      -- module, a module-system split part (.olean.private), an olean it had
      -- to skip, or a stale orphan olean under a custom `srcDir` that
      -- `getProjectModules`'s source check could not resolve.
      let hint := "\n\nDuplicate declaration across imported modules. All built modules must be\n" ++
        "co-importable into a single Lean environment (see README \"Supported Projects\").\n" ++
        "Possible causes: a stale .olean from a renamed or deleted module that Lake\n" ++
        "did not remove (fix: run `lake clean` in the target project, then re-run\n" ++
        "extract), or a duplicate the preflight check cannot see. A non-conflicting\n" ++
        "subset can be extracted manually with `--module <exact.module.name>`." ++
        skippedModulesNote skippedPreflight
      return .error s!"Failed to import modules: {msg}{hint}"
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

/-- Run analysis via lake env to get correct search paths. Returns the atoms. -/
def runAnalysisViaLakeEnv (projectPath : System.FilePath) (modules : Array ProjectModule) (crate : String)
    (nixMode : Option NixMode := none)
    : IO (Except String (Array Atom)) := do
  let env ← match ← importProjectEnv projectPath modules nixMode with
    | .error msg => return .error msg
    | .ok env => pure env
  let moduleNames := modules.map (·.name)
  -- Built once and shared by declaration discovery and per-atom dep partitioning.
  let projFilter := mkProjectFilter env moduleNames

  IO.println "Extracting declarations..."

  let decls := getProjectDecls env moduleNames projFilter

  IO.println s!"Found {decls.size} declarations"

  -- Auto-detected `deriving`-generated instance clusters and attribute-macro
  -- companion theorems (names only). Flagged below alongside projections; see
  -- the marking loop for why.
  let derivedNames := derivedInstanceClusterNames decls
  -- Companion parents can live outside the emitted declarations (`attribute
  -- [step]` on an external theorem/axiom, or a module-filtered parent); resolve
  -- their kind from the full environment so an external axiom's proxy is not
  -- misflagged.
  let companionNames := generatedCompanionTheoremNames decls
    (externalParentKind := fun n => (env.find? n).map (getDeclKind env n))

  let fileCache : FileCache ← IO.mkRef {}
  let mut atoms : Array Atom := #[]
  for decl in decls do
    let atom ← declInfoToAtom env projectPath projFilter crate fileCache decl
    -- Generated code is flagged hidden + generated so viewify and the web UI
    -- omit it from the presented graph, split by origin: deriving clusters and
    -- structure/class projections are core-Lean output (`is-lean-generated`),
    -- while `@[step]`'s mvcgen companion theorems exist only because of Aeneas
    -- (`is-aeneas-generated`). Either way the atom is kept in the atom set (not
    -- dropped), so `enrichTransitiveVerification` still traverses it and
    -- contamination still flows through it — hiding is sound precisely because
    -- the atom stays in the graph, unlike dropping.
    let isLeanGen := derivedNames.contains decl.name || decl.kind == .projection
    let isAeneasGen := companionNames.contains decl.name
    let atom :=
      if isLeanGen then { atom with isHidden := true, isLeanGenerated := true }
      else if isAeneasGen then { atom with isHidden := true, isAeneasGenerated := true }
      else atom
    atoms := atoms.push atom

  return .ok atoms

end ProbeLean
