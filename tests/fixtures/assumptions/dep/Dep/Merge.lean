/-- Merged with the project axiom `h1` (`Asm.MergeAx`). The project version is an
axiom, so `h1` is in its own set and in the set of each caller. -/
theorem h1 : True := True.intro

/-- Merged with the project theorem `h2` (`Asm.MergeAx`). Lean keeps the theorem, and
this axiom version still puts `h2` in its own set. -/
axiom h2 : True

/-- Merged with the project axiom `h3` (`Asm.MergeAx`). Its `sorry` is outside P, so
trust does not excuse it. -/
theorem h3 : True := sorry
