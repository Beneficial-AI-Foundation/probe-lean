import Merge.Good

/-- Built against the proved `shared`. The merged environment cannot tell it apart
from `Merge.Use.caller`, so it reads `verified` too: the walk fails closed. -/
theorem callerGood : True := shared
