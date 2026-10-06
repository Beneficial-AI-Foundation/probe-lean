module
import ModMerge.Good

/-- Built against the proved `shared`. The merged environment cannot tell it apart
from `ModMerge.Use.caller`, so it reads `verified` too: the walk fails closed. -/
public theorem callerGood : True := shared
