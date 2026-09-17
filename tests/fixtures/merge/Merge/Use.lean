import Merge.Bad

/-- Built against the sorried `shared`. Whichever body the co-import kept, this
must read `verified` (rests on a project `sorry`), never `transitively-verified`. -/
theorem caller : True := shared
