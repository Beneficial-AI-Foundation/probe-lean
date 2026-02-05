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
  IO.println "Testing DeclKind JSON serialization..."
  result ← test "def toJson" (Lean.toJson DeclKind.def == "def") result
  result ← test "theorem toJson" (Lean.toJson DeclKind.theorem == "theorem") result
  result ← test "structure toJson" (Lean.toJson DeclKind.structure == "structure") result

  IO.println ""
  IO.println s!"Results: {result.passed} passed, {result.failed} failed"

  if result.failed > 0 then
    return 1
  else
    return 0
