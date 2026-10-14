import Dep.Attr

/-- A dependency axiom: it enters the set of every caller. -/
axiom d : Nat

/-- A dependency `sorry`: the taint walk does not search dependency proofs, so a
caller stays `transitively-verified`, and its set holds `sorryAx`. -/
theorem depSorry : True := by sorry

/-- A dependency `@[externally_verified]` theorem with `sorry`. Trust rules apply only
inside the project, so a caller lists `sorryAx`, not this name. -/
@[externally_verified] theorem depVouched : True := by sorry
