/-
  Transitive verification enrichment via reverse-BFS contamination.
  Ports the algorithm from probe's propagate.rs to Lean.
-/
import Lean
import ProbeLean.Types

namespace ProbeLean

open Lean

private def isVerified (status : Option WebVerificationStatus) : Bool :=
  match status with
  | some .verified | some .transitivelyVerified => true
  | _ => false

private def isContaminationSource (status : Option WebVerificationStatus) : Bool :=
  match status with
  | some .unverified | some .failed => true
  | _ => false

/-- Enrich verification status through the dependency graph using
    reverse-BFS contamination.

    For each verified atom, determines whether it is **transitively verified**
    (all transitive dependencies are verified or trusted) or only
    **locally verified** (the atom itself is verified but at least one
    transitive dependency is not).

    Returns `(enrichedAtoms, transitiveCount, localCount)`. -/
def enrichTransitiveVerification (atoms : Array UnifiedAtom)
    : Array UnifiedAtom × Nat × Nat := Id.run do
  -- 1. Build reverse dependency index and verified set
  let mut reverseDeps : RBMap String (Array String) compare := .empty
  let mut verifiedSet : RBTree String compare := .empty

  for atom in atoms do
    if isVerified atom.verificationStatus then
      verifiedSet := verifiedSet.insert atom.name
    for dep in atom.dependencies do
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

  (result, transitiveCount, localCount)

end ProbeLean
