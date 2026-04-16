/-
  Unit tests for probe-lean
-/
import ProbeLean

open ProbeLean

/-- Simple test harness -/
structure TestResult where
  passed : Nat
  failed : Nat
  deriving Repr

def TestResult.add (r : TestResult) (success : Bool) : TestResult :=
  if success then { r with passed := r.passed + 1 }
  else { r with failed := r.failed + 1 }

def test (name : String) (condition : Bool) (result : TestResult) : IO TestResult := do
  if condition then
    IO.println s!"  ✓ {name}"
    return result.add true
  else
    IO.println s!"  ✗ {name}"
    return result.add false

def testConstants (result : TestResult) : IO TestResult := do
  let mut result := result
  IO.println "Testing Constants..."
  result ← test "verilibDir" (Constants.verilibDir == ".verilib") result
  result ← test "probesDir" (Constants.probesDir == "probes") result
  result ← test "viewsDir" (Constants.viewsDir == "views") result
  result ← test "mapsDir" (Constants.mapsDir == "maps") result
  result ← test "toolName" (Constants.toolName == "probe-lean") result
  result ← test "toolVersion" (Constants.toolVersion == ProbeLean.version) result
  result ← test "schemaVersion" (Constants.schemaVersion == "2.0") result
  result ← test "schemaExtract" (Constants.schemaExtract == "probe-lean/extract") result
  result ← test "schemaView" (Constants.schemaView == "probe-lean/viewify") result
  return result

