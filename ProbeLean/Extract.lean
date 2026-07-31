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
  classOverride : Option String := none
  deriving Repr

/-- Map probe-lean VerifyStatus to the web frontend's verification status -/
def mapVerifyStatus : VerifyStatus → WebVerificationStatus
  | .success => .verified
  | .sorries => .unverified
  | .failure => .failed

/-- Determine why an atom is trusted, if at all. Precedence:
    1. `axiom` kind — always trusted
    2. `@[externally_verified]` attribute — proof is discharged outside Lean
    3. Non-theorem declarations in `*External.lean` — Aeneas trust-base convention
    Theorems in `*External.lean` without `@[externally_verified]` are *not* trusted;
    they carry real proofs and receive their normal status from sorry detection. -/
def trustedReason (atom : Atom) : Option String :=
  if atom.kind == .axiom then some "axiom"
  else if atom.attributes.contains "externally_verified" then some "externally_verified"
  else if atom.codePath.endsWith "External.lean" && atom.kind != .theorem
    then some "external"
  else none

/-- Backward-compatible wrapper: `true` when the atom belongs to the trust base. -/
def isTrustedAtom (atom : Atom) : Bool :=
  (trustedReason atom).isSome

/-- Combine an Atom with its optional proof entry into a UnifiedAtom,
    preserving all atom fields. Axioms, declarations carrying
    `@[externally_verified]`, and non-theorem declarations from `*External.lean`
    files are overridden to `trusted` regardless of sorry detection. -/
def unifyAtom (atom : Atom) (proofEntry : Option ProofEntry)
    (classification : Option Classification := none)
    : UnifiedAtom :=
  let baseStatus := proofEntry.map fun p => mapVerifyStatus p.status
  let reason := trustedReason atom
  let status := if reason.isSome then some .trusted else baseStatus
  {
    name := atom.name
    displayName := atom.displayName
    dependencies := atom.dependencies
    typeDependencies := atom.typeDependencies
    termDependencies := atom.termDependencies
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
    verificationStatus := status
    trustedReason := reason
    classification := classification
  }

/-- A lean-generated atom is *contaminated* — worth surfacing so users can trace
    why a downstream atom isn't fully verified — when, after full enrichment, it is
    locally verified but not transitively verified (`.verified`), or is itself
    `.unverified`/`.failed`. `.transitivelyVerified` and `.trusted` generated atoms
    are clean and stay hidden. (Assumes enrichment ran; `--skip-enrich` is a
    debugging path and not accounted for here.) -/
def isContaminatedGenerated (atom : UnifiedAtom) : Bool :=
  atom.isLeanGenerated &&
    match atom.verificationStatus with
    | some .verified | some .unverified | some .failed => true
    | _ => false

/-- Clear `is-hidden` on contaminated lean-generated atoms so they remain visible
    for tracing; clean (transitively-verified/trusted) generated atoms stay hidden. -/
def unhideContaminatedGenerated (atoms : Array UnifiedAtom) : Array UnifiedAtom :=
  atoms.map fun atom =>
    if isContaminatedGenerated atom then { atom with isHidden := false } else atom

/-- Index per-declaration classifications by the emitted atom's `probe:`-prefixed
    code-name, so the merge can attach each atom's classification in O(1). The
    classifier keys by raw `Name`; atoms are keyed by `probeRef name` (the same
    expression `declInfoToAtom` uses), so the two sides line up. -/
def buildClassMap (classifications : Array (Name × Classification)) : Std.HashMap String Classification :=
  classifications.foldl (fun m (n, c) => m.insert (probeRef n) c) {}

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

/-- Build (honouring the cache) and discover/select the project's modules.
    Shared by `runExtractInProject` and the `check-axioms` command so the audit path
    and the extraction path can't drift on nix detection, build, or module selection.
    Returns `(selected modules, nix mode, captured build output)`, or an exit code. -/
def prepareProject (projectPath : System.FilePath) (libraries : Option (Array String))
    (moduleFilter : Option String) : IO (Except UInt32 (Array ProjectModule × Option NixMode × String)) := do
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
  return .ok (filteredModules, nixMode, buildOutput)

