/-- The helper of `B` has the same user-facing name as the one of `A` and no `sorry`. -/
private def aux : Nat := 0

/-- Uses the `aux` of `B`. -/
theorem useB : aux = 0 := rfl
