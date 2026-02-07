/-
  Unit tests for probe-lean
-/
import ProbeLean

set_option maxRecDepth 1024

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

def main : IO UInt32 := do
  let mut result : TestResult := { passed := 0, failed := 0 }

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

  IO.println ""
  IO.println "Testing addProbePrefix..."
  result ← test "add probe prefix" (addProbePrefix "Test.foo" == "probe:Test.foo") result
  result ← test "add probe prefix simple" (addProbePrefix "foo" == "probe:foo") result

  IO.println ""
  IO.println "Testing DeclKind JSON serialization..."
  result ← test "def toJson" (Lean.toJson DeclKind.def == "def") result
  result ← test "theorem toJson" (Lean.toJson DeclKind.theorem == "theorem") result
  result ← test "structure toJson" (Lean.toJson DeclKind.structure == "structure") result

  IO.println ""
  IO.println "Testing isAlwaysSpecified..."
  result ← test "theorem is specified" (isAlwaysSpecified DeclKind.theorem) result
  result ← test "def is specified" (isAlwaysSpecified DeclKind.def) result
  result ← test "structure is specified" (isAlwaysSpecified DeclKind.structure) result
  result ← test "class is specified" (isAlwaysSpecified DeclKind.class) result
  result ← test "inductive is specified" (isAlwaysSpecified DeclKind.inductive) result
  result ← test "instance is specified" (isAlwaysSpecified DeclKind.instance) result

  IO.println ""
  IO.println "Testing atomToSpecEntry..."
  let testAtom : Atom := {
    name := "probe:Test.foo"
    displayName := "foo"
    dependencies := #["probe:Test.helper"]
    codeModule := "Test"
    codePath := "Test.lean"
    codeText := some { linesStart := 10, linesEnd := 15 }
    kind := .theorem
  }
  let specEntry := atomToSpecEntry testAtom
  result ← test "specEntry specified" specEntry.specified result
  result ← test "specEntry codePath" (specEntry.codePath == "Test.lean") result
  result ← test "specEntry specText" (specEntry.specText == some { linesStart := 10, linesEnd := 15 }) result

  IO.println ""
  IO.println "Testing AtomsOutput JSON serialization..."
  let atomsOutput : AtomsOutput := { atoms := #[testAtom] }
  let atomsJson := Lean.toJson atomsOutput
  -- Check that the JSON is an object keyed by atom name
  let hasProbeKey := match atomsJson.getObjVal? "probe:Test.foo" with
    | .ok _ => true
    | _ => false
  result ← test "atoms keyed by probe: name" hasProbeKey result
  -- Check that the atom value has the expected fields
  let hasDeps := match atomsJson.getObjVal? "probe:Test.foo" with
    | .ok v => match v.getObjValAs? (Array String) "dependencies" with
      | .ok deps => deps.size == 1 && deps[0]! == "probe:Test.helper"
      | _ => false
    | _ => false
  result ← test "atom has probe: prefixed dependencies" hasDeps result

  IO.println ""
  IO.println "Testing SpecEntry JSON serialization..."
  let specJson := Lean.toJson specEntry
  let hasSpecified := match specJson.getObjValAs? Bool "specified" with
    | .ok true => true
    | _ => false
  let hasCodePath := match specJson.getObjValAs? String "code-path" with
    | .ok "Test.lean" => true
    | _ => false
  result ← test "specEntry toJson has specified" hasSpecified result
  result ← test "specEntry toJson has code-path" hasCodePath result

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

  IO.println ""
  IO.println "Testing parseFunctionEntry..."
  let funcJson1 := Lean.Json.mkObj [("lean_name", "Test.foo"), ("is_relevant", true)]
  let funcEntry1 := parseFunctionEntry funcJson1
  result ← test "parse function entry" funcEntry1.isOk result
  match funcEntry1 with
  | .ok entry =>
    result ← test "function lean_name" (entry.leanName == "Test.foo") result
    result ← test "function is_relevant true" entry.isRelevant result
  | .error _ => pure ()

  let funcJson2 := Lean.Json.mkObj [("lean_name", "Test.bar"), ("is_relevant", false)]
  let funcEntry2 := parseFunctionEntry funcJson2
  match funcEntry2 with
  | .ok entry =>
    result ← test "function is_relevant false" (!entry.isRelevant) result
  | .error _ => pure ()

  -- Test is_relevant defaults to true when missing
  let funcJson3 := Lean.Json.mkObj [("lean_name", "Test.baz")]
  let funcEntry3 := parseFunctionEntry funcJson3
  match funcEntry3 with
  | .ok entry =>
    result ← test "function is_relevant defaults true" entry.isRelevant result
  | .error _ => pure ()

  IO.println ""
  IO.println "Testing filterAtoms..."
  let testAtom2 : Atom := {
    name := "probe:Test.bar"
    displayName := "bar"
    dependencies := #[]
    codeModule := "Test"
    codePath := "Test.lean"
    codeText := some { linesStart := 20, linesEnd := 25 }
    kind := .def
  }
  let atomsOutput : AtomsOutput := { atoms := #[testAtom, testAtom2] }
  let functions : Array FunctionEntry := #[
    { leanName := "Test.foo", isRelevant := true, source := "src/test.rs", lines := "10-20", rustName := "test_foo", specFile := none },
    { leanName := "Test.bar", isRelevant := false, source := "src/test.rs", lines := "30-40", rustName := "test_bar", specFile := none },
    { leanName := "Test.missing", isRelevant := true, source := "src/test.rs", lines := "50-60", rustName := "test_missing", specFile := none }
  ]
  let filtered := filterFunctions atomsOutput functions
  result ← test "filterFunctions keeps relevant" (filtered.size == 1) result
  let correctFunc := match filtered[0]? with
    | some f => f.leanName == "Test.foo"
    | none => false
  result ← test "filterFunctions correct function" correctFunc result

  IO.println ""
  IO.println "Testing getLastNamePart..."
  result ← test "last part simple" (getLastNamePart "foo" == "foo") result
  result ← test "last part qualified" (getLastNamePart "Foo.Bar.baz" == "baz") result
  result ← test "last part two" (getLastNamePart "Foo.bar" == "bar") result

  IO.println ""
  IO.println "Testing getSecondLastNamePart..."
  result ← test "second last simple" (getSecondLastNamePart "foo" == "") result
  result ← test "second last two" (getSecondLastNamePart "Foo.bar" == "Foo") result
  result ← test "second last three" (getSecondLastNamePart "Foo.Bar.baz" == "Bar") result

  IO.println ""
  IO.println "Testing parseLines..."
  result ← test "parse lines normal" (parseLines "42-58" == { linesStart := 42, linesEnd := 58 }) result
  result ← test "parse lines single" (parseLines "10" == { linesStart := 10, linesEnd := 10 }) result
  result ← test "parse lines empty" (parseLines "" == { linesStart := 0, linesEnd := 0 }) result

  IO.println ""
  IO.println "Testing generateStubKey..."
  result ← test "stub key simple" (generateStubKey "src/test.rs" "Test.foo" false == "src/test.rs/foo") result
  result ← test "stub key with clash" (generateStubKey "src/test.rs" "Module.Test.foo" true == "src/test.rs/foo#Test") result

  IO.println ""
  IO.println "Testing StubEntry JSON serialization..."
  let stubEntry : StubEntry := {
    leanPath := none
    leanLines := none
    leanName := "probe:Test.foo"
    rustPath := "src/test.rs"
    rustLines := { linesStart := 10, linesEnd := 20 }
    rustName := "test_foo"
    codePath := some "specs/test_spec.lean"
    codeLines := none
    codeName := some "probe:Test.foo_spec"
  }
  let stubJson := Lean.toJson stubEntry
  let hasLeanName := match stubJson.getObjValAs? String "lean-name" with
    | .ok "probe:Test.foo" => true
    | _ => false
  result ← test "stubEntry toJson has lean-name" hasLeanName result
  let hasRustPath := match stubJson.getObjValAs? String "rust-path" with
    | .ok "src/test.rs" => true
    | _ => false
  result ← test "stubEntry toJson has rust-path" hasRustPath result
  let hasCodeName := match stubJson.getObjValAs? (Option String) "code-name" with
    | .ok (some "probe:Test.foo_spec") => true
    | _ => false
  result ← test "stubEntry toJson has code-name" hasCodeName result
  let hasNullLeanPath := match stubJson.getObjValAs? (Option String) "lean-path" with
    | .ok none => true
    | _ => false
  result ← test "stubEntry toJson has null lean-path" hasNullLeanPath result

  IO.println ""
  IO.println "Testing StubEntry without spec file..."
  let stubEntryNoSpec : StubEntry := {
    leanPath := none
    leanLines := none
    leanName := "probe:Test.bar"
    rustPath := "src/test.rs"
    rustLines := { linesStart := 30, linesEnd := 40 }
    rustName := "test_bar"
    codePath := none
    codeLines := none
    codeName := none
  }
  let stubJsonNoSpec := Lean.toJson stubEntryNoSpec
  let hasNullCodePath := match stubJsonNoSpec.getObjValAs? (Option String) "code-path" with
    | .ok none => true
    | _ => false
  result ← test "stubEntry without spec has null code-path" hasNullCodePath result

  IO.println ""
  IO.println s!"Results: {result.passed} passed, {result.failed} failed"

  if result.failed > 0 then
    return 1
  else
    return 0
