/-
  Extract command: combined atomize + sorry detection.
  Produces unified atoms with verification status and specs.
  Schema: probe-lean/extract
-/
import Lean
import ProbeLean.Types
import ProbeLean.Environment
import ProbeLean.Metadata
import ProbeLean.Atomize
import ProbeLean.Transitive
import ProbeLean.Targets

namespace ProbeLean

open Lean

/-- Configuration for the extract command -/
structure ExtractConfig where
  projectPath : System.FilePath
  outputPath : Option System.FilePath
  moduleFilter : Option String
  skipVerify : Bool
  libraries : Option (Array Name) := none
  allLibraries : Bool := false
  skipEnrich : Bool := false
  deriving Repr

/-- Lift an `Atom` to a `UnifiedAtom`, preserving all atom fields. No status yet:
    `applyTaintStatus` stamps `verification-status`/`trusted-reason` from the kernel
    taint pass, joined on `leanName`. -/
def unifyAtom (atom : Atom) : UnifiedAtom :=
  {
    name := atom.name
    leanName := atom.leanName
    displayName := atom.displayName
    dependencies := atom.dependencies
    typeDependencies := atom.typeDependencies
    termDependencies := atom.termDependencies
    typeDependenciesExternal := atom.typeDependenciesExternal
    termDependenciesExternal := atom.termDependenciesExternal
    codeModule := atom.codeModule
    codePath := atom.codePath
    codeText := atom.codeText
    kind := atom.kind
    language := atom.language
    isHidden := atom.isHidden
    isLeanGenerated := atom.isLeanGenerated
    isAeneasGenerated := atom.isAeneasGenerated
    isIgnored := atom.isIgnored
    isRelevant := atom.isRelevant
    isInPackage := atom.isInPackage
    rustSource := atom.rustSource
    attributes := atom.attributes
    specs := atom.specs
    isPrimarySpec := atom.isPrimarySpec
    primarySpec := atom.primarySpec
    verificationStatus := none
    trustedReason := none
    statusOrigin := none
    codomainHead := atom.codomainHead
    codomainIsProp := atom.codomainIsProp
    codomainLastArgIsBool := atom.codomainLastArgIsBool
  }

/-- A generated atom (lean- or aeneas-generated) is *contaminated* in two cases.
    It reads `.verified`: with the upgrade to `transitively-verified`, that means the
    kernel walk found it tainted. Or it is itself `.unverified`/`.failed`. Such an
    atom is worth surfacing, so users can trace why a downstream atom is not fully
    verified. `.transitivelyVerified` and `.trusted` generated atoms are clean and
    stay hidden. The test has meaning only with the upgrade. The caller skips the
    unhide pass under `--skip-enrich`, where every clean atom reads `.verified` and
    so looks contaminated. -/
def isContaminatedGenerated (atom : UnifiedAtom) : Bool :=
  (atom.isLeanGenerated || atom.isAeneasGenerated) &&
    match atom.verificationStatus with
    | some .verified | some .unverified | some .failed => true
    | _ => false

/-- Clear `is-hidden` on contaminated generated atoms so consumers that read
    `extract` output directly (for example the web UI) surface them for tracing.
    Clean (transitively-verified/trusted) generated atoms stay hidden. Note: `viewify`
    (`filterAtomsForView`) drops all generated atoms regardless of `is-hidden`. -/
def unhideContaminatedGenerated (atoms : Array UnifiedAtom) : Array UnifiedAtom :=
  atoms.map fun atom =>
    if isContaminatedGenerated atom then { atom with isHidden := false } else atom

/-- Check if project depends on Mathlib and auto-download the olean cache if missing.
    Without the pre-built cache, `lake build` compiles Mathlib from source (hours). -/
