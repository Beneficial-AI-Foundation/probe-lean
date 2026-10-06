import Dep.Shared

/-- Built against the dependency's proved `shared`. Loads `Dep.Shared` into the
environment before `CrossMerge.Restate`, by import order, which is what makes `shared`
a cross-boundary merge won by the dependency. The merged environment cannot tell this
caller apart from `CrossMerge.Use.caller`, and the project's version of `shared` is a
`sorry`, so it reads `verified` too. -/
theorem viaDep : True := shared

/-- Built against the dependency's proved `shared2`, whose project restatement
(`CrossMerge.RestateGood`) is proved as well: `transitively-verified`. -/
theorem viaDep2 : True := shared2
