/-!
Rule 3 of the trusted base: a non-proof declared in a `*External` module is
trusted (reason `external`); theorems, and any other declaration whose type is a
proposition, are not.
-/

/-- Trusted by the module convention although its body is a `sorry`. -/
def externalOp : Nat := sorry

/-- Its statement names the trusted `externalOp`: clean modulo the trusted base. -/
theorem usesExternal : externalOp = externalOp := rfl

/-- A theorem in an `External` module gets its normal status: `unverified`. -/
theorem extThm : (0 : Nat) < 1 := by sorry

/-- A proof in disguise: a `def` whose *type* is a proposition. Rule 3 excludes it, since
the convention trusts models of external functions and types, not admitted facts:
`unverified`. -/
def admittedFact : (0 : Nat) < 1 := by sorry

/-- A Prop-*valued* definition — its type is `Prop`, which is not itself a
proposition — is a model like any other: `trusted`. -/
def externalPred : Prop := sorry
