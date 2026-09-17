import Demo.Attr

/-- A sorried lemma a human vouches for. Rule 2 of the trusted base: `trusted`,
reason `externally_verified`, read from the tag set the target's own registration
(`Demo.Attr`) stored in the olean — invisible to probe-lean's handle lookup, found by
the static tag-set reader. -/
@[externally_verified]
step_theorem vouched : (0 : Nat) < 5 := by sorry

/-- Rests on a `sorry` only through the trusted `vouched`: clean modulo the trusted
base, so `transitively-verified`. -/
theorem viaVouched : (0 : Nat) < 5 := vouched

/-!
Fabricated-trust shapes. Rule 2 is membership in the tag set, so a
`@[externally_verified]` that is *not* the declaration's own annotation must never
make it trusted, and the source scan that fills `attributes` must not show it either.
Each of the declarations below is a plain `sorry` and must read `unverified`.
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

/-!
Round 3 (2026-09-17): shapes the source scan got wrong. Rule 2 now reads the tag set
from the environment (`ProbeLean/TagSet.lean`), so none of these can fabricate trust;
the scan stays for the informative `attributes` array and for the tag audit that
prints `Divergence(tag):` where it would have differed.
-/

/-- A type whose `Inhabited` instance is a project `sorry`. -/
inductive Cell | mk

/-- `unverified`: the sorry the derived instance below rests on. -/
instance : Inhabited Cell := sorry

/-- Tagged, one line, with a field named like a generated helper. Lean derives
`instInhabitedBox` **and** `instInhabitedBox.default`; both share this range, the
helper is neither a projection nor internal, and its name ends in the field's name,
so the head-line rule named it and the scan would have trusted it (`Divergence(tag)`
is printed for it). Only `Box` is in the tag set: `Box` is `trusted`, the helper and
the instance are `verified`. -/
@[externally_verified] structure Box where default : Cell deriving Inhabited

/-- Through the derived instance: `verified`. -/
def defaultBox : Box := default

/-- The inner string literal of the interpolation used to be lexed as code, which put
`@[externally_verified]` on this head line: `unverified`, and no tag shown. -/
def interpolationVictim : String := s!"{(sorry : String)} {"@[externally_verified]"}"

-- Two commands on one line share the line range: `endorsed` is `trusted`; `victim`
-- is `unverified` — the line-based scan shows it `endorsed`'s tag (cosmetic, in
-- `attributes` only), the tag set does not contain it, and the tag audit prints a
-- `Divergence(tag)` line for it.
@[externally_verified] theorem endorsed : True := True.intro theorem victim : (0 : Nat) < 5 := by sorry

/-- A syntax quotation whose last line but one is a pure attribute line; the old
two-line look-back read it as `victim2`'s. `quoted` itself is clean. -/
def quoted : Lean.MacroM Lean.Syntax := `(declModifiers|
@[externally_verified]
)
/-- `unverified`, no tag shown. -/
theorem victim2 : (0 : Nat) < 5 := by sorry

/-- Tagged after the fact: a tag is a tag, so `trusted`, reason `externally_verified`,
with a `Note(tag):` line because the header does not show it. -/
theorem laterVouched : (0 : Nat) < 5 := by sorry
attribute [externally_verified] laterVouched

namespace Deep
/-- Declared with `_root_.` inside a namespace: in the tag set, `trusted`, and the
head-line token `_root_.rootVouched` matches after the prefix is dropped, so no
`Divergence(tag)` is printed for it. -/
@[externally_verified] theorem _root_.rootVouched : (0 : Nat) < 5 := by sorry
end Deep