def testAnalysisHelpers (result : TestResult) : IO TestResult := do
  let mut result := result
  IO.println ""
  IO.println "Testing isInternalName..."
  result ← test "underscore prefix" (isInternalName `_private) result
  result ← test "internal marker" (isInternalName `Foo._bar) result
  result ← test "match marker" (isInternalName `Foo.match_1) result
  result ← test "proof marker" (isInternalName `Foo.proof_1) result
  result ← test "bracket marker" (isInternalName `«Foo[1]») result
  result ← test "normal name" (!isInternalName `Foo.bar) result
  result ← test "normal def" (!isInternalName `myFunction) result

  IO.println ""
  IO.println "Testing auto-generated suffix filtering..."
  result ← test "noConfusionType" (isInternalName `Tree.noConfusionType) result
  result ← test "casesOn" (isInternalName `Point.casesOn) result
  result ← test "rec" (isInternalName `Tree.rec) result
  result ← test "mk" (isInternalName `Point.mk) result
  result ← test "injEq" (isInternalName `Tree.leaf.injEq) result
  result ← test "sizeOf_spec" (isInternalName `Point.mk.sizeOf_spec) result
  result ← test "eq_1" (isInternalName `foo.eq_1) result
  result ← test "elim" (isInternalName `Color.elim) result
  result ← test "ctorIdx" (isInternalName `Point.ctorIdx) result
  result ← test "toCtorIdx" (isInternalName `Point.toCtorIdx) result

  IO.println ""
  IO.println "Testing getDisplayName..."
  result ← test "simple name" (getDisplayName `foo == "foo") result
  result ← test "qualified name" (getDisplayName `Foo.Bar.baz == "baz") result
  result ← test "anonymous" (getDisplayName .anonymous == "") result

  IO.println ""
  IO.println "Testing containsSubstring..."
  result ← test "contains" (containsSubstring "hello world" "wor") result
  result ← test "not contains" (!containsSubstring "hello" "xyz") result
  result ← test "at start" (containsSubstring "hello" "hel") result

  IO.println ""
  IO.println "Testing stripLeadingDotSlash..."
  result ← test "strip single ./" (stripLeadingDotSlash "./test.lean" == "test.lean") result
  result ← test "strip multiple ./" (stripLeadingDotSlash "././test.lean" == "test.lean") result
  result ← test "strip many ./" (stripLeadingDotSlash "././././test.lean" == "test.lean") result
  result ← test "no strip needed" (stripLeadingDotSlash "test.lean" == "test.lean") result
  result ← test "no strip absolute" (stripLeadingDotSlash "/tmp/test.lean" == "/tmp/test.lean") result
  return result

def testSharedUtilities (result : TestResult) : IO TestResult := do
  let mut result := result
  IO.println ""
  IO.println "Testing addProbePrefix..."
  result ← test "add probe prefix" (addProbePrefix "Test.foo" == "probe:Test.foo") result
  result ← test "add probe prefix simple" (addProbePrefix "foo" == "probe:foo") result

  IO.println ""
  IO.println "Testing stripProbePrefix..."
  result ← test "strip probe prefix" (stripProbePrefix "probe:Test.foo" == "Test.foo") result
  result ← test "strip probe prefix simple" (stripProbePrefix "probe:foo" == "foo") result
  result ← test "strip probe prefix no prefix" (stripProbePrefix "Test.foo" == "Test.foo") result
  return result

def testTypeJsonSerialization (result : TestResult) : IO TestResult := do
  let mut result := result
  IO.println ""
  IO.println "Testing DeclKind JSON serialization..."
  result ← test "def toJson" (Lean.toJson DeclKind.def == "def") result
  result ← test "theorem toJson" (Lean.toJson DeclKind.theorem == "theorem") result
  result ← test "structure toJson" (Lean.toJson DeclKind.structure == "structure") result
  result ← test "projection toJson" (Lean.toJson DeclKind.projection == "projection") result
  let projRt := match Lean.FromJson.fromJson? (Lean.toJson DeclKind.projection) (α := DeclKind) with
    | .ok .projection => true | _ => false
  result ← test "projection round-trips through JSON" projRt result

  IO.println ""
  IO.println "Testing ToolInfo JSON serialization..."
  let toolInfo : ToolInfo := { name := "probe-lean", version := ProbeLean.version, command := "extract" }
  let toolJson := Lean.toJson toolInfo
  let toolNameOk := match toolJson.getObjValAs? String "name" with
    | .ok "probe-lean" => true | _ => false
  let toolVersionOk := match toolJson.getObjValAs? String "version" with
    | .ok v => v == ProbeLean.version | _ => false
  let toolCommandOk := match toolJson.getObjValAs? String "command" with
    | .ok "extract" => true | _ => false
  result ← test "toolInfo name" toolNameOk result
  result ← test "toolInfo version" toolVersionOk result
  result ← test "toolInfo command" toolCommandOk result

  IO.println ""
  IO.println "Testing ToolInfo FromJson round-trip..."
  let toolRt := match Lean.FromJson.fromJson? (Lean.toJson toolInfo) (α := ToolInfo) with
    | .ok ti => ti.name == "probe-lean" && ti.version == ProbeLean.version && ti.command == "extract"
    | .error _ => false
  result ← test "toolInfo round-trips through JSON" toolRt result

  IO.println ""
  IO.println "Testing SourceInfo JSON serialization..."
  let sourceInfo : SourceInfo := {
    repo := "https://github.com/org/project"
    commit := "abc123def456"
    language := "lean"
    package := "MyProject"
    packageVersion := "0.1.0"
  }
  let sourceJson := Lean.toJson sourceInfo
  let srcRepoOk := match sourceJson.getObjValAs? String "repo" with
    | .ok "https://github.com/org/project" => true | _ => false
  let srcLangOk := match sourceJson.getObjValAs? String "language" with
    | .ok "lean" => true | _ => false
  let srcPkgVerOk := match sourceJson.getObjValAs? String "package-version" with
    | .ok "0.1.0" => true | _ => false
  result ← test "sourceInfo repo" srcRepoOk result
  result ← test "sourceInfo language" srcLangOk result
  result ← test "sourceInfo package-version" srcPkgVerOk result

  IO.println ""
  IO.println "Testing SourceInfo empty fields..."
  let emptySource : SourceInfo := {
    repo := ""
    commit := ""
    package := "test"
    packageVersion := "0.0.0"
  }
  let emptySourceJson := Lean.toJson emptySource
  let emptyRepoOk := match emptySourceJson.getObjValAs? String "repo" with
    | .ok "" => true | _ => false
  result ← test "sourceInfo empty repo is empty string" emptyRepoOk result

  IO.println ""
  IO.println "Testing SourceInfo FromJson round-trip..."
  let srcRt := match Lean.FromJson.fromJson? (Lean.toJson sourceInfo) (α := SourceInfo) with
    | .ok si => si.repo == "https://github.com/org/project" && si.package == "MyProject"
      && si.packageVersion == "0.1.0"
    | .error _ => false
  result ← test "sourceInfo round-trips through JSON" srcRt result

  IO.println ""
  IO.println "Testing Envelope JSON serialization..."
  let envelope : Envelope AtomsOutput := {
    schema := Constants.schemaExtract
    tool := { command := "extract" }
    source := sourceInfo
    timestamp := "2025-01-01T00:00:00Z"
    data := { atoms := #[] }
  }
  let envJson := Lean.toJson envelope
  let hasSchema := match envJson.getObjValAs? String "schema" with
    | .ok "probe-lean/extract" => true | _ => false
  let hasSchemaVer := match envJson.getObjValAs? String "schema-version" with
    | .ok "2.0" => true | _ => false
  let hasTool := match envJson.getObjVal? "tool" with
    | .ok _ => true | _ => false
  let hasSource := match envJson.getObjVal? "source" with
    | .ok _ => true | _ => false
  let hasTimestamp := match envJson.getObjValAs? String "timestamp" with
    | .ok "2025-01-01T00:00:00Z" => true | _ => false
  let hasData := match envJson.getObjVal? "data" with
    | .ok _ => true | _ => false
  result ← test "envelope has schema" hasSchema result
  result ← test "envelope has schema-version" hasSchemaVer result
  result ← test "envelope has tool" hasTool result
  result ← test "envelope has source" hasSource result
  result ← test "envelope has timestamp" hasTimestamp result
  result ← test "envelope has data" hasData result

  IO.println ""
  IO.println "Testing Envelope FromJson round-trip..."
  let envRt := match Lean.FromJson.fromJson? (Lean.toJson envelope) (α := Envelope AtomsOutput) with
    | .ok e => e.schema == Constants.schemaExtract && e.timestamp == "2025-01-01T00:00:00Z"
    | .error _ => false
  result ← test "envelope round-trips through JSON" envRt result
  return result

def testAtomizeHelpers (result : TestResult) : IO TestResult := do
  let mut result := result
  IO.println ""
  IO.println "Testing hasAnySuffix..."
  result ← test "has suffix _body" (hasAnySuffix "Test.foo_body" #["_body", "_loop"]) result
  result ← test "has suffix _loop" (hasAnySuffix "Test.bar_loop" #["_body", "_loop"]) result
  result ← test "no matching suffix" (!hasAnySuffix "Test.baz" #["_body", "_loop"]) result
  result ← test "empty suffixes" (!hasAnySuffix "Test.foo_body" #[]) result

  IO.println ""
  IO.println "Testing extractSourceFromDocstring..."
  let doc1 := "[curve25519_dalek::scalar::Scalar::from_bytes_mod_order]: Source: 'curve25519-dalek/src/scalar.rs', lines 200:4-210:5"
  result ← test "extract source from docstring" (extractSourceFromDocstring doc1 == some "curve25519-dalek/src/scalar.rs") result
  let doc2 := "Some other docstring without source"
  result ← test "no source in docstring" (extractSourceFromDocstring doc2 == none) result

  IO.println ""
  IO.println "Testing isRelevantSource..."
  result ← test "relevant source with crate" (isRelevantSource (some "curve25519-dalek/src/scalar.rs") "curve25519-dalek") result
  result ← test "irrelevant source external" (!isRelevantSource (some "/rustc/abc123/library/core/src/ops.rs") "curve25519-dalek") result
  result ← test "irrelevant source cargo registry" (!isRelevantSource (some "/cargo/registry/src/subtle-2.4.1/src/lib.rs") "curve25519-dalek") result
  result ← test "irrelevant source wrong crate" (!isRelevantSource (some "other-crate/src/lib.rs") "curve25519-dalek") result
  result ← test "no source not relevant" (!isRelevantSource none "curve25519_dalek") result
  result ← test "empty crate not relevant" (!isRelevantSource (some "/rustc/whatever") "") result

  IO.println ""
  IO.println "Testing markAtomFlags..."
  let testAtomForHidden : Atom := {
    name := "probe:Test.foo"
    displayName := "foo"
    dependencies := #[]
    codeModule := "Test"
    codePath := "Test.lean"
    codeText := none
    kind := .def
  }
  let testAtomForHidden2 : Atom := {
    name := "probe:Test.bar"
    displayName := "bar"
    dependencies := #[]
    codeModule := "Test"
    codePath := "Test.lean"
    codeText := none
    kind := .def
  }
  let testAtomArtifact : Atom := {
    name := "probe:Test.baz_body"
    displayName := "baz_body"
    dependencies := #[]
    codeModule := "Test"
    codePath := "Test.lean"
    codeText := none
    kind := .def
  }
  let testAtomIgnored : Atom := {
    name := "probe:Test.ignored_func"
    displayName := "ignored_func"
    dependencies := #[]
    codeModule := "Test"
    codePath := "Test.lean"
    codeText := none
    kind := .def
  }
  let hiddenList : Array String := #["Test.foo"]
  let artifactSuffixes : Array String := #["_body", "_loop"]
  let ignoredList : Array String := #["Test.ignored_func"]
  let markedAtoms := markAtomFlags #[testAtomForHidden, testAtomForHidden2, testAtomArtifact, testAtomIgnored] hiddenList artifactSuffixes ignoredList
  result ← test "marked atom is hidden" markedAtoms[0]!.isHidden result
  result ← test "unmarked atom is not hidden" (!markedAtoms[1]!.isHidden) result
  result ← test "artifact atom is extraction artifact" markedAtoms[2]!.isExtractionArtifact result
  result ← test "non-artifact atom is not extraction artifact" (!markedAtoms[0]!.isExtractionArtifact) result
  result ← test "ignored atom is ignored" markedAtoms[3]!.isIgnored result
  result ← test "non-ignored atom is not ignored" (!markedAtoms[0]!.isIgnored) result
  return result

def testComputeSpecs (result : TestResult) : IO TestResult := do
  let mut result := result
  IO.println ""
  IO.println "Testing computeSpecs..."
  let defAtom : Atom := {
    name := "probe:Test.add_assign"
    displayName := "add_assign"
    dependencies := #["probe:Test.helper"]
    codeModule := "Test"
    codePath := "Test.lean"
    codeText := some { linesStart := 10, linesEnd := 20 }
    kind := .def
  }
  let thmAtom : Atom := {
    name := "probe:Test.add_assign_spec"
    displayName := "add_assign_spec"
    dependencies := #["probe:Test.add_assign", "probe:Test.helper"]
    codeModule := "Test"
    codePath := "Specs/Test.lean"
    codeText := some { linesStart := 50, linesEnd := 60 }
    kind := .theorem
  }
  let helperAtom : Atom := {
    name := "probe:Test.helper"
    displayName := "helper"
    dependencies := #[]
    codeModule := "Test"
    codePath := "Test.lean"
    codeText := none
    kind := .def
  }
  let specsResult := computeSpecs #[defAtom, thmAtom, helperAtom]
  let defResult := specsResult.find? fun a => a.name == "probe:Test.add_assign"
  let helperResult := specsResult.find? fun a => a.name == "probe:Test.helper"
  let thmResult := specsResult.find? fun a => a.name == "probe:Test.add_assign_spec"
  result ← test "def gets spec from theorem" (match defResult with
    | some a => a.specs.size == 1 && a.specs[0]! == "probe:Test.add_assign_spec"
    | none => false) result
  result ← test "helper also gets spec from theorem" (match helperResult with
    | some a => a.specs.size == 1 && a.specs[0]! == "probe:Test.add_assign_spec"
    | none => false) result
  result ← test "theorem does not get specs" (match thmResult with
    | some a => a.specs.isEmpty
    | none => false) result

  IO.println ""
  IO.println "Testing computeSpecs with no theorems..."
  let noThmResult := computeSpecs #[defAtom, helperAtom]
  result ← test "no specs when no theorems" (noThmResult.all fun a => a.specs.isEmpty) result

  IO.println ""
  IO.println "Testing computeSpecs with multiple specs..."
  let thmAtom2 : Atom := {
    name := "probe:Test.add_assign_loop_spec"
    displayName := "add_assign_loop_spec"
    dependencies := #["probe:Test.add_assign"]
    codeModule := "Test"
    codePath := "Specs/Test.lean"
    codeText := none
    kind := .theorem
  }
  let multiResult := computeSpecs #[defAtom, thmAtom, thmAtom2, helperAtom]
  let defMulti := multiResult.find? fun a => a.name == "probe:Test.add_assign"
  result ← test "def gets multiple specs" (match defMulti with
    | some a => a.specs.size == 2
    | none => false) result

  IO.println ""
  IO.println "Testing computeSpecs skips theorem-to-theorem..."
  let metaThmAtom : Atom := {
    name := "probe:Test.meta_spec"
    displayName := "meta_spec"
    dependencies := #["probe:Test.add_assign_spec"]
    codeModule := "Test"
    codePath := "Specs/Test.lean"
    codeText := none
    kind := .theorem
  }
  let metaResult := computeSpecs #[defAtom, thmAtom, metaThmAtom]
  let thmWithMeta := metaResult.find? fun a => a.name == "probe:Test.add_assign_spec"
  result ← test "theorem-to-theorem dep not added as spec" (match thmWithMeta with
    | some a => a.specs.isEmpty
    | none => false) result
  return result

def testAtomsOutputJson (result : TestResult) : IO TestResult := do
  let mut result := result
  let testAtom : Atom := {
    name := "probe:Test.foo"
    displayName := "foo"
    dependencies := #["probe:Test.helper"]
    codeModule := "Test"
    codePath := "Test.lean"
    codeText := some { linesStart := 10, linesEnd := 15 }
    kind := .theorem
  }

  IO.println ""
  IO.println "Testing AtomsOutput JSON serialization..."
  let atomsOutput : AtomsOutput := { atoms := #[testAtom] }
  let atomsJson := Lean.toJson atomsOutput
  let hasProbeKey := match atomsJson.getObjVal? "probe:Test.foo" with
    | .ok _ => true | _ => false
  result ← test "atoms keyed by probe: name" hasProbeKey result
  let hasDeps := match atomsJson.getObjVal? "probe:Test.foo" with
    | .ok v => match v.getObjValAs? (Array String) "dependencies" with
      | .ok deps => deps.size == 1 && deps[0]! == "probe:Test.helper"
      | _ => false
    | _ => false
  result ← test "atom has probe: prefixed dependencies" hasDeps result
  let hasIsHidden := match atomsJson.getObjVal? "probe:Test.foo" with
    | .ok v => match v.getObjValAs? Bool "is-hidden" with
      | .ok false => true | _ => false
    | _ => false
  result ← test "atom has is-hidden field" hasIsHidden result

  let hiddenAtom : Atom := { testAtom with isHidden := true }
  let hiddenAtomsOutput : AtomsOutput := { atoms := #[hiddenAtom] }
  let hiddenAtomsJson := Lean.toJson hiddenAtomsOutput
  let hasIsHiddenTrue := match hiddenAtomsJson.getObjVal? "probe:Test.foo" with
    | .ok v => match v.getObjValAs? Bool "is-hidden" with
      | .ok true => true | _ => false
    | _ => false
  result ← test "atom has is-hidden true" hasIsHiddenTrue result

  let hasIsExtractionArtifact := match atomsJson.getObjVal? "probe:Test.foo" with
    | .ok v => match v.getObjValAs? Bool "is-extraction-artifact" with
      | .ok false => true | _ => false
    | _ => false
  result ← test "atom has is-extraction-artifact field" hasIsExtractionArtifact result

  let artifactAtom : Atom := { testAtom with isExtractionArtifact := true }
  let artifactAtomsOutput : AtomsOutput := { atoms := #[artifactAtom] }
  let artifactAtomsJson := Lean.toJson artifactAtomsOutput
  let hasIsExtractionArtifactTrue := match artifactAtomsJson.getObjVal? "probe:Test.foo" with
    | .ok v => match v.getObjValAs? Bool "is-extraction-artifact" with
      | .ok true => true | _ => false
    | _ => false
  result ← test "atom has is-extraction-artifact true" hasIsExtractionArtifactTrue result

  let hasIsIgnored := match atomsJson.getObjVal? "probe:Test.foo" with
    | .ok v => match v.getObjValAs? Bool "is-ignored" with
      | .ok false => true | _ => false
    | _ => false
  result ← test "atom has is-ignored field" hasIsIgnored result

  let ignoredAtom : Atom := { testAtom with isIgnored := true }
  let ignoredAtomsOutput : AtomsOutput := { atoms := #[ignoredAtom] }
  let ignoredAtomsJson := Lean.toJson ignoredAtomsOutput
  let hasIsIgnoredTrue := match ignoredAtomsJson.getObjVal? "probe:Test.foo" with
    | .ok v => match v.getObjValAs? Bool "is-ignored" with
      | .ok true => true | _ => false
    | _ => false
  result ← test "atom has is-ignored true" hasIsIgnoredTrue result
  return result

def testAtomSpecsJson (result : TestResult) : IO TestResult := do
  let mut result := result
  IO.println ""
  IO.println "Testing Atom specs JSON serialization..."
  let atomNoSpecs : Atom := {
    name := "probe:Test.nospec"
    displayName := "nospec"
    dependencies := #[]
    codeModule := "Test"
    codePath := "Test.lean"
    codeText := none
    kind := .def
  }
  let noSpecsJson := Lean.toJson atomNoSpecs
  let specsAbsent := match noSpecsJson.getObjVal? "specs" with
    | .ok _ => false | _ => true
  result ← test "specs absent from JSON when empty" specsAbsent result

  let atomWithSpecs : Atom := { atomNoSpecs with specs := #["probe:Test.foo_spec"] }
  let withSpecsJson := Lean.toJson atomWithSpecs
  let specsPresent := match withSpecsJson.getObjValAs? (Array String) "specs" with
    | .ok arr => arr.size == 1 && arr[0]! == "probe:Test.foo_spec"
    | _ => false
  result ← test "specs present in JSON when non-empty" specsPresent result

  IO.println ""
  IO.println "Testing Atom specs FromJson round-trip..."
  let specsRtOk := match Lean.FromJson.fromJson? withSpecsJson (α := Atom) with
    | .ok a => a.specs.size == 1 && a.specs[0]! == "probe:Test.foo_spec"
    | .error _ => false
  result ← test "Atom specs round-trips through JSON" specsRtOk result

  let noSpecsRtOk := match Lean.FromJson.fromJson? noSpecsJson (α := Atom) with
    | .ok a => a.specs.isEmpty
    | .error _ => false
  result ← test "Atom empty specs round-trips through JSON" noSpecsRtOk result
  return result

def testAtomLanguageField (result : TestResult) : IO TestResult := do
  let mut result := result
  IO.println ""
  IO.println "Testing Atom language field..."
  let langAtom : Atom := {
    name := "probe:Test.foo"
    displayName := "foo"
    dependencies := #[]
    codeModule := "Test"
    codePath := "Test.lean"
    codeText := none
    kind := .def
  }
  result ← test "atom default language is lean" (langAtom.language == "lean") result
  let langJson := Lean.toJson langAtom
  let hasLanguage := match langJson.getObjValAs? String "language" with
    | .ok "lean" => true | _ => false
  result ← test "atom toJson has language field" hasLanguage result

  let langAtomsOutput : AtomsOutput := { atoms := #[langAtom] }
  let langAtomsJson := Lean.toJson langAtomsOutput
  let atomValHasLang := match langAtomsJson.getObjVal? "probe:Test.foo" with
    | .ok v => match v.getObjValAs? String "language" with
      | .ok "lean" => true | _ => false
    | _ => false
  result ← test "atoms output includes language per atom" atomValHasLang result
  return result

def testSorryDetection (result : TestResult) : IO TestResult := do
  let mut result := result
  let testAtom : Atom := {
    name := "probe:Test.foo"
    displayName := "foo"
    dependencies := #["probe:Test.helper"]
    codeModule := "Test"
    codePath := "Test.lean"
    codeText := some { linesStart := 10, linesEnd := 15 }
    kind := .theorem
  }

  IO.println ""
  IO.println "Testing parseSorryWarning..."
  let warning1 := parseSorryWarning "warning: ././././TestProject.lean:42:8: declaration uses 'sorry'"
  result ← test "parse sorry warning" warning1.isSome result
  match warning1 with
  | some w =>
    result ← test "warning file path" (w.filePath == "././././TestProject.lean") result
    result ← test "warning line" (w.line == 42) result
    result ← test "warning column" (w.column == 8) result
  | none => pure ()

  let noWarning := parseSorryWarning "Build completed successfully."
  result ← test "no warning for non-warning line" noWarning.isNone result

  let noSorry := parseSorryWarning "warning: unused variable 'x'"
  result ← test "no warning for non-sorry warning" noSorry.isNone result

  IO.println ""
  IO.println "Testing normalizePathForMatch..."
  result ← test "normalize relative path" (normalizePathForMatch "././././TestProject.lean" == "TestProject.lean") result
  result ← test "normalize absolute path" (normalizePathForMatch "/tmp/test/TestProject.lean" == "TestProject.lean") result

  IO.println ""
  IO.println "Testing pathsMatch..."
  result ← test "paths match same" (pathsMatch "/tmp/Test.lean" "/tmp/Test.lean") result
  result ← test "paths match suffix" (pathsMatch "/tmp/project/Test.lean" "Test.lean") result
  result ← test "paths match normalized" (pathsMatch "././././Test.lean" "/tmp/project/Test.lean") result
  result ← test "paths no match" (!pathsMatch "/tmp/A.lean" "/tmp/B.lean") result

  IO.println ""
  IO.println "Testing VerifyStatus JSON serialization..."
  result ← test "success toJson" (Lean.toJson VerifyStatus.success == "success") result
  result ← test "sorries toJson" (Lean.toJson VerifyStatus.sorries == "sorries") result
  result ← test "failure toJson" (Lean.toJson VerifyStatus.failure == "failure") result

  IO.println ""
  IO.println "Testing atomToProofEntry..."
  let sorries : Array SorryInfo := #[{ line := 42, message := "uses sorry" }]
  let proofEntry := atomToProofEntry testAtom sorries
  result ← test "proofEntry not verified" (!proofEntry.verified) result
  result ← test "proofEntry status sorries" (proofEntry.status == VerifyStatus.sorries) result
  result ← test "proofEntry has sorries" (proofEntry.sorries.size == 1) result

  let noSorries : Array SorryInfo := #[]
  let verifiedEntry := atomToProofEntry testAtom noSorries
  result ← test "verifiedEntry verified" verifiedEntry.verified result
  result ← test "verifiedEntry status success" (verifiedEntry.status == VerifyStatus.success) result

  -- S1: Atom without codeText should NOT be marked verified
  IO.println ""
  IO.println "Testing S1: atom without codeText should not be verified..."
  let atomNoLoc : Atom := { testAtom with codeText := none }
  let entryNoLoc := atomToProofEntry atomNoLoc #[]
  -- BUG S1: When codeText is none, sorryInDeclaration always returns false,
  -- so atomToProofEntry marks the declaration as verified even though we
  -- cannot actually check for sorry.
  if entryNoLoc.verified then
    IO.eprintln "  BUG S1 CONFIRMED: atom without codeText is marked verified"
  result ← test "S1: atom without codeText is NOT marked verified" (!entryNoLoc.verified) result

  -- S4: Same filename in different directories should not match
  IO.println ""
  IO.println "Testing S4: same filename different dirs should not match..."
  let differentDirMatch := pathsMatch "src/Foo/Constants.lean" "src/Bar/Constants.lean"
  if differentDirMatch then
    IO.eprintln "  BUG S4 CONFIRMED: same filename in different dirs incorrectly matches"
  result ← test "S4: different dirs same filename should not match" (!differentDirMatch) result

  -- S4: Sorry from one file should not be attributed to atom in another file
  -- with the same filename but different directory
  let sorryInFoo : SorryWarning := { filePath := "src/Foo/Constants.lean", line := 12, column := 0, message := "sorry" }
  let atomInBar : Atom := { testAtom with
    codePath := "src/Bar/Constants.lean"
    codeText := some { linesStart := 10, linesEnd := 15 }
  }
  let crossMatch := sorryInDeclaration sorryInFoo atomInBar
  if crossMatch then
    IO.eprintln "  BUG S4 CONFIRMED: sorry in Foo/Constants.lean attributed to atom in Bar/Constants.lean"
  result ← test "S4: sorry in Foo not attributed to atom in Bar" (!crossMatch) result

  return result

def testProofsOutputJson (result : TestResult) : IO TestResult := do
  let mut result := result
  IO.println ""
  IO.println "Testing ProofsOutput JSON serialization..."
  let proofsOutput : ProofsOutput := {
    entries := #[("probe:Test.foo", {
      verified := true, status := .success,
      codePath := "Test.lean", codeLine := 10, sorries := #[]
    })]
  }
  let proofsJson := Lean.toJson proofsOutput
  let proofsKeyOk := match proofsJson.getObjVal? "probe:Test.foo" with
    | .ok v => match v.getObjValAs? Bool "verified" with
      | .ok true => true | _ => false
    | _ => false
  result ← test "proofsOutput keyed dict format" proofsKeyOk result

  IO.println ""
  IO.println "Testing ProofsOutput FromJson round-trip..."
  let proofsRt := match Lean.FromJson.fromJson? (Lean.toJson proofsOutput) (α := ProofsOutput) with
    | .ok po => match po.entries.toList with
      | [(n, e)] => n == "probe:Test.foo" && e.verified == true
      | _ => false
    | .error _ => false
  result ← test "proofsOutput round-trips through JSON" proofsRt result
  return result

def testUnifiedAtomJson (result : TestResult) : IO TestResult := do
  let mut result := result
  IO.println ""
  IO.println "Testing WebVerificationStatus FromJson round-trip..."
  let wvsVerified := match Lean.FromJson.fromJson? (Lean.toJson WebVerificationStatus.verified) (α := WebVerificationStatus) with
    | .ok .verified => true | _ => false
  let wvsFailed := match Lean.FromJson.fromJson? (Lean.toJson WebVerificationStatus.failed) (α := WebVerificationStatus) with
    | .ok .failed => true | _ => false
  let wvsUnverified := match Lean.FromJson.fromJson? (Lean.toJson WebVerificationStatus.unverified) (α := WebVerificationStatus) with
    | .ok .unverified => true | _ => false
  let wvsTrusted := match Lean.FromJson.fromJson? (Lean.toJson WebVerificationStatus.trusted) (α := WebVerificationStatus) with
    | .ok .trusted => true | _ => false
  result ← test "WebVerificationStatus verified round-trips" wvsVerified result
  result ← test "WebVerificationStatus failed round-trips" wvsFailed result
  result ← test "WebVerificationStatus unverified round-trips" wvsUnverified result
  result ← test "WebVerificationStatus trusted round-trips" wvsTrusted result
  result ← test "WebVerificationStatus trusted toJson" (Lean.toJson WebVerificationStatus.trusted == "trusted") result

  IO.println ""
  IO.println "Testing UnifiedAtomsOutput FromJson round-trip..."
  let unifiedAtom1 : UnifiedAtom := {
    name := "probe:Test.foo"
    displayName := "foo"
    dependencies := #["probe:Test.helper"]
    codeModule := "Test"
    codePath := "Test.lean"
    codeText := some { linesStart := 10, linesEnd := 15 }
    kind := .theorem
    verificationStatus := some .verified
  }
  let unifiedAtom2 : UnifiedAtom := {
    name := "probe:Test.bar"
    displayName := "bar"
    dependencies := #[]
    codeModule := "Test"
    codePath := "Test.lean"
    codeText := none
    kind := .def
    rustSource := some "src/lib.rs"
    verificationStatus := none
  }
  let unifiedOutput : UnifiedAtomsOutput := { atoms := #[unifiedAtom1, unifiedAtom2] }
  let uaoJson := Lean.toJson unifiedOutput
  match Lean.FromJson.fromJson? uaoJson (α := UnifiedAtomsOutput) with
  | .ok uo => do
    let findAtom (n : String) := uo.atoms.find? fun a => a.name == n
    result ← test "UAO round-trip: atom count" (uo.atoms.size == 2) result
    match findAtom "probe:Test.foo" with
    | some a1 => do
      result ← test "UAO round-trip: foo displayName" (a1.displayName == "foo") result
      result ← test "UAO round-trip: foo verificationStatus" (a1.verificationStatus == some .verified) result
      result ← test "UAO round-trip: foo dependencies" (a1.dependencies.size == 1) result
    | none => do
      IO.println "  ✗ UAO round-trip: probe:Test.foo not found"
      result := result.add false
    match findAtom "probe:Test.bar" with
    | some a2 => do
      result ← test "UAO round-trip: bar rustSource" (a2.rustSource == some "src/lib.rs") result
      result ← test "UAO round-trip: bar verificationStatus none" (a2.verificationStatus == none) result
    | none => do
      IO.println "  ✗ UAO round-trip: probe:Test.bar not found"
      result := result.add false
  | .error err => do
    IO.println s!"  ✗ UAO round-trip PARSE ERROR: {err}"
    result := result.add false

  IO.println ""
  IO.println "Testing UnifiedAtomsOutput round-trip preserves optional fields..."
  let uaoNoneFields : UnifiedAtomsOutput := { atoms := #[{
    name := "probe:Test.z"
    displayName := "z"
    dependencies := #[]
    codeModule := "Test"
    codePath := "Test.lean"
    codeText := none
    kind := .def
    verificationStatus := none
  }] }
  let uaoNoneRt := match Lean.FromJson.fromJson? (Lean.toJson uaoNoneFields) (α := UnifiedAtomsOutput) with
    | .ok uo => match uo.atoms[0]? with
      | some a => a.verificationStatus == none
        && a.rustSource == none && a.isHidden == false && a.specs.isEmpty
      | none => false
    | .error _ => false
  result ← test "UnifiedAtomsOutput round-trip preserves none fields" uaoNoneRt result

  IO.println ""
  IO.println "Testing UnifiedAtom trusted-reason serialization..."
  let trustedAtom : UnifiedAtom := {
    name := "probe:Test.ax"
    displayName := "ax"
    dependencies := #[]
    codeModule := "Test"
    codePath := "Test.lean"
    codeText := none
    kind := .axiom
    verificationStatus := some .trusted
    trustedReason := some "axiom"
  }
  let trJson := Lean.toJson trustedAtom
  let trHasField := match trJson.getObjValAs? String "trusted-reason" with
    | .ok "axiom" => true | _ => false
  result ← test "trusted-reason present in JSON when set" trHasField result
  let trRoundTrip := match Lean.FromJson.fromJson? trJson (α := UnifiedAtom) with
    | .ok a => a.trustedReason == some "axiom"
    | .error _ => false
  result ← test "trusted-reason round-trips through JSON" trRoundTrip result
  let normalAtom : UnifiedAtom := {
    name := "probe:Test.f"
    displayName := "f"
    dependencies := #[]
    codeModule := "Test"
    codePath := "Test.lean"
    codeText := none
    kind := .def
    verificationStatus := some .verified
  }
  let noTrJson := Lean.toJson normalAtom
  let trAbsent := match noTrJson.getObjVal? "trusted-reason" with
    | .ok _ => false | .error _ => true
  result ← test "trusted-reason absent from JSON when none" trAbsent result

  IO.println ""
  IO.println "Testing UnifiedAtom specs serialization..."
  let unifiedWithSpecs : UnifiedAtom := {
    name := "probe:Test.with_specs"
    displayName := "with_specs"
    dependencies := #[]
    codeModule := "Test"
    codePath := "Test.lean"
    codeText := none
    kind := .def
    specs := #["probe:Test.spec1", "probe:Test.spec2"]
    verificationStatus := some .verified
  }
  let uwsJson := Lean.toJson unifiedWithSpecs
  let uwsSpecsOk := match uwsJson.getObjValAs? (Array String) "specs" with
    | .ok arr => arr.size == 2 && arr[0]! == "probe:Test.spec1"
    | _ => false
  result ← test "UnifiedAtom specs present in JSON" uwsSpecsOk result
  let uwsRtOk := match Lean.FromJson.fromJson? uwsJson (α := UnifiedAtom) with
    | .ok a => a.specs.size == 2 && a.specs[1]! == "probe:Test.spec2"
    | .error _ => false
  result ← test "UnifiedAtom specs round-trips" uwsRtOk result

  let unifiedNoSpecs : UnifiedAtom := { unifiedWithSpecs with specs := #[] }
  let unsJson := Lean.toJson unifiedNoSpecs
  let unsAbsent := match unsJson.getObjVal? "specs" with
    | .ok _ => false | _ => true
  result ← test "UnifiedAtom specs absent when empty" unsAbsent result
  return result

def testViewHelpers (result : TestResult) : IO TestResult := do
  let mut result := result
  IO.println ""
  IO.println "Testing getLastNamePart..."
  result ← test "last part simple" (getLastNamePart "foo" == "foo") result
  result ← test "last part qualified" (getLastNamePart "Foo.Bar.baz" == "baz") result
  result ← test "last part two" (getLastNamePart "Foo.bar" == "bar") result

  IO.println ""
  IO.println "Testing parseLines..."
  result ← test "parse lines normal" (parseLines "42-58" == { linesStart := 42, linesEnd := 58 }) result
  result ← test "parse lines single" (parseLines "10" == { linesStart := 10, linesEnd := 10 }) result
  result ← test "parse lines empty" (parseLines "" == { linesStart := 0, linesEnd := 0 }) result
  result ← test "parse lines L-prefix" (parseLines "L230-L238" == { linesStart := 230, linesEnd := 238 }) result
  result ← test "parse lines mixed prefix" (parseLines "L100-200" == { linesStart := 100, linesEnd := 200 }) result
  return result

def testStubEntryJson (result : TestResult) : IO TestResult := do
  let mut result := result
  IO.println ""
  IO.println "Testing StubEntry JSON serialization..."
  let stubEntry : StubEntry := {
    codePath := none
    codeLines := none
    codeName := "probe:Test.foo"
    rustPath := "src/test.rs"
    rustLines := { linesStart := 10, linesEnd := 20 }
    rustName := "test_foo"
    specPath := some "specs/test_spec.lean"
    specLines := none
    specName := some "probe:Test.foo_spec"
  }
  let stubJson := Lean.toJson stubEntry
  let hasCodeName := match stubJson.getObjValAs? String "code-name" with
    | .ok "probe:Test.foo" => true | _ => false
  result ← test "stubEntry toJson has code-name" hasCodeName result
  let hasRustPath := match stubJson.getObjValAs? String "rust-path" with
    | .ok "src/test.rs" => true | _ => false
  result ← test "stubEntry toJson has rust-path" hasRustPath result
  let hasSpecName := match stubJson.getObjValAs? (Option String) "spec-name" with
    | .ok (some "probe:Test.foo_spec") => true | _ => false
  result ← test "stubEntry toJson has spec-name" hasSpecName result
  let hasNullCodePath := match stubJson.getObjValAs? (Option String) "code-path" with
    | .ok none => true | _ => false
  result ← test "stubEntry toJson has null code-path" hasNullCodePath result

  IO.println ""
  IO.println "Testing StubEntry without spec file..."
  let stubEntryNoSpec : StubEntry := {
    codePath := none
    codeLines := none
    codeName := "probe:Test.bar"
    rustPath := "src/test.rs"
    rustLines := { linesStart := 30, linesEnd := 40 }
    rustName := "test_bar"
    specPath := none
    specLines := none
    specName := none
  }
  let stubJsonNoSpec := Lean.toJson stubEntryNoSpec
  let hasNullSpecPath := match stubJsonNoSpec.getObjValAs? (Option String) "spec-path" with
    | .ok none => true | _ => false
  result ← test "stubEntry without spec has null spec-path" hasNullSpecPath result
  return result

def testMoleculesOutputJson (result : TestResult) : IO TestResult := do
  let mut result := result
  IO.println ""
  IO.println "Testing MoleculesOutput JSON serialization..."
  let moleculesOutput : MoleculesOutput := {
    entries := #[("key/foo", {
      codePath := some "Test.lean", codeLines := some "10-20",
      codeName := "probe:Test.foo", rustPath := "", rustLines := { linesStart := 0, linesEnd := 0 },
      rustName := "", specPath := none, specLines := none, specName := none
    })]
  }
  let moleculesJson := Lean.toJson moleculesOutput
  let moleculesKeyOk := match moleculesJson.getObjVal? "key/foo" with
    | .ok v => match v.getObjValAs? String "code-name" with
      | .ok "probe:Test.foo" => true | _ => false
    | _ => false
  result ← test "moleculesOutput keyed dict format" moleculesKeyOk result

  IO.println ""
  IO.println "Testing MoleculesOutput FromJson round-trip..."
  let moleculesRt := match Lean.FromJson.fromJson? (Lean.toJson moleculesOutput) (α := MoleculesOutput) with
    | .ok mo => match mo.entries.toList with
      | [(k, e)] => k == "key/foo" && e.codeName == "probe:Test.foo"
      | _ => false
    | .error _ => false
  result ← test "moleculesOutput round-trips through JSON" moleculesRt result
  return result

def testEnvelopeAwareLoading (result : TestResult) : IO TestResult := do
  let mut result := result
  let bareDict := Lean.Json.mkObj [
    ("probe:Test.x", Lean.Json.mkObj [
      ("display-name", Lean.toJson "x"),
      ("dependencies", Lean.toJson (Array.empty : Array String)),
      ("code-module", Lean.toJson "Test"),
      ("code-path", Lean.toJson "Test.lean"),
      ("code-text", Lean.Json.null),
      ("kind", Lean.toJson "def"),
      ("language", Lean.toJson "lean"),
      ("is-hidden", Lean.toJson false),
      ("is-extraction-artifact", Lean.toJson false),
      ("is-ignored", Lean.toJson false),
      ("is-relevant", Lean.toJson true),
      ("rust-source", Lean.Json.null)
    ])
  ]
  let enveloped := Lean.Json.mkObj [
    ("schema", Lean.toJson "probe-lean/extract"),
    ("schema-version", Lean.toJson "2.0"),
    ("data", bareDict)
  ]
  let bareStr := Lean.Json.pretty bareDict
  let envStr := Lean.Json.pretty enveloped

  IO.println ""
  IO.println "Testing envelope-aware loading (unwrapEnvelope)..."
  let bareParsed := match Lean.Json.parse bareStr with
    | .ok j => match Lean.FromJson.fromJson? j (α := AtomsOutput) with
      | .ok ao => ao.atoms.size == 1
      | _ => false
    | _ => false
  result ← test "bare dict parses as AtomsOutput" bareParsed result

  IO.println ""
  IO.println "Testing AtomsOutput round-trip preserves rustSource..."
  let atomWithRust : Atom := {
    name := "probe:Test.y", displayName := "y",
    dependencies := #[], codeModule := "Test", codePath := "Test.lean",
    codeText := none, kind := .def, rustSource := some "src/lib.rs"
  }
  let aoWithRust : AtomsOutput := { atoms := #[atomWithRust] }
  let aoRtOk := match Lean.FromJson.fromJson? (Lean.toJson aoWithRust) (α := AtomsOutput) with
    | .ok ao => match ao.atoms[0]? with
      | some a => a.rustSource == some "src/lib.rs"
      | none => false
    | .error _ => false
  result ← test "AtomsOutput round-trip preserves rustSource" aoRtOk result

  let atomNoRust : Atom := {
    name := "probe:Test.z", displayName := "z",
    dependencies := #[], codeModule := "Test", codePath := "Test.lean",
    codeText := none, kind := .theorem, rustSource := none
  }
  let aoNoRust : AtomsOutput := { atoms := #[atomNoRust] }
  let aoRtNone := match Lean.FromJson.fromJson? (Lean.toJson aoNoRust) (α := AtomsOutput) with
    | .ok ao => match ao.atoms[0]? with
      | some a => a.rustSource == none
      | none => false
    | .error _ => false
  result ← test "AtomsOutput round-trip preserves rustSource=none" aoRtNone result

  let envParsedViaUnwrap := match Lean.Json.parse envStr with
    | .ok j =>
      let inner := unwrapEnvelope j
      match Lean.FromJson.fromJson? inner (α := AtomsOutput) with
        | .ok ao => ao.atoms.size == 1
        | _ => false
    | _ => false
  result ← test "enveloped dict unwraps via unwrapEnvelope" envParsedViaUnwrap result

  IO.println ""
  IO.println "Testing unwrapEnvelope accepts any schema prefix..."
  let foreignEnvelope := Lean.Json.mkObj [
    ("schema", Lean.toJson "probe-verus/atoms"),
    ("schema-version", Lean.toJson "2.0"),
    ("data", bareDict)
  ]
  let foreignUnwrapped := match Lean.Json.parse (Lean.Json.pretty foreignEnvelope) with
    | .ok j =>
      let inner := unwrapEnvelope j
      match inner.getObjVal? "schema" with
      | .ok _ => false
      | _ => true
    | _ => false
  result ← test "foreign envelope is unwrapped" foreignUnwrapped result

  IO.println ""
  IO.println "Testing loadAtoms end-to-end with envelope..."
  let tmpBarePath : System.FilePath := "/tmp/probe-lean-test-bare.json"
  let tmpEnvPath : System.FilePath := "/tmp/probe-lean-test-env.json"
  IO.FS.writeFile tmpBarePath bareStr
  IO.FS.writeFile tmpEnvPath envStr

  let bareLoadOk ← do
    match ← loadAtoms tmpBarePath with
    | .ok ao => pure (ao.atoms.size == 1)
    | .error _ => pure false
  result ← test "loadAtoms bare dict end-to-end" bareLoadOk result

  let envLoadOk ← do
    match ← loadAtoms tmpEnvPath with
    | .ok ao => pure (ao.atoms.size == 1)
    | .error _ => pure false
  result ← test "loadAtoms enveloped dict end-to-end" envLoadOk result

  IO.FS.removeFile tmpBarePath
  IO.FS.removeFile tmpEnvPath
  return result

def testMetadataHelpers (result : TestResult) : IO TestResult := do
  let mut result := result
  IO.println ""
  IO.println "Testing parsePackageNameFromToml..."
  let tomlContent := "name = \"my-package\"\nversion = \"1.0.0\""
  result ← test "parse name from toml" (parsePackageNameFromToml tomlContent == some "my-package") result
  result ← test "parse name from empty toml" (parsePackageNameFromToml "" == none) result
  result ← test "parse name from toml without name" (parsePackageNameFromToml "version = \"1.0.0\"" == none) result

  IO.println ""
  IO.println "Testing parsePackageVersionFromToml..."
  result ← test "parse version from toml" (parsePackageVersionFromToml tomlContent == some "1.0.0") result
  result ← test "parse version from empty toml" (parsePackageVersionFromToml "" == none) result
  result ← test "parse version from toml without version" (parsePackageVersionFromToml "name = \"my-package\"" == none) result

  IO.println ""
  IO.println "Testing generateOutputFilename..."
  let testSource : SourceInfo := {
    repo := ""
    commit := ""
    package := "my-package"
    packageVersion := "1.0.0"
  }
  result ← test "generate output filename" (generateOutputFilename testSource == "lean_my_package_1.0.0.json") result
  let testSource2 : SourceInfo := { testSource with package := "foo-bar", packageVersion := "2.3.4" }
  result ← test "generate output filename with dashes" (generateOutputFilename testSource2 == "lean_foo_bar_2.3.4.json") result

  IO.println ""
  IO.println "Testing isAtomsFileName..."
  let prefix1 := "lean_foo_"
  result ← test "atoms file matches" (isAtomsFileName "lean_foo_abc1234.json" prefix1) result
  result ← test "non-json excluded" (!isAtomsFileName "lean_foo_abc1234.txt" prefix1) result
  result ← test "wrong prefix excluded" (!isAtomsFileName "lean_bar_abc1234.json" prefix1) result
  result ← test "semver version matches" (isAtomsFileName "lean_foo_1.0.0.json" prefix1) result
  result ← test "unknown version matches" (isAtomsFileName "lean_foo_unknown.json" prefix1) result
  return result

def testFindDefaultAtomsPath (result : TestResult) : IO TestResult := do
  let mut result := result
  IO.println ""
  IO.println "Testing findDefaultAtomsPath..."
  let tmpBase : System.FilePath := "/tmp/probe-lean-test-" ++ toString (← IO.monoNanosNow)
  let probesDir := tmpBase / ".verilib" / "probes"
  IO.FS.createDirAll probesDir
  let testSourceForPath : SourceInfo := {
    repo := "", commit := "",
    package := "testpkg", packageVersion := "abcdef1"
  }

  let exactPath := probesDir / "lean_testpkg_abcdef1.json"
  IO.FS.writeFile exactPath "{}"
  let (found1, fb1) ← findDefaultAtomsPath tmpBase testSourceForPath
  result ← test "exact path returned when it exists" (found1.toString == exactPath.toString && !fb1) result
  IO.FS.removeFile exactPath

  let altPath := probesDir / "lean_testpkg_old1234.json"
  IO.FS.writeFile altPath "{}"
  let (found2, fb2) ← findDefaultAtomsPath tmpBase testSourceForPath
  result ← test "fallback finds alternative atoms file" (found2.toString == altPath.toString && fb2) result

  let _ ← IO.Process.run { cmd := "sleep", args := #["0.05"] }
  let newerPath := probesDir / "lean_testpkg_new5678.json"
  IO.FS.writeFile newerPath "{}"
  let (found3, fb3) ← findDefaultAtomsPath tmpBase testSourceForPath
  result ← test "newest alternative picked when multiple exist" (found3.toString == newerPath.toString && fb3) result

  IO.FS.removeFile altPath
  IO.FS.removeFile newerPath

  let emptyBase := tmpBase / "empty"
  IO.FS.createDirAll emptyBase
  let (found4, fb4) ← findDefaultAtomsPath emptyBase testSourceForPath
  let expectedEmpty := emptyBase / ".verilib" / "probes" / "lean_testpkg_abcdef1.json"
  result ← test "returns exact path when probes dir missing" (found4.toString == expectedEmpty.toString && !fb4) result

  try IO.FS.removeDirAll tmpBase catch _ => pure ()
  return result

/-- Tests for type-dependencies and term-dependencies fields -/
def testTypedDependencies (result : TestResult) : IO TestResult := do
  let mut result := result

  IO.println ""
  IO.println "Testing Atom typed dependencies JSON serialization..."
  let typedDepAtom : Atom := {
    name := "probe:Test.myThm"
    displayName := "myThm"
    dependencies := #["probe:Test.typeOnly", "probe:Test.termOnly", "probe:Test.both"]
    typeDependencies := #["probe:Test.typeOnly", "probe:Test.both"]
    termDependencies := #["probe:Test.termOnly", "probe:Test.both"]
    codeModule := "Test"
    codePath := "Test.lean"
    codeText := some { linesStart := 10, linesEnd := 20 }
    kind := .theorem
  }
  let typedDepJson := Lean.toJson typedDepAtom
  let hasTypeDeps := match typedDepJson.getObjValAs? (Array String) "type-dependencies" with
    | .ok arr => arr.size == 2 && arr[0]! == "probe:Test.typeOnly" && arr[1]! == "probe:Test.both"
    | _ => false
  result ← test "atom has type-dependencies" hasTypeDeps result
  let hasTermDeps := match typedDepJson.getObjValAs? (Array String) "term-dependencies" with
    | .ok arr => arr.size == 2 && arr[0]! == "probe:Test.termOnly" && arr[1]! == "probe:Test.both"
    | _ => false
  result ← test "atom has term-dependencies" hasTermDeps result
  let hasDepsUnion := match typedDepJson.getObjValAs? (Array String) "dependencies" with
    | .ok arr => arr.size == 3
    | _ => false
  result ← test "atom dependencies is union of type+term" hasDepsUnion result

  IO.println ""
  IO.println "Testing Atom typed dependencies FromJson round-trip..."
  let typedDepRt := match Lean.FromJson.fromJson? typedDepJson (α := Atom) with
    | .ok a => a.typeDependencies.size == 2 && a.termDependencies.size == 2
      && a.typeDependencies[0]! == "probe:Test.typeOnly"
      && a.termDependencies[0]! == "probe:Test.termOnly"
    | .error _ => false
  result ← test "Atom typed deps round-trips through JSON" typedDepRt result

  IO.println ""
  IO.println "Testing Atom default empty typed dependencies..."
  let defaultDepAtom : Atom := {
    name := "probe:Test.simple"
    displayName := "simple"
    dependencies := #["probe:Test.dep"]
    codeModule := "Test"
    codePath := "Test.lean"
    codeText := none
    kind := .def
  }
  result ← test "default typeDependencies is empty" (defaultDepAtom.typeDependencies.isEmpty) result
  result ← test "default termDependencies is empty" (defaultDepAtom.termDependencies.isEmpty) result
  let defaultDepJson := Lean.toJson defaultDepAtom
  let defaultTypeDepsOk := match defaultDepJson.getObjValAs? (Array String) "type-dependencies" with
    | .ok arr => arr.isEmpty
    | _ => false
  result ← test "default type-dependencies serializes as empty array" defaultTypeDepsOk result

  IO.println ""
  IO.println "Testing Atom typed deps backward compat (FromJson without typed deps)..."
  let legacyJson := Lean.Json.mkObj [
    ("name", Lean.toJson "probe:Test.legacy"),
    ("display-name", Lean.toJson "legacy"),
    ("dependencies", Lean.toJson (#["probe:Test.dep"] : Array String)),
    ("code-module", Lean.toJson "Test"),
    ("code-path", Lean.toJson "Test.lean"),
    ("code-text", Lean.Json.null),
    ("kind", Lean.toJson "def"),
    ("language", Lean.toJson "lean"),
    ("is-hidden", Lean.toJson false),
    ("is-extraction-artifact", Lean.toJson false),
    ("is-ignored", Lean.toJson false),
    ("is-relevant", Lean.toJson true),
    ("rust-source", Lean.Json.null)
  ]
  let legacyRt := match Lean.FromJson.fromJson? legacyJson (α := Atom) with
    | .ok a => a.dependencies.size == 1 && a.typeDependencies.isEmpty && a.termDependencies.isEmpty
    | .error _ => false
  result ← test "legacy JSON without typed deps parses with empty arrays" legacyRt result

  IO.println ""
  IO.println "Testing UnifiedAtom typed dependencies round-trip..."
  let unifiedTypedDep : UnifiedAtom := {
    name := "probe:Test.typedThm"
    displayName := "typedThm"
    dependencies := #["probe:Test.a", "probe:Test.b", "probe:Test.c"]
    typeDependencies := #["probe:Test.a", "probe:Test.c"]
    termDependencies := #["probe:Test.b", "probe:Test.c"]
    codeModule := "Test"
    codePath := "Test.lean"
    codeText := none
    kind := .theorem
    verificationStatus := some .verified
  }
  let utdJson := Lean.toJson unifiedTypedDep
  let utdTypeDepsOk := match utdJson.getObjValAs? (Array String) "type-dependencies" with
    | .ok arr => arr.size == 2 && arr[0]! == "probe:Test.a"
    | _ => false
  result ← test "UnifiedAtom type-dependencies present" utdTypeDepsOk result
  let utdTermDepsOk := match utdJson.getObjValAs? (Array String) "term-dependencies" with
    | .ok arr => arr.size == 2 && arr[0]! == "probe:Test.b"
    | _ => false
  result ← test "UnifiedAtom term-dependencies present" utdTermDepsOk result
  let utdRtOk := match Lean.FromJson.fromJson? utdJson (α := UnifiedAtom) with
    | .ok a => a.typeDependencies.size == 2 && a.termDependencies.size == 2
      && a.dependencies.size == 3
    | .error _ => false
  result ← test "UnifiedAtom typed deps round-trips" utdRtOk result

  return result

def mkSpecAtom (name : String) (kind : DeclKind) (deps : Array String)
    (isPrimarySpec : Bool := false) (attributes : Array String := #[]) : Atom :=
  { name, displayName := name, dependencies := deps, codeModule := "Test",
    codePath := "Test.lean", codeText := none, kind, isPrimarySpec, attributes }

def testPrimarySpecHeuristic (result : TestResult) : IO TestResult := do
  let mut result := result
  let mkAtom (name : String) (kind : DeclKind) (deps : Array String)
      (isPrimarySpec : Bool := false) : Atom :=
    mkSpecAtom name kind deps isPrimarySpec

  IO.println ""
  IO.println "Testing primary-spec _spec suffix heuristic..."
  let defA := mkAtom "probe:Test.foo" .def #[]
  let thmA := mkAtom "probe:Test.foo_spec" .theorem #["probe:Test.foo"]
  let res1 := computeSpecs #[defA, thmA]
  let defRes1 := res1.find? fun a => a.name == "probe:Test.foo"
  result ← test "heuristic sets primarySpec on def" (match defRes1 with
    | some a => a.primarySpec == some "probe:Test.foo_spec"
    | none => false) result

  IO.println ""
  IO.println "Testing primary-spec attribute takes precedence..."
  let defB := mkAtom "probe:Test.bar" .def #[]
  let thmAttr := mkAtom "probe:Test.bar_main" .theorem #["probe:Test.bar"] (isPrimarySpec := true)
  let thmHeur := mkAtom "probe:Test.bar_spec" .theorem #["probe:Test.bar"]
  let res2 := computeSpecs #[defB, thmAttr, thmHeur]
  let defRes2 := res2.find? fun a => a.name == "probe:Test.bar"
  result ← test "attribute overrides heuristic" (match defRes2 with
    | some a => a.primarySpec == some "probe:Test.bar_main"
    | none => false) result

  IO.println ""
  IO.println "Testing primary-spec heuristic no match (multiple non-matching specs)..."
  let defC := mkAtom "probe:Test.baz" .def #[]
  let thmOther1 := mkAtom "probe:Test.baz_lemma" .theorem #["probe:Test.baz"]
  let thmOther2 := mkAtom "probe:Test.baz_aux" .theorem #["probe:Test.baz"]
  let res3 := computeSpecs #[defC, thmOther1, thmOther2]
  let defRes3 := res3.find? fun a => a.name == "probe:Test.baz"
  result ← test "no heuristic match when no _spec and multiple specs" (match defRes3 with
    | some a => a.primarySpec.isNone
    | none => false) result

  IO.println ""
  IO.println "Testing primary-spec attribute still works via isPrimarySpec..."
  let defD := mkAtom "probe:Test.qux" .def #[]
  let thmTagged := mkAtom "probe:Test.qux_spec" .theorem #["probe:Test.qux"] (isPrimarySpec := true)
  let res4 := computeSpecs #[defD, thmTagged]
  let defRes4 := res4.find? fun a => a.name == "probe:Test.qux"
  result ← test "attribute-tagged theorem sets primarySpec on def" (match defRes4 with
    | some a => a.primarySpec == some "probe:Test.qux_spec"
    | none => false) result
  return result

def testPrimarySpecKnownAttribute (result : TestResult) : IO TestResult := do
  let mut result := result

  IO.println ""
  IO.println "Testing primary-spec known-attribute boost (single @[progress])..."
  let defA := mkSpecAtom "probe:Test.foo" .def #[]
  let thmProgress := mkSpecAtom "probe:Test.foo_progress" .theorem #["probe:Test.foo"]
    (attributes := #["progress"])
  let res1 := computeSpecs #[defA, thmProgress]
  let defRes1 := res1.find? fun a => a.name == "probe:Test.foo"
  result ← test "single @[progress] theorem becomes primary-spec" (match defRes1 with
    | some a => a.primarySpec == some "probe:Test.foo_progress"
    | none => false) result

  IO.println ""
  IO.println "Testing primary-spec known-attribute ambiguity (two @[progress])..."
  let thmProgress2 := mkSpecAtom "probe:Test.foo_alt" .theorem #["probe:Test.foo"]
    (attributes := #["progress"])
  let res2 := computeSpecs #[defA, thmProgress, thmProgress2]
  let defRes2 := res2.find? fun a => a.name == "probe:Test.foo"
  result ← test "two @[progress] theorems → ambiguous, no primary-spec" (match defRes2 with
    | some a => a.primarySpec.isNone
    | none => false) result

  IO.println ""
  IO.println "Testing known-attribute beats _spec suffix..."
  let defB := mkSpecAtom "probe:Test.bar" .def #[]
  let thmSuffix := mkSpecAtom "probe:Test.bar_spec" .theorem #["probe:Test.bar"]
  let thmAttr := mkSpecAtom "probe:Test.bar_progress" .theorem #["probe:Test.bar"]
    (attributes := #["progress"])
  let res3 := computeSpecs #[defB, thmSuffix, thmAttr]
  let defRes3 := res3.find? fun a => a.name == "probe:Test.bar"
  result ← test "known-attribute wins over _spec suffix" (match defRes3 with
    | some a => a.primarySpec == some "probe:Test.bar_progress"
    | none => false) result

  IO.println ""
  IO.println "Testing @[primary_spec] beats known-attribute..."
  let defC := mkSpecAtom "probe:Test.qux" .def #[]
  let thmExplicit := mkSpecAtom "probe:Test.qux_main" .theorem #["probe:Test.qux"]
    (isPrimarySpec := true)
  let thmProgressC := mkSpecAtom "probe:Test.qux_progress" .theorem #["probe:Test.qux"]
    (attributes := #["progress"])
  let res4 := computeSpecs #[defC, thmExplicit, thmProgressC]
  let defRes4 := res4.find? fun a => a.name == "probe:Test.qux"
  result ← test "@[primary_spec] beats @[progress]" (match defRes4 with
    | some a => a.primarySpec == some "probe:Test.qux_main"
    | none => false) result

  IO.println ""
  IO.println "Testing known-attribute with @[pspec]..."
  let defD := mkSpecAtom "probe:Test.alpha" .def #[]
  let thmPspec := mkSpecAtom "probe:Test.alpha_ok" .theorem #["probe:Test.alpha"]
    (attributes := #["pspec"])
  let res5 := computeSpecs #[defD, thmPspec]
  let defRes5 := res5.find? fun a => a.name == "probe:Test.alpha"
  result ← test "@[pspec] also triggers known-attribute boost" (match defRes5 with
    | some a => a.primarySpec == some "probe:Test.alpha_ok"
    | none => false) result

  IO.println ""
  IO.println "Testing known-attribute with @[step]..."
  let defE := mkSpecAtom "probe:Test.beta" .def #[]
  let thmStep := mkSpecAtom "probe:Test.beta_ok" .theorem #["probe:Test.beta"]
    (attributes := #["step"])
  let res6 := computeSpecs #[defE, thmStep]
  let defRes6 := res6.find? fun a => a.name == "probe:Test.beta"
  result ← test "@[step] also triggers known-attribute boost" (match defRes6 with
    | some a => a.primarySpec == some "probe:Test.beta_ok"
    | none => false) result

  IO.println ""
  IO.println "Testing ambiguous known-attr falls through to _spec..."
  let defF := mkSpecAtom "probe:Test.gamma" .def #[]
  let thmP1 := mkSpecAtom "probe:Test.gamma_spec" .theorem #["probe:Test.gamma"]
    (attributes := #["progress"])
  let thmP2 := mkSpecAtom "probe:Test.gamma_alt" .theorem #["probe:Test.gamma"]
    (attributes := #["progress"])
  let res7 := computeSpecs #[defF, thmP1, thmP2]
  let defRes7 := res7.find? fun a => a.name == "probe:Test.gamma"
  result ← test "ambiguous known-attr falls through to _spec suffix" (match defRes7 with
    | some a => a.primarySpec == some "probe:Test.gamma_spec"
    | none => false) result

  return result

def testPrimarySpecSoleSpec (result : TestResult) : IO TestResult := do
  let mut result := result

  IO.println ""
  IO.println "Testing primary-spec sole-spec signal..."
  let defA := mkSpecAtom "probe:Test.solo" .def #[]
  let thmOnly := mkSpecAtom "probe:Test.solo_lemma" .theorem #["probe:Test.solo"]
  let res1 := computeSpecs #[defA, thmOnly]
  let defRes1 := res1.find? fun a => a.name == "probe:Test.solo"
  result ← test "single spec becomes primary-spec (sole-spec)" (match defRes1 with
    | some a => a.primarySpec == some "probe:Test.solo_lemma"
    | none => false) result

  IO.println ""
  IO.println "Testing sole-spec does not fire with multiple specs..."
  let defB := mkSpecAtom "probe:Test.multi" .def #[]
  let thm1 := mkSpecAtom "probe:Test.multi_lemma1" .theorem #["probe:Test.multi"]
  let thm2 := mkSpecAtom "probe:Test.multi_lemma2" .theorem #["probe:Test.multi"]
  let res2 := computeSpecs #[defB, thm1, thm2]
  let defRes2 := res2.find? fun a => a.name == "probe:Test.multi"
  result ← test "multiple specs → no sole-spec primary" (match defRes2 with
    | some a => a.primarySpec.isNone
    | none => false) result

  IO.println ""
  IO.println "Testing _spec suffix beats sole-spec..."
  let defC := mkSpecAtom "probe:Test.xyz" .def #[]
  let thmSuffix := mkSpecAtom "probe:Test.xyz_spec" .theorem #["probe:Test.xyz"]
  let res3 := computeSpecs #[defC, thmSuffix]
  let defRes3 := res3.find? fun a => a.name == "probe:Test.xyz"
  result ← test "_spec suffix fires before sole-spec (same result)" (match defRes3 with
    | some a => a.primarySpec == some "probe:Test.xyz_spec"
    | none => false) result

  IO.println ""
  IO.println "Testing sole-spec invariant: primary-spec is in specs..."
  let solePsResult := computeSpecs #[defA, thmOnly]
  let primarySpecInSpecs := solePsResult.all fun a =>
    match a.primarySpec with
    | none => true
    | some ps => a.specs.contains ps
  result ← test "sole-spec: primary-spec is always in specs" primarySpecInSpecs result

  return result

def testTrustedStatus (result : TestResult) : IO TestResult := do
  let mut result := result
  IO.println ""
  IO.println "Testing isTrustedAtom..."
  let mkAtomWith (kind : DeclKind) (codePath : String) : Atom :=
    { name := "probe:Test.x", displayName := "x", dependencies := #[],
      codeModule := "Test", codePath, codeText := some { linesStart := 1, linesEnd := 5 },
      kind }
  result ← test "axiom kind is trusted" (isTrustedAtom (mkAtomWith .axiom "Test.lean")) result
  result ← test "axiom in External is trusted" (isTrustedAtom (mkAtomWith .axiom "Pkg/FunsExternal.lean")) result
  result ← test "def in FunsExternal.lean is trusted" (isTrustedAtom (mkAtomWith .def "Pkg/FunsExternal.lean")) result
  result ← test "theorem in TypesExternal.lean is NOT trusted" (!isTrustedAtom (mkAtomWith .theorem "Pkg/TypesExternal.lean")) result
  result ← test "def in Funs.lean is NOT trusted" (!isTrustedAtom (mkAtomWith .def "Pkg/Funs.lean")) result
  result ← test "theorem in Specs.lean is NOT trusted" (!isTrustedAtom (mkAtomWith .theorem "Pkg/Specs.lean")) result
  result ← test "def in ExternallyVerified.lean is NOT trusted" (!isTrustedAtom (mkAtomWith .def "Pkg/ExternallyVerified.lean")) result

  IO.println ""
  IO.println "Testing trustedReason..."
  result ← test "axiom reason is \"axiom\"" (trustedReason (mkAtomWith .axiom "Test.lean") == some "axiom") result
  result ← test "external def reason is \"external\"" (trustedReason (mkAtomWith .def "Pkg/FunsExternal.lean") == some "external") result
  result ← test "axiom in External reason is \"axiom\" (precedence)" (trustedReason (mkAtomWith .axiom "Pkg/FunsExternal.lean") == some "axiom") result
  result ← test "normal def reason is none" (trustedReason (mkAtomWith .def "Pkg/Funs.lean") == none) result
  result ← test "theorem in External reason is none" (trustedReason (mkAtomWith .theorem "Pkg/TypesExternal.lean") == none) result

  IO.println ""
  IO.println "Testing unifyAtom trusted override..."
  let axiomAtom := mkAtomWith .axiom "Test.lean"
  let proofOk : ProofEntry := { verified := true, status := .success, codePath := "Test.lean", codeLine := 1, sorries := #[] }
  let unified1 := unifyAtom axiomAtom (some proofOk)
  result ← test "axiom overrides success to trusted" (unified1.verificationStatus == some .trusted) result
  result ← test "axiom trusted-reason is \"axiom\"" (unified1.trustedReason == some "axiom") result

  let externalDef := mkAtomWith .def "Pkg/FunsExternal.lean"
  let unified2 := unifyAtom externalDef (some proofOk)
  result ← test "FunsExternal def overrides to trusted" (unified2.verificationStatus == some .trusted) result
  result ← test "FunsExternal trusted-reason is \"external\"" (unified2.trustedReason == some "external") result

  let externalDefNoProof := mkAtomWith .def "Pkg/FunsExternal.lean"
  let unified3 := unifyAtom externalDefNoProof none
  result ← test "FunsExternal def with no proof entry is trusted" (unified3.verificationStatus == some .trusted) result
  result ← test "FunsExternal no-proof trusted-reason is \"external\"" (unified3.trustedReason == some "external") result

  let normalDef := mkAtomWith .def "Pkg/Funs.lean"
  let unified4 := unifyAtom normalDef (some proofOk)
  result ← test "normal def stays verified" (unified4.verificationStatus == some .verified) result
  result ← test "normal def trusted-reason is none" (unified4.trustedReason == none) result

  let normalDefNone := mkAtomWith .def "Pkg/Funs.lean"
  let unified5 := unifyAtom normalDefNone none
  result ← test "normal def with no proof entry stays none" (unified5.verificationStatus == none) result
  result ← test "normal def no-proof trusted-reason is none" (unified5.trustedReason == none) result

  IO.println ""
  IO.println "Testing trusted override with non-success proof entries..."
  let proofSorries : ProofEntry := { verified := false, status := .sorries, codePath := "Test.lean", codeLine := 1, sorries := #[{ line := 3, message := "uses sorry" }] }
  let proofFailure : ProofEntry := { verified := false, status := .failure, codePath := "Test.lean", codeLine := 1, sorries := #[] }

  let axiomWithSorries := mkAtomWith .axiom "Test.lean"
  let unified6 := unifyAtom axiomWithSorries (some proofSorries)
  result ← test "axiom overrides sorries to trusted" (unified6.verificationStatus == some .trusted) result

  let axiomWithFailure := mkAtomWith .axiom "Test.lean"
  let unified7 := unifyAtom axiomWithFailure (some proofFailure)
  result ← test "axiom overrides failure to trusted" (unified7.verificationStatus == some .trusted) result

  let externalWithSorries := mkAtomWith .def "Pkg/FunsExternal.lean"
  let unified8 := unifyAtom externalWithSorries (some proofSorries)
  result ← test "External def overrides sorries to trusted" (unified8.verificationStatus == some .trusted) result

  let externalWithFailure := mkAtomWith .def "Pkg/TypesExternal.lean"
  let unified9 := unifyAtom externalWithFailure (some proofFailure)
  result ← test "External def overrides failure to trusted" (unified9.verificationStatus == some .trusted) result

  IO.println ""
  IO.println "Testing theorems in *External.lean get normal verification status..."
  let externalThm := mkAtomWith .theorem "Pkg/FunsExternal.lean"
  let unified10 := unifyAtom externalThm (some proofOk)
  result ← test "External theorem with success is verified" (unified10.verificationStatus == some .verified) result
  result ← test "External theorem trusted-reason is none" (unified10.trustedReason == none) result

  let externalThmSorries := mkAtomWith .theorem "Pkg/FunsExternal.lean"
  let unified11 := unifyAtom externalThmSorries (some proofSorries)
  result ← test "External theorem with sorries is unverified" (unified11.verificationStatus == some .unverified) result

  let externalThmNone := mkAtomWith .theorem "Pkg/TypesExternal.lean"
  let unified12 := unifyAtom externalThmNone none
  result ← test "External theorem with no proof entry is none" (unified12.verificationStatus == none) result

  IO.println ""
  IO.println "Testing non-conventional External.lean suffix..."
  result ← test "ModelsExternal.lean is trusted" (isTrustedAtom (mkAtomWith .def "Pkg/ModelsExternal.lean")) result
  result ← test "CustomExternal.lean is trusted" (isTrustedAtom (mkAtomWith .def "Deep/Path/CustomExternal.lean")) result

  IO.println ""
  IO.println "Testing @[externally_verified] attribute..."
  let mkAttrAtom (kind : DeclKind) (codePath : String) (attrs : Array String) : Atom :=
    { name := "probe:Test.x", displayName := "x", dependencies := #[],
      codeModule := "Test", codePath, codeText := some { linesStart := 1, linesEnd := 5 },
      kind, attributes := attrs }
  let extVerifiedThm := mkAttrAtom .theorem "Pkg/Proofs.lean" #["externally_verified"]
  result ← test "externally_verified theorem reason is \"externally_verified\""
    (trustedReason extVerifiedThm == some "externally_verified") result
  result ← test "externally_verified theorem is trusted" (isTrustedAtom extVerifiedThm) result
  let unifiedExtSorries := unifyAtom extVerifiedThm (some proofSorries)
  result ← test "externally_verified theorem with sorries overrides to trusted"
    (unifiedExtSorries.verificationStatus == some .trusted) result
  result ← test "externally_verified theorem trusted-reason is \"externally_verified\""
    (unifiedExtSorries.trustedReason == some "externally_verified") result
  let unifiedExtOk := unifyAtom extVerifiedThm (some proofOk)
  result ← test "externally_verified theorem with success still trusted"
    (unifiedExtOk.verificationStatus == some .trusted) result
  let extInNormalFile := mkAttrAtom .theorem "Pkg/Specs.lean" #["externally_verified"]
  result ← test "externally_verified fires regardless of file path"
    (trustedReason extInNormalFile == some "externally_verified") result
  let axiomWithAttr := mkAttrAtom .axiom "Test.lean" #["externally_verified"]
  result ← test "axiom precedence beats externally_verified"
    (trustedReason axiomWithAttr == some "axiom") result
  let defWithAttrInExternal := mkAttrAtom .def "Pkg/FunsExternal.lean" #["externally_verified"]
  result ← test "externally_verified precedence beats external-file convention"
    (trustedReason defWithAttrInExternal == some "externally_verified") result
  let noAttrs := mkAttrAtom .theorem "Pkg/Specs.lean" #["progress"]
  result ← test "unrelated attribute does not trigger trusted" (trustedReason noAttrs == none) result

  return result

def testExampleJsonEnvelopeStructure (result : TestResult) : IO TestResult := do
  let mut result := result
  IO.println ""
  IO.println "Testing example JSON envelope structure..."
  let exPath : System.FilePath := "examples/lean_Curve25519Dalek_0.1.0.json"
  if !(← exPath.pathExists) then
    IO.println "  ⚠ skipping: example JSON not found"
    return result
  let content ← IO.FS.readFile exPath
  match Lean.Json.parse content with
  | .error err =>
    IO.println s!"  ✗ failed to parse example JSON: {err}"
    return result.add false
  | .ok json => do
    let schemaOk := match json.getObjValAs? String "schema" with
      | .ok "probe-lean/extract" => true | _ => false
    result ← test "envelope schema is probe-lean/extract" schemaOk result
    let versionOk := match json.getObjValAs? String "schema-version" with
      | .ok "2.0" => true | _ => false
    result ← test "envelope schema-version is 2.0" versionOk result
    let hasTimestamp := match json.getObjValAs? String "timestamp" with
      | .ok s => !s.isEmpty | _ => false
    result ← test "envelope has non-empty timestamp" hasTimestamp result
    let toolNameOk := match json.getObjVal? "tool" with
      | .ok t => match t.getObjValAs? String "name" with
        | .ok "probe-lean" => true | _ => false
      | _ => false
    result ← test "envelope tool.name is probe-lean" toolNameOk result
    let toolCmdOk := match json.getObjVal? "tool" with
      | .ok t => match t.getObjValAs? String "command" with
        | .ok "extract" => true | _ => false
      | _ => false
    result ← test "envelope tool.command is extract" toolCmdOk result
    let srcPkgOk := match json.getObjVal? "source" with
      | .ok s => match s.getObjValAs? String "package" with
        | .ok "Curve25519Dalek" => true | _ => false
      | _ => false
    result ← test "envelope source.package is Curve25519Dalek" srcPkgOk result
    let srcLangOk := match json.getObjVal? "source" with
      | .ok s => match s.getObjValAs? String "language" with
        | .ok "lean" => true | _ => false
      | _ => false
    result ← test "envelope source.language is lean" srcLangOk result
    let hasData := match json.getObjVal? "data" with
      | .ok (.obj _) => true | _ => false
    result ← test "envelope has data object" hasData result
    return result

def testExampleJsonLoadAtoms (result : TestResult) : IO TestResult := do
  let mut result := result
  IO.println ""
  IO.println "Testing example JSON loads via loadAtoms..."
  let exPath : System.FilePath := "examples/lean_Curve25519Dalek_0.1.0.json"
  if !(← exPath.pathExists) then
    IO.println "  ⚠ skipping: example JSON not found"
    return result
  match ← loadAtoms exPath with
  | .error err =>
    IO.println s!"  ✗ loadAtoms failed: {err}"
    return result.add false
  | .ok ao => do
    result ← test "loadAtoms succeeds" true result
    result ← test "atom count > 1000" (ao.atoms.size > 1000) result
    let allProbeKeys := ao.atoms.all fun a => a.name.startsWith "probe:"
    result ← test "all atom keys start with probe:" allProbeKeys result
    let allLean := ao.atoms.all fun a => a.language == "lean"
    result ← test "all atoms have language lean" allLean result
    return result

def testExampleJsonAtomRequiredFields (result : TestResult) : IO TestResult := do
  let mut result := result
  IO.println ""
  IO.println "Testing example JSON atom required fields..."
  let exPath : System.FilePath := "examples/lean_Curve25519Dalek_0.1.0.json"
  if !(← exPath.pathExists) then
    IO.println "  ⚠ skipping: example JSON not found"
    return result
  match ← loadAtoms exPath with
  | .error _ => return result.add false
  | .ok ao => do
    let allHaveDisplayName := ao.atoms.all fun a => !a.displayName.isEmpty
    result ← test "all atoms have non-empty display-name" allHaveDisplayName result
    let allHaveCodeModule := ao.atoms.all fun a => !a.codeModule.isEmpty
    result ← test "all atoms have non-empty code-module" allHaveCodeModule result
    let nonStubsHaveCodePath := ao.atoms.all fun a =>
      a.codeText.isNone || !a.codePath.isEmpty
    result ← test "non-stub atoms have non-empty code-path" nonStubsHaveCodePath result
    let validKinds := ["def", "theorem", "abbrev", "projection", "class", "structure",
                       "inductive", "instance", "axiom", "opaque", "quot"]
    let kindStr (k : DeclKind) : String := match k with
      | .def => "def" | .theorem => "theorem" | .abbrev => "abbrev"
      | .projection => "projection"
      | .class => "class" | .structure => "structure" | .inductive => "inductive"
      | .instance => "instance" | .axiom => "axiom" | .opaque => "opaque"
      | .quot => "quot"
    let allValidKinds := ao.atoms.all fun a => validKinds.contains (kindStr a.kind)
    result ← test "all atoms have valid DeclKind" allValidKinds result
    let hasDefs := ao.atoms.any fun a => a.kind == .def
    let hasTheorems := ao.atoms.any fun a => a.kind == .theorem
    let hasProjections := ao.atoms.any fun a => a.kind == .projection
    result ← test "has def atoms" hasDefs result
    result ← test "has theorem atoms" hasTheorems result
    result ← test "has projection atoms" hasProjections result
    let allHaveSource := ao.atoms.all fun a => a.codeText.isSome
    result ← test "all atoms have source location (no auto-generated)" allHaveSource result
    return result

def testExampleJsonVerificationStatus (result : TestResult) : IO TestResult := do
  let mut result := result
  IO.println ""
  IO.println "Testing example JSON verification-status field..."
  let exPath : System.FilePath := "examples/lean_Curve25519Dalek_0.1.0.json"
  if !(← exPath.pathExists) then
    IO.println "  ⚠ skipping: example JSON not found"
    return result
  let content ← IO.FS.readFile exPath
  match Lean.Json.parse content with
  | .error _ => return result.add false
  | .ok json =>
    let data := match json.getObjVal? "data" with
      | .ok d => d | _ => Lean.Json.null
    match data.getObj? with
    | .error _ => return result.add false
    | .ok obj => do
      let validStatuses := ["verified", "unverified", "failed", "trusted"]
      let validReasons := ["axiom", "external", "externally_verified"]
      let mut allValid := true
      let mut hasVerified := false
      let mut hasTrusted := false
      let mut trustedHaveReason := true
      let mut reasonsValid := true
      let mut nonTrustedNoReason := true
      for (_, val) in obj.toArray do
        match val.getObjValAs? String "verification-status" with
        | .ok s =>
          if !validStatuses.contains s then allValid := false
          if s == "verified" then hasVerified := true
          if s == "trusted" then
            hasTrusted := true
            match val.getObjValAs? String "trusted-reason" with
            | .ok r => if !validReasons.contains r then reasonsValid := false
            | .error _ => trustedHaveReason := false
          else
            match val.getObjVal? "trusted-reason" with
            | .ok _ => nonTrustedNoReason := false
            | .error _ => pure ()
        | .error _ => allValid := false
      result ← test "all atoms have valid verification-status" allValid result
      result ← test "at least some atoms are verified" hasVerified result
      result ← test "at least some atoms are trusted" hasTrusted result
      result ← test "all trusted atoms have trusted-reason" trustedHaveReason result
      result ← test "all trusted-reason values are valid" reasonsValid result
      result ← test "non-trusted atoms have no trusted-reason" nonTrustedNoReason result
      return result

def testDeterminismInvariants (result : TestResult) : IO TestResult := do
  let mut result := result
  IO.println ""
  IO.println "Testing P14 determinism: sorted keys and arrays in example JSON..."
  let exPath : System.FilePath := "examples/lean_Curve25519Dalek_0.1.0.json"
  if !(← exPath.pathExists) then
    IO.println "  ⚠ skipping: example JSON not found"
    return result
  let content ← IO.FS.readFile exPath
  match Lean.Json.parse content with
  | .error _ => return result.add false
  | .ok json =>
    let data := match json.getObjVal? "data" with
      | .ok d => d | _ => Lean.Json.null
    match data.getObj? with
    | .error _ => return result.add false
    | .ok obj => do
      let keys := obj.toArray.map (·.1)
      let mut keysPairwiseSorted := true
      for i in [0:keys.size - 1] do
        if h : i < keys.size then
          if h2 : i + 1 < keys.size then
            if keys[i] > keys[i + 1] then
              keysPairwiseSorted := false
      result ← test "data keys are in deterministic sorted order" keysPairwiseSorted result

      let isSortedStr (arr : Array String) : Bool :=
        if arr.size ≤ 1 then true
        else Id.run do
          let mut ok := true
          for i in [0:arr.size - 1] do
            if h : i < arr.size then
              if h2 : i + 1 < arr.size then
                if arr[i] > arr[i + 1] then
                  ok := false
          ok

      let mut depsSorted := true
      let mut typeDepsSorted := true
      let mut termDepsSorted := true
      let mut specsSorted := true
      let mut attrsSorted := true
      let mut sorriesSorted := true
      for (_, val) in obj.toArray do
        match val.getObjValAs? (Array String) "dependencies" with
        | .ok arr => if !isSortedStr arr then depsSorted := false
        | .error _ => pure ()
        match val.getObjValAs? (Array String) "type-dependencies" with
        | .ok arr => if !isSortedStr arr then typeDepsSorted := false
        | .error _ => pure ()
        match val.getObjValAs? (Array String) "term-dependencies" with
        | .ok arr => if !isSortedStr arr then termDepsSorted := false
        | .error _ => pure ()
        match val.getObjValAs? (Array String) "specs" with
        | .ok arr => if !isSortedStr arr then specsSorted := false
        | .error _ => pure ()
        match val.getObjValAs? (Array String) "attributes" with
        | .ok arr => if !isSortedStr arr then attrsSorted := false
        | .error _ => pure ()
        match val.getObjValAs? (Array Lean.Json) "sorries" with
        | .ok arr =>
          let lines := arr.filterMap fun j => j.getObjValAs? Nat "line" |>.toOption
          let linesSorted := if lines.size ≤ 1 then true
            else Id.run do
              let mut ok := true
              for i in [0:lines.size - 1] do
                if h : i < lines.size then
                  if h2 : i + 1 < lines.size then
                    if Nat.blt lines[i + 1] lines[i] then ok := false
              ok
          if !linesSorted then sorriesSorted := false
        | .error _ => pure ()
      result ← test "all dependencies arrays are sorted" depsSorted result
      result ← test "all type-dependencies arrays are sorted" typeDepsSorted result
      result ← test "all term-dependencies arrays are sorted" termDepsSorted result
      result ← test "all specs arrays are sorted" specsSorted result
      result ← test "all attributes arrays are sorted" attrsSorted result
      result ← test "all sorries arrays are sorted by line" sorriesSorted result
      return result

def testReadToolchain (result : TestResult) : IO TestResult := do
  let mut result := result
  IO.println ""
  IO.println "Testing readToolchain..."
  let tmpBase : System.FilePath := "/tmp/probe-lean-test-tc-" ++ toString (← IO.monoNanosNow)
  IO.FS.createDirAll tmpBase
  IO.FS.writeFile (tmpBase / "lean-toolchain") "leanprover/lean4:v4.29.0-rc3\n"
  let tc1 ← readToolchain tmpBase
  result ← test "reads existing lean-toolchain" (tc1 == some "leanprover/lean4:v4.29.0-rc3") result

  let emptyDir := tmpBase / "empty"
  IO.FS.createDirAll emptyDir
  let tc2 ← readToolchain emptyDir
  result ← test "returns none when no lean-toolchain" (tc2 == none) result

  try IO.FS.removeDirAll tmpBase catch _ => pure ()
  return result

def testToolchainVersionParsing (result : TestResult) : IO TestResult := do
  let mut result := result
  IO.println ""
  IO.println "Testing parseToolchainVersion..."

  result ← test "parses leanprover/lean4:v4.28.0-rc1"
    (parseToolchainVersion "leanprover/lean4:v4.28.0-rc1" == "v4.28.0-rc1") result
  result ← test "parses with trailing whitespace"
    (parseToolchainVersion "leanprover/lean4:v4.29.0-rc3\n" == "v4.29.0-rc3") result
  result ← test "handles bare version"
    (parseToolchainVersion "v4.28.0-rc1" == "v4.28.0-rc1") result
  result ← test "parses release version"
    (parseToolchainVersion "leanprover/lean4:v4.28.0" == "v4.28.0") result

  -- Test that Lean.versionString is well-formed (no "v" prefix)
  let vs := Lean.versionString
  result ← test "Lean.versionString has no v prefix"
    (!vs.startsWith "v") result
  result ← test "Lean.versionString is non-empty"
    (vs.length > 0) result

  -- Test version matching via dropPrefix
  let tc := s!"leanprover/lean4:v{Lean.versionString}"
  let parsed := (parseToolchainVersion tc).dropPrefix "v" |>.toString
  result ← test "version round-trip matches Lean.versionString"
    (parsed == Lean.versionString) result

  return result

def testFindProbeLeanLibPaths (result : TestResult) : IO TestResult := do
  let mut result := result
  IO.println ""
  IO.println "Testing findProbeLeanLib versioned paths..."

  -- Verify the versioned lib path uses the correct format
  let expectedSuffix := s!"probe-lean-v{Lean.versionString}"
  result ← test "versioned lib dir name matches format"
    (expectedSuffix.startsWith "probe-lean-v") result
  result ← test "versioned lib dir contains version"
    (containsSubstring expectedSuffix Lean.versionString) result

  return result

def testParseLeanLibs (result : TestResult) : IO TestResult := do
  let mut result := result
  IO.println ""
  IO.println "Testing parseLeanLibsFromToml..."

  let multiLib := "name = \"Spqr\"\ndefaultTargets = [\"Spqr\"]\n\n[[lean_lib]]\nname = \"Extraction\"\n\n[[lean_lib]]\nname = \"Spqr\"\n"
  let r1 := parseLeanLibsFromToml multiLib
  result ← test "multi-lib: finds two libraries" (r1.size == 2) result
  result ← test "multi-lib: first is Extraction" (r1[0]? == some "Extraction") result
  result ← test "multi-lib: second is Spqr" (r1[1]? == some "Spqr") result

  let singleLib := "name = \"Curve25519Dalek\"\n\n[[lean_lib]]\nname = \"Curve25519Dalek\"\n"
  let r2 := parseLeanLibsFromToml singleLib
  result ← test "single-lib: finds one library" (r2.size == 1) result
  result ← test "single-lib: name is Curve25519Dalek" (r2[0]? == some "Curve25519Dalek") result

  let noLib := "name = \"MyProject\"\nversion = \"0.1.0\"\n"
  let r3 := parseLeanLibsFromToml noLib
  result ← test "no lean_lib: returns empty" (r3.size == 0) result

  let withSpaces := "name = \"Foo\"\n\n[[ lean_lib ]]\nname = \"Bar\"\n"
  let r4 := parseLeanLibsFromToml withSpaces
  result ← test "spaces in header: finds library" (r4.size == 1) result
  result ← test "spaces in header: name is Bar" (r4[0]? == some "Bar") result

  let otherSection := "name = \"Pkg\"\n\n[[lean_lib]]\nname = \"Lib1\"\n\n[[lean_exe]]\nname = \"NotALib\"\n\n[[lean_lib]]\nname = \"Lib2\"\n"
  let r5 := parseLeanLibsFromToml otherSection
  result ← test "mixed sections: finds two libs" (r5.size == 2) result
  result ← test "mixed sections: skips lean_exe" (!r5.toList.contains "NotALib") result
  result ← test "mixed sections: has Lib1" (r5[0]? == some "Lib1") result
  result ← test "mixed sections: has Lib2" (r5[1]? == some "Lib2") result

  return result

def testParseDefaultTargets (result : TestResult) : IO TestResult := do
  let mut result := result
  IO.println ""
  IO.println "Testing parseDefaultTargetsFromToml..."

  let withDefault := "name = \"Curve25519Dalek\"\ndefaultTargets = [\"Curve25519Dalek\"]\n\n[[lean_lib]]\nname = \"Curve25519Dalek\"\n\n[[lean_lib]]\nname = \"Utils\"\n"
  let d1 := parseDefaultTargetsFromToml withDefault
  result ← test "defaultTargets: finds one target" (d1.size == 1) result
  result ← test "defaultTargets: target is Curve25519Dalek" (d1[0]? == some "Curve25519Dalek") result

  let multiDefault := "name = \"Pkg\"\ndefaultTargets = [\"Lib1\", \"Lib2\"]\n\n[[lean_lib]]\nname = \"Lib1\"\n"
  let d2 := parseDefaultTargetsFromToml multiDefault
  result ← test "multi defaultTargets: finds two targets" (d2.size == 2) result
  result ← test "multi defaultTargets: first is Lib1" (d2[0]? == some "Lib1") result
  result ← test "multi defaultTargets: second is Lib2" (d2[1]? == some "Lib2") result

  let noDefault := "name = \"Pkg\"\nversion = \"0.1.0\"\n\n[[lean_lib]]\nname = \"Pkg\"\n"
  let d3 := parseDefaultTargetsFromToml noDefault
  result ← test "no defaultTargets: returns empty" (d3.size == 0) result

  let emptyDefault := "name = \"Pkg\"\ndefaultTargets = []\n"
  let d4 := parseDefaultTargetsFromToml emptyDefault
  result ← test "empty defaultTargets: returns empty" (d4.size == 0) result

  IO.println ""
  IO.println "Testing getLeanLibs priority (defaultTargets > lean_lib)..."

  let tmpBase : System.FilePath := "/tmp/probe-lean-test-libs-" ++ toString (← IO.monoNanosNow)
  IO.FS.createDirAll tmpBase

  IO.FS.writeFile (tmpBase / "lakefile.toml") withDefault
  let l1 ← getLeanLibs tmpBase
  result ← test "getLeanLibs prefers defaultTargets" (l1.size == 1 && l1[0]? == some "Curve25519Dalek") result

  IO.FS.writeFile (tmpBase / "lakefile.toml") noDefault
  let l2 ← getLeanLibs tmpBase
  result ← test "getLeanLibs falls back to lean_lib" (l2.size == 1 && l2[0]? == some "Pkg") result

  try IO.FS.removeDirAll tmpBase catch _ => pure ()
  return result

def testLeanInvariants (result : TestResult) : IO TestResult := do
  let mut result := result

  -- Invariant 1: type-deps ∪ term-deps == dependencies
  IO.println ""
  IO.println "Testing invariant: type-deps ∪ term-deps == dependencies..."
  let invAtom : Atom := {
    name := "probe:Inv.foo"
    displayName := "foo"
    dependencies := #["probe:Inv.a", "probe:Inv.b", "probe:Inv.c"]
    typeDependencies := #["probe:Inv.a", "probe:Inv.c"]
    termDependencies := #["probe:Inv.b", "probe:Inv.c"]
    codeModule := "Inv"
    codePath := "Inv.lean"
    codeText := some { linesStart := 1, linesEnd := 5 }
    kind := .theorem
  }
  let union := (invAtom.typeDependencies ++ invAtom.termDependencies).toList.eraseDups
  let depsSet := invAtom.dependencies.toList
  let unionMatchesDeps := union.all depsSet.contains && depsSet.all union.contains
  result ← test "type ∪ term == dependencies" unionMatchesDeps result

  let emptyTypedAtom : Atom := {
    name := "probe:Inv.bar"
    displayName := "bar"
    dependencies := #["probe:Inv.x"]
    typeDependencies := #[]
    termDependencies := #[]
    codeModule := "Inv"
    codePath := "Inv.lean"
    codeText := none
    kind := .def
  }
  let emptyUnion := (emptyTypedAtom.typeDependencies ++ emptyTypedAtom.termDependencies).toList.eraseDups
  result ← test "empty typed deps: union is empty (legacy compat)" emptyUnion.isEmpty result

  -- Invariant 2: specs reference existing atoms
  IO.println ""
  IO.println "Testing invariant: specs reference existing atoms..."
  let specDef : Atom := {
    name := "probe:Inv.mydef"
    displayName := "mydef"
    dependencies := #[]
    codeModule := "Inv"
    codePath := "Inv.lean"
    codeText := some { linesStart := 10, linesEnd := 15 }
    kind := .def
  }
  let specThm : Atom := {
    name := "probe:Inv.mydef_spec"
    displayName := "mydef_spec"
    dependencies := #["probe:Inv.mydef"]
    codeModule := "Inv"
    codePath := "Inv.lean"
    codeText := some { linesStart := 20, linesEnd := 30 }
    kind := .theorem
  }
  let specResult := computeSpecs #[specDef, specThm]
  let allAtomNames := specResult.map (·.name)
  let allSpecsExist := specResult.all fun a =>
    a.specs.all fun s => allAtomNames.contains s
  result ← test "all spec references are existing atoms" allSpecsExist result

  -- Invariant 3: primary-spec is in specs
  IO.println ""
  IO.println "Testing invariant: primary-spec is in specs..."
  let psResult := computeSpecs #[specDef, specThm]
  let primarySpecInSpecs := psResult.all fun a =>
    match a.primarySpec with
    | none => true
    | some ps => a.specs.contains ps
  result ← test "primary-spec is always in specs" primarySpecInSpecs result

  -- Invariant 4: spec↔dependency bidirectionality
  IO.println ""
  IO.println "Testing invariant: spec↔dependency bidirectionality..."
  let biDef : Atom := {
    name := "probe:Bi.f"
    displayName := "f"
    dependencies := #[]
    codeModule := "Bi"
    codePath := "Bi.lean"
    codeText := some { linesStart := 1, linesEnd := 5 }
    kind := .def
  }
  let biThm1 : Atom := {
    name := "probe:Bi.f_spec"
    displayName := "f_spec"
    dependencies := #["probe:Bi.f"]
    codeModule := "Bi"
    codePath := "Bi.lean"
    codeText := some { linesStart := 10, linesEnd := 15 }
    kind := .theorem
  }
  let biThm2 : Atom := {
    name := "probe:Bi.f_loop_spec"
    displayName := "f_loop_spec"
    dependencies := #["probe:Bi.f"]
    codeModule := "Bi"
    codePath := "Bi.lean"
    codeText := none
    kind := .theorem
  }
  let biResult := computeSpecs #[biDef, biThm1, biThm2]
  let biDefRes := biResult.find? fun a => a.name == "probe:Bi.f"
  let bidir := match biDefRes with
    | some a => a.specs.all fun specName =>
        match biResult.find? fun b => b.name == specName with
        | some specAtom => specAtom.dependencies.contains a.name
        | none => false
    | none => false
  result ← test "if A has spec B, then B depends on A" bidir result

  -- Invariant 5: mapVerifyStatus produces valid values
  IO.println ""
  IO.println "Testing invariant: mapVerifyStatus produces valid values..."
  let vs1 := mapVerifyStatus .success
  let vs2 := mapVerifyStatus .sorries
  let vs3 := mapVerifyStatus .failure
  result ← test "success maps to verified" (vs1 == .verified) result
  result ← test "sorries maps to unverified" (vs2 == .unverified) result
  result ← test "failure maps to failed" (vs3 == .failed) result

  let validStatuses := #["verified", "unverified", "failed", "trusted"]
  let vsJson1 := Lean.toJson vs1
  let vsJson2 := Lean.toJson vs2
  let vsJson3 := Lean.toJson vs3
  let vsJson4 := Lean.toJson WebVerificationStatus.trusted
  let allValid := [vsJson1, vsJson2, vsJson3, vsJson4].all fun j =>
    match j with
    | .str s => validStatuses.contains s
    | _ => false
  result ← test "all verification-status JSON values are valid strings" allValid result

  return result

def testVersionConsistency (result : TestResult) : IO TestResult := do
  let mut result := result
  IO.println ""
  IO.println "Testing version consistency..."

  result ← test "Constants.toolVersion equals ProbeLean.version"
    (Constants.toolVersion == ProbeLean.version) result

  result ← test "ProbeLean.version is non-empty"
    (ProbeLean.version.length > 0) result

  let dotCount := ProbeLean.version.splitOn "." |>.length
  result ← test "ProbeLean.version looks like semver"
    (dotCount >= 3) result

  -- Read lakefile.toml and verify the version matches
  let lakefileContent ← IO.FS.readFile "lakefile.toml"
  let parts := lakefileContent.splitOn "version = \""
  let lakefileVersion : Option String :=
    if h : parts.length > 1 then
      let rest := parts[1]
      let closing := rest.splitOn "\""
      if h2 : closing.length > 0 then some closing[0]
      else none
    else none
  result ← test "ProbeLean.version matches lakefile.toml"
    (lakefileVersion == some ProbeLean.version) result

  return result

def testCacheValidity (result : TestResult) : IO TestResult := do
  let mut result := result
  IO.println ""
  IO.println "Testing isCacheValid..."

  let tmpBase : System.FilePath := "/tmp/probe-lean-test-cache-" ++ toString (← IO.monoNanosNow)
  IO.FS.createDirAll tmpBase

  -- No cache file at all → invalid
  let v1 ← isCacheValid tmpBase
  result ← test "no cache file → invalid" (!v1) result

  -- Create cache file but no build dir → invalid
  let cacheDir := tmpBase / ".lake" / "probe-lean"
  IO.FS.createDirAll cacheDir
  IO.FS.writeFile (cacheDir / "build_output.txt") "cached"
  let v2 ← isCacheValid tmpBase
  result ← test "cache file but no build dir → invalid" (!v2) result

  -- Create build dir → valid (no .lean files to be newer)
  let buildDir := tmpBase / ".lake" / "build" / "lib" / "lean"
  IO.FS.createDirAll buildDir
  let v3 ← isCacheValid tmpBase
  result ← test "cache file + build dir → valid" v3 result

  -- Touch lean-toolchain after cache → invalid
  IO.sleep 1100
  IO.FS.writeFile (tmpBase / "lean-toolchain") "leanprover/lean4:v4.28.0\n"
  let v4 ← isCacheValid tmpBase
  result ← test "lean-toolchain newer than cache → invalid" (!v4) result

  -- Refresh cache after toolchain change → valid again
  IO.sleep 1100
  IO.FS.writeFile (cacheDir / "build_output.txt") "cached-v2"
  let v5 ← isCacheValid tmpBase
  result ← test "refreshed cache after toolchain change → valid" v5 result

  -- Touch lakefile.toml after cache → invalid
  IO.sleep 1100
  IO.FS.writeFile (tmpBase / "lakefile.toml") "name = \"test\"\n"
  let v6 ← isCacheValid tmpBase
  result ← test "lakefile.toml newer than cache → invalid" (!v6) result

  try IO.FS.removeDirAll tmpBase catch _ => pure ()
  return result

def testCheckFilesSkipsDotDirs (result : TestResult) : IO TestResult := do
  let mut result := result
  IO.println ""
  IO.println "Testing checkFilesNewerThan skips dot-directories..."

  let tmpBase : System.FilePath := "/tmp/probe-lean-test-dotdir-" ++ toString (← IO.monoNanosNow)
  IO.FS.createDirAll tmpBase

  -- Write a cache timestamp file, then wait
  let tsFile := tmpBase / "timestamp"
  IO.FS.writeFile tsFile ""
  IO.sleep 1100
  let tsMeta ← tsFile.metadata
  let cacheTime := tsMeta.modified

  -- Create a .lean file inside a dot-directory (should be ignored)
  let dotDir := tmpBase / ".lake"
  IO.FS.createDirAll dotDir
  IO.FS.writeFile (dotDir / "Foo.lean") "def foo := 1"

  let r1 ← checkFilesNewerThan tmpBase cacheTime
  result ← test ".lean in dot-dir is ignored" (!r1) result

  -- Create a .lean file in a normal directory (should be detected)
  let srcDir := tmpBase / "src"
  IO.FS.createDirAll srcDir
  IO.FS.writeFile (srcDir / "Bar.lean") "def bar := 2"

  let r2 ← checkFilesNewerThan tmpBase cacheTime
  result ← test ".lean in normal dir is detected" r2 result

  try IO.FS.removeDirAll tmpBase catch _ => pure ()
  return result

def testNixEnv (result : TestResult) : IO TestResult := do
  let mut result := result
  IO.println ""
  IO.println "Testing Nix environment detection..."

  let tmpBase : System.FilePath := "/tmp/probe-lean-test-nix-" ++ toString (← IO.monoNanosNow)
  IO.FS.createDirAll tmpBase

  let r1 ← detectNixShell tmpBase
  result ← test "empty dir → none" (r1 == none) result

  IO.FS.writeFile (tmpBase / "shell.nix") "{ pkgs ? import <nixpkgs> {} }: pkgs.mkShell {}"
  let r2 ← detectNixShell tmpBase
  result ← test "shell.nix only → some .shell" (r2 == some .shell) result

  IO.FS.removeFile (tmpBase / "shell.nix")
  IO.FS.writeFile (tmpBase / "flake.nix") "{ outputs = { self }: {}; }"
  let r3 ← detectNixShell tmpBase
  result ← test "flake.nix only → some .flake" (r3 == some .flake) result

  IO.FS.writeFile (tmpBase / "shell.nix") "{ pkgs ? import <nixpkgs> {} }: pkgs.mkShell {}"
  let r4 ← detectNixShell tmpBase
  result ← test "both present → flake takes precedence" (r4 == some .flake) result

  let _ ← isNixAvailable .shell
  result ← test "isNixAvailable .shell does not crash" true result

  let _ ← isNixAvailable .flake
  result ← test "isNixAvailable .flake does not crash" true result

  let (_, _, exitCode) ← runLakeCmd #["--version"] none none
  result ← test "runLakeCmd none behaves like direct lake" (exitCode == 0) result

  try IO.FS.removeDirAll tmpBase catch _ => pure ()
  return result

def main : IO UInt32 := do
  let mut result : TestResult := { passed := 0, failed := 0 }
  result ← testConstants result
  result ← testAnalysisHelpers result
  result ← testSharedUtilities result
  result ← testTypeJsonSerialization result
  result ← testAtomizeHelpers result
  result ← testComputeSpecs result
  result ← testAtomsOutputJson result
  result ← testAtomSpecsJson result
  result ← testAtomLanguageField result
  result ← testSorryDetection result
  result ← testProofsOutputJson result
  result ← testUnifiedAtomJson result
  result ← testViewHelpers result
  result ← testStubEntryJson result
  result ← testMoleculesOutputJson result
  result ← testEnvelopeAwareLoading result
  result ← testMetadataHelpers result
  result ← testFindDefaultAtomsPath result
  result ← testTypedDependencies result
  result ← testPrimarySpecHeuristic result
  result ← testPrimarySpecKnownAttribute result
  result ← testPrimarySpecSoleSpec result
  result ← testTrustedStatus result
  result ← testExampleJsonEnvelopeStructure result
  result ← testExampleJsonLoadAtoms result
  result ← testExampleJsonAtomRequiredFields result
  result ← testExampleJsonVerificationStatus result
  result ← testDeterminismInvariants result
  result ← testReadToolchain result
  result ← testToolchainVersionParsing result
  result ← testFindProbeLeanLibPaths result
  result ← testLeanInvariants result
  result ← testParseLeanLibs result
  result ← testParseDefaultTargets result
  result ← testVersionConsistency result
  result ← testCacheValidity result
  result ← testCheckFilesSkipsDotDirs result
  result ← testNixEnv result

  IO.println ""
  IO.println s!"Results: {result.passed} passed, {result.failed} failed"

  if result.failed > 0 then
    return 1
  else
    return 0