def ensureMathlibCache (projectPath : System.FilePath)
    (nixMode : Option NixMode := none) : IO Unit := do
  let manifestPath := projectPath / "lake-manifest.json"
  if !(← manifestPath.pathExists) then return
  let content ← IO.FS.readFile manifestPath
  unless containsSubstring content "mathlib" do return
  let oleanPath := projectPath / ".lake" / "packages" / "mathlib" /
    ".lake" / "build" / "lib" / "lean" / "Mathlib.olean"
  if ← oleanPath.pathExists then return
  IO.println "Mathlib dependency detected but no pre-built cache found."
  IO.println "Running `lake exe cache get` to download pre-built .olean files..."
  IO.println ""
  let (_, stderr, exitCode) ← runLakeCmd #["exe", "cache", "get"] (some projectPath) nixMode
  if exitCode != 0 then
    IO.eprintln s!"⚠ `lake exe cache get` failed (exit {exitCode}):"
    IO.eprintln stderr
    IO.eprintln "  Building Mathlib from source may take hours."
    IO.eprintln s!"  Try running manually: cd {projectPath} && lake exe cache get"
    IO.eprintln ""
  else
    IO.println "  ✓ Mathlib cache downloaded"
    IO.println ""

/-- Published atom names occurring more than once. Only private declarations can
    collide, when their user-facing names coincide across modules (for example,
    a top-level `private theorem aux` in two files both publish as `probe:aux`).
    Reported as a warning, not deduplicated. -/
def duplicateAtomNames (atoms : Array Atom) : Array String := Id.run do
  let mut counts : Std.HashMap String Nat := {}
  for a in atoms do
    counts := counts.insert a.name (counts.getD a.name 0 + 1)
  let dups := counts.toList.filterMap fun (name, n) => if n > 1 then some name else none
  return dups.toArray.qsort (· < ·)

/-- A target whose `primary-spec` was an arbitrary tie-break. -/
structure PrimarySpecCollision where
  target : String
  winner : String
  /-- Tagged candidates other than the winner: sorted, de-duplicated, non-empty. -/
  rejected : Array String
  deriving Repr, BEq

/-- Targets whose `primary-spec` was an arbitrary tie-break: two or more
    `@[primary_spec]`-tagged theorems resolve to the same target. One record per
    target name, sorted by target name, candidate names de-duplicated.

    Only targets with `primarySpec` set are considered, so this must run on the
    post-`computeSpecs` array. The records come from the same `specs` /
    `isPrimarySpec` data the artifact emits. So a warning cannot disagree with
    the emitted JSON when published names are unique. Under duplicate names it
    follows the pre-serialization array and is the more correct of the two.

    The tagged set is a union over names rather than a `name → Bool` map: with
    duplicate published names, an untagged namesake must not clobber a tagged
    theorem. The `kind == theorem` gate mirrors `attrPrimarySpecMap`. The cost is
    a spurious record when a tagged theorem's published name is shared by an
    untagged namesake that some other target lists: the name counts as tagged for
    that target too. Only this warning is affected, because `attrPrimarySpecMap`
    keys on each tagged theorem's own `specTargets`, so the emitted `primary-spec`
    stays correct. Suppressing the record means masking real candidates instead. -/
def ambiguousPrimarySpecs (atoms : Array Atom) : Array PrimarySpecCollision := Id.run do
  let mut tagged : Std.HashSet String := {}
  for a in atoms do
    if a.kind == DeclKind.theorem && a.isPrimarySpec then
      tagged := tagged.insert a.name
  -- Keyed by target name: `computeSpecs` sets `primarySpec` on every atom whose
  -- name matches the target, so iterating atoms would report a duplicated
  -- target twice.
  let mut seen : Std.HashSet String := {}
  let mut collisions : Array PrimarySpecCollision := #[]
  for a in atoms do
    if seen.contains a.name then continue
    seen := seen.insert a.name
    let some winner := a.primarySpec | continue
    let mut candidates : Array String := #[]
    let mut candidateSeen : Std.HashSet String := {}
    for s in a.specs do
      if tagged.contains s && !candidateSeen.contains s then
        candidateSeen := candidateSeen.insert s
        candidates := candidates.push s
    if candidates.size ≥ 2 then
      collisions := collisions.push
        { target := a.name, winner, rejected := (candidates.filter (· != winner)).qsort (· < ·) }
  return collisions.qsort (fun x y => x.target < y.target)

/-- Render one collision as its stderr warning line. Pure, so the exact text is
    testable without capturing stderr. Takes the record rather than positional
    strings so `target` and `winner` bind by name. -/
