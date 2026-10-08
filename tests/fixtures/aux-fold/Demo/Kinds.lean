/-!
`kind` fixtures (issues #111 and #115). probe-lean imports with `loadExts := false`, so the
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

/-- Issue #115: the projection of a Prop-valued field compiles to a theorem, but its
    kind is `projection`. -/
structure Bundle where
  val : Nat
  pos : 0 < val

/-- A Prop-valued class parent: `PosNat.toIsPos` is a projection too. -/
class IsPos (n : Nat) : Prop where
  out : 0 < n

class PosNat (n : Nat) extends IsPos n where
  tag : Nat
