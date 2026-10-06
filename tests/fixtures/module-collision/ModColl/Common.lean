module

/-- Not selected by `--module ModColl.Main`, but loaded transitively through it. Its
`sorry` must taint `ModColl.Main.thm` even though the full import fell back to the
selection. In this module's base `.olean` it is an axiom; the sorried proof is only in
`.olean.private`. -/
public theorem bad : (0 : Nat) < 5 := by sorry