def formatPrimarySpecWarning (c : PrimarySpecCollision) : String :=
  let count := c.rejected.size + 1
  let alsoTagged := ", ".intercalate c.rejected.toList
  s!"Warning: {count} @[primary_spec] theorems target {c.target} — " ++
    s!"chose {c.winner} (arbitrary tie-break); also tagged: {alsoTagged}"

/-- The `extract` wiring for `ambiguousPrimarySpecs`, split out so the call site
    is covered by a test rather than only by review. -/
def warnAmbiguousPrimarySpecs (atoms : Array Atom) : IO Unit := do
  for c in ambiguousPrimarySpecs atoms do
    IO.eprintln (formatPrimarySpecWarning c)

/-- Detect the Nix environment of the project. -/
private def detectNixMode (projectPath : System.FilePath) : IO (Option NixMode) := do
  match ← detectNixShell projectPath with
  | some mode =>
    if ← isNixAvailable mode then
      IO.println s!"Nix environment detected ({mode}.nix), lake commands will run inside it."
      IO.println "  (first run may be slow while Nix downloads dependencies)"
      return some mode
    else
      let bin := match mode with | .flake => "nix" | .shell => "nix-shell"
      IO.eprintln s!"Warning: Project has {mode}.nix but `{bin}` is not installed."
      IO.eprintln "  System dependencies may be missing. Install Nix or install deps manually."
      return none
  | none => return none

/-- The selection flags of `extract` and `check-axioms`. -/
structure Selection where
  libraries : Option (Array Name) := none
  allLibraries : Bool := false
  moduleFilter : Option String := none

/-- Load the workspace, check the build directory, choose the
    targets and build them. Returns the workspace, the targets and the real path of
    the project. -/
private def loadAndBuild (projectPath : System.FilePath) (sel : Selection)
    (nixMode : Option NixMode)
    : IO (Except String (WorkspaceInfo × Array Target × System.FilePath)) := do
  IO.println "Reading the Lake workspace..."
  let info ← match ← queryWorkspaceInfo projectPath nixMode with
    | .error e => return .error e
    | .ok i => pure i
  let projectReal ← IO.FS.realPath projectPath
  if let .error e := checkLeanLibDir projectReal info.leanLibDir then return .error e
  let (targets, skipped) ← match chooseTargets info sel.libraries sel.allLibraries with
    | .error e => return .error e
    | .ok r => pure r
  for d in skipped do
    IO.eprintln s!"Note: default target {d} is not a lean_lib or lean_exe, skipped."
  ensureMathlibCache projectPath nixMode
  let args := buildArgs targets
  IO.println s!"Building at {projectPath}: lake {" ".intercalate args.toList}"
  let (out, err, code) ← runLakeCmd args (some projectPath) nixMode
  if code != 0 then
    return .error s!"Lake build failed:\n{out}{err}"
  return .ok (info, targets, projectReal)

/-- The import set, the `.olean` check and the closure. The closure of every
    target module comes first. Without `--module`, the target modules are the
    import set. With `--module`, the import set is the modules of that closure
    under the prefix, and P narrows to their closure (`narrowClosure`). The prefix
    filters the closure, not the target list, because a library with the default
    glob lists only its root module. -/
private def importClosure (info : WorkspaceInfo) (targets : Array Target)
    (projectReal : System.FilePath) (moduleFilter : Option String)
    : IO (Except String (Array Name × Option Name × Array ProjectHeader × SearchPath × System.FilePath)) := do
  let pre? ← match moduleFilter with
    | none => pure none
    | some s => match parseModulePrefix s with
      | .error e => return .error e
      | .ok n => pure (some n)
  -- Sorted by name, for a deterministic import order (P14). The order decides
  -- which module a merged declaration's name goes to.
  let targetMods := (targetModules info targets).qsort (·.toString < ·.toString)
  if targetMods.isEmpty then
    return .error "Error: No modules found in the target libraries."
  -- A real path, as the search path entries are (`resolveSearchPath`), so that a
  -- symlinked `.lake` or `.lake/build` passes the prefix test of `isInBuildDir`.
  let buildDir := projectReal / ".lake" / "build" / "lib" / "lean"
  let buildDir ← if ← buildDir.pathExists then IO.FS.realPath buildDir else pure buildDir
  let missing ← missingOleans buildDir targetMods
  if !missing.isEmpty then return .error (formatMissingOleans missing)
  let sp ← resolveSearchPath projectReal info.leanPath
  let full ← match ← computeClosure buildDir sp targetMods with
    | .error e => return .error e
    | .ok hs => pure hs
  match pre? with
  | none => return .ok (targetMods, none, full, sp, buildDir)
  | some pre =>
    -- `full` is sorted by name, so the import set is too.
    let importSet := filterModulePrefix (full.map (·.name)) pre
    if importSet.isEmpty then return .error (formatEmptyModuleFilter pre full.size)
    return .ok (importSet, pre?, narrowClosure full importSet, sp, buildDir)

