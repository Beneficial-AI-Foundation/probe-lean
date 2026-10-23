/-- A private `pub` in a module that does not import `PrivColl.C`. -/
private def pub : Nat := 2

/-- Uses the private `pub`. -/
theorem usePub : pub = 2 := rfl
