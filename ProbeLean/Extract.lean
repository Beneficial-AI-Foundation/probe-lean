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

namespace ProbeLean

open Lean

/-- Configuration for the extract command -/
structure ExtractConfig where
  projectPath : System.FilePath
  outputPath : Option System.FilePath
  moduleFilter : Option String
  skipVerify : Bool
  skipBuild : Bool
  fromFile : Option System.FilePath
  deriving Repr

/-- Map probe-lean VerifyStatus to the web frontend's verification status -/
def mapVerifyStatus : VerifyStatus → WebVerificationStatus
  | .success => .verified
  | .sorries => .unverified
  | .failure => .failed

/-- Combine an Atom with its optional proof entry into a UnifiedAtom,
    preserving all atom fields. -/
def unifyAtom (atom : Atom) (proofEntry : Option ProofEntry)
    : UnifiedAtom :=
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
    isExtractionArtifact := atom.isExtractionArtifact
    isIgnored := atom.isIgnored
    isRelevant := atom.isRelevant
    rustSource := atom.rustSource
    specs := atom.specs
    verificationStatus := proofEntry.map fun p => mapVerifyStatus p.status
  }

/-- Run the combined extract pipeline: build → atomize → markAtomFlags → sorry detection → merge → envelope → write -/
def runExtractInProject (config : ExtractConfig) : IO UInt32 := do
  if !(← isLakeProject config.projectPath) then
    IO.eprintln s!"Error: Not a Lake project: {config.projectPath}"
    return 1

  let buildOutput ← if config.skipBuild then
    IO.println "Skipping build (--skip-build), assuming .olean files exist..."
    pure ""
  else do
    IO.println s!"Building project at {config.projectPath}..."
    let (buildStdout, buildStderr, buildExit) ← runCmd "lake" #["build"] (some config.projectPath)
    if buildExit != 0 then
      IO.eprintln s!"Lake build failed:\n{buildStderr}"
      return 1
    let output := buildStdout ++ "\n" ++ buildStderr
    saveCache config.projectPath output
    pure output

  -- === Step 1: Atomize ===
  IO.println "=== Step 1/3: Atomize ==="

  IO.println "Getting project modules..."
  let modules ← match ← getProjectModules config.projectPath with
    | .error msg =>
      IO.eprintln msg
      return 1
    | .ok mods => pure mods

  if modules.isEmpty then
    IO.eprintln "Error: No modules found in project"
    return 1

  let filteredModules := match config.moduleFilter with
    | some filter =>
      let filterName := String.toName filter
      modules.filter fun m =>
        m == filterName || m.toString.startsWith (filter ++ ".")
    | none => modules

  IO.println s!"Analyzing {filteredModules.size} modules..."

  let userConfig ← loadUserConfig config.projectPath
  let crate := loadRelevantCrate userConfig

  let atoms ← match ← runAnalysisViaLakeEnv config.projectPath filteredModules crate with
    | .error msg =>
      IO.eprintln s!"Analysis failed: {msg}"
      return 1
    | .ok atoms => pure atoms

  IO.println s!"Found {atoms.size} atoms"

  -- Mark filtering flags from .verilib/probes/config.json (bug fix: was missing in old pipeline)
  let hiddenList := loadIsHiddenList userConfig
  let artifactSuffixes := loadExtractionArtifactSuffixes userConfig
  let ignoredList := loadIsIgnoredList userConfig
  let atoms := markAtomFlags atoms hiddenList artifactSuffixes ignoredList
  let atoms := computeSpecs atoms

  -- === Step 2: Sorry detection ===
  IO.println "=== Step 2/2: Verify ==="
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

  -- === Merge (parallel arrays, O(n)) ===
  IO.println "=== Merging results ==="

  let unifiedAtoms := atoms.mapIdx fun i atom =>
    let proof := proofEntries.bind fun ps => ps[i]?
    unifyAtom atom proof

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
