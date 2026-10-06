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

    `memo` holds only *finalised* answers. A node can be on the DFS path or wait in
    an unfinished strongly connected component. Such a node sits in `onStack` with
    its DFS index and has no memo entry yet. This avoids the old scheme's bug (issue #103), which
    memoized a frame's result while a back-edge into it was still suppressed. -/
structure ReachState where
  memo    : Std.HashMap Name Bool := {}
  onStack : Std.HashMap Name Nat := {}
  stack   : Array Name := #[]
  next    : Nat := 0

/-- Pop the SCC stack down to and including `c`, finalising every popped node with
    `res`. Everything above `c` was pushed inside `c`'s DFS subtree. It reaches a
    node on the current DFS path at or below `c` (Tarjan's stack invariant), so it
    shares `c`'s answer. If `c` reaches the target, so does everything above it. If
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

    Returns `(reaches, lowlink)`. `lowlink` is the smallest DFS index among the
    nodes still on the stack that this frame's subtree reached through a back-edge.
    It is `none` when the frame finalised itself. The order of the tests matters for correctness:

    1. finalised memo: decided.
    2. on the stack: a back-edge. It contributes `false` and its index as lowlink.
    3. `c == target`: reached. This test comes **before** the blocked test, so a
       blocked node that *is* the target still counts (`sorryAx` lives outside every
       project).
    4. `blocked c`: a leaf. Memoised `false`, never expanded (neither type nor value).
    5. otherwise: expand the children, stopping at the first `true`.

    A frame that found the target finalises its whole stack segment as `true`. A
    frame that is its own SCC root (`lowlink == index`) finalises the component as
    `false`. Any other frame stays on the stack for its SCC root to decide, so no
    answer computed across a suppressed back-edge is ever memoised.

    The DFS is recursive. A single dependency chain of about 8k constants overflowed
    the *interpreter* stack in a `lake env lean --run` test script. The compiled
    binary has a larger stack, and real dependency chains are far shallower. -/
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
    node. All roots share one state. Each root's visit leaves the stack empty, so
    every root's answer is finalised. -/
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

namespace UsedConstantsImpl

unsafe structure State where
  visited       : PtrSet Expr := mkPtrSet
  visitedConsts : NameHashSet := {}

/-- `Expr.FoldConstsImpl.fold` as Lean 4.34 writes it: the `.proj` case records the
    structure name as well as visiting the operand. The DAG traversal (pointer-keyed
    `visited`, one callback per constant) is the same, so the cost is that of
    `getUsedConstants`. -/
unsafe def fold (f : Name → α → α) (e : Expr) (acc : α) : StateM State α :=
  let visitConst (c : Name) (acc : α) : StateM State α := do
    if (← get).visitedConsts.contains c then
      return acc
    modify fun s => { s with visitedConsts := s.visitedConsts.insert c }
    return f c acc
  let rec visit (e : Expr) (acc : α) : StateM State α := do
    if (← get).visited.contains e then
      return acc
    modify fun s => { s with visited := s.visited.insert e }
    match e with
    | .forallE _ d b _   => visit b (← visit d acc)
    | .lam _ d b _       => visit b (← visit d acc)
    | .mdata _ b         => visit b acc
    | .letE _ t v b _    => visit b (← visit v (← visit t acc))
    | .app f a           => visit a (← visit f acc)
    | .proj typeName _ b => visit b (← visitConst typeName acc)
    | .const c _         => visitConst c acc
    | _ => return acc
  visit e acc

@[inline] unsafe def usedConstantsUnsafe (e : Expr) : Array Name :=
  (fold (fun c cs => cs.push c) e #[]).run' {}

end UsedConstantsImpl

/-- The constants `e` uses, each once, **`Expr.proj` structure names included**.
    `Expr.getUsedConstants` on Lean ≤ 4.33 visits a projection's operand and drops its
    structure name (`| .proj _ _ b => visit b acc`). Lean 4.34 counts the structure
    (`visitConst typeName`). The kernel needs the structure's constructor to type a
    projection, so the edge is real. When the operand is a blocked constant, it is
    the *only* edge to the structure. For example, take a trusted `axiom x : S` whose
    `S` constructor rests on `sorry`. Without this edge, `theorem t : P := x.1` read
    clean on the pinned toolchain. (`Lean.collectAxioms`, unblocked, recovers `S`
    through `x`'s type and cannot show the difference.) Only the taint walk uses this
    (`constChildren`). The emitted graph (`Analysis.getDependencies` and the auxiliary
    fold's `constChildrenEmitted`) keeps `getUsedConstants`, so the output arrays do
    not depend on this. -/
@[implemented_by UsedConstantsImpl.usedConstantsUnsafe]
opaque usedConstants (e : Expr) : Array Name

/-- The constants directly used in `c`'s type and value (and constructors, for an
    inductive). These are the out-edges of the transitive closure. `used` collects
    the constants of one expression. The match is exhaustive over `ConstantInfo` on
    purpose: if Lean ever adds a constructor, this fails to compile rather than
    silently under-reporting axioms. Reads the value fields directly, so the Lean
    4.30 `ConstantInfo.value?` default change does not apply. Mirrors
    `Lean.collectAxioms`. It takes the `ConstantInfo` itself, so the walk can also
    cover a version of a constant that the environment did *not* keep. An example
    is a co-import duplicate read from its module's olean. -/
def constInfoChildrenWith (used : Expr → Array Name) : ConstantInfo → Array Name
  | .axiomInfo v  => used v.type
  | .defnInfo v   => used v.type ++ used v.value
  | .thmInfo v    => used v.type ++ used v.value
  | .opaqueInfo v => used v.type ++ used v.value
  | .ctorInfo v   => used v.type
  | .recInfo v    => used v.type
  | .inductInfo v => used v.type ++ v.ctors.toArray
  | .quotInfo _   => #[]

/-- The taint walk's out-edges: `constInfoChildrenWith usedConstants`, projection
    structure names included on every supported toolchain. -/
def constInfoChildren : ConstantInfo → Array Name :=
  constInfoChildrenWith usedConstants

/-- `constInfoChildren` of the constant the environment holds under `c`. -/
def constChildren (env : Environment) (c : Name) : Array Name :=
  match env.find? c with
  | some ci => constInfoChildren ci
  | none    => #[]

/-- The emitted graph's out-edges: `constInfoChildrenWith Expr.getUsedConstants`, the
    same collector `Analysis.getDependencies` uses for an atom's direct edges. The
    auxiliary fold traverses with this one (`Analysis.FoldWalk.ofEnv`). What it
    recovers into `term-dependencies` then comes from the same edge set as the direct
    arrays, whatever the toolchain's `getUsedConstants` does with projections. -/
def constChildrenEmitted (env : Environment) (c : Name) : Array Name :=
  match env.find? c with
  | some ci => constInfoChildrenWith Expr.getUsedConstants ci
  | none    => #[]

/-- The out-edges of a trusted constant: the constants of its statement, never of its
    value. For an inductive, the statement includes its constructors, because their
    types hold the field types. So a trusted structure whose field type rests on
    `sorry` is tainted, and so is a raw projection (`x.1`) out of a value of it. A
    trusted constructor in turn contributes only its own type. -/
def statementChildren (env : Environment) (c : Name) : Array Name :=
  match env.find? c with
  | some (.inductInfo v) => usedConstants v.type ++ v.ctors.toArray
  | some ci => usedConstants ci.type
  | none => #[]

/-- Result of the project-boundary taint walk. -/
structure TaintResult where
  /-- Project constants that are **not clean modulo T**: `sorryAx` is reachable from
      them over the walk's edges. A trusted constant is tainted if its statement
      reaches `sorryAx`: trust excuses its proof, not its statement. -/
  tainted : Std.HashSet Name
  /-- Project constants whose walk edges name `sorryAx`. For an untrusted constant
      these are its type and value, for a trusted one only its statement
      (`statementChildren`). A vouched lemma (trusted, `sorry` in the proof only) is
      therefore not a direct carrier. -/
  direct : Std.HashSet Name

/-- The walk `extract` and `check-axioms` share. `roots` is P, the project's
    constants. Children outside P are blocked: dependency packages are trusted
    wholesale. `sorryAx` itself lives outside every project, but the walk still
    recognises it because the target test precedes the blocked test.

    A trusted root (`trusted`) has its statement as its only out-edges
    (`statementChildren`). The trusted-base decision excuses its proof but not its
    statement, so a `sorry` behind the statement still taints it and its callers.

    `childrenOverride` replaces the environment's out-edges for the untrusted names
    it holds. The caller uses it for a name that several project modules declare
    (the importer kept one version). The walk then follows the union of every
    version's dependencies, and the proof that survived cannot steer it clean. A
    trusted name ignores it: the importer merges versions only if their types are
    equal, so the kept type is every version's statement. -/
def projectTaint (env : Environment) (isProject trusted : Name → Bool)
    (roots : Array Name) (childrenOverride : Std.HashMap Name (Array Name) := {})
    : TaintResult :=
  let blocked (n : Name) : Bool := !isProject n
  -- `getUsedConstants` over every root's type and value is the dominant cost of
  -- the pass (about a second on dalek), and both the walk and the direct-carrier
  -- test need it, so compute it once. Only unblocked nodes are ever expanded, and
  -- with `roots = P` those are all roots; a non-root falls back to `constChildren`.
  let childrenOf : Std.HashMap Name (Array Name) := roots.foldl (init := {}) fun m r =>
    if trusted r then m.insert r (statementChildren env r)
    else
      m.insert r (childrenOverride.getD r (constChildren env r))
  let children (n : Name) : Array Name :=
    match childrenOf[n]? with
    | some cs => cs
    | none => constChildren env n
  let tainted := reachingNames children blocked sorryAxiomName roots
  let direct := roots.foldl (init := ({} : Std.HashSet Name)) fun acc r =>
    if (children r).contains sorryAxiomName then acc.insert r else acc
  { tainted, direct }

end ProbeLean
