import Merge.Good

/-- A caller in a *submodule* of `Merge.Good`, so that `--module Merge.Good` selects it
together with `Merge.Good` but not `Merge.Bad`, which owns `shared` in the merged
environment. `shared` is then an atom emitted from `Merge.Good`, and this caller's edge
to it must be a project edge (`term-dependencies`), not an `*-external` one. -/
theorem callerSub : True := shared
