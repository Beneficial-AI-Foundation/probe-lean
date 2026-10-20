import Step.Stub

open Aeneas.Std.WP

/-! One shape per primary-spec rule. The proofs are `trivial` because the stub
statement is `True`. -/

-- Rule 4: the spec lives in another namespace, and two step theorems have the
-- program `Fx.Ns.mont_mul`. Expected primary spec: `Props.mont_mul.spec`.
namespace Fx.Ns
def mont_mul (a b : Nat) : Option Nat := some (a * b)
end Fx.Ns

namespace Props
@[step] theorem mont_mul.spec (a b : Nat) :
    spec (Fx.Ns.mont_mul a b) (fun r => r = a * b) := trivial
@[step] theorem mont_mul_bound (a b : Nat) (_h : a < 10) :
    spec (Fx.Ns.mont_mul a b) (fun r => r ≤ 10 * b) := trivial
end Props

namespace Step

-- Rule 2 with the program head: the postcondition of `to_edwards_spec` names
-- `invert`, but its program is `to_edwards` (#132).
def invert (x : Nat) : Option Nat := some x
def to_edwards (x : Nat) : Option Nat := invert x
@[step] theorem invert_correct (x : Nat) : spec (invert x) (fun r => r = x) := trivial
@[step] theorem to_edwards_spec (x : Nat) :
    spec (to_edwards x) (fun r => invert x = some r) := trivial

-- #129: the only tagged candidate of `lfactor` is about `part1`. Expected primary
-- spec of `lfactor`: `lfactor_spec`, by rule 3.
def lfactor : Nat := 5
def part1 (x : Nat) : Option Nat := some (x * lfactor)
@[step] theorem part1_spec (x : Nat) : spec (part1 x) (fun r => r = x * lfactor) := trivial
theorem lfactor_spec : lfactor = 5 := rfl

-- `@[local step]` counts as `step` (#133).
def chi_row (x : Nat) : Option Nat := some x
@[local step] theorem chi_row_correct (x : Nat) : spec (chi_row x) (fun r => r = x) := trivial
theorem chi_row_bound (x : Nat) (_h : x < 5) : spec (chi_row x) (fun r => r < 5) := trivial

-- Rule 3 with `<T>.spec`: two step theorems with the program `append`.
def append (x : Nat) : Option Nat := some x
@[step] theorem append.spec (x : Nat) : spec (append x) (fun r => r = x) := trivial
@[step] theorem append_aux_spec (x : Nat) : spec (append x) (fun r => x ≤ r) := trivial

-- An axiom spec and its companion (#132 follow-up). The companion `X.mvcgen_spec` of
-- an axiom is a spec source, and in Aeneas it shares the `@[step]` of its parent. It
-- is tagged here by hand. Its statement is not in `WP.spec` form, so it takes the head
-- of the axiom: `to_slice`. Expected: `hkdf` gets no primary spec, `to_slice` gets
-- the companion.
def hkdf (x : Nat) : Nat := x
def to_slice (x : Nat) : Option Nat := some (hkdf x)
def to_vec (x : Nat) : Option Nat := some (hkdf x)
@[step] axiom to_slice_spec (x : Nat) : spec (to_slice x) (fun r => r = hkdf x)
@[step] theorem to_slice_spec.mvcgen_spec (x : Nat) : to_slice x = some (hkdf x) := rfl
@[step] theorem to_vec_spec (x : Nat) : spec (to_vec x) (fun r => r = hkdf x) := trivial

end Step
