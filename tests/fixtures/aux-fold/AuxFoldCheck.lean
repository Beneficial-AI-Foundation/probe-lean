/-
  End-to-end assertions for the auxiliary-dependency fold (issue #99).

  Run from this directory, *after* `probe-lean extract .`:

      lake env lean --run AuxFoldCheck.lean

  It is not part of the `Demo` library (that globs `Demo.lean` and `Demo/**`),
  so `lake build` never elaborates it.

  Two halves, and the first is the point:

  1. **Precondition.** The test asserts that the auxiliary actually exists and
     that the edge really is hidden behind it. Whether Lean abstracts a proof
     obligation depends on the elaborator: `⟨3, sorried_bound 3⟩` abstracts on
     v4.28.0-rc1 but need not on every release. Without this half the second
     half silently degrades into testing a direct dependency that was never
     lost in the first place.
  2. **Extract output.** The recovered edge appears, the contaminated hosts drop
     from `transitively-verified` to `verified`, the direct-edge control is
     unaffected, and the clean auxiliary does not contaminate its host.

  `verified` is the assertion, not "agrees with `check-axioms`": `verified` is
  the locally-verified-but-contaminated state, which is all the fold buys. It
  does not make `verification-status` sound.
-/
import Lean
import Demo

open Lean

def valueOf : ConstantInfo → Option Expr
  | .defnInfo v   => some v.value
  | .thmInfo v    => some v.value
  | .opaqueInfo v => some v.value
  | _             => none

def usedConsts (ci : ConstantInfo) : Array Name :=
  ci.type.getUsedConstants ++ (valueOf ci).elim #[] Expr.getUsedConstants

/-- Independent of `ProbeLean.isInternalName` on purpose: this script is the
oracle, so it must not share the predicate it is checking. `_proof_N`,
`match_N` and friends all carry a `._` component. -/
def looksAuxiliary (n : Name) : Bool := (n.toString.splitOn "._").length > 1

abbrev Failures := IO.Ref (Array String)

def check (fs : Failures) (name : String) (ok : Bool) : IO Unit := do
  if ok then IO.println s!"  ✓ {name}"
  else
    IO.println s!"  ✗ {name}"
    fs.modify (·.push name)

/-- Whether `n` reaches `sorried_bound` through auxiliary constants only. -/
partial def reachesViaAux (env : Environment) (n : Name) : Bool :=
  match env.find? n with
  | none => false
  | some ci => (usedConsts ci).any fun d =>
      d == `sorried_bound || (looksAuxiliary d && reachesViaAux env d)

def checkPrecondition (fs : Failures) : IO Unit := do
  initSearchPath (← findSysroot)
  let env ← importModules #[{ module := `Demo }] {} (level := OLeanLevel.private)
  IO.println "Precondition: the edge is hidden behind an auxiliary"
  for host in [`tacticUse, `atomicUse] do
    match env.find? host with
    | none => check fs s!"{host} exists" false
    | some ci =>
      let direct := usedConsts ci
      check fs s!"{host} has no direct edge to sorried_bound"
        (!direct.contains `sorried_bound)
      check fs s!"{host} references an auxiliary that reaches sorried_bound"
        (direct.any fun d => looksAuxiliary d && reachesViaAux env d)
  match env.find? `theoremUse with
  | none => check fs "theoremUse exists" false
  | some ci =>
    check fs "theoremUse keeps its direct edge to sorried_bound"
      ((usedConsts ci).contains `sorried_bound)
  match env.find? `cleanUse with
  | none => check fs "cleanUse exists" false
  | some ci =>
    let direct := usedConsts ci
    check fs "cleanUse references an auxiliary"
      (direct.any looksAuxiliary)
    check fs "cleanUse's auxiliary does not reach sorried_bound"
      (!direct.any fun d => looksAuxiliary d && reachesViaAux env d)

/-- The single extract artifact under `.verilib/probes/`. -/
def findArtifact : IO (Option System.FilePath) := do
  let dir : System.FilePath := ".verilib/probes"
  if !(← dir.pathExists) then return none
  let entries ← dir.readDir
  let jsons := entries.filter fun e => e.fileName.endsWith ".json"
  return (jsons.map (·.path)).qsort (fun a b => a.toString < b.toString) |>.back?

def atomField (data : Json) (atom field : String) : Option Json :=
  (data.getObjVal? atom >>= (·.getObjVal? field)).toOption

def statusOf (data : Json) (atom : String) : Option String :=
  atomField data atom "verification-status" >>= (·.getStr?.toOption)

def depsOf (data : Json) (atom field : String) : Array String :=
  match atomField data atom field with
  | some j => match j.getArr? with
    | .ok arr => arr.filterMap (·.getStr?.toOption)
    | .error _ => #[]
  | none => #[]

def checkExtractOutput (fs : Failures) : IO Unit := do
  IO.println ""
  IO.println "Extract output: the recovered edge and its status consequence"
  let some path ← findArtifact
    | check fs "extract artifact exists under .verilib/probes" false
  IO.println s!"  (artifact: {path})"
  let contents ← IO.FS.readFile path
  let .ok json := Json.parse contents
    | check fs "artifact parses as JSON" false
  let .ok data := json.getObjVal? "data"
    | check fs "artifact has a data object" false
  -- The fold case: the hidden edge is recovered, in the term bucket (the
  -- auxiliary occurred in the value), and the host loses transitive verification.
  for host in ["probe:tacticUse", "probe:atomicUse"] do
    check fs s!"{host} term-dependencies gained sorried_bound"
      ((depsOf data host "term-dependencies").contains "probe:sorried_bound")
    check fs s!"{host} dependencies union contains sorried_bound"
      ((depsOf data host "dependencies").contains "probe:sorried_bound")
    check fs s!"{host} type-dependencies unchanged (empty)"
      ((depsOf data host "type-dependencies").isEmpty)
    check fs s!"{host} is verified, not transitively-verified"
      (statusOf data host == some "verified")
  -- Control: a direct edge is neither lost nor duplicated by the fold.
  check fs "theoremUse keeps exactly its direct edge"
    (depsOf data "probe:theoremUse" "term-dependencies" == #["probe:sorried_bound"])
  check fs "theoremUse is verified"
    (statusOf data "probe:theoremUse" == some "verified")
  -- Negative control: a clean auxiliary contaminates nothing.
  check fs "cleanUse gained no project dependency"
    ((depsOf data "probe:cleanUse" "dependencies").isEmpty)
  check fs "cleanUse stays transitively-verified"
    (statusOf data "probe:cleanUse" == some "transitively-verified")
  check fs "sorried_bound is unverified"
    (statusOf data "probe:sorried_bound" == some "unverified")

def main : IO UInt32 := do
  let fs : Failures ← IO.mkRef #[]
  checkPrecondition fs
  checkExtractOutput fs
  let failures ← fs.get
  IO.println ""
  if failures.isEmpty then
    IO.println "aux-fold end-to-end check: all assertions passed"
    return 0
  IO.eprintln s!"aux-fold end-to-end check: {failures.size} assertion(s) failed:"
  for f in failures do IO.eprintln s!"  {f}"
  return 1
