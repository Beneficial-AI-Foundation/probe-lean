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

/-
@[externally_verified]
-/
/-- A commented-out tag in the block comment just above (the way one removes trust
temporarily). The scan lexes the file from the top, so the comment's content is not a
pure attribute line: `unverified`. -/
theorem commentedOutTag : (0 : Nat) < 5 := by sorry

/-!
Range-sharers. A one-line `structure … deriving …` puts the structure, its derived
instance and its projection on the same declaration range, so all three *show* the
structure's scanned `@[externally_verified]` in `attributes`. Only the structure is
named on that line, so only the structure is trusted; the instance, which rests on
a project `sorry`, must not become a trusted leaf that shields its callers.
-/

/-- A field type whose `Repr` instance is a project `sorry`. -/
structure Payload where
  v : Nat

/-- `unverified`: the `sorry` the derived instance below rests on. -/
instance : Repr Payload := ⟨fun _ _ => sorry⟩

/-- Tagged, one line: the structure is `trusted`. Its derived `instReprTagged` shares
the range and shows the tag, but rests on the sorried `Repr Payload`: `verified`. -/
@[externally_verified] structure Tagged where p : Payload deriving Repr

/-- Renders through the derived instance: `verified`, never `transitively-verified`. -/
def showTagged (t : Tagged) : String := reprStr t
