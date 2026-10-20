/-
  Atomize: core logic for extracting dependency graph atoms from a Lean environment.
  Not a CLI command - used by Extract.lean.
-/
import Lean
import ProbeLean.Types
import ProbeLean.Environment
import ProbeLean.Coimport
import ProbeLean.Analysis
import ProbeLean.SpecFramework
import ProbeLean.Taint

namespace ProbeLean

open Lean

/-- Read the target project's lean-toolchain file and return its contents (trimmed),
    or `none` if the file does not exist or cannot be read. -/
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

/-- The kinds of a spec target (`isSpecTarget`). -/
def specTargetKinds : List DeclKind := [.def, .abbrev, .instance, .opaque, .axiom]

/-- A spec target is a constant with computational behavior that a theorem can describe:
    its kind is in `specTargetKinds`, and it is a data constant: not a proof
    (`isProof`), not a predicate (`codomainIsProp`) and not a type former
    (`codomainIsType`). Types, type aliases, projections, proofs and predicates are
    never targets. -/
def isSpecTarget (a : Atom) : Bool :=
  specTargetKinds.contains a.kind && !a.isProof && !a.codomainIsProp && !a.codomainIsType

/-- True when the components of `n` end in `[last, "spec"]`, or its last component is
    `last ++ "_spec"`. Components come from the `Name`, so a `«a.b»` part is one
    component. -/
private def specNameMatches (n : Name) (last : String) : Bool :=
  match n with
  | .str (.str _ l) "spec" => l == last
  | .str _ s => s == last ++ "_spec"
  | _ => false