/-- Build the targets on every run and compute what to import and what to emit.
    Shared by `runExtractInProject` and `check-axioms` (`runCheckAxiomsInProject`)
    so the audit path and the extraction path cannot drift. Steps, in order: the
    workspace load with the Lean version check, the build directory check
    (`checkLeanLibDir`), the targets (`chooseTargets`), `ensureMathlibCache`, the
    target build, the `.olean` check (`missingOleans`), the closure
    (`computeClosure`), the `--module` filter (`narrowClosure`), the owners
    (`queryOwners`), the ownership check
    (`classifyOwnership`) and the emitted set (`emittedSet`). Returns the
    `PreparedProject` or the exit code to fail with. -/
def prepareProject (projectPath : System.FilePath) (sel : Selection)
    : IO (Except UInt32 PreparedProject) := do
  if !(← isLakeProject projectPath) then
    IO.eprintln s!"Error: Not a Lake project: {projectPath}"
    return .error 1
  let nixMode ← detectNixMode projectPath
  let targetTC ← readToolchain projectPath
  let targetVersionStr := match targetTC with
    | some tc => parseToolchainVersion tc
    | none    => "unknown (no lean-toolchain file)"
  IO.println s!"probe-lean built with Lean {Lean.versionString}, target project uses {targetVersionStr}"
  let fail (e : String) : IO (Except UInt32 PreparedProject) := do
    IO.eprintln e
    return .error 1
  let (info, targets, projectReal) ← match ← loadAndBuild projectPath sel nixMode with
    | .error e => return ← fail e
    | .ok r => pure r
  let (importSet, pre?, headers, sp, buildDir) ←
    match ← importClosure info targets projectReal sel.moduleFilter with
    | .error e => return ← fail e
    | .ok r => pure r
  let p := headers.map (·.name)
  let owners ← match ← queryOwners projectPath nixMode p with
    | .error e => return ← fail e
    | .ok o => pure o
  let exeRoots := targets.filterMap fun | .exe _ root => some root | .lib _ => none
  let imported := importedNames headers
  let rejected := classifyOwnership p owners exeRoots imported.contains
  if !rejected.isEmpty then return ← fail (formatRejections rejected)
  let emitted := emittedSet importSet p owners pre? sel.libraries
  IO.println s!"Analyzing {emitted.size} of {p.size} project modules..."
  return .ok { importSet, headers, emitted, searchPath := sp, buildDir, nixMode }

/-- Step 2. The kernel walk decides the status. This step prints how many atoms
    are direct carriers. -/
private def runVerifyStep (config : ExtractConfig) (atoms : Array Atom) (pt : ProjectTaint)
    : IO Unit := do
  IO.println "=== Step 2/3: Verify ==="
  if config.skipVerify then
    IO.println "Verification skipped (--skip-verify)"
    return
  -- Only the direct count is printed here: the final statuses are mutually exclusive
  -- and the enrich step prints them (`Transitively verified | Locally verified | Not
  -- verified`); a "verified n/m" of the non-direct atoms would count tainted and
  -- trusted atoms alike under a word that is also a status.
  let direct := atoms.filter fun a => pt.taint.direct.contains a.leanName
  IO.println s!"Direct sorry carriers (kernel): {direct.size} of {atoms.size} atoms"

/-- Enrich. Prints the final status counts. The graph check of the emitted
    `dependencies` against these statuses is `tools/audit/check-graph.py`. -/
