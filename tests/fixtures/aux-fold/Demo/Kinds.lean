/-!
`kind` fixtures (issue #111). probe-lean imports with `loadExts := false`, so the
class and instance extension *states* are empty; `kind` must come from the
per-module extension entries. Every declaration here is sorry-free and untrusted,
so the taint totals are unchanged; `AuxFoldCheck.lean` asserts the kinds.
-/

/-- A class: must be `class`, not `structure`. -/
class Foo (α : Type) where
  x : α

/-- User-named instance, no `inst` prefix: must be `instance`. -/
instance fooNat : Foo Nat := ⟨0⟩

/-- Auto-named instance (`instFooBool`): must be `instance`. -/
instance : Foo Bool := ⟨true⟩

/-- A def whose name starts with `inst` but is not an instance: must be `def`. -/
def instLike : Nat := 1

/-- A def promoted with `attribute [instance]`: must be `instance`. -/
def fooUnit : Foo Unit := ⟨()⟩
attribute [instance] fooUnit
