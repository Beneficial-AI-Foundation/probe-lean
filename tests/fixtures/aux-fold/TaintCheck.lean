/-
  End-to-end assertions for the kernel-backed `verification-status` (the sound
  sorry taint, spec Part A).

  Run from this directory, after

      probe-lean extract . 2>extract.stderr
      probe-lean check-axioms . >check-axioms.out
      lake env lean --run TaintCheck.lean extract.stderr check-axioms.out

  Not part of the `Demo` library, so `lake build` never elaborates it.

  Two halves, like `AuxFoldCheck.lean`:

  1. **Precondition.** The shapes the fixture exists for must really be there:
     `noRangeMid` is a `sorry` carrier with **no** declaration range (the SPQR
     `impl_def` shape), and `vouched.mvcgen_spec` shares `vouched`'s range (the
     `@[step]` companion shape). Without this half, an elaborator that started
     registering a range for `addDecl`, or a macro that stopped sharing the range,
     would silently turn the checks below into tests of something else.
  2. **Extract output.** Every status the trusted base and the walk prescribe; the
     companion is *not* trusted and carries none of its parent's attributes; the
     range-less carrier taints its caller and the graph-BFS disagreement is printed;
     `check-axioms` lists exactly the tainted set, marking the non-atom.
-/
import Lean
import Demo

open Lean

abbrev Failures := IO.Ref (Array String)

def check (fs : Failures) (name : String) (ok : Bool) : IO Unit := do
  if ok then IO.println s!"  ✓ {name}"
  else
    IO.println s!"  ✗ {name}"
    fs.modify (·.push name)

/-- The body of a theorem or definition, read by pattern match: since Lean 4.30
    `ConstantInfo.value?`/`value!` hide theorem bodies unless `allowOpaque := true`
    (the `value!` on the newest toolchain panicked here). -/
def bodyOf (ci : ConstantInfo) : Option Expr :=
  match ci with
  | .thmInfo v => some v.value
  | .defnInfo v => some v.value
  | _ => none

def usesSorry (ci : ConstantInfo) : Bool :=
  ci.type.getUsedConstants.contains ``sorryAx ||
    ((bodyOf ci).map (·.getUsedConstants.contains ``sorryAx)).getD false

def checkPrecondition (fs : Failures) : IO Unit := do
  initSearchPath (← findSysroot)
  let env ← importModules #[{ module := `Demo }] {} (level := OLeanLevel.private)
  IO.println "Precondition: the fixture has the shapes it claims"
  match env.find? `noRangeMid with
  | none => check fs "noRangeMid exists" false
  | some ci =>
    check fs "noRangeMid carries a sorry" (usesSorry ci)
    check fs "noRangeMid has no declaration range" (declRangeExt.find? env `noRangeMid).isNone
  match env.find? `viaNoRange with
  | none => check fs "viaNoRange exists" false
  | some ci =>
    check fs "viaNoRange references noRangeMid directly"
      (((bodyOf ci).map (·.getUsedConstants.contains `noRangeMid)).getD false)
  match declRangeExt.find? env `vouched, declRangeExt.find? env `vouched.mvcgen_spec with
  | some r1, some r2 =>
    check fs "vouched and its companion share one declaration range"
      (r1.range.pos == r2.range.pos && r1.range.endPos == r2.range.endPos)
  | _, _ => check fs "vouched and vouched.mvcgen_spec both have ranges" false
  match env.find? `vouched with
  | none => check fs "vouched exists" false
  | some ci => check fs "vouched carries a sorry" (usesSorry ci)
  match env.find? `externalOp with
  | none => check fs "externalOp exists" false
  | some ci => check fs "externalOp carries a sorry" (usesSorry ci)

