/-
  `verification-status` from the kernel taint pass, plus the graph-BFS it replaced.

  `applyTaintStatus` stamps every atom from `ProjectTaint` (see `Taint`). The
  reverse-BFS contamination (`enrichTransitiveVerification`, ported from probe's
  propagate.rs) is kept but no longer decides anything: `extract` runs it over the
  emitted graph and prints every atom on which it disagrees with the walk
  (`divergenceLines`) — a disagreement localises a node or edge the emitted graph is
  missing, which is exactly the signal that was absent when Lean 4.30 emptied the
  proof edges.
-/
import Lean
import ProbeLean.Types
import ProbeLean.Taint

namespace ProbeLean

open Lean

/-- The status the taint pass assigns to the constant `n`, with its `trusted-reason`.
    Per the spec's definitions: `trusted` if in T; else `unverified` if a direct
    carrier; else `verified` if an unexcused project `sorry` is reachable; else
    `transitively-verified`. `none` for a name outside P: the walk never assessed it,
    and absence from the analysis is not evidence of verification. -/
def taintVerdict (pt : ProjectTaint) (n : Name) : Option (Option String × WebVerificationStatus) :=
  if !pt.constants.contains n then none
  else some <| match pt.trust[n]? with
    | some reason => (some reason, .trusted)
    | none =>
      if pt.taint.direct.contains n then (none, .unverified)
      else if pt.taint.tainted.contains n then (none, .verified)
      else (none, .transitivelyVerified)

/-- Stamp `verification-status`/`trusted-reason` on every atom from the taint pass,
    joined on `leanName`. `applyTaint := false` (`--skip-verify`) stamps only the
    trusted atoms and leaves the rest without a status; `upgrade := false`
    (`--skip-enrich`) caps clean atoms at `verified`. Atoms whose name is not in P
    get no status at all and are returned by name so the caller can warn
    (`formatUnknownAtomWarning`). -/
def applyTaintStatus (atoms : Array UnifiedAtom) (pt : ProjectTaint)
    (applyTaint upgrade : Bool) : Array UnifiedAtom × Array String := Id.run do
  let mut out : Array UnifiedAtom := Array.mkEmpty atoms.size
  let mut unknown : Array String := #[]
  for a in atoms do
    match taintVerdict pt a.leanName with
    | none =>
      unknown := unknown.push a.name
      out := out.push { a with verificationStatus := none, trustedReason := none }
    | some (reason, .trusted) =>
      out := out.push { a with verificationStatus := some .trusted, trustedReason := reason }
    | some (_, status) =>
      if !applyTaint then
        out := out.push { a with verificationStatus := none, trustedReason := none }
      else
        let status := if status == .transitivelyVerified && !upgrade then .verified else status
        out := out.push { a with verificationStatus := some status, trustedReason := none }
  return (out, unknown)

/-- The graph-BFS input: the oracle's statuses with the upgrade undone, so the BFS
    re-derives `transitively-verified` from the emitted edges alone. -/
def demoteTransitive (atoms : Array UnifiedAtom) : Array UnifiedAtom :=
  atoms.map fun a =>
    if a.verificationStatus == some .transitivelyVerified
    then { a with verificationStatus := some .verified } else a

/-- Where the graph-BFS and the walk disagree, one line per atom. `oracle` and
    `graph` are index-aligned (the same atom array, stamped two ways). Only the
    `verified`/`transitively-verified` pair can differ: seeds and trusted atoms are
    identical inputs to both. Never reconciled — printed as a bug signal. -/
def divergenceLines (oracle graph : Array UnifiedAtom) : Array String := Id.run do
  let mut out : Array String := #[]
  for i in [:oracle.size] do
    let o := oracle[i]!
    let some g := graph[i]? | break
    match o.verificationStatus, g.verificationStatus with
    | some .transitivelyVerified, some .verified =>
      out := out.push s!"Divergence: {o.name} graph says tainted, oracle says clean"
    | some .verified, some .transitivelyVerified =>
      out := out.push s!"Divergence: {o.name} graph says clean, oracle says tainted"
    | _, _ => pure ()
  return out

/-- `(transitivelyVerified, locallyVerified, other)` over the final statuses. -/
def statusCounts (atoms : Array UnifiedAtom) : Nat × Nat × Nat :=
  atoms.foldl (init := (0, 0, 0)) fun (t, l, o) a =>
    match a.verificationStatus with
    | some .transitivelyVerified => (t + 1, l, o)
    | some .verified => (t, l + 1, o)
    | _ => (t, l, o + 1)

private def isVerified (status : Option WebVerificationStatus) : Bool :=
  match status with
  | some .verified | some .transitivelyVerified => true
  | _ => false

private def isContaminationSource (status : Option WebVerificationStatus) : Bool :=
  match status with
  | some .unverified | some .failed => true
  | _ => false

