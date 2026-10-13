import Merge.FixAdd

/-- A caller in a submodule of `Merge.FixAdd`, so that `--module Merge.FixAdd` selects
it but not `Merge.FixRestate`. That run does not emit `Merge.Fix.mutual`, and no
`partial_fixpoint` block made it, so the edge must stay. -/
theorem fixCallerAdd : True := Merge.Fix.«mutual»
