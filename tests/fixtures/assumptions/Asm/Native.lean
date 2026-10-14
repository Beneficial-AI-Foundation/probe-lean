import Std.Tactic.BVDecide

/-! Compiled-code axioms. From Lean 4.31 on, each proof adds its own
`X._native.<tactic>.ax_N` axiom. Before, it rests on `Lean.ofReduceBool`, whose type
uses `Lean.reduceBool`, whose value uses `Lean.trustCompiler`. -/

theorem nd : 2 ^ 10 = 1024 := by native_decide

theorem dn : 3 * 7 = 21 := by decide +native

theorem bv (x y : BitVec 4) : (x &&& y) ||| (x ^^^ y) = x ||| y := by bv_decide