private def runEnrichStep (config : ExtractConfig) (atoms : Array UnifiedAtom) : IO Unit := do
  if config.skipEnrich then
    IO.println "Enrichment skipped (--skip-enrich)"
    return
  IO.println "=== Enrich ==="
  let (transitive, local_, notVerified) := statusCounts atoms
  IO.println s!"Transitively verified: {transitive} | Locally verified: {local_} | Not verified: {notVerified}"

/-- Run the combined extract pipeline: build → atomize (+ kernel taint pass) →
    markAtomFlags → specs → verify (direct carrier count) → merge (status from the
    taint pass) → enrich (status counts) → envelope → write -/
def runExtractInProject (config : ExtractConfig) : IO UInt32 := do
  let sel : Selection := { libraries := config.libraries, allLibraries := config.allLibraries,
                           moduleFilter := config.moduleFilter }
  let prepared ← match ← prepareProject config.projectPath sel with
    | .error code => return code
    | .ok r => pure r

  -- === Step 1: Atomize ===
  IO.println "=== Step 1/3: Atomize ==="

  let userConfig ← loadUserConfig config.projectPath
  let crate := loadRelevantCrate userConfig

  let (atoms, pt) ← match ← runAnalysisViaLakeEnv config.projectPath prepared crate
      (computeAssumptions := !config.skipVerify) with
    | .error msg =>
      IO.eprintln s!"Analysis failed: {msg}"
      return 1
    | .ok result => pure result

  IO.println s!"Found {atoms.size} atoms"

  for dupName in duplicateAtomNames atoms do
    IO.eprintln s!"Warning: duplicate atom name {dupName} (private declarations in different modules recover to the same user-facing name)"

  -- Mark filtering flags from .verilib/probes/config.json (bug fix: was missing in old pipeline)
  let hiddenList := loadIsHiddenList userConfig
  let aeneasGeneratedSuffixes := loadAeneasGeneratedSuffixes userConfig
  let ignoredList := loadIsIgnoredList userConfig
  let atoms := markAtomFlags atoms hiddenList aeneasGeneratedSuffixes ignoredList
  let atoms := computeSpecs atoms

  -- Must run after `computeSpecs`: the collision is only visible once `specs`
  -- and `primarySpec` are populated.
  warnAmbiguousPrimarySpecs atoms

  runVerifyStep config atoms pt

  -- === Step 3: Merge — status from the taint pass, joined on `leanName` ===
  IO.println "=== Step 3/3: Merge ==="
  let (unifiedAtoms, unknown) := applyTaintStatus (atoms.map unifyAtom) pt
    (applyTaint := !config.skipVerify) (upgrade := !config.skipEnrich)
  for name in unknown do
    IO.eprintln (formatUnknownAtomWarning name)

  runEnrichStep config unifiedAtoms

  -- Contaminated generated atoms (lean- or aeneas-generated) have their isHidden
  -- cleared so the user can trace why downstream atoms aren't fully verified (see
  -- `isContaminatedGenerated`). Contamination is only meaningful with the upgrade
  -- to `transitively-verified`: under `--skip-enrich` every clean atom reads
  -- `.verified`, so the pass would misread all clean generated atoms as
  -- contaminated and unhide them.
  let unifiedAtoms :=
    if config.skipEnrich then unifiedAtoms else unhideContaminatedGenerated unifiedAtoms

  writeExtractOutput config unifiedAtoms

where
  writeExtractOutput (config : ExtractConfig) (unifiedAtoms : Array UnifiedAtom) : IO UInt32 := do
  let source ← collectSourceInfo config.projectPath
  let timestamp ← getCurrentTimestamp

  let output : UnifiedAtomsOutput := { atoms := unifiedAtoms }
  let envelope : Envelope UnifiedAtomsOutput := {
    schema := Constants.schemaExtract
    tool := { command := "extract" }
    source := source
    timestamp := timestamp
    data := output
  }
  let json := Lean.toJson envelope
  let jsonStr := json.pretty

  let outputPath := config.outputPath.getD (buildProbesOutputPath config.projectPath source)
  if let some parentDir := outputPath.parent then
    IO.FS.createDirAll parentDir
  IO.FS.writeFile outputPath jsonStr
  IO.println s!"Wrote {unifiedAtoms.size} unified atoms to {outputPath}"
  return 0

end ProbeLean