/-- Rules 2 to 5 of the primary-spec precedence (see `computeSpecs`) for target `t`
    with spec names `specs`. `specAtom` looks up the atom of a spec name.

    A spec is about another function when its step program head is known and differs
    from `t.leanName`. Rules 2 and 3 skip such a spec. Without that, a step theorem
    whose postcondition names `t` counts for `t` (`to_edwards_spec` for `invert`,
    #132), and a theorem named `<T>.spec` about another function wins rule 3 once
    rule 2 rejects all tagged candidates. A tagged spec with head `none` stays a rule 2
    candidate. Rule 4 ignores the namespace, so it needs the program head: the same
    short name exists in other namespaces. Rule 5 has no head check, so the only spec
    of `t` wins even if it is about another function.

    Several candidates at a rule never resolve arbitrarily: the next rule decides.

    Known limit: `specs` and `specAtom` are keyed by published names. A #88 collision
    merges targets and makes colliding specs share one atom's program head. The head
    comparison itself is exact (raw names, private prefix kept). -/
def heuristicPrimarySpec (t : Atom) (specs : Array String)
    (specAtom : String → Option Atom) : Option String := Id.run do
  let aboutOther : Atom → Bool := fun s =>
    match s.stepProgramHead with
    | some h => h != t.leanName
    | none => false
  -- Rule 2: the only framework-tagged spec not about another function
  let tagged := specs.filter fun n =>
    match specAtom n with
    | some s => hasKnownSpecAttribute s.attributes && !aboutOther s
    | none => false
  if tagged.size == 1 then return some tagged[0]!
  -- Rule 3: exactly one of `<T>_spec` and `<T>.spec`, not about another function
  let exact := #[t.name ++ "_spec", t.name ++ ".spec"].filter fun n =>
    specs.contains n && match specAtom n with
      | some s => !aboutOther s
      | none => true
  if exact.size == 1 then return some exact[0]!
  -- Rule 4: the only spec about `t` whose name ends in `<last>.spec` or `<last>_spec`
  if let .str _ last := privateToUserName t.leanName then
    let named := specs.filter fun n =>
      match specAtom n with
      | some s => s.stepProgramHead == some t.leanName &&
          specNameMatches (privateToUserName s.leanName) last
      | none => false
    if named.size == 1 then return some named[0]!
  -- Rule 5: sole spec
  if specs.size == 1 then return some specs[0]!
  return none

/-- Compute reverse edges: for each theorem atom, add its name to the `specs`
    list of every spec-target **type** dependency (`isSpecTarget`). Also propagate `primarySpec`
    using a precedence chain:
    1. `@[primary_spec]` attribute (always wins)
    2. The only framework-tagged spec (`primarySpecAttributes`) that is not about
       another function (`heuristicPrimarySpec`)
    3. The exact name `<T>_spec` or `<T>.spec`, unless about another function
    4. The only spec about `T` whose name ends in `<last>.spec` or `<last>_spec`
    5. Sole-spec inference (exactly one spec)

    Only `typeDependencies` are walked, not the union `dependencies`: a theorem
    specifies what its *statement* is about. A constant that only the proof uses
    (a helper lemma, a definition it unfolds) is not something the theorem
    specifies. Following proof edges puts a spurious spec on most definitions in the
    project. It also defeats primary-spec detection, because its
    known-attribute and sole-spec rules both require exactly one candidate.

    Fallback for explicit tags: a theorem can carry `@[primary_spec]` while its
    *statement* names no spec target (an abstract statement whose
    specified function enters only through the proof term). Such a theorem falls
    back to the union `dependencies` if that leaves exactly one candidate, so the
    user's explicit override can still attach. With several candidates the
    tag is ambiguous (it marks the theorem, not a target) and attaches to
    nothing, like an untagged abstract theorem. The `specs` map and the
    `@[primary_spec]` map share one target set (`specTargets`), so `primary-spec`
    never points outside `specs`.

    Generated theorems (attribute-macro companions like `X.mvcgen_spec`,
    whatever their origin flag) are not user specs: they enter neither the
    `specs` lists nor the heuristic primary-spec candidate pool (rules 2-5).
    Without this, a generated companion sits next to its parent spec on every
    dependency and defeats rules 2 and 5, which require exactly one
    candidate. The explicit `@[primary_spec]` tag is the user's escape hatch:
    it wins rule 1 as usual, and a tagged generated theorem also re-enters
    the `specs` lists, so `primary-spec` never points outside `specs`. -/
def computeSpecs (atoms : Array Atom) : Array Atom :=
  let targetMap : Lean.RBMap String Bool compare :=
    atoms.foldl (init := .empty) fun m a => m.insert a.name (isSpecTarget a)
  -- Spec name → spec atom, for the rules that read a spec's attributes, step
  -- program head and Lean name. Keyed by the published name like `specs`, so a #88
  -- collision keeps one of the colliding atoms.
  let specAtomMap : Lean.RBMap String Atom compare :=
    atoms.foldl (init := .empty) fun m a =>
      if a.kind == DeclKind.theorem then m.insert a.name a else m
  let isGeneratedTheorem : Atom → Bool := fun a =>
    (a.isLeanGenerated || a.isAeneasGenerated) && !a.isPrimarySpec
  -- A constant a spec can attach to (`isSpecTarget`; unknown names are never
  -- spec targets).
  let isSpecifiable : String → Bool := fun dep =>
    (targetMap.find? dep).getD false
  -- The constants a theorem is a spec *of*: normally those named in its statement
  -- (`typeDependencies`). Fallback: an explicitly `@[primary_spec]`-tagged theorem
  -- whose statement names no spec target walks the union `dependencies`
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
  -- Rule 1: @[primary_spec] attribute (always wins). Deliberately NOT
  -- filtered by isLeanGenerated: the explicit tag is the user's escape hatch,
  -- including for a false positive of the generated-companion detection.
  let attrPrimarySpecMap : Lean.RBMap String String compare :=
    atoms.foldl (init := .empty) fun m a =>
      if a.kind == DeclKind.theorem && a.isPrimarySpec then
        (specTargets a).foldl (init := m) fun m dep =>
          m.insert dep a.name
      else m
  -- Rules 2-5 (`heuristicPrimarySpec`)
  let primarySpecMap :=
    atoms.foldl (init := attrPrimarySpecMap) fun m a =>
      if !isSpecTarget a then m
      else
        match m.find? a.name, specsMap.find? a.name with
        | none, some specs =>
          match heuristicPrimarySpec a specs specAtomMap.find? with
          | some ps => m.insert a.name ps
          | none => m
        | _, _ => m
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
  let pre ← detectCoimportCollisions modules

  if !pre.proofless.isEmpty then
    return .error (formatProoflessError pre.proofless)
  if !pre.collisions.isEmpty then
    return .error (formatCoimportError pre.collisions pre.skipped)

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
      -- module, an olean it had to skip, or a stale orphan olean under a custom
      -- `srcDir` that `getProjectModules`'s source check could not resolve.
      let hint := "\n\nDuplicate declaration across imported modules. All built modules must be\n" ++
        "co-importable into a single Lean environment (see README \"Supported Projects\").\n" ++
        "Possible causes: a stale .olean from a renamed or deleted module that Lake\n" ++
        "did not remove (fix: run `lake clean` in the target project, then re-run\n" ++
        "extract), or a duplicate the preflight check cannot see. A non-conflicting\n" ++
        "subset can be extracted manually with `--module <exact.module.name>`." ++
        skippedModulesNote pre.skipped
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

/-- The project modules an environment actually holds: `all` restricted to
    `loaded` (`env.allImportedModuleNames`). Importing a selection loads every
    project module in its import closure too, and those must be in P. A constant can
    only reference constants of its own module's import closure. With P built this
    way, every emitted atom's whole dependency closure is inside P, even when only the
    selection imports. Building P from the selection itself left a transitively
    loaded sorried module outside P, where it was blocked and so read as clean. -/
def loadedProjectModules (all : Array ProjectModule) (loaded : Array Name)
    : Array ProjectModule :=
  let set := Std.HashSet.ofArray loaded
  all.filter fun m => set.contains m.name

/-- The orphan modules (oleans discovery dropped for lack of a source,
    `getProjectModules`) that the import loaded anyway, sorted by name. If a kept
    module imports a dropped module, `importModules` still loads it. Such a module is
    then outside P, so it is blocked and trusted like a dependency package, and a
    `sorry` in it shields its callers. A non-empty result means the extraction must
    abort (`formatLoadedOrphansError`): the artifact is stale and there is no source
    to build its atoms from. -/
def loadedOrphans (orphans loaded : Array Name) : Array Name :=
  let set := Std.HashSet.ofArray loaded
  (orphans.filter set.contains).qsort fun a b => a.toString < b.toString

/-- The abort message for a non-empty `loadedOrphans`. -/
def formatLoadedOrphansError (names : Array Name) : String :=
  s!"{names.size} stale module(s) with no .lean source were imported by a live module: \
    {", ".intercalate (names.map (·.toString)).toList}. Their constants would sit outside \
    the project boundary and be trusted. Run `lake clean` in the target project and rebuild."

/-- The error when the fallback import of the selection fails too: the selection's
    own error first, then the full import's. The full import's message holds the
    readable diagnosis: the preflight's collision list, or `formatProoflessError` for
    a module missing its split parts. The selection's message can be Lean's raw form
    of the same fault (`missing data file` for a part-less module inside the
    selection's import closure). That message alone does not say what to rebuild. -/
def formatFallbackFailure (fullMsg selectedMsg : String) : String :=
  s!"{selectedMsg}\n\nThe import of all project modules had already failed:\n{fullMsg}"

/-- Import the project for the taint walk. This imports **all** built project modules,
    because P must cover the whole project, whatever `--module`/`--library` selected
    for output. If the full set does not import, it falls back to the selected modules.
    Returns the environment and the project modules it holds (`loadedProjectModules`).

    The full import runs only when the cheap olean-header preflight passes. A project
    that relies on the selection to avoid a collision then pays one preflight, not a
    failed import. The fallback runs whatever the full import failed on: a preflight
    collision, an import-time duplicate the preflight cannot see, or an unselected
    library's stale or part-less oleans (`formatProoflessError`). `--library` builds
    only the selected libraries, so an unselected one can have stale artifacts.

    The argument that makes the fallback sound does not depend on the fault. The
    modules left out are exactly those outside the selection's import closure. No
    emitted status can depend on them, and only the `check-axioms` audit loses them
    (`formatFallbackWarning`). A fault *inside* the closure fails the selection's
    import too (`formatFallbackFailure`).

    This is the import without the orphan check. `importProjectEnvWithFallback` adds it. -/
private def importProjectEnvSelecting (projectPath : System.FilePath)
    (all selected : Array ProjectModule) (nixMode : Option NixMode)
    : IO (Except String (Environment × Array ProjectModule)) := do
  if selected.size == all.size then
    return (← importProjectEnv projectPath all nixMode).map fun env => (env, all)
  match ← importProjectEnv projectPath all nixMode with
  | .ok env => return .ok (env, all)
  | .error msg =>
    match ← importProjectEnv projectPath selected nixMode with
    | .error e => return .error (formatFallbackFailure msg e)
    | .ok env =>
      let imported := loadedProjectModules all env.allImportedModuleNames
      if imported.size < all.size then
        IO.eprintln (formatFallbackWarning (all.size - imported.size))
      IO.eprintln s!"  (full import failed: {(msg.splitOn "\n").headD msg})"
      return .ok (env, imported)

/-- `importProjectEnvSelecting` (all modules, falling back to the selection), then the
    orphan check. Whichever import succeeded, an orphan module among `orphans` that it
    loaded (`loadedOrphans`) is fatal (see `formatLoadedOrphansError`). Returns the
    environment and the project modules it holds. -/
def importProjectEnvWithFallback (projectPath : System.FilePath)
    (all selected : Array ProjectModule) (nixMode : Option NixMode := none)
    (orphans : Array Name := #[])
    : IO (Except String (Environment × Array ProjectModule)) := do
  match ← importProjectEnvSelecting projectPath all selected nixMode with
  | .error e => return .error e
  | .ok r =>
    let stale := loadedOrphans orphans r.1.allImportedModuleNames
    if !stale.isEmpty then
      return .error (formatLoadedOrphansError stale)
    return .ok r

/-- The warning for a declaration whose type `Meta.isProp` could not check. -/
def formatSpecProofWarning (n : Name) : String :=
  s!"Warning: could not decide whether the type of {n} is a proposition; \
    it is not a spec target"

/-- Of `decls`, those of a spec-target kind (`specTargetKinds`) whose type is a
    proposition (`propTypedNamesWithFailures`, one `MetaM` run). A declaration whose
    type cannot be checked is reported and counted as a proof, so it is not a spec
    target (fail closed, like rule 3). Theorems need no check and are not included. -/
def specProofNames (env : Environment) (decls : Array DeclInfo) : IO (Std.HashSet Name) := do
  let cands := decls.filterMap fun d =>
    if specTargetKinds.contains d.kind then (env.find? d.name).map (d.name, ·) else none
  let (props, failed) ← propTypedNamesWithFailures env cands
  for n in failed do
    IO.eprintln (formatSpecProofWarning n)
  return props

/-- The per-declaration atom loop. Generated code is flagged hidden + generated so
    viewify and the web UI omit it from the presented graph, split by origin:
    deriving clusters and structure/class projections are core-Lean output
    (`is-lean-generated`), while `@[step]`'s mvcgen companion theorems exist only
    because of Aeneas (`is-aeneas-generated`). Either way the atom is kept in the
    atom set (not dropped), so the emitted graph still carries it. -/
private def buildAtoms (env : Environment) (projectPath : System.FilePath)
    (selFilter : ProjectFilter) (crate : String) (pathCache : ModulePathCache)
    (auxCache : AuxDepCache) (attrs : Std.HashMap Name DeclAttrs)
    (decls : Array DeclInfo) : IO (Array Atom) := do
  -- Auto-detected `deriving`-generated instance clusters and attribute-macro
  -- companion theorems (names only).
  let derivedNames := derivedInstanceClusterNames decls
  -- Companion parents can live outside the emitted declarations (`attribute
  -- [step]` on an external theorem/axiom, or a module-filtered parent); resolve
  -- their kind from the full environment so an external axiom's proxy is not
  -- misflagged.
  let companionNames := generatedCompanionTheoremNames decls
    (externalParentKind := fun n => (env.find? n).map (getDeclKind env n))
  let propTyped ← specProofNames env decls
  let emitted := decls.foldl (init := ({} : NameSet)) fun s d => s.insert d.name
  let mut atoms : Array Atom := #[]
  for decl in decls do
    let atom ← declInfoToAtom env projectPath selFilter crate pathCache auxCache
      emitted (attrs.getD decl.name default).attributes decl
    let atom := { atom with
      isProof := (env.find? decl.name).any (· matches .thmInfo _) ||
        propTyped.contains decl.name }
    let isLeanGen := derivedNames.contains decl.name || decl.kind == .projection
    let isAeneasGen := companionNames.contains decl.name
    let atom :=
      if isLeanGen then { atom with isHidden := true, isLeanGenerated := true }
      else if isAeneasGen then { atom with isHidden := true, isAeneasGenerated := true }
      else atom
    atoms := atoms.push atom
  return atoms

/-- Auxiliary-fold accounting. The counters are the performance gate's inputs:
    node expansions, edges scanned, materialised closure entries and peak cache
    size. The unresolved report is why `classifyFoldCandidate` consults
    `env.find?` before any name test. A dependency the environment cannot
    resolve is a diagnostic, not something to drop by suffix. -/
private def reportFoldStats (auxCache : AuxDepCache) : IO Unit := do
  let fold ← auxCache.get
  let cachedNames := fold.cache.fold (init := 0) fun n _ v => n + v.size
  -- `nonCacheable` is reported because a run where it stays 0 never hit a
  -- back-edge, i.e. the cycle rules were not exercised at all on that project.
  IO.println s!"Auxiliary fold: recovered {fold.addedEdges} dependency edge(s) \
    ({fold.expansions} expansions, {fold.edgesScanned} edges scanned, \
    {fold.nonCacheable} cycle suppression(s), \
    cache {fold.cache.size} entr(ies) / {cachedNames} name(s))"
  if !fold.unresolved.isEmpty then
    let names := (fold.unresolved.toArray.map (·.toString)).qsort (· < ·)
    IO.eprintln s!"Warning: {names.size} dependency name(s) could not be resolved \
      in the environment during the auxiliary fold (edges under them are not recovered):"
    for n in names do
      IO.eprintln s!"  {n}"

/-- Import the project, run the kernel taint pass over all of it, and build the
    atoms for the selected modules. `all` is every built project module (P), `selected`
    the `--module`/`--library` selection that decides which declarations become atoms
    and which dependencies count as project-internal. Atoms carry `leanName`, the
    join key for `applyTaintStatus`. -/
def runAnalysisViaLakeEnv (projectPath : System.FilePath) (all selected : Array ProjectModule)
    (crate : String) (nixMode : Option NixMode := none) (orphans : Array Name := #[])
    (computeAssumptions : Bool := true)
    : IO (Except String (Array Atom × ProjectTaint)) := do
  let (env, imported) ← match ← importProjectEnvWithFallback projectPath all selected
      nixMode orphans with
    | .error msg => return .error msg
    | .ok r => pure r
  -- P is decided by the imported project modules; emission by the selection.
  let pFilter := mkProjectFilter env (imported.map (·.name))
  let selFilter := mkProjectFilter env (selected.map (·.name))

  IO.println "Extracting declarations..."
  let consts := projectConstants env pFilter
  let fileCache : FileCache ← IO.mkRef {}
  let pathCache : ModulePathCache ← IO.mkRef {}
  let (pt, attrs) ← computeProjectTaint env projectPath pFilter fileCache pathCache consts
    (moduleCount := imported.size) (computeAssumptions := computeAssumptions)
  let decls := getProjectDeclsFrom env consts selFilter pt.mergedVersions
  IO.println s!"Found {decls.size} declarations"
  IO.println (formatTaintSummary pt)
  IO.println (formatTagSetLine pt.tagSet)
  reportTaintWarnings pt

  -- A merged declaration emitted from a selected declaring module while the
  -- environment attributes the name to an unselected one is an atom, so its
  -- callers' edges to it are project edges: count those names as selected for the
  -- dependency partition and the fold (`ProjectFilter.names`). With no selection
  -- every owner is selected and the set is empty.
  let atomFilter := selFilter.withNames
    (decls.filterMap fun d => if selFilter.contains env d.name then none else some d.name)
  -- One fold state per run: its closure cache is keyed to this `Environment`
  -- and this project filter, and extraction is sequential (see `FoldState`).
  let auxCache : AuxDepCache ← IO.mkRef {}
  let atoms ← buildAtoms env projectPath atomFilter crate pathCache auxCache attrs decls
  reportFoldStats auxCache
  return .ok (atoms, pt)

end ProbeLean
