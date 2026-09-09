/-
  Generates the committed example extract artifact under `examples/`.

  The fixture is written through probe-lean's own `Envelope` / `UnifiedAtomsOutput`
  serializers, so the committed file is genuine tool output rather than a
  hand-written approximation. That is what makes the `probe-extract-check` CI job
  meaningful: it validates the shape probe-lean actually emits against the shared
  probe schema, not the shape we believe it emits.

  Output is byte-deterministic — the timestamp and source metadata are fixed
  literals — so CI can regenerate the file and fail on any diff, the same way
  `check-version` guards `ProbeLean/Version.lean`.
-/
import ProbeLean.Types

namespace ProbeLean.GenFixture

open ProbeLean

/-- Canonical output path, following the `lean_<Package>_<version>.json`
    filename convention documented in `docs/SCHEMA.md`. -/
def defaultPath : System.FilePath :=
  "examples" / "lean_ExampleProject_0.1.0.json"

/-- Fixed so regeneration is byte-identical. -/
private def fixedTimestamp : String := "2026-01-01T00:00:00Z"

private def fixedSource : SourceInfo := {
  repo := "https://github.com/Beneficial-AI-Foundation/probe-lean"
  commit := "0000000000000000000000000000000000000000"
  package := "ExampleProject"
  packageVersion := "0.1.0"
}

private def coreModule : String := "ExampleProject.Core"
private def corePath : String := "ExampleProject/Core.lean"

/-- Base atom with the fields every assertion in `Tests/Main.lean` requires
    non-empty: `display-name`, `code-module`, `code-path`, and a source location. -/
private def mkAtom (shortName : String) (kind : DeclKind)
    (status : WebVerificationStatus) (startLine : Nat) : UnifiedAtom := {
  name := addProbePrefix s!"ExampleProject.{shortName}"
  displayName := shortName
  dependencies := #[]
  codeModule := coreModule
  codePath := corePath
  codeText := some { linesStart := startLine, linesEnd := startLine + 2 }
  kind := kind
  verificationStatus := some status
}

private def configRef : String := addProbePrefix "ExampleProject.Config"
private def helperRef : String := addProbePrefix "ExampleProject.helper"
private def boundsRef : String := addProbePrefix "ExampleProject.helper_bounds"
private def correctRef : String := addProbePrefix "ExampleProject.helper_correct"

/-- The fixture atoms. Deliberately covers every shape the integration tests
    assert on: a `def`, a `theorem`, a `projection`, a `structure`, and an
    `axiom`; at least one `verified` and one `trusted` atom; `trusted-reason`
    present only on trusted atoms; and `specs` / `primary-spec` / `attributes`
    populated on a target.

    `helper_bounds` and `helper_correct` are both `@[primary_spec]`-tagged and
    both target `helper`, so the fixture also exercises the ambiguous-primary-spec
    tie-break. Dependency, `specs`, and `attributes` arrays are pre-sorted (P14). -/
private def fixtureAtoms : Array UnifiedAtom := #[
  { mkAtom "Config" .structure .verified 5 with
    codomainHead := some "Type" },
  -- Distinct source range from `Config`: a real projection shares its parent
  -- structure's lines, but `probe-extract-check` warns on overlapping locations
  -- and a warning-free fixture lets that check run without `--allow-warnings`.
  { mkAtom "Config.limit" .projection .verified 9 with
    dependencies := #[configRef]
    typeDependencies := #[configRef]
    codomainHead := some "Nat" },
  { mkAtom "axiomatic_truth" .axiom .trusted 12 with
    trustedReason := some "axiom"
    codomainIsProp := true },
  { mkAtom "external_helper" .def .trusted 3 with
    codeModule := "ExampleProject.CoreExternal"
    codePath := "ExampleProject/CoreExternal.lean"
    trustedReason := some "external"
    codomainHead := some "Nat" },
  { mkAtom "helper" .def .verified 18 with
    dependencies := #[configRef]
    typeDependencies := #[configRef]
    specs := #[boundsRef, correctRef]
    primarySpec := some correctRef
    codomainHead := some "Nat" },
  { mkAtom "helper_bounds" .theorem .verified 24 with
    dependencies := #[helperRef]
    typeDependencies := #[helperRef]
    attributes := #["primary_spec"]
    isPrimarySpec := true
    codomainHead := some "LE.le"
    codomainIsProp := true },
  { mkAtom "helper_correct" .theorem .verified 30 with
    dependencies := #[helperRef]
    typeDependencies := #[helperRef]
    attributes := #["primary_spec"]
    isPrimarySpec := true
    codomainHead := some "Eq"
    codomainIsProp := true },
  { mkAtom "unproved" .theorem .unverified 36 with
    dependencies := #[helperRef]
    typeDependencies := #[helperRef]
    codomainHead := some "Eq"
    codomainIsProp := true }
]

def run (path : System.FilePath) : IO Unit := do
  let envelope : Envelope UnifiedAtomsOutput := {
    schema := Constants.schemaExtract
    tool := { command := "extract" }
    source := fixedSource
    timestamp := fixedTimestamp
    data := { atoms := fixtureAtoms }
  }
  if let some parent := path.parent then
    IO.FS.createDirAll parent
  -- Same write as `runExtractInProject`, so the fixture is byte-identical to
  -- what `extract` would produce for these atoms.
  IO.FS.writeFile path (Lean.toJson envelope).pretty
  IO.println s!"Wrote {fixtureAtoms.size} atoms to {path}"

end ProbeLean.GenFixture

def main (args : List String) : IO UInt32 := do
  let path : System.FilePath := match args with
    | p :: _ => p
    | [] => ProbeLean.GenFixture.defaultPath
  ProbeLean.GenFixture.run path
  return 0
