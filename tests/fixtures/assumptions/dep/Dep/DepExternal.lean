/-- A def with `sorry` in a dependency `*External` module. Rule 3 applies only inside
the project, so a caller lists `sorryAx`, not this name. -/
def depExt (k : Nat) : Nat := sorry
