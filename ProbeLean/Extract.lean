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
import ProbeLean.VerifyInternal
import ProbeLean.Transitive

namespace ProbeLean

open Lean

/-- Configuration for the extract command -/
structure ExtractConfig where
  projectPath : System.FilePath
  outputPath : Option System.FilePath
  moduleFilter : Option String
  skipVerify : Bool
  fromFile : Option System.FilePath
  libraries : Option (Array String) := none
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
    codomainHead := atom.codomainHead
    codomainIsProp := atom.codomainIsProp
    codomainLastArgIsBool := atom.codomainLastArgIsBool
  }

/-- A generated atom (lean- or aeneas-generated) is *contaminated* — worth
    surfacing so users can trace why a downstream atom isn't fully verified —
    when, after full enrichment, it is locally verified but not transitively
    verified (`.verified`), or is itself `.unverified`/`.failed`.
    `.transitivelyVerified` and `.trusted` generated atoms are clean and stay
    hidden. Only meaningful after enrichment — the caller skips the unhide
    pass under `--skip-enrich`, where every proved atom still reads
    `.verified` and would be misread as contaminated. -/
def isContaminatedGenerated (atom : UnifiedAtom) : Bool :=
  (atom.isLeanGenerated || atom.isAeneasGenerated) &&
    match atom.verificationStatus with
    | some .verified | some .unverified | some .failed => true
    | _ => false

/-- Clear `is-hidden` on contaminated generated atoms so consumers that read
    `extract` output directly (e.g. the web UI) surface them for tracing; clean
    (transitively-verified/trusted) generated atoms stay hidden. Note: `viewify`
    (`filterAtomsForView`) drops all generated atoms regardless of `is-hidden`. -/
def unhideContaminatedGenerated (atoms : Array UnifiedAtom) : Array UnifiedAtom :=
  atoms.map fun atom =>
    if isContaminatedGenerated atom then { atom with isHidden := false } else atom

/-- Check whether a module belongs to one of the given library roots.
    A module `A.B.C` belongs to library `A` if its name equals `A` or starts with `A.`. -/
def moduleInLibraries (m : Lean.Name) (libs : Array String) : Bool :=
  libs.any fun lib => m.toString == lib || m.toString.startsWith (lib ++ ".")

/-- Choose which collected modules to analyze.

    Restricts to `libraries` ONLY when they are explicitly provided (via the
    `--library` flag). Auto-detected build targets are deliberately NOT used as a
    module filter here: `defaultTargets` may name a `lean_exe` and a `lean_lib` may
    declare custom `roots` that differ from its name, so filtering by them can
    silently drop every module. `.lake/build/lib/lean` already contains only the
    project's own modules, so the default is to analyze all of them. A single
    `moduleFilter` (`--module`) further narrows the result by name prefix.
    Filters operate on whole `ProjectModule` records so each module keeps the
    olean path it was discovered with. -/
def selectModules (modules : Array ProjectModule) (libraries : Option (Array String))
    (moduleFilter : Option String) : Array ProjectModule :=
  let byLib := match libraries with
    | some libs => modules.filter fun m => moduleInLibraries m.name libs
    | none => modules
  match moduleFilter with
  | some filter =>
    let filterName := String.toName filter
    byLib.filter fun m => m.name == filterName || m.name.toString.startsWith (filter ++ ".")
  | none => byLib

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

/-- Published atom names occurring more than once. Collisions are only possible
    among private declarations whose user-facing names coincide across modules
    (e.g. a top-level `private theorem aux` in two files both publish as
    `probe:aux`). Reported as a warning; not deduplicated. -/
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
    post-`computeSpecs` array. Derived from the same `specs` / `isPrimarySpec`
    data the artifact emits, so a warning cannot disagree with the emitted JSON
    when published names are unique; under duplicate names it follows the
    pre-serialization array and is the more correct of the two.

    The tagged set is a union over names rather than a `name → Bool` map: with
    duplicate published names, an untagged namesake must not clobber a tagged
    theorem. The `kind == theorem` gate mirrors `attrPrimarySpecMap`. The cost is
    a spurious record when a tagged theorem's published name is shared by an
    untagged namesake that some other target lists: the name counts as tagged for
    that target too. Only this warning is affected — `attrPrimarySpecMap` keys on
    each tagged theorem's own `specTargets`, so the emitted `primary-spec` stays
    correct. Suppressing it would mean masking real candidates instead. -/
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

/-- What `prepareProject` hands to the pipeline. -/
structure PreparedProject where
  /-- Every built project module — P, the taint walk's domain, whatever was selected. -/
  allModules : Array ProjectModule
  /-- The `--library`/`--module` selection: which declarations become atoms. -/
  selectedModules : Array ProjectModule
  nixMode : Option NixMode
  /-- Captured `lake build` output (or the cached copy). -/
  buildOutput : String

/-- Build (honouring the cache) and discover/select the project's modules.
    Shared by `runExtractInProject` and the `check-axioms` command so the audit path
    and the extraction path can't drift on nix detection, build, or module selection.
    Returns the built and selected modules, nix mode and captured build output, or an
    exit code. -/
