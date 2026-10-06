/-- The dependency's version: a real proof. Restated with a `sorry` by
`CrossMerge.Restate`, which loses the name to this module (imported first). -/
theorem shared : True := True.intro

/-- Restated with a real proof by `CrossMerge.RestateGood`, which loses the name to this
module: the project's proved body must still leave its callers clean. -/
theorem shared2 : True := True.intro

/-- Restated with a real proof by `CrossMerge.AFirst`, which is imported before this
module and therefore *wins* the name while the environment keeps this body. -/
theorem shared3 : True := True.intro

/-- Restated with a `sorry` by `CrossMerge.ABad`, imported before this module: the
project wins the name and the environment keeps *this* proved body, so only the
environment header's copy of the project version shows the `sorry`. -/
theorem shared4 : True := True.intro
