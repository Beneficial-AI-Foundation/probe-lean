/-- Not selected by `--module Coll.Main`, but loaded transitively through it. Its
`sorry` must taint `Coll.Main.thm` even though the full import fell back to the
selection. -/
theorem bad : (0 : Nat) < 5 := by sorry
