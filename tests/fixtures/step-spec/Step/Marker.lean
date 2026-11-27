import Step.Stub
import Step.Attrs

open Aeneas.Std.WP

/-! The primary-spec docstring marker. This module docstring has the word
primary-spec, and it marks no declaration: a module docstring belongs to none. -/

namespace Marker

-- Rule 3 picks `double_spec`. The docstring of `double_correct` has the marker, and the
-- marker wins (rule 1).
def double (x : Nat) : Option Nat := some (2 * x)
theorem double_spec (x : Nat) : spec (double x) (fun r => r = 2 * x) := trivial
/-- The main spec of `double`. primary-spec -/
theorem double_correct (x : Nat) : spec (double x) (fun r => r = x + x) := trivial

-- Plain comments never mark. `square_bound` has two plain comments with the word, and
-- `square_aux` has the word inside a longer word. Rule 3 picks `square_spec`.
def square (x : Nat) : Option Nat := some (x * x)
theorem square_spec (x : Nat) : spec (square x) (fun r => r = x * x) := trivial
-- primary-spec
/- primary-spec -/
theorem square_bound (x : Nat) : spec (square x) (fun r => x ≤ r ∨ x = 0) := trivial
/-- Not the primary-specs of `square`. -/
theorem square_aux (x : Nat) : spec (square x) (fun r => r = x ^ 2) := trivial

-- Two marked theorems on one target: an arbitrary tie-break and a warning on stderr.
def twice (x : Nat) : Option Nat := some (x + x)
/-- primary-spec -/
theorem twice_a (x : Nat) : spec (twice x) (fun r => r = x + x) := trivial
/-- primary-spec -/
theorem twice_b (x : Nat) : spec (twice x) (fun r => r = 2 * x) := trivial

-- One tagged and one marked theorem on one target: the same tie-break and warning.
def quad (x : Nat) : Option Nat := some (4 * x)
@[primary_spec] theorem quad_tagged (x : Nat) : spec (quad x) (fun r => r = 4 * x) := trivial
/-- primary-spec -/
theorem quad_marked (x : Nat) : spec (quad x) (fun r => r = 2 * (2 * x)) := trivial

-- A theorem both tagged and marked counts once: it wins rule 1 with no warning.
def half (x : Nat) : Option Nat := some (x / 2)
theorem half_spec (x : Nat) : spec (half x) (fun r => r = x / 2) := trivial
/-- primary-spec -/
@[primary_spec] theorem half_both (x : Nat) : spec (half x) (fun r => 2 * r ≤ x) := trivial

-- A marked non-theorem: `is-primary-spec` is true, and nothing else changes.
/-- primary-spec -/
def marked_def (x : Nat) : Nat := x

-- An axiom spec and its companion, as in `Step.Funs`. The marker on the axiom does not
-- reach the companion, as a tag would not. The companion gets its own marker with
-- `add_decl_doc`. Rule 2 alone would also pick the companion, so `triple_spec` is a
-- second candidate that rule 2 cannot drop: it is tagged `step` and is about `triple`.
def triple (x : Nat) : Option Nat := some (3 * x)
/-- primary-spec -/
@[step] axiom triple_ax (x : Nat) : spec (triple x) (fun r => r = 3 * x)
@[step] theorem triple_ax.mvcgen_spec (x : Nat) : triple x = some (3 * x) := rfl
@[step] theorem triple_spec (x : Nat) : spec (triple x) (fun r => r = x + 2 * x) := trivial
/-- primary-spec -/
add_decl_doc triple_ax.mvcgen_spec

-- An inherited docstring counts: `cube_correct` has no docstring, tag or marker of its
-- own, and inherits the marked docstring of `cube_doc` with `@[inherit_doc]`. Rule 3
-- alone would pick `cube_spec`. `cube_doc` is about no target, so it changes nothing else.
/-- primary-spec -/
theorem cube_doc : True := trivial
def cube (x : Nat) : Option Nat := some (x * x * x)
theorem cube_spec (x : Nat) : spec (cube x) (fun r => r = x * x * x) := trivial
@[inherit_doc cube_doc]
theorem cube_correct (x : Nat) : spec (cube x) (fun r => r = x ^ 3) := trivial

end Marker
