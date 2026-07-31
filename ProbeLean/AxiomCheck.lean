/-
  Kernel-level `sorry` detection via transitive axiom reachability.

  `sorry` compiles to the `sorryAx` axiom, so a declaration rests on an unproven
  placeholder iff `sorryAx` is reachable in its transitive closure (type + value of
  every used constant, generated code included — recursors, instances, projections,
  everything). This mirrors `Lean.collectAxioms` but is specialized to a single
  reachability question and works from an `Environment` value directly (so callers
  in plain `IO` don't need a `MonadEnv` monad), with a shared memo so a whole project
  can be audited in roughly one pass over the dependency graph rather than
  re-walking each declaration's closure.

  It never prunes generated constants, so it is immune to whatever probe-lean's
  extraction chooses to emit or drop — the independent ground truth for cross-checking
  that no atom marked `transitively-verified` actually depends on a `sorry`.

  The reachability core is generic over a `children` function, so its memo/cycle
  handling is unit-testable with a fabricated graph (see `Tests`); the `Environment`
  is only a thin `constChildren` adapter.
-/
import Lean

namespace ProbeLean

open Lean

/-- The axiom `sorry` elaborates to. -/
def sorryAxiomName : Name := `sorryAx

/-- Memoized reachability: can `c` reach `target` following `children` edges?
    Memo entries: `some b` decided, `none` on the DFS stack — a cyclic back-edge
    contributes `false`, which is correct because a reachable node always has an
    acyclic path to it. Pure, so it is unit-testable with a fabricated `children`. -/
private partial def reachesAux (children : Name → Array Name) (target c : Name) :
    StateM (Std.HashMap Name (Option Bool)) Bool := do
  match (← get).get? c with
  | some (some b) => return b
  | some none     => return false
  | none =>
    if c == target then
      modify (·.insert c (some true)); return true
    modify (·.insert c none)
    let mut res := false
    for ch in children c do
      unless res do
        if ← reachesAux children target ch then res := true
    modify (·.insert c (some res))
    return res

/-- Of `roots`, the subset that can reach `target`. One shared memo across all roots. -/
def reachingNames (children : Name → Array Name) (target : Name) (roots : Array Name) :
    Std.HashSet Name := Id.run do
  let mut memo : Std.HashMap Name (Option Bool) := {}
  let mut out : Std.HashSet Name := {}
  for r in roots do
    let (b, memo') := (reachesAux children target r).run memo
    memo := memo'
    if b then out := out.insert r
  return out

/-- Whether a single `root` can reach `target`. -/
def reaches (children : Name → Array Name) (target root : Name) : Bool :=
  (reachesAux children target root).run' {}

/-- The constants directly used in `c`'s type and value (and constructors, for an
    inductive) — the out-edges of the transitive closure. The match is exhaustive
    over `ConstantInfo` on purpose: if Lean ever adds a constructor, this fails to
    compile rather than silently under-reporting axioms. Mirrors `Lean.collectAxioms`. -/
def constChildren (env : Environment) (c : Name) : Array Name :=
  match env.find? c with
  | some (.axiomInfo v)  => v.type.getUsedConstants
  | some (.defnInfo v)   => v.type.getUsedConstants ++ v.value.getUsedConstants
  | some (.thmInfo v)    => v.type.getUsedConstants ++ v.value.getUsedConstants
  | some (.opaqueInfo v) => v.type.getUsedConstants ++ v.value.getUsedConstants
  | some (.ctorInfo v)   => v.type.getUsedConstants
  | some (.recInfo v)    => v.type.getUsedConstants
  | some (.inductInfo v) => v.type.getUsedConstants ++ v.ctors.toArray
  | some (.quotInfo _)   => #[]
  | none                 => #[]

/-- Of `roots`, the subset whose transitive closure reaches `sorryAx`. -/
def sorryReachingNames (env : Environment) (roots : Array Name) : Std.HashSet Name :=
  reachingNames (constChildren env) sorryAxiomName roots

/-- Whether `name`'s transitive closure reaches `sorryAx`. -/
def dependsOnSorryAxIn (env : Environment) (name : Name) : Bool :=
  reaches (constChildren env) sorryAxiomName name

end ProbeLean
