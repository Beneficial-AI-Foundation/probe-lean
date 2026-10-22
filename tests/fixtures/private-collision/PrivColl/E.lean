module

/-- A private `aux` in a module-system module. -/
private def aux : Nat := 3

/-- Uses the private `aux` in its proof. A public statement cannot name it. -/
public theorem useE : True := by
  have : aux = 3 := rfl
  trivial
