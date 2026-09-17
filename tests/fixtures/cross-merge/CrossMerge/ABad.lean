/-- Sorts before `CrossMerge.Other` (which loads the dependency), imports nothing: the
project wins the name `shared4` and `finalizeImport` keeps the *last* body — the
dependency's proved one. The environment therefore shows a clean `shared4` under a
project name while the project's own body is a `sorry`. The walk must follow the
header's copy of this version: `shared4` reads `unverified`, its caller `verified`. -/
theorem shared4 : True := by sorry
