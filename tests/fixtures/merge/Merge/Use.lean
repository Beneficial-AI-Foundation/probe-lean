import Merge.Bad

/-- Built against the sorried `shared`. Whichever body the co-import kept, this rests on
a project `sorry` and must read `verified`, never `transitively-verified`. -/
theorem caller : True := shared

/-- The same, as a private declaration: `check-axioms` lists it under its raw name
`_private.Merge.Use.0.privCaller`, the artifact publishes it as `privCaller`, and
`check-status-consistency.py` must match the two. -/
private theorem privCaller : True := shared
