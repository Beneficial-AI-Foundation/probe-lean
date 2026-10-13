/-!
Generated `partial_fixpoint` bodies (issue #135). For a mutual pair, and for a single
function whose fixed parameters are not a prefix, Lean compiles the body into a
constant `f.mutual` with no declaration range, and `f` references only that constant.
`extract` never emits `f.mutual` as an atom, so it drops the direct edge and lists the
callees that the fold finds under it.
-/

def fpHelper (n : Nat) : Option Nat := some n
def fpOther (n : Nat) : Option Nat := some (n + 1)

/-- Control: the fixed parameter is a prefix, so Lean creates no `fpLoop2.mutual`. -/
def fpLoop2 (fixed : Nat) (n : Nat) : Option Nat :=
  if n == 0 then fpHelper fixed else if n == 1 then fpOther fixed else fpLoop2 fixed (n - 2)
partial_fixpoint

/-- The fixed parameter is not a prefix: Lean creates `fpLoop.mutual`. -/
def fpLoop (n : Nat) (fixed : Nat) : Option Nat :=
  if n == 0 then fpHelper fixed else if n == 1 then fpOther fixed else fpLoop (n - 2) fixed
partial_fixpoint

mutual
def fpEv (n : Nat) : Option Nat := if n == 0 then fpHelper 0 else fpOd (n - 1)
partial_fixpoint
def fpOd (n : Nat) : Option Nat := if n == 0 then fpOther 1 else fpEv (n - 1)
partial_fixpoint
end

/-- A statement that names the generated body. -/
theorem fpEv_mutual_type : fpEv.mutual = fpEv.mutual := rfl

/-- A hand-written `.mutual` name: it has a range, so it is an atom and an edge. -/
def Demo.User.«mutual» : Option Nat := fpHelper 2

theorem user_mutual_some : Demo.User.«mutual» = some 2 := rfl
