import Dep.Shared

/-- Built against the dependency's proved `shared`. Loads `Dep.Shared` into the
environment (before `CrossMerge.Restate`, by import order), which is what makes
`shared` a cross-boundary merge. The merged environment cannot tell this caller apart
from `CrossMerge.Use.caller`, so it reads `verified` too: the walk fails closed. -/
theorem viaDep : True := shared
