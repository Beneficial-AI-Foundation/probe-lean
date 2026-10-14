import Dep.Attr

/-! Project rows of the assumption-set spec. -/

/-- Rests only on the standard axioms: `[]`. -/
theorem onlyS (p : Prop) : p ∨ ¬p := Classical.em p

/-- A project axiom: its own set is `["bad"]`. -/
axiom bad : False

/-- A caller of a project axiom: `["bad"]`, `transitively-verified`. -/
theorem useBad : 1 = 2 := bad.elim

/-- A universe-typed project axiom: `["T"]`. -/
axiom T : Type

/-- `["T"]`. -/
def useT (x : T) : T := x

/-- A vouched lemma with a `sorry` proof: its own name. -/
@[externally_verified] theorem vouched : 1 + 1 = 2 := by sorry

/-- A caller of the vouched lemma: `["vouched"]`. -/
theorem useVouched : 1 + 1 = 2 := vouched

/-- A vouched lemma with a full proof and no axioms: `[]`. -/
@[externally_verified] theorem vouchedClean : 2 + 2 = 4 := rfl

/-- `[]`. -/
theorem useVouchedClean : 2 + 2 = 4 := vouchedClean

/-- A trusted constant whose proof uses only an axiom: the axiom, not its own name. -/
@[externally_verified] theorem vouchedAx : False := bad

/-- A project axiom named by a vouched lemma's statement. -/
axiom n : Nat

/-- A vouched lemma with a full proof whose statement names an axiom: `["n"]`. -/
@[externally_verified] theorem same : n = n := rfl

/-- `["n"]`. -/
theorem useSame : n = n := same

/-- An unexcused project `sorry`, direct carrier: `unverified`, `["sorryAx"]`. -/
theorem holey : 1 = 1 := by sorry

/-- A caller of `holey`: `verified` with `kernel-taint`, `["sorryAx"]`. -/
theorem useHoley : 1 = 1 := holey

/-- A def with an unexcused `sorry`: `unverified`. -/
def holeyDef : Nat := sorry

/-- A trusted constant whose statement names `sorryAx` directly: `unverified`. -/
@[externally_verified] theorem stmtSorry : (sorry : Prop) → True := fun _ => trivial

/-- A trusted constant whose statement rests on `holeyDef`: `verified` with
`kernel-taint`. -/
@[externally_verified] theorem stmtIndirect : holeyDef = holeyDef := rfl

/-- `Box.a` reaches `sorry` only through `Box` and its other constructor. `Box.a` is
a project constant that is not emitted. -/
inductive Box where
  | a (k : Nat)
  | b (h : holeyDef = 0)

/-- A caller of `Box.a`: `["sorryAx"]`. -/
def mkA : Box := Box.a 0
