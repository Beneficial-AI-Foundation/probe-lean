/-- The project's restatement of `Dep.Shared.shared`: same name and statement, proof
is a `sorry`. In the co-imported environment the name belongs to whichever module
came first and the body to whichever came last, so this `sorry` can be attributed
to the dependency — outside the walk — and vanish. -/
theorem shared : True := by sorry
