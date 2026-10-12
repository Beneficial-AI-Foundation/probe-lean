import Merge.FixRestate

/-- A caller in a submodule of `Merge.FixRestate`, so that `--module Merge.FixRestate`
selects it but not `Merge.FixAdd`, which owns `Merge.Fix.mutual`. -/
theorem fixCallerSub : True := Merge.Fix.«mutual»
