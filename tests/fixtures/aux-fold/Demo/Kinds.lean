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

/-!
Spec targets (issue #130): only data `def`, `abbrev`, `instance`, `opaque` and `axiom`
atoms receive `specs`. Each non-target below is named in the statement of a theorem,
so under the old rule (`kind != theorem`) it would receive that theorem as a spec.
`AuxFoldCheck.lean` asserts the specs. Everything is sorry-free and untrusted.
-/

/-- A structure with a data field and a Prop field. -/
structure Bundle where
  val : Nat
  pos : 0 < val

/-- A Prop-valued class. -/
class IsPos (n : Nat) : Prop where
  out : 0 < n

/-- A class that extends a Prop-valued class: `PosNat.toIsPos` is a Prop projection. -/
class PosNat (n : Nat) extends IsPos n where
  tag : Nat

/-- A data def: the only spec target in this section. -/
def needsPos (n : Nat) [IsPos n] : Nat := n

/-- Names `needsPos`, `PosNat` and, through the instance argument, `PosNat.toIsPos`. -/
theorem needsPos_eq (n : Nat) [PosNat n] : needsPos n = n := rfl

/-- Names `Bundle`, `Bundle.val` and `Bundle.pos`. -/
theorem bundle_pos_eq (b : Bundle) (h : 0 < b.val) : b.pos = h := rfl

/-- A proof written as a `def`. -/
def provedDef : 0 < 1 := Nat.one_pos

theorem provedDef_eq : provedDef = Nat.one_pos := rfl

/-- A predicate. -/
def IsSmall (n : Nat) : Prop := n < 3

theorem isSmall_one : IsSmall 1 := by unfold IsSmall; decide

/-- A proof of a Prop-valued class with kind `instance`. Lean elaborates
    `instance : IsPos 5` as a theorem, so the fixture promotes a `def` instead. -/
def isPosFive : IsPos 5 := ⟨by decide⟩
attribute [instance] isPosFive

theorem isPosFive_eq : isPosFive = ⟨by decide⟩ := rfl
