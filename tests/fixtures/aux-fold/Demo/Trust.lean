import Demo.Attr

/-- A sorried lemma a human vouches for. Rule 2 of the trusted base: `trusted`,
reason `externally_verified`, found by the source scan (the tag is the target's own
registration, invisible to probe-lean's handle lookup). -/
@[externally_verified]
step_theorem vouched : (0 : Nat) < 5 := by sorry

/-- Rests on a `sorry` only through the trusted `vouched`: clean modulo the trusted
base, so `transitively-verified`. -/
theorem viaVouched : (0 : Nat) < 5 := vouched

/-!
Fabricated-trust shapes. The source scan feeds rule 2, so a `@[externally_verified]`
that is *not* the declaration's own annotation must never make it trusted. Each of the
declarations below is a plain `sorry` and must read `unverified`.
-/

/-- Tagged, one line, directly above an untagged neighbour: `trusted`. -/
@[externally_verified] theorem taggedOneLiner : (0 : Nat) < 5 := by sorry
theorem neighbour : (0 : Nat) < 5 := by sorry

/-- Quotes the tag in its docstring and in a body comment — `@[externally_verified]`
is not on this declaration: `unverified`. -/
theorem docMention : (0 : Nat) < 5 := by
  -- not this one either: @[externally_verified]
  sorry
