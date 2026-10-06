/-!
Statement taint (#119). Trust excuses a declaration's proof, not its statement. The
walk follows the statement of a trusted constant, so a `sorry` behind it taints the
constant and every caller, also a caller whose every path goes through trusted
axioms.
-/

/-- A proposition whose meaning is a project `sorry`: `unverified`. -/
def stmtP : Prop := sorry

/-- Trusted by rule 1, but its statement rests on `stmtP`: `verified`, `kernel-taint`,
no `trusted-reason`. -/
axiom stmtAx : stmtP

/-- The same for a statement that only mentions `stmtP`. -/
axiom stmtUse : stmtP → True

/-- Names neither `stmtP` nor a `sorry`: both paths go through trusted axioms.
`verified`, `kernel-taint`. -/
theorem stmtCaller : True := stmtUse stmtAx

/-- Trusted by rule 1, and its statement names `sorry` itself: `unverified`. -/
axiom stmtLit : (sorry : Prop)

/-- Trusted with a clean statement: stays `trusted`. -/
axiom stmtClean : (0 : Nat) < 5

/-- Rests only on `stmtClean`: `transitively-verified`. -/
theorem viaStmtClean : (0 : Nat) < 5 := stmtClean