/-- Run the combined extract pipeline: build → atomize → markAtomFlags → specs → sorry detection → merge → enrich → envelope → write -/
def runExtractInProject (config : ExtractConfig) : IO UInt32 := do
  let (filteredModules, nixMode, buildOutput) ←
    match ← prepareProject config.projectPath config.libraries config.moduleFilter with
    | .error code => return code
    | .ok r => pure r

  -- === Step 1: Atomize ===
  IO.println "=== Step 1/3: Atomize ==="

  let userConfig ← loadUserConfig config.projectPath
  let crate := loadRelevantCrate userConfig

  let (atoms, projectClass, classifications) ← match ← runAnalysisViaLakeEnv config.projectPath filteredModules crate nixMode config.classOverride with
    | .error msg =>
      IO.eprintln s!"Analysis failed: {msg}"
      return 1
    | .ok result => pure result

  let classMap := buildClassMap classifications

  IO.println s!"Found {atoms.size} atoms"

  for dupName in duplicateAtomNames atoms do
    IO.eprintln s!"Warning: duplicate atom name {dupName} (private declarations in different modules recover to the same user-facing name)"

  -- Mark filtering flags from .verilib/probes/config.json (bug fix: was missing in old pipeline)
  let hiddenList := loadIsHiddenList userConfig
  let aeneasGeneratedSuffixes := loadAeneasGeneratedSuffixes userConfig
  let ignoredList := loadIsIgnoredList userConfig
  let atoms := markAtomFlags atoms hiddenList aeneasGeneratedSuffixes ignoredList
  let atoms := computeSpecs atoms

  -- === Step 2: Sorry detection ===
  IO.println "=== Step 2/3: Verify ==="
  let proofEntries : Option (Array ProofEntry) ← if config.skipVerify then
    IO.println "Verification skipped (--skip-verify)"
    pure none
  else do
    let verifyOutput ← match config.fromFile with
      | some file =>
        IO.println s!"Reading build output from {file}..."
        IO.FS.readFile file
      | none =>
        pure buildOutput

    let warnings := parseSorryWarnings verifyOutput
    IO.println s!"Found {warnings.size} sorry warnings"

    let entries := atoms.map fun atom =>
      let sorries := findSorriesForAtom warnings atom
      atomToProofEntry atom sorries

    let verified := entries.filter fun p => p.verified
    IO.println s!"Verified: {verified.size}/{entries.size} declarations"
    pure (some entries)

  -- === Step 3: Merge (parallel arrays, O(n)) ===
  IO.println "=== Step 3/3: Merge ==="

  let unifiedAtoms := atoms.mapIdx fun i atom =>
    let proof := proofEntries.bind fun ps => ps[i]?
    unifyAtom atom proof classMap[atom.name]?

  -- === Enrich: transitive verification via reverse-BFS ===
  let unifiedAtoms ← if config.skipEnrich then
    IO.println "Enrichment skipped (--skip-enrich)"
    pure unifiedAtoms
  else do
    IO.println "=== Enrich ==="
    let (enriched, transitive, local_, missingDeps) := enrichTransitiveVerification unifiedAtoms
    -- Only surface genuine orphans. References to constructors/fields of an
    -- extracted type (inductive/structure/class) are benign and collapsed into
    -- a single note so real gaps are not lost in the noise.
    let (orphans, typeMemberCount) := partitionMissingDeps unifiedAtoms missingDeps
    for dep in orphans do
      IO.eprintln s!"Warning: dependency \"{dep}\" not found in atom map (treated as trusted)"
    if typeMemberCount > 0 then
      IO.eprintln s!"Note: {typeMemberCount} reference(s) to constructors/fields of extracted types treated as trusted"
    let notVerified := enriched.size - transitive - local_
    IO.println s!"Transitively verified: {transitive} | Locally verified: {local_} | Not verified: {notVerified}"
    pure enriched

  -- Contaminated lean-generated atoms have their isHidden cleared so the user can
  -- trace why downstream atoms aren't fully verified (see `isContaminatedGenerated`).
  let unifiedAtoms := unhideContaminatedGenerated unifiedAtoms

  let baseSource ← collectSourceInfo config.projectPath
  let source := { baseSource with sourceClass := projectClass }
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