def findArtifact (fs : Failures) : IO (Option System.FilePath) := do
  let dir : System.FilePath := ".verilib/probes"
  if !(← dir.pathExists) then
    check fs s!"{dir} exists (run `probe-lean extract .` first)" false
    return none
  let entries ← dir.readDir
  let jsons := (entries.filter fun e =>
    e.fileName.startsWith "lean_" && e.fileName.endsWith ".json").map (·.path)
  if jsons.size == 1 then return jsons[0]?
  check fs s!"exactly one lean_*.json artifact under {dir} (found {jsons.size}) — remove stale ones" false
  return none

def atomField (data : Json) (atom field : String) : Option Json :=
  (data.getObjVal? atom >>= (·.getObjVal? field)).toOption

def statusOf (data : Json) (atom : String) : Option String :=
  atomField data atom "verification-status" >>= (·.getStr?.toOption)

def reasonOf (data : Json) (atom : String) : Option String :=
  atomField data atom "trusted-reason" >>= (·.getStr?.toOption)

def strArray (data : Json) (atom field : String) : Array String :=
  match atomField data atom field with
  | some j => match j.getArr? with
    | .ok arr => arr.filterMap (·.getStr?.toOption)
    | .error _ => #[]
  | none => #[]

def boolOf (data : Json) (atom field : String) : Bool :=
  (atomField data atom field >>= (·.getBool?.toOption)).getD false

def checkStatuses (fs : Failures) (data : Json) : IO Unit := do
  IO.println ""
  IO.println "Extract output: statuses under the trusted base"
  let expect (atom status : String) : IO Unit :=
    check fs s!"{atom} is {status}" (statusOf data atom == some status)
  -- Rule 2: the target's own `externally_verified`, found by the source scan.
  expect "probe:vouched" "trusted"
  check fs "vouched trusted-reason is externally_verified"
    (reasonOf data "probe:vouched" == some "externally_verified")
  expect "probe:viaVouched" "transitively-verified"
  -- Decision 4: the companion gets its own status. It still *shows* the parent's
  -- scanned attributes (shared range), which is exactly why the assertion below
  -- matters: the tag it displays must not make it trusted.
  expect "probe:vouched.mvcgen_spec" "transitively-verified"
  check fs "vouched.mvcgen_spec has no trusted-reason" (reasonOf data "probe:vouched.mvcgen_spec").isNone
  check fs "vouched.mvcgen_spec shows the parent's scanned externally_verified (shared range)"
    ((strArray data "probe:vouched.mvcgen_spec" "attributes").contains "externally_verified")
  check fs "vouched.mvcgen_spec is flagged as a generated companion"
    (boolOf data "probe:vouched.mvcgen_spec" "is-aeneas-generated")
  -- Fabricated trust: a tag that is not the declaration's own annotation.
  expect "probe:taggedOneLiner" "trusted"
  expect "probe:neighbour" "unverified"
  check fs "neighbour shows no externally_verified (the line above is not its header)"
    (!(strArray data "probe:neighbour" "attributes").contains "externally_verified")
  expect "probe:docMention" "unverified"
  check fs "docMention shows no externally_verified (docstring and body comment are not read)"
    (!(strArray data "probe:docMention" "attributes").contains "externally_verified")
  -- Rule 3: the `*External` module convention.
  expect "probe:externalOp" "trusted"
  check fs "externalOp trusted-reason is external" (reasonOf data "probe:externalOp" == some "external")
  expect "probe:usesExternal" "transitively-verified"
  expect "probe:extThm" "unverified"
  -- The range-less carrier: not an atom, but its caller is tainted.
  check fs "noRangeMid is not an atom" (data.getObjVal? "probe:noRangeMid").toOption.isNone
  expect "probe:viaNoRange" "verified"
  -- Direct carriers and clean declarations.
  expect "probe:sorried_bound" "unverified"
  expect "probe:cleanUse" "transitively-verified"
  expect "probe:theoremUse" "verified"

