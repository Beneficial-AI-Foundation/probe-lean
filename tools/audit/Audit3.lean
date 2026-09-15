import Lean
open Lean

/-- Corpora to report separately, by module-name prefix. -/
def corpora : Array (String × Array Name) := #[
  ("core (Init/Std/Lean)", #[`Init, `Std, `Lean]),
  ("Batteries",            #[`Batteries]),
  ("Mathlib",              #[`Mathlib]),
  ("Aeneas",               #[`Aeneas]),
  ("Curve25519Dalek",      #[`Curve25519Dalek]),
  ("ProbeLean",            #[`ProbeLean])
]

/-- Cheap, allocation-free test for an abstracted-proof auxiliary: the last
name component is `_proof_N` / `proof_N`. -/
def isProofAux (n : Name) : Bool :=
  match n with
  | .str _ s => s.startsWith "_proof_" || s.startsWith "proof_"
  | _ => false

def isMatcherAux (n : Name) : Bool :=
  match n with
  | .str _ s => s.startsWith "match_" || s.startsWith "_match_"
  | _ => false

inductive Kind | thm | defn | other deriving BEq, Hashable

def kindOf : ConstantInfo → Kind
  | .thmInfo _ => .thm
  | .defnInfo _ => .defn
  | _ => .other

structure Stats where
  decls      : Nat := 0   -- declarations with a source range (probe-lean atoms)
  defs       : Nat := 0   -- of those, non-theorem
  thms       : Nat := 0
  proofAux   : Nat := 0   -- X._proof_N constants
  matchAux   : Nat := 0
  hostDefs   : Nat := 0   -- distinct non-theorem hosts of a _proof_N
  hostThms   : Nat := 0
  hostOther  : Nat := 0
  deriving Inhabited

def main (args : List String) : IO Unit := do
  initSearchPath (← findSysroot)
  let roots := (args.map fun s => s.toName).toArray
  let env ← importModules (roots.map fun p => ({ module := p } : Import)) {} (trustLevel := 1024)

  let modOf (n : Name) : Option Name :=
    env.getModuleIdxFor? n >>= fun i => env.allImportedModuleNames[i.toNat]?
  let inCorpus (ps : Array Name) (n : Name) : Bool :=
    match modOf n with
    | none => false
    | some m => ps.any fun p => m == p || m.toString.startsWith (p.toString ++ ".")

  -- one pass: bucket every constant into its corpus, tally
  let mut stats : Array Stats := corpora.map fun _ => {}
  let mut hosts : Array (Std.HashSet Name) := corpora.map fun _ => {}

  for (name, ci) in env.constants.map₁.toList do
    let some ci' := some ci | continue
    let mut idx : Option Nat := none
    for i in [:corpora.size] do
      if idx.isNone && inCorpus corpora[i]!.2 name then idx := some i
    let some i := idx | continue
    let mut s := stats[i]!
    if isProofAux name then
      s := { s with proofAux := s.proofAux + 1 }
      hosts := hosts.set! i (hosts[i]!.insert name.getPrefix)
    else if isMatcherAux name then
      s := { s with matchAux := s.matchAux + 1 }
    else if (declRangeExt.find? env name).isSome then
      match ci' with
      | .ctorInfo _ | .recInfo _ => pure ()
      | _ =>
        s := { s with decls := s.decls + 1 }
        match kindOf ci' with
        | .thm => s := { s with thms := s.thms + 1 }
        | _    => s := { s with defs := s.defs + 1 }
    stats := stats.set! i s

  for i in [:corpora.size] do
    let mut s := stats[i]!
    for h in hosts[i]! do
      match env.find? h with
      | none => s := { s with hostOther := s.hostOther + 1 }
      | some ci =>
        match kindOf ci with
        | .thm  => s := { s with hostThms := s.hostThms + 1 }
        | .defn => s := { s with hostDefs := s.hostDefs + 1 }
        | .other => s := { s with hostOther := s.hostOther + 1 }
    if s.decls == 0 && s.proofAux == 0 then continue
    let pct (a b : Nat) : String :=
      if b == 0 then "n/a" else s!"{(a * 1000 / b) / 10}.{(a * 1000 / b) % 10}%"
    IO.println s!"── {corpora[i]!.1}"
    IO.println s!"   decls w/ source range : {s.decls}  ({s.defs} non-theorem, {s.thms} theorem)"
    IO.println s!"   _proof_N constants    : {s.proofAux}   match_N: {s.matchAux}"
    IO.println s!"   distinct hosts        : {hosts[i]!.size}  (non-theorem {s.hostDefs}, theorem {s.hostThms}, other {s.hostOther})"
    IO.println s!"   non-theorem decls carrying an embedded proof: {pct s.hostDefs s.defs}"
