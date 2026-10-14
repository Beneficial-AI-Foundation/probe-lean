/-! Axiom/theorem merges across the project boundary (`Dep.Merge`). This module does
not import the dependency, so both packages build. -/

/-- Merged with the dependency theorem `h1`: `["h1"]`. -/
axiom h1 : True

/-- Merged with the dependency axiom `h2`: `["h2"]`. -/
theorem h2 : True := True.intro

/-- Merged with the dependency theorem `h3`, whose proof uses `sorry`. Trust excuses
only a `sorry` of a project version, so `["h3", "sorryAx"]`. -/
axiom h3 : True
