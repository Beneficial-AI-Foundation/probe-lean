/-- The project's proved restatement of `Dep.Shared.shared2`. Sorts after
`CrossMerge.Other`, so the dependency wins the name and this body is the one kept.
Walked from the project's own version: clean, and so are its callers. Before the
round-4 change every cross-boundary name was taken to rest on `sorry`. -/
theorem shared2 : True := True.intro
