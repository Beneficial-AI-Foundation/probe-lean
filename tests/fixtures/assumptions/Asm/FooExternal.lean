import Asm.Basic

/-! A `*External` module: rule 3 trusts every non-proof. -/

/-- A hand-written model with `sorry`: its own name. -/
def ext_add (a b : Nat) : Nat := sorry

/-- A vouched `sorry` about `ext_add`: `["add_spec", "ext_add"]`. -/
@[externally_verified] theorem add_spec (a b : Nat) : ext_add a b = ext_add b a := by sorry

/-- A model without `sorry` that calls `ext_add`: `["ext_add"]`. -/
def mul (a b : Nat) : Nat := ext_add a b

/-- A vouched lemma with a full proof through `add_spec`. Trust excuses only `sorry`,
so the names of the proof flow through: `["add_spec", "ext_add"]`. -/
@[externally_verified] theorem mul_spec (a b : Nat) : mul a b = mul b a := add_spec a b

/-- Not trusted (a theorem): `["add_spec", "ext_add"]`. -/
theorem caller_spec (a b : Nat) : mul a b = mul b a := mul_spec a b

/-- An External def without axioms: `[]`. -/
def ext_id (a : Nat) : Nat := a

/-- A trusted `opaque` whose value holds `sorry`: its own name. -/
opaque extOpaque : Nat → Nat := fun _ => sorry

/-- A trusted inductive whose constructor type rests on the unexcused `holeyDef`:
`verified` with `kernel-taint`, `["sorryAx"]`. -/
inductive BadBox where
  | mk (h : holeyDef = 0)

mutual
/-- Trusted inductives in one kernel cycle (each names the other through its
constructors) that reach the axiom `T`: `["T"]` each. -/
inductive EvenE where
  | zero
  | succ (o : OddE)
/-- See `EvenE`. -/
inductive OddE where
  | succ (e : EvenE) (t : T)
end
