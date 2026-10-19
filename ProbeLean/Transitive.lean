/-
  `verification-status` from the kernel taint pass.

  `applyTaintStatus` stamps every atom from `ProjectTaint` (see `Taint`), joined on
  `leanName`. The graph check of the emitted `dependencies` against these statuses
  is `tools/audit/check-graph.py`.
-/
import Lean
import ProbeLean.Types
import ProbeLean.Taint

namespace ProbeLean

open Lean

/-- The status the taint pass assigns to the constant `n`, with its `trusted-reason`.
    The first match wins: `unverified` if a direct carrier, `verified` if an
    unexcused project `sorry` is reachable, `trusted` if in T, and
    `transitively-verified` otherwise. The walk follows a trusted constant's
    statement, so a member of T whose statement rests on a `sorry` loses its trust
    and its `trusted-reason`. `none` for a name outside P: the walk never assessed
    it, and absence from the analysis is not evidence of verification. -/
def taintVerdict (pt : ProjectTaint) (n : Name) : Option (Option String × WebVerificationStatus) :=
  if !pt.constants.contains n then none
  else if pt.taint.direct.contains n then some (none, .unverified)
  else if pt.taint.tainted.contains n then some (none, .verified)
  else some <| match pt.trust[n]? with
    | some reason => (some reason, .trusted)
    | none => (none, .transitivelyVerified)

/-- The `assumptions` value of the constant `n`: its set from `pt.assumptions` as
    bare names sorted by string, `[]` if the computed map has no entry, `none` if
    the set walk did not run. -/
def assumptionsOf (pt : ProjectTaint) (n : Name) : Option (Array String) :=
  pt.assumptions.map fun m => ((m.getD n #[]).map toString).qsort (· < ·)

/-- Stamp `verification-status`/`trusted-reason`/`status-origin`/`assumptions` on
    every atom from the taint pass, joined on `leanName`. `applyTaint := false`
    (`--skip-verify`) stamps only the atoms that read `trusted` and leaves the rest
    without a status, a member of T whose statement is tainted included. No atom
    gets `assumptions` then, a trusted one included.
    `upgrade := false` (`--skip-enrich`) caps clean atoms at `verified`. A tainted
    atom (`verified` from the walk, not from the cap) gets `status-origin:
    "kernel-taint"` in both modes. The emitted graph can lack the path to its
    `sorry`, and the marker stops a consumer from promoting it or its callers.
    Atoms whose name is not in P get no status at all. They are returned by name
    so the caller can warn (`formatUnknownAtomWarning`). -/
def applyTaintStatus (atoms : Array UnifiedAtom) (pt : ProjectTaint)
    (applyTaint upgrade : Bool) : Array UnifiedAtom × Array String := Id.run do
  let mut out : Array UnifiedAtom := Array.mkEmpty atoms.size
  let mut unknown : Array String := #[]
  for a in atoms do
    let assumptions := if applyTaint then assumptionsOf pt a.leanName else none
    match taintVerdict pt a.leanName with
    | none =>
      unknown := unknown.push a.name
      out := out.push { a with verificationStatus := none, trustedReason := none, statusOrigin := none,
                               assumptions := none }
    | some (reason, .trusted) =>
      out := out.push { a with verificationStatus := some .trusted, trustedReason := reason,
                               statusOrigin := none, assumptions }
    | some (_, status) =>
      if !applyTaint then
        out := out.push { a with verificationStatus := none, trustedReason := none, statusOrigin := none,
                                 assumptions := none }
      else
        let origin := if status == .verified then some .kernelTaint else none
        let status := if status == .transitivelyVerified && !upgrade then .verified else status
        out := out.push { a with verificationStatus := some status, trustedReason := none,
                                 statusOrigin := origin, assumptions }
  return (out, unknown)

/-- `(transitivelyVerified, locallyVerified, other)` over the final statuses. -/
def statusCounts (atoms : Array UnifiedAtom) : Nat × Nat × Nat :=
  atoms.foldl (init := (0, 0, 0)) fun (t, l, o) a =>
    match a.verificationStatus with
    | some .transitivelyVerified => (t + 1, l, o)
    | some .verified => (t, l + 1, o)
    | _ => (t, l, o + 1)

end ProbeLean
