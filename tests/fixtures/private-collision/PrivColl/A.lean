/-- The helper of `A` rests on a `sorry`. -/
private def aux : Nat := sorry

/-- Uses the `aux` of `A` and has no `sorry` of its own. -/
theorem useA : aux = aux := rfl