/-- Kinds whose members (enum constructors, struct fields/projections, class
    fields) are referenced as dependencies but are not emitted as standalone
    atoms. -/
def isTypeDefinition (kind : DeclKind) : Bool :=
  match kind with
  | .inductive | .structure | .class => true
  | _ => false

/-- The parent path segment of a dotted code-name: everything before the final
    `.` (e.g. `probe:spqr.Error.StateDecode` → `probe:spqr.Error`). `none` when
    the name has no `.` separator. -/
def parentName (dep : String) : Option String :=
  let parts := dep.splitOn "."
  if parts.length ≤ 1 then none
  else some (String.intercalate "." parts.dropLast)

/-- Partition missing-dependency names into genuine orphans vs. benign
    references to members of an extracted type. A dep `Foo.Bar` is a benign
    "type member" when `Foo` names an extracted `inductive`/`structure`/`class`
    atom: its constructors/fields/projections are not emitted as their own
    atoms, carry no verification status, and treating them as trusted is
    correct — so they should not be surfaced. Everything else (a reference whose
    parent is absent, or whose parent is a `def`/`theorem`/etc.) is a genuine
    orphan worth reporting.

    Returns `(orphans, typeMemberCount)`. `orphans` preserves the sorted,
    deduplicated order of `missingDeps` (P14). -/
def partitionMissingDeps (atoms : Array UnifiedAtom) (missingDeps : Array String)
    : Array String × Nat := Id.run do
  let mut typeDefs : RBTree String compare := .empty
  for atom in atoms do
    if isTypeDefinition atom.kind then
      typeDefs := typeDefs.insert atom.name
  let mut orphans : Array String := #[]
  let mut typeMemberCount : Nat := 0
  for dep in missingDeps do
    let isMember :=
      match parentName dep with
      | some parent => typeDefs.contains parent
      | none => false
    if isMember then
      typeMemberCount := typeMemberCount + 1
    else
      orphans := orphans.push dep
  (orphans, typeMemberCount)

/-- Enrich verification status through the dependency graph using
    reverse-BFS contamination.

    For each verified atom, determines whether it is **transitively verified**
    (all transitive dependencies are verified or trusted) or only
    **locally verified** (the atom itself is verified but at least one
    transitive dependency is not).

    Returns `(enrichedAtoms, transitiveCount, localCount, missingDeps)`.
    `missingDeps` lists dependency names not found in the atom map
    (treated as trusted, matching `probe`'s `propagate.rs` behavior). -/
def enrichTransitiveVerification (atoms : Array UnifiedAtom)
    : Array UnifiedAtom × Nat × Nat × Array String := Id.run do
  -- 1. Build reverse dependency index, verified set, and track missing deps
  let mut reverseDeps : RBMap String (Array String) compare := .empty
  let mut verifiedSet : RBTree String compare := .empty
  let mut atomNames : RBTree String compare := .empty
  let mut missingDepsSet : RBTree String compare := .empty

  for atom in atoms do
    atomNames := atomNames.insert atom.name

  for atom in atoms do
    if isVerified atom.verificationStatus then
      verifiedSet := verifiedSet.insert atom.name
    for dep in atom.dependencies do
      if !atomNames.contains dep then
        missingDepsSet := missingDepsSet.insert dep
      let cur := (reverseDeps.find? dep).getD #[]
      reverseDeps := reverseDeps.insert dep (cur.push atom.name)

  -- 2. Seed contamination
  let mut contaminated : RBTree String compare := .empty
  for atom in atoms do
    if isContaminationSource atom.verificationStatus then
      contaminated := contaminated.insert atom.name

  -- 3. Find direct contacts and start BFS
  let mut queue : Array String := #[]
  let initialSources := contaminated.toArray
  for source in initialSources do
    match reverseDeps.find? source with
    | some callers =>
      for caller in callers do
        if verifiedSet.contains caller && !contaminated.contains caller then
          contaminated := contaminated.insert caller
          queue := queue.push caller
    | none => pure ()

  -- 4. Propagate via reverse edges (BFS)
  let mut front : Nat := 0
  while h : front < queue.size do
    let atomName := queue[front]
    front := front + 1
    match reverseDeps.find? atomName with
    | some callers =>
      for caller in callers do
        if verifiedSet.contains caller && !contaminated.contains caller then
          contaminated := contaminated.insert caller
          queue := queue.push caller
    | none => pure ()

  -- 5. Upgrade non-contaminated verified atoms to transitively-verified
  let mut transitiveCount : Nat := 0
  let mut localCount : Nat := 0
  let mut result := atoms

  for i in [:atoms.size] do
    let atom := atoms[i]!
    if verifiedSet.contains atom.name then
      if contaminated.contains atom.name then
        localCount := localCount + 1
      else
        transitiveCount := transitiveCount + 1
        result := result.set! i { atom with verificationStatus := some .transitivelyVerified }

  (result, transitiveCount, localCount, missingDepsSet.toArray)

end ProbeLean
