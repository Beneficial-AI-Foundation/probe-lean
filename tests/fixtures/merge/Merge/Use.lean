import Merge.Bad

/-- Built against the sorried `shared`. Whichever body the co-import kept, this rests on
a project `sorry` and must read `verified`, never `transitively-verified`. -/
theorem caller : True := shared
