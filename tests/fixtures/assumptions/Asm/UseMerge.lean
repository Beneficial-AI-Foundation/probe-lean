import Asm.MergeAx

/-- Built against the project axiom `h1`: `["h1"]`. -/
theorem useH1 : True := h1

/-- Built against the project theorem `h2`, which has an axiom version: `["h2"]`. -/
theorem useH2 : True := h2

/-- Built against the project axiom `h3`: `["h3", "sorryAx"]`. -/
theorem useH3 : True := h3