def checkStderr (fs : Failures) (path : String) : IO Unit := do
  IO.println ""
  IO.println s!"Extract stderr ({path}): the graph-BFS disagreement is printed"
  let lines := ((← IO.FS.readFile path).splitOn "\n").toArray
  check fs "divergence on viaNoRange is reported"
    (lines.contains "Divergence: probe:viaNoRange graph says clean, oracle says tainted")
  check fs "no divergence on viaVouched (trust shields the graph and the walk alike)"
    (!lines.any fun l => l.startsWith "Divergence: probe:viaVouched")
  check fs "no divergence on the companion"
    (!lines.any fun l => l.startsWith "Divergence: probe:vouched.mvcgen_spec")
  check fs "exactly one graph divergence"
    (lines.contains "Divergence: 1 atom(s) where the emitted graph disagrees with the kernel walk")
  check fs "the full module set was imported (no fallback warning)"
    (!lines.any fun l => l.startsWith "Warning:" && (l.splitOn "not imported").length > 1)
  check fs "every atom was covered by the walk (no unknown-atom warning)"
    (!lines.any fun l => l.startsWith "Warning: atom ")
  check fs "no build-log divergence (log and kernel agree on the direct carriers)"
    (!lines.any fun l => l.startsWith "Divergence:" && (l.splitOn "build log").length > 1)

def checkAxiomsReport (fs : Failures) (path : String) : IO Unit := do
  IO.println ""
  IO.println s!"check-axioms report ({path}): the same tainted set, non-atoms marked"
  let lines := ((← IO.FS.readFile path).splitOn "\n").toArray
  let has (l : String) : Bool := lines.contains l
  check fs "range-less carrier is listed as direct and not emitted"
    (has "  noRangeMid [direct] [not emitted]")
  check fs "its caller is listed" (has "  viaNoRange")
  check fs "External-module theorem is listed as direct" (has "  extThm [direct]")
  check fs "sorried_bound is listed as direct" (has "  sorried_bound [direct]")
  check fs "the fold's auxiliary is listed and not emitted" (has "  tacticUse._proof_1 [not emitted]")
  check fs "the untagged neighbour and the docstring-mention are listed as direct"
    (has "  neighbour [direct]" && has "  docMention [direct]")
  check fs "trusted declarations are not listed"
    (!lines.any fun l => l.startsWith "  vouched" || l.startsWith "  externalOp" ||
      l.startsWith "  taggedOneLiner")
  check fs "clean-modulo-T declarations are not listed"
    (!lines.any fun l => l.startsWith "  viaVouched" || l.startsWith "  usesExternal" ||
      l.startsWith "  cleanUse")
  check fs "the count line matches" (has "10 constant(s) rest on an unexcused project sorry:")

def main (args : List String) : IO UInt32 := do
  let fs : Failures ← IO.mkRef #[]
  let some stderrPath := args[0]? | IO.eprintln "usage: TaintCheck.lean <extract.stderr> <check-axioms.out>"; return 2
  let some reportPath := args[1]? | IO.eprintln "usage: TaintCheck.lean <extract.stderr> <check-axioms.out>"; return 2
  checkPrecondition fs
  match ← findArtifact fs with
  | none => pure ()
  | some path =>
    IO.println s!"  (artifact: {path})"
    match Json.parse (← IO.FS.readFile path) with
    | .error e => check fs s!"artifact parses as JSON ({e})" false
    | .ok json =>
      match json.getObjVal? "data" with
      | .error _ => check fs "artifact has a data object" false
      | .ok data => checkStatuses fs data
  checkStderr fs stderrPath
  checkAxiomsReport fs reportPath
  let failures ← fs.get
  IO.println ""
  if failures.isEmpty then
    IO.println "sorry-taint end-to-end check: all assertions passed"
    return 0
  (← IO.getStdout).flush
  IO.eprintln s!"sorry-taint end-to-end check: {failures.size} assertion(s) failed:"
  for f in failures do IO.eprintln s!"  {f}"
  return 1
