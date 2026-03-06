/-
  Pipeline command implementation.
  Runs atomize, specify, and verify in a single pass, producing an enriched atom dict
  with verification status suitable for the web frontend.
-/
import Lean
import ProbeLean.Types
import ProbeLean.Environment
import ProbeLean.Metadata
import ProbeLean.Atomize
import ProbeLean.Specify
import ProbeLean.Verify

namespace ProbeLean

open Lean

/-- Configuration for the pipeline command -/
structure PipelineConfig where
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

/-- Combine an Atom with its optional spec and proof entries into an EnrichedAtom -/
def enrichAtom (atom : Atom) (specEntry : Option SpecEntry) (proofEntry : Option ProofEntry)
    : EnrichedAtom :=
  {
    name := atom.name
    displayName := atom.displayName
    dependencies := atom.dependencies
    codeModule := atom.codeModule
    codePath := atom.codePath
    codeText := atom.codeText
    kind := atom.kind
    language := atom.language
    verificationStatus := proofEntry.map fun p => mapVerifyStatus p.status
    specified := specEntry.map fun s => s.specified
  }

/-- Run the full pipeline: atomize → specify → verify → merge -/
def runPipelineInProject (config : PipelineConfig) : IO UInt32 := do
  -- Validate project
  if !(← isLakeProject config.projectPath) then
    IO.eprintln s!"Error: Not a Lake project: {config.projectPath}"
    return 1

  -- Build (unless --skip-build, which assumes .olean files already exist)
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

  -- Load config to get crate name for relevance detection
  let userConfig ← loadUserConfig config.projectPath
  let crate := loadRelevantCrate userConfig

  let atoms ← match ← runAnalysisViaLakeEnv config.projectPath filteredModules crate with
    | .error msg =>
      IO.eprintln s!"Analysis failed: {msg}"
      return 1
    | .ok atoms => pure atoms

  IO.println s!"Found {atoms.size} atoms"

  -- === Step 2: Specify ===
  IO.println "=== Step 2/3: Specify ==="
  let specEntries := atoms.map fun atom => (atom.name, atomToSpecEntry atom)
  IO.println s!"Computed specification status for {specEntries.size} declarations"

  -- === Step 3: Verify ===
  IO.println "=== Step 3/3: Verify ==="
  let proofEntries : Array (String × ProofEntry) ← if config.skipVerify then
    IO.println "Verification skipped (--skip-verify)"
    pure #[]
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
      (atom.name, atomToProofEntry atom sorries)

    let verified := entries.filter fun (_, p) => p.verified
    IO.println s!"Verified: {verified.size}/{entries.size} declarations"
    pure entries

  -- === Merge ===
  IO.println "=== Merging results ==="

  let enrichedAtoms := atoms.map fun atom =>
    let spec := specEntries.findSome? fun (n, entry) =>
      if n == atom.name then some entry else none
    let proof := proofEntries.findSome? fun (n, entry) =>
      if n == atom.name then some entry else none
    enrichAtom atom spec proof

  let output : EnrichedAtomsOutput := { atoms := enrichedAtoms }
  let pm ← gatherMetadata config.projectPath
  let envelope := wrapInEnvelopeWith "probe-lean/enriched-atoms" "pipeline" (Lean.toJson output) pm
  let jsonStr := envelope.pretty

  let outputPath := config.outputPath.getD (getDefaultOutputPath config.projectPath pm "_graph")
  if let some parentDir := outputPath.parent then
    IO.FS.createDirAll parentDir
  IO.FS.writeFile outputPath jsonStr
  IO.println s!"Wrote {enrichedAtoms.size} enriched atoms to {outputPath}"
  return 0

end ProbeLean
