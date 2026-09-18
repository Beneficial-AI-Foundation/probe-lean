/-
  Kernel-level `sorry` detection via transitive axiom reachability.

  `sorry` compiles to the `sorryAx` axiom, so a declaration rests on an unproven
  placeholder iff `sorryAx` is reachable in its transitive closure (type + value of
  every used constant, generated code included — recursors, instances, projections,
  everything). This mirrors `Lean.collectAxioms` but is specialized to a single
  reachability question, works from an `Environment` value directly (so callers in
  plain `IO` don't need a `MonadEnv` monad), takes a *blocked* set whose members are
  never expanded, and shares one memo across roots so a whole project is audited in
  one pass over the dependency graph rather than by re-walking each closure.

  It never prunes generated constants, so it is immune to whatever probe-lean's
  extraction chooses to emit or drop — `extract` decides `verification-status` from
  it (see `Taint`), and `check-axioms` reports the same set.

  The reachability core is generic over a `children` function, so its memo/cycle
  handling is unit-testable with a fabricated graph (see `Tests`); the `Environment`
  is only a thin `constChildren` adapter.
-/
import Lean

namespace ProbeLean

open Lean

/-- The axiom `sorry` elaborates to. -/
def sorryAxiomName : Name := `sorryAx

/-- Traversal state shared across roots.

    `memo` holds only *finalised* answers. A node on the DFS path or waiting in an
    unfinished strongly connected component sits in `onStack` with its DFS index and
    has no memo entry yet — the scheme that memoized a frame's result while a
    back-edge into it was still suppressed (issue #103) is exactly what this avoids. -/
structure ReachState where
  memo    : Std.HashMap Name Bool := {}
  onStack : Std.HashMap Name Nat := {}
  stack   : Array Name := #[]
  next    : Nat := 0

/-- Pop the SCC stack down to and including `c`, finalising every popped node with
    `res`. Everything above `c` was pushed inside `c`'s DFS subtree and reaches a
    node on the current DFS path at or below `c` (Tarjan's stack invariant), so it
    shares `c`'s answer: if `c` reaches the target so does everything above it; if
    `c` is an SCC root that does not, neither does its component. -/
private def finalizeFrom (c : Name) (res : Bool) : StateM ReachState Unit := do
  -- Take the fields out and release the record before mutating. With the record
  -- `s` still referenced (and the state monad holding its own copy), the first
  -- `insert`/`erase`/`pop` of every finalisation detached the whole container —
  -- one copy per SCC, so the walk was quadratic in |P| (964 ms → 12 ms on a
  -- 15k-constant project). The `set {}` is material: destructuring alone keeps
  -- the monad's reference alive.
  let ⟨memo₀, onStack₀, stack₀, next⟩ ← get
  set ({} : ReachState)
  let mut stack := stack₀
  let mut memo := memo₀
  let mut onStack := onStack₀
  let mut go := true
  while go do
    match stack.back? with
    | none => go := false
    | some top =>
      stack := stack.pop
      memo := memo.insert top res
      onStack := onStack.erase top
      if top == c then go := false
  set ({ memo, onStack, stack, next } : ReachState)

/-- Memoized reachability with Tarjan-style SCC finalisation.

    Returns `(reaches, lowlink)`; `lowlink` is the smallest DFS index of a node still
    on the stack that this frame's subtree reached through a back-edge (`none` when
    the frame finalised itself). Test order is load-bearing:

    1. finalised memo — decided;
    2. on the stack — a back-edge: contributes `false` and its index as lowlink;
    3. `c == target` — reached, **before** the blocked test, so a blocked node that
       *is* the target still counts (`sorryAx` lives outside every project);
    4. `blocked c` — a leaf: memoised `false`, never expanded (neither type nor value);
    5. otherwise expand the children, stopping at the first `true`.

    A frame that found the target finalises its whole stack segment as `true`. A
    frame that is its own SCC root (`lowlink == index`) finalises the component as
    `false`. Any other frame stays on the stack for its SCC root to decide, so no
    answer computed across a suppressed back-edge is ever memoised.

    The DFS is recursive: a single dependency chain of ~8k constants overflowed the
    *interpreter* stack in a `lake env lean --run` harness; the compiled binary has a
    larger stack and real dependency chains are far shallower. -/
private partial def visit (children : Name → Array Name) (blocked : Name → Bool)
    (target c : Name) : StateM ReachState (Bool × Option Nat) := do
  if let some b := (← get).memo[c]? then
    return (b, none)
  if let some i := (← get).onStack[c]? then
    return (false, some i)
  if c == target then
    modify fun s => { s with memo := s.memo.insert c true }
    return (true, none)
  if blocked c then
    modify fun s => { s with memo := s.memo.insert c false }
    return (false, none)
  let idx := (← get).next
  modify fun s => { s with
    next := s.next + 1
    onStack := s.onStack.insert c idx
    stack := s.stack.push c }
  let mut res := false
  let mut low := idx
  for ch in children c do
    if res then break
    let (r, l) ← visit children blocked target ch
    if r then res := true
    if let some l := l then low := min low l
  if res then
    finalizeFrom c true
    return (true, none)
  if low == idx then
    finalizeFrom c false
    return (false, none)
  return (false, some low)

/-- Of `roots`, the subset that can reach `target` without expanding a `blocked`
    node. One shared state across all roots; each root's visit leaves the stack
    empty, so every root's answer is finalised. -/
def reachingNames (children : Name → Array Name) (blocked : Name → Bool) (target : Name)
    (roots : Array Name) : Std.HashSet Name := Id.run do
  let mut st : ReachState := {}
  let mut out : Std.HashSet Name := {}
  for r in roots do
    let ((b, _), st') := (visit children blocked target r).run st
    st := st'
    if b then out := out.insert r
  return out

/-- Whether a single `root` can reach `target` without expanding a `blocked` node. -/
def reaches (children : Name → Array Name) (blocked : Name → Bool) (target root : Name) : Bool :=
  ((visit children blocked target root).run' {}).1

/-- The constants directly used in `c`'s type and value (and constructors, for an
    inductive) — the out-edges of the transitive closure. The match is exhaustive
    over `ConstantInfo` on purpose: if Lean ever adds a constructor, this fails to
    compile rather than silently under-reporting axioms. Reads the value fields
    directly, so the Lean 4.30 `ConstantInfo.value?` default change does not apply.
    Mirrors `Lean.collectAxioms`. Takes the `ConstantInfo` itself so a version of
    a constant the environment did *not* keep (a co-import duplicate read from its
    module's olean) can be walked too. -/
def constInfoChildren : ConstantInfo → Array Name
  | .axiomInfo v  => v.type.getUsedConstants
  | .defnInfo v   => v.type.getUsedConstants ++ v.value.getUsedConstants
  | .thmInfo v    => v.type.getUsedConstants ++ v.value.getUsedConstants
  | .opaqueInfo v => v.type.getUsedConstants ++ v.value.getUsedConstants
  | .ctorInfo v   => v.type.getUsedConstants
  | .recInfo v    => v.type.getUsedConstants
  | .inductInfo v => v.type.getUsedConstants ++ v.ctors.toArray
  | .quotInfo _   => #[]

/-- `constInfoChildren` of the constant the environment holds under `c`. -/
def constChildren (env : Environment) (c : Name) : Array Name :=
  match env.find? c with
  | some ci => constInfoChildren ci
  | none    => #[]

/-- Whether `c`'s *type* (its statement) names `sorryAx`. -/
def typeNamesSorry (env : Environment) (c : Name) : Bool :=
  match env.find? c with
  | some ci => ci.type.getUsedConstants.contains sorryAxiomName
  | none => false

/-- Result of the project-boundary taint walk. -/
structure TaintResult where
  /-- Project constants that are **not clean modulo T**: `sorryAx` is reachable from
      them without expanding a non-project or trusted constant. Disjoint from the
      trusted set by construction (trusted roots are blocked, hence never reach). -/
  tainted : Std.HashSet Name
  /-- Project constants whose own type or value names `sorryAx` — trusted ones
      included (a trusted direct carrier is the intended human-vouches case). -/
  direct : Std.HashSet Name
  /-- Trusted constants whose *statement* names `sorryAx`: their meaning is unknown,
      which the caller reports as a warning. Sorted by name. -/
  typeTainted : Array Name

/-- The walk `extract` and `check-axioms` share. `roots` is P, the project's
    constants; children outside P or in T (`trusted`) are blocked — taken as leaves
    by the trusted-base decision — while `sorryAx` itself, which lives outside every
    project, is still recognised because the target test precedes the blocked test.

    `childrenOverride` replaces the environment's out-edges for the names it holds:
    the caller uses it for a name several project modules declare (the importer
    kept one version), so that the walk follows the union of every version's
    dependencies and cannot be steered clean by whichever proof survived. -/
def projectTaint (env : Environment) (isProject trusted : Name → Bool)
    (roots : Array Name) (childrenOverride : Std.HashMap Name (Array Name) := {})
    : TaintResult :=
  let blocked (n : Name) : Bool := !isProject n || trusted n
  -- `getUsedConstants` over every root's type and value is the dominant cost of
  -- the pass (about a second on dalek), and both the walk and the direct-carrier
  -- test need it, so compute it once. Only unblocked nodes are ever expanded, and
  -- with `roots = P` those are all roots; a non-root falls back to `constChildren`.
  let childrenOf : Std.HashMap Name (Array Name) := roots.foldl (init := {}) fun m r =>
    m.insert r (childrenOverride.getD r (constChildren env r))
  let children (n : Name) : Array Name :=
    match childrenOf[n]? with
    | some cs => cs
    | none => constChildren env n
  let tainted := reachingNames children blocked sorryAxiomName roots
  let direct := roots.foldl (init := ({} : Std.HashSet Name)) fun acc r =>
    if (children r).contains sorryAxiomName then acc.insert r else acc
  let typeTainted := (roots.filter fun r => trusted r && typeNamesSorry env r).qsort
    fun a b => a.toString < b.toString
  { tainted, direct, typeTainted }

end ProbeLean
