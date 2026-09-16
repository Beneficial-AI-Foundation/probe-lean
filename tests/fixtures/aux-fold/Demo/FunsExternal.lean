/-!
Rule 3 of the trusted base: a non-theorem declared in a `*External` module is
trusted (reason `external`), theorems there are not.
-/

/-- Trusted by the module convention although its body is a `sorry`. -/
def externalOp : Nat := sorry

/-- Its statement names the trusted `externalOp`: clean modulo the trusted base. -/
theorem usesExternal : externalOp = externalOp := rfl

/-- A theorem in an `External` module gets its normal status: `unverified`. -/
theorem extThm : (0 : Nat) < 1 := by sorry
