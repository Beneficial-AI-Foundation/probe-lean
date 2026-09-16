import Demo.Attr

/-- A sorried lemma a human vouches for. Rule 2 of the trusted base: `trusted`,
reason `externally_verified`, found by the source scan (the tag is the target's own
registration, invisible to probe-lean's handle lookup). -/
@[externally_verified]
step_theorem vouched : (0 : Nat) < 5 := by sorry

/-- Rests on a `sorry` only through the trusted `vouched`: clean modulo the trusted
base, so `transitively-verified`. -/
theorem viaVouched : (0 : Nat) < 5 := vouched