def prepareProject (projectPath : System.FilePath) (libraries : Option (Array String))
    (moduleFilter : Option String) : IO (Except UInt32 PreparedProject) := do
  if !(← isLakeProject projectPath) then
    IO.eprintln s!"Error: Not a Lake project: {projectPath}"
    return .error 1

  let nixMode ← do
    match ← detectNixShell projectPath with
    | some mode =>
      if ← isNixAvailable mode then
        IO.println s!"Nix environment detected ({mode}.nix), lake commands will run inside it."
        IO.println "  (first run may be slow while Nix downloads dependencies)"
        pure (some mode)
      else
        let bin := match mode with | .flake => "nix" | .shell => "nix-shell"
        IO.eprintln s!"Warning: Project has {mode}.nix but `{bin}` is not installed."
        IO.eprintln "  System dependencies may be missing. Install Nix or install deps manually."
        pure none
    | none => pure none

  let probeLeanVersion := Lean.versionString
  let targetTC ← readToolchain projectPath
  let targetVersionStr := match targetTC with
    | some tc => parseToolchainVersion tc
    | none    => "unknown (no lean-toolchain file)"
  IO.println s!"probe-lean built with Lean {probeLeanVersion}, target project uses {targetVersionStr}"

  let libs ← match libraries with
    | some ls => pure ls
    | none => getLeanLibs projectPath

  let buildOutput ← if ← isCacheValid projectPath then
    IO.println "Build cache is up-to-date, skipping lake build..."
    match ← loadCache projectPath with
    | some cached => pure cached
    | none => pure ""
  else do
    ensureMathlibCache projectPath nixMode
    let buildArgs := if libs.isEmpty then #["build"] else #["build"] ++ libs
    if !libs.isEmpty then
      IO.println s!"Building libraries: {", ".intercalate libs.toList}"
    IO.println s!"Building project at {projectPath}..."
    let (buildStdout, buildStderr, buildExit) ← runLakeCmd buildArgs (some projectPath) nixMode
    if buildExit != 0 then
      IO.eprintln s!"Lake build failed:\n{buildStderr}"
      return .error 1
    let output := buildStdout ++ "\n" ++ buildStderr
    saveCache projectPath output
    pure output

  IO.println "Getting project modules..."
  let sourceRoots ← getSourceRoots projectPath
  let modules ← match ← getProjectModules projectPath nixMode sourceRoots with
    | .error msg =>
      IO.eprintln msg
      return .error 1
    | .ok mods => pure mods

  if modules.isEmpty then
    IO.eprintln "Error: No modules found in project"
    return .error 1

  let filteredModules := selectModules modules libraries moduleFilter

  -- Warn about any explicit `--library` entry that matched no built module, so a
  -- partial filter (e.g. one good name + one typo, or a name that differs from
  -- the library's actual module root) isn't applied silently. Note `--library`
  -- matches by module-name prefix, so it cannot select a library whose `roots`
  -- differ from its name (use `--module <root>` for those).
  if let some libs := libraries then
    for lib in libs do
      if !(modules.any fun m => moduleInLibraries m.name #[lib]) then
        IO.eprintln s!"Warning: --library {lib} matched no built module (it is not a module-name root)."

  -- Fail loudly instead of silently writing 0 atoms: if we built modules but
  -- every one was filtered out, the `--library`/`--module` selection didn't
  -- match anything that was built.
  if filteredModules.isEmpty && !modules.isEmpty then
    IO.eprintln "Error: every project module was filtered out by --library/--module."
    IO.eprintln s!"  {modules.size} module(s) were built but none matched the requested filter."
    let roots := (modules.map fun m => (m.name.toString.splitOn ".").headD m.name.toString).toList.eraseDups
    IO.eprintln s!"  Available top-level module roots: {", ".intercalate roots}"
    return .error 1

  IO.println s!"Analyzing {filteredModules.size} modules..."
  return .ok { allModules := modules, selectedModules := filteredModules, nixMode, buildOutput }

/-- Where the build log and the kernel disagree about an atom. The log is matched to
    atoms by file and line range, so a `sorry` abstracted into an auxiliary
    (`X._proof_N`) is attributed to `X` by the log while the kernel makes `X` tainted
    rather than direct — that is agreement, not divergence. Generated atoms share
    their range with the declaration that produced them (a `.mvcgen_spec` companion
    with its parent, a derived instance with its type), so the log cannot speak about
    them and they are skipped. Reported: the log flags an atom the kernel finds clean
    modulo T, or the kernel finds a direct carrier the log never warned about (a
    module with errors, `warn.sorry` off). -/
def logDivergences (warnings : Array SorryWarning) (atoms : Array Atom) (pt : ProjectTaint)
    : Array String := Id.run do
  let mut out : Array String := #[]
  for atom in atoms do
    if atom.isLeanGenerated || atom.isAeneasGenerated then
      continue
    let logSorry := !(findSorriesForAtom warnings atom).isEmpty
    let direct := pt.taint.direct.contains atom.leanName
    let restsOnSorry := direct || pt.taint.tainted.contains atom.leanName
    if logSorry && !restsOnSorry then
      out := out.push s!"Divergence: {atom.name} build log says sorry, kernel says clean"
    else if direct && !logSorry then
      out := out.push s!"Divergence: {atom.name} kernel says sorry, build log says clean"
  return out

/-- Step 2. The build log decides nothing — the kernel walk does — but it is parsed
    as before and cross-checked against the walk (`logDivergences`). -/
private def runVerifyStep (config : ExtractConfig) (buildOutput : String) (atoms : Array Atom)
    (pt : ProjectTaint) : IO Unit := do
  IO.println "=== Step 2/3: Verify ==="
  if config.skipVerify then
    IO.println "Verification skipped (--skip-verify)"
    return
  let verifyOutput ← match config.fromFile with
    | some file =>
      IO.println s!"Reading build output from {file}..."
      IO.FS.readFile file
    | none => pure buildOutput
  let warnings := parseSorryWarnings verifyOutput
  IO.println s!"Found {warnings.size} sorry warnings (build log)"
  let direct := atoms.filter fun a => pt.taint.direct.contains a.leanName
  let clean := atoms.filter fun a => !pt.taint.direct.contains a.leanName
  IO.println s!"Direct sorry carriers (kernel): {direct.size}"
  IO.println s!"Verified: {clean.size}/{atoms.size} declarations"
  if warnings.isEmpty && !direct.isEmpty then
    IO.eprintln s!"Note: the build log carries no sorry warnings (cached build without output, \
      or warnings suppressed); the kernel finds {direct.size} direct carrier(s)"
  else
    for line in logDivergences warnings atoms pt do
      IO.eprintln line

/-- Enrich. The reverse-BFS over the emitted graph no longer decides status; it runs
    on the oracle's seeds and every atom on which it disagrees with the walk is
    printed (`divergenceLines`), never reconciled. -/
private def runEnrichStep (config : ExtractConfig) (oracle : Array UnifiedAtom) : IO Unit := do
  if config.skipEnrich then
    IO.println "Enrichment skipped (--skip-enrich)"
    return
  IO.println "=== Enrich ==="
  let (graph, _, _, missingDeps) := enrichTransitiveVerification (demoteTransitive oracle)
  -- Only surface genuine orphans. References to constructors/fields of an
  -- extracted type (inductive/structure/class) are benign and collapsed into
  -- a single note so real gaps are not lost in the noise.
  let (orphans, typeMemberCount) := partitionMissingDeps oracle missingDeps
  for dep in orphans do
    IO.eprintln s!"Warning: dependency \"{dep}\" not found in atom map (graph cross-check only; status comes from the kernel walk)"
  if typeMemberCount > 0 then
    IO.eprintln s!"Note: {typeMemberCount} reference(s) to constructors/fields of extracted types (graph cross-check only)"
  let divs := divergenceLines oracle graph
  for d in divs do
    IO.eprintln d
  if !divs.isEmpty then
    IO.eprintln s!"Divergence: {divs.size} atom(s) where the emitted graph disagrees with the kernel walk"
  let (transitive, local_, notVerified) := statusCounts oracle
  IO.println s!"Transitively verified: {transitive} | Locally verified: {local_} | Not verified: {notVerified}"

/-- Run the combined extract pipeline: build → atomize (+ kernel taint pass) →
    markAtomFlags → specs → verify (log cross-check) → merge (status from the taint
    pass) → enrich (graph cross-check) → envelope → write -/
def runExtractInProject (config : ExtractConfig) : IO UInt32 := do
  let prepared ← match ← prepareProject config.projectPath config.libraries config.moduleFilter with
    | .error code => return code
    | .ok r => pure r

  -- === Step 1: Atomize ===
  IO.println "=== Step 1/3: Atomize ==="

  let userConfig ← loadUserConfig config.projectPath
  let crate := loadRelevantCrate userConfig

  let (atoms, pt) ← match ← runAnalysisViaLakeEnv config.projectPath prepared.allModules
      prepared.selectedModules crate prepared.nixMode with
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

  runVerifyStep config prepared.buildOutput atoms pt

  -- === Step 3: Merge — status from the taint pass, joined on `leanName` ===
  IO.println "=== Step 3/3: Merge ==="
  let unifiedAtoms := applyTaintStatus (atoms.map unifyAtom) pt
    (applyTaint := !config.skipVerify) (upgrade := !config.skipEnrich)

  runEnrichStep config unifiedAtoms

  -- Contaminated generated atoms (lean- or aeneas-generated) have their isHidden
  -- cleared so the user can trace why downstream atoms aren't fully verified (see
  -- `isContaminatedGenerated`). Contamination is only meaningful after enrichment:
  -- without it every proved atom still reads `.verified`, so the pass would
  -- misread all clean generated atoms as contaminated and unhide them.
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
