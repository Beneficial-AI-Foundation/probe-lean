import Orph.Dep

/-- Rests on `Orph.Dep.bad`: `verified` while `Orph/Dep.lean` exists. Once the source is
deleted the extraction must abort instead of reading this clean. -/
theorem thm : (0 : Nat) < 5 := bad
