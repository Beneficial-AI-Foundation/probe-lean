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
     `check-axioms` lists exactly the tainted set, marking the non-atom, and then T
     with each entry's reason, module and (rule 3) statement.

  Round 3 (2026-09-17): rule 2 reads the `externally_verified` tag set from the
  environment. The precondition pins the shapes that defeated the source scan
  (`instInhabitedBox.default` sharing `Box`'s line and resting on a sorry; two
  commands on one line; `loopy._unsafe_rec` carrying the `partial def`'s sorry), the
  output half asserts none of them is trusted, that an `attribute` command is, and
  that the tag audit prints exactly the expected `Divergence(tag)`/`Note(tag)` lines.
  Whether `instInhabitedBox.default` has a declaration range at all depends on the
  toolchain (v4.33 registers none), so the precondition reports that and the output
  half asserts the matching shape: an atom with the shared tag and its own
  `Divergence(tag)` line, or no atom, no line and `[not emitted]` in the report. The
  tainted count of 24 is the same either way on the toolchains CI tests; it is
  agreement, not an invariant.

  Round 8 (2026-09-18): `ownSorry`, a `def` whose own proof obligation is `sorry`. Lean
  ≤ 4.28 abstracts it into `ownSorry._proof_1`, so the kernel constant is tainted but not
  direct (`verified`, a `Divergence(graph)` line, the auxiliary listed `[direct] [not
  emitted]`); Lean ≥ 4.29 keeps the `sorry` inline (`unverified`, no divergence). The
  precondition reads which shape the toolchain produced and the output half asserts the
  matching one; on both it is tainted and never `transitively-verified`.
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
    `ConstantInfo.value?`/`value!` hide theorem bodies unless `allowOpaque := true`. -/
def bodyOf (ci : ConstantInfo) : Option Expr :=
  match ci with
  | .thmInfo v => some v.value
  | .defnInfo v => some v.value
  | _ => none

def usesSorry (ci : ConstantInfo) : Bool :=
  ci.type.getUsedConstants.contains ``sorryAx ||
    ((bodyOf ci).map (·.getUsedConstants.contains ``sorryAx)).getD false

/-- `Lean.collectAxioms` from IO: the public entry point, stable across 4.28–4.34; the
    internal `CollectAxioms.collect` is private since 4.30. -/
def axiomsOf (env : Environment) (n : Name) : IO (Array Name) := do
  let (axs, _) ← (collectAxioms n : CoreM (Array Name)).toIO
    { fileName := "<TaintCheck>", fileMap := default } { env }
  return axs

/-- Returns `(helperHasRange, ownSorryDirect)`: whether `instInhabitedBox.default` has a
    declaration range on this toolchain, and whether `ownSorry`'s own kernel constant
    names `sorryAx` (Lean ≥ 4.29) or the elaborator abstracted the sorried proof
    obligation into `ownSorry._proof_1` (Lean ≤ 4.28). Both decide which shape of the
    output half applies. -/
def checkPrecondition (fs : Failures) : IO (Bool × Bool) := do
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
  -- The one-line structure: its derived instance and its projection share its range
  -- (the head line names only `Tagged`), and the instance reaches the sorried
  -- `Repr Payload` — the shape in which a range-sharer used to be a trusted leaf.
  match declRangeExt.find? env `Tagged, declRangeExt.find? env `instReprTagged,
        declRangeExt.find? env `Tagged.p with
  | some r1, some r2, some r3 =>
    check fs "Tagged, instReprTagged and Tagged.p share the head line"
      (r1.range.endPos.line == r2.range.pos.line && r2.range.pos.line == r3.range.pos.line)
  | _, _, _ => check fs "Tagged, instReprTagged and Tagged.p all have ranges" false
  match env.find? `instReprPayload with
  | none => check fs "instReprPayload exists" false
  | some ci => check fs "instReprPayload carries a sorry" (usesSorry ci)
  let axs ← axiomsOf env `instReprTagged
  check fs "instReprTagged rests on a sorry (through the derived implementation)"
    (axs.contains ``sorryAx)
  match env.find? `admittedFact with
  | none => check fs "admittedFact exists" false
  | some ci => check fs "admittedFact carries a sorry" (usesSorry ci)
  -- Round 3. The generated helper: not a projection, not internal, rests on the
  -- sorried `Inhabited Cell`. Whether it has a declaration range depends on the
  -- toolchain (v4.28–v4.31 give it `Box`'s range, v4.33 registers none), and that
  -- decides whether it is an atom, shows the scanned tag and gets a `Divergence(tag)`
  -- line below. What does not depend on the toolchain: it is never trusted and always
  -- tainted.
  let helperHasRange := (declRangeExt.find? env `instInhabitedBox.default).isSome
  IO.println s!"  (instInhabitedBox.default has a declaration range: {helperHasRange})"
  if helperHasRange then
    match declRangeExt.find? env `Box, declRangeExt.find? env `instInhabitedBox.default with
    | some r1, some r2 =>
      check fs "instInhabitedBox.default shares Box's head line"
        (r1.range.endPos.line == r2.range.pos.line)
    | _, _ => check fs "Box has a range" false
  check fs "instInhabitedBox.default is neither a projection nor internal"
    (env.contains `instInhabitedBox.default && !env.isProjectionFn `instInhabitedBox.default &&
     !(`instInhabitedBox.default).isInternal)
  let axs2 ← axiomsOf env `instInhabitedBox.default
  check fs "instInhabitedBox.default rests on a sorry" (axs2.contains ``sorryAx)
  -- Two commands on one line: same line range, different columns.
  match declRangeExt.find? env `endorsed, declRangeExt.find? env `victim with
  | some r1, some r2 =>
    check fs "endorsed and victim share the line range"
      (r1.range.pos.line == r2.range.pos.line && r1.range.endPos.line == r2.range.endPos.line)
    check fs "victim starts at a later column" (r2.range.pos.column > r1.range.pos.column)
  | _, _ => check fs "endorsed and victim both have ranges" false
  -- The partial def: the kernel constant is clean, its compiled body is a carrier.
  let axs3 ← axiomsOf env `loopy
  check fs "loopy's kernel constant does not depend on sorryAx" (!axs3.contains ``sorryAx)
  match env.find? `loopy._unsafe_rec with
  | none => check fs "loopy._unsafe_rec exists" false
  | some ci => check fs "loopy._unsafe_rec carries the sorry" (usesSorry ci)
  -- The target's tag set, straight from the olean entries: what rule 2 reads.
  let mut tagSet : Array Name := #[]
  for i in [:env.header.moduleData.size] do
    if env.header.moduleNames[i]! == `Demo.Trust then
      for (ext, es) in env.header.moduleData[i]!.entries do
        if ext == `externallyVerifiedAttr then tagSet := unsafe unsafeCast es
  check fs "Demo.Trust's olean stores the tag set under the target's extension name"
    ([`vouched, `taggedOneLiner, `Tagged, `Box, `endorsed, `laterVouched, `rootVouched].all tagSet.contains &&
     !tagSet.contains `instInhabitedBox.default && !tagSet.contains `victim &&
     !tagSet.contains `interpolationVictim && !tagSet.contains `victim2)
  -- The own-sorry def: rests on a sorry on every toolchain; whether its own constant
  -- names `sorryAx` or the proof obligation sits in `ownSorry._proof_1` depends on the
  -- elaborator (abstracted on ≤ 4.28, inline from 4.29).
  let ownSorryDirect := match env.find? `ownSorry with
    | some ci => usesSorry ci
    | none => false
  check fs "ownSorry exists" (env.contains `ownSorry)
  let axs4 ← axiomsOf env `ownSorry
  check fs "ownSorry rests on a sorry" (axs4.contains ``sorryAx)
  IO.println s!"  (ownSorry names sorryAx in its own constant: {ownSorryDirect})"
  if !ownSorryDirect then
    match env.find? `ownSorry._proof_1 with
    | none => check fs "ownSorry._proof_1 exists (the abstracted proof obligation)" false
    | some ci => check fs "ownSorry._proof_1 carries the sorry" (usesSorry ci)
  return (helperHasRange, ownSorryDirect)

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

def checkRound3 (fs : Failures) (data : Json) (helperHasRange : Bool) : IO Unit := do
  let expect (atom status : String) : IO Unit :=
    check fs s!"{atom} is {status}" (statusOf data atom == some status)
  let noTag (atom : String) : IO Unit :=
    check fs s!"{atom} shows no externally_verified"
      (!(strArray data atom "attributes").contains "externally_verified")
  -- The generated helper named by a field: with a range it is an atom that shows
  -- the tag (shared line) and is not trusted; without one it is not an atom at all.
  expect "probe:Box" "trusted"
  check fs "Box trusted-reason is externally_verified" (reasonOf data "probe:Box" == some "externally_verified")
  expect "probe:instInhabitedCell" "unverified"
  expect "probe:instInhabitedBox" "verified"
  if helperHasRange then
    expect "probe:instInhabitedBox.default" "verified"
    check fs "instInhabitedBox.default has no trusted-reason" (reasonOf data "probe:instInhabitedBox.default").isNone
    check fs "instInhabitedBox.default shows the structure's scanned tag (shared line)"
      ((strArray data "probe:instInhabitedBox.default" "attributes").contains "externally_verified")
  else
    check fs "instInhabitedBox.default is not an atom (no declaration range on this toolchain)"
      (data.getObjVal? "probe:instInhabitedBox.default").toOption.isNone
  expect "probe:defaultBox" "verified"
  -- Interpolated string, two commands on one line, quotation look-back.
  expect "probe:interpolationVictim" "unverified"
  noTag "probe:interpolationVictim"
  expect "probe:endorsed" "trusted"
  expect "probe:victim" "unverified"
  check fs "victim shows endorsed's tag (same line; cosmetic, reported by the tag audit)"
    ((strArray data "probe:victim" "attributes").contains "externally_verified")
  check fs "victim has no trusted-reason" (reasonOf data "probe:victim").isNone
  expect "probe:quoted" "transitively-verified"
  expect "probe:victim2" "unverified"
  noTag "probe:victim2"
  -- A tag is a tag: the `attribute` command and the `_root_.` declaration.
  expect "probe:laterVouched" "trusted"
  check fs "laterVouched trusted-reason is externally_verified"
    (reasonOf data "probe:laterVouched" == some "externally_verified")
  check fs "laterVouched shows externally_verified in attributes (from the tag set)"
    ((strArray data "probe:laterVouched" "attributes").contains "externally_verified")
  expect "probe:rootVouched" "trusted"
  -- Executable bodies: kernel dependencies only.
  expect "probe:loopy" "transitively-verified"
  check fs "loopy._unsafe_rec is not an atom" (data.getObjVal? "probe:loopy._unsafe_rec").toOption.isNone

def checkStatuses (fs : Failures) (data : Json) (helperHasRange ownSorryDirect : Bool) : IO Unit := do
  IO.println ""
  IO.println "Extract output: statuses under the trusted base"
  let expect (atom status : String) : IO Unit :=
    check fs s!"{atom} is {status}" (statusOf data atom == some status)
  -- Rule 2: the target's own `externally_verified`, found in the olean tag set.
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
  expect "probe:commentedOutTag" "unverified"
  check fs "commentedOutTag shows no externally_verified (a block comment opened above the window)"
    (!(strArray data "probe:commentedOutTag" "attributes").contains "externally_verified")
  -- Range-sharers of a tagged one-line structure: they show the tag, only the
  -- structure is trusted by it.
  expect "probe:Tagged" "trusted"
  check fs "Tagged trusted-reason is externally_verified"
    (reasonOf data "probe:Tagged" == some "externally_verified")
  expect "probe:instReprPayload" "unverified"
  expect "probe:instReprTagged" "verified"
  check fs "instReprTagged has no trusted-reason" (reasonOf data "probe:instReprTagged").isNone
  check fs "instReprTagged shows the structure's scanned externally_verified (shared range)"
    ((strArray data "probe:instReprTagged" "attributes").contains "externally_verified")
  check fs "instReprTagged is flagged as Lean-generated" (boolOf data "probe:instReprTagged" "is-lean-generated")
  expect "probe:Tagged.p" "transitively-verified"
  check fs "Tagged.p has no trusted-reason" (reasonOf data "probe:Tagged.p").isNone
  expect "probe:showTagged" "verified"
  -- Rule 3: the `*External` module convention.
  expect "probe:externalOp" "trusted"
  check fs "externalOp trusted-reason is external" (reasonOf data "probe:externalOp" == some "external")
  expect "probe:usesExternal" "transitively-verified"
  expect "probe:extThm" "unverified"
  -- …excludes proofs whatever their keyword, and keeps Prop-*valued* models.
  expect "probe:admittedFact" "unverified"
  check fs "admittedFact has no trusted-reason" (reasonOf data "probe:admittedFact").isNone
  expect "probe:externalPred" "trusted"
  check fs "externalPred trusted-reason is external" (reasonOf data "probe:externalPred" == some "external")
  -- The range-less carrier: not an atom, but its caller is tainted.
  check fs "noRangeMid is not an atom" (data.getObjVal? "probe:noRangeMid").toOption.isNone
  expect "probe:viaNoRange" "verified"
  -- Direct carriers and clean declarations.
  expect "probe:sorried_bound" "unverified"
  expect "probe:cleanUse" "transitively-verified"
  expect "probe:theoremUse" "verified"
  -- The own-sorry def: `unverified` when its constant names `sorryAx`, `verified` when
  -- the toolchain abstracted the proof obligation into `ownSorry._proof_1` (which is
  -- then the direct carrier and never an atom). Never `transitively-verified`.
  expect "probe:ownSorry" (if ownSorryDirect then "unverified" else "verified")
  check fs "ownSorry._proof_1 is not an atom" (data.getObjVal? "probe:ownSorry._proof_1").toOption.isNone
  checkRound3 fs data helperHasRange

def checkStderr (fs : Failures) (path : String) (helperHasRange ownSorryDirect : Bool) : IO Unit := do
  IO.println ""
  IO.println s!"Extract stderr ({path}): the graph-BFS disagreement is printed"
  let lines := ((← IO.FS.readFile path).splitOn "\n").toArray
  check fs "divergence on viaNoRange is reported"
    (lines.contains "Divergence(graph): probe:viaNoRange graph says clean, oracle says tainted")
  check fs "no divergence on viaVouched (trust shields the graph and the walk alike)"
    (!lines.any fun l => l.startsWith "Divergence(graph): probe:viaVouched")
  check fs "no divergence on the companion"
    (!lines.any fun l => l.startsWith "Divergence(graph): probe:vouched.mvcgen_spec")
  -- With the proof obligation abstracted, the emitted graph has no node for
  -- `ownSorry._proof_1` (the fold recovers project edges, and the auxiliary has none),
  -- so the graph-BFS sees `ownSorry` as clean while the walk does not.
  let ownSorryDiv := "Divergence(graph): probe:ownSorry graph says clean, oracle says tainted"
  check fs (if ownSorryDirect then "no graph divergence on ownSorry (direct carrier, seeded on both sides)"
            else "divergence on ownSorry (its sorry sits in an auxiliary the graph has no node for)")
    (lines.contains ownSorryDiv == !ownSorryDirect)
  let expectedGraphDivs := if ownSorryDirect then 1 else 2
  check fs s!"exactly {expectedGraphDivs} graph divergence(s)"
    (lines.contains s!"Graph cross-check: {expectedGraphDivs} atom(s) where the emitted graph disagrees with the kernel walk")
  check fs "the full module set was imported (no fallback warning)"
    (!lines.any fun l => l.startsWith "Warning:" && (l.splitOn "not imported").length > 1)
  check fs "every atom was covered by the walk (no unknown-atom warning)"
    (!lines.any fun l => l.startsWith "Warning: atom ")
  check fs "no build-log divergence (log and kernel agree on the direct carriers; trusted hosts are moot)"
    (!lines.any fun l => l.startsWith "Divergence(log):")
  check fs "the partial def never produces a generic log divergence (its own Note(log) line, if the log was read)"
    (!lines.any fun l => l.startsWith "Divergence(log): probe:loopy")
  check fs "no cross-boundary note (nothing here restates a dependency)"
    (!lines.any fun l => l.startsWith "Note:" && (l.splitOn "by a module outside the project").length > 1)
  -- The tag audit: the shapes the scan would have trusted (the generated helper
  -- named by its field — only when it has a header to scan — and the second command
  -- on a tagged line), and the one tag the scan cannot see (the `attribute` command).
  if helperHasRange then
    check fs "Divergence(tag) for the generated helper the scan would have trusted"
      (lines.contains "Divergence(tag): instInhabitedBox.default header shows @[externally_verified] naming it, but the attribute's tag set does not contain it; the source text does not decide trust")
  else
    check fs "no Divergence(tag) for the range-less generated helper (no header to scan)"
      (!lines.any fun l => l.startsWith "Divergence(tag): instInhabitedBox.default")
  check fs "Divergence(tag) for the second command on a tagged line"
    (lines.contains "Divergence(tag): victim header shows @[externally_verified] naming it, but the attribute's tag set does not contain it; the source text does not decide trust")
  let expectedTagLines := if helperHasRange then 2 else 1
  check fs s!"exactly {expectedTagLines} Divergence(tag) line(s)"
    ((lines.filter fun l => l.startsWith "Divergence(tag):").size == expectedTagLines)
  check fs "Note(tag) for the attribute command"
    (lines.contains "Note(tag): laterVouched is tagged externally_verified by an `attribute` command or a macro; its header does not show the tag; the tag set decides trust")
  check fs "exactly one Note(tag) line" ((lines.filter fun l => l.startsWith "Note(tag):").size == 1)
  -- No generated axiom: the fixture writes no `native_decide` and no `addDecl`ed axiom.
  check fs "no Note(axiom) line (no range-less project axiom)"
    (!lines.any fun l => l.startsWith "Note(axiom):")

/-- The indented lines under `header`, up to the next unindented line: the report has
    two such sections (the tainted list, then T) with the same indentation. -/
def sectionUnder (lines : Array String) (header : String → Bool) : Array String := Id.run do
  let mut out : Array String := #[]
  let mut inside := false
  for l in lines do
    if header l then inside := true
    else if !l.startsWith "  " then inside := false
    else if inside then out := out.push l
  return out

def checkAxiomsReport (fs : Failures) (path : String) (helperHasRange ownSorryDirect : Bool) : IO Unit := do
  IO.println ""
  IO.println s!"check-axioms report ({path}): the same tainted set, non-atoms marked"
  let allLines := ((← IO.FS.readFile path).splitOn "\n").toArray
  let lines := sectionUnder allLines (fun l => l.endsWith " constant(s) rest on an unexcused project sorry:")
  let has (l : String) : Bool := lines.contains l
  check fs "range-less carrier is listed as direct and not emitted"
    (has "  noRangeMid [direct] [not emitted]")
  check fs "its caller is listed" (has "  viaNoRange")
  check fs "External-module theorem is listed as direct" (has "  extThm [direct]")
  check fs "sorried_bound is listed as direct" (has "  sorried_bound [direct]")
  check fs "the fold's auxiliary is listed and not emitted" (has "  tacticUse._proof_1 [not emitted]")
  check fs "the untagged neighbour, the docstring-mention and the commented-out tag are listed as direct"
    (has "  neighbour [direct]" && has "  docMention [direct]" && has "  commentedOutTag [direct]")
  check fs "the range-sharing derived instance and its caller are listed"
    (has "  instReprTagged" && has "  showTagged")
  check fs "the Prop-typed External def is listed as direct" (has "  admittedFact [direct]")
  -- The helper is tainted on every toolchain; only whether it was emitted varies.
  let helperLine := if helperHasRange then "  instInhabitedBox.default" else "  instInhabitedBox.default [not emitted]"
  check fs "round 3: the generated helper, the derived instance and their caller are listed"
    (has "  instInhabitedBox" && has helperLine && has "  defaultBox" &&
     has "  instInhabitedCell [direct]")
  check fs "round 3: the scan victims are listed as direct"
    (has "  interpolationVictim [direct]" && has "  victim [direct]" && has "  victim2 [direct]")
  check fs "round 3: the partial def's compiled body is listed as direct and not emitted"
    (has "  loopy._unsafe_rec [direct] [not emitted]")
  check fs "trusted declarations are not listed"
    (!lines.any fun l => l.startsWith "  vouched" || l.startsWith "  externalOp" ||
      l.startsWith "  taggedOneLiner" || l.startsWith "  Tagged " || l == "  Tagged" ||
      l.startsWith "  externalPred" || l == "  Box" || l.startsWith "  Box " ||
      l.startsWith "  endorsed" || l.startsWith "  laterVouched" || l.startsWith "  rootVouched")
  check fs "clean-modulo-T declarations are not listed"
    (!lines.any fun l => l.startsWith "  viaVouched" || l.startsWith "  usesExternal" ||
      l.startsWith "  cleanUse" || l.startsWith "  Tagged.p" || l == "  loopy" || l.startsWith "  quoted")
  -- The own-sorry def: listed on every toolchain; `[direct]` itself, or plain with its
  -- abstracted proof obligation as the direct, non-emitted carrier.
  check fs "ownSorry is listed with the toolchain's carrier shape"
    (if ownSorryDirect then has "  ownSorry [direct]" && !has "  ownSorry._proof_1 [direct] [not emitted]"
     else has "  ownSorry" && has "  ownSorry._proof_1 [direct] [not emitted]")
  -- 24 constants before `ownSorry`; it adds itself, plus its auxiliary when abstracted.
  let expectedTainted := 24 + (if ownSorryDirect then 1 else 2)
  check fs "the count line matches"
    (allLines.contains s!"{expectedTainted} constant(s) rest on an unexcused project sorry:")
  check fs s!"the tainted section lists exactly {expectedTainted} constants" (lines.size == expectedTainted)
  check fs "the tag-set line names the target's extension"
    (allLines.contains "externally_verified tag set: 7 name(s) from externallyVerifiedAttr")
  -- The trusted base itself: every rule's entries with reason and module, and the
  -- statement of each rule-3 model.
  let trusted := sectionUnder allLines (fun l => l.endsWith " trusted constant(s) (T):")
  check fs "T header counts the summary's trusted constants"
    (allLines.contains "9 trusted constant(s) (T):")
  check fs "T lists exactly 9 constants" (trusted.size == 9)
  check fs "T: rule-2 entries carry their reason and module"
    (trusted.contains "  vouched [externally_verified] Demo.Trust" &&
     trusted.contains "  laterVouched [externally_verified] Demo.Trust" &&
     trusted.contains "  rootVouched [externally_verified] Demo.Trust" &&
     trusted.contains "  Box [externally_verified] Demo.Trust")
  check fs "T: rule-3 entries carry their statement"
    (trusted.contains "  externalOp [external] Demo.FunsExternal : Nat" &&
     trusted.contains "  externalPred [external] Demo.FunsExternal : Prop")
  check fs "T: nothing tainted or clean-modulo-T is trusted"
    (!trusted.any fun l => l.startsWith "  admittedFact" || l.startsWith "  extThm" ||
      l.startsWith "  viaVouched" || l.startsWith "  instInhabitedBox" || l.startsWith "  victim")

def main (args : List String) : IO UInt32 := do
  let fs : Failures ← IO.mkRef #[]
  let some stderrPath := args[0]? | IO.eprintln "usage: TaintCheck.lean <extract.stderr> <check-axioms.out>"; return 2
  let some reportPath := args[1]? | IO.eprintln "usage: TaintCheck.lean <extract.stderr> <check-axioms.out>"; return 2
  let (helperHasRange, ownSorryDirect) ← checkPrecondition fs
  match ← findArtifact fs with
  | none => pure ()
  | some path =>
    IO.println s!"  (artifact: {path})"
    match Json.parse (← IO.FS.readFile path) with
    | .error e => check fs s!"artifact parses as JSON ({e})" false
    | .ok json =>
      match json.getObjVal? "data" with
      | .error _ => check fs "artifact has a data object" false
      | .ok data => checkStatuses fs data helperHasRange ownSorryDirect
  checkStderr fs stderrPath helperHasRange ownSorryDirect
  checkAxiomsReport fs reportPath helperHasRange ownSorryDirect
  let failures ← fs.get
  IO.println ""
  if failures.isEmpty then
    IO.println "sorry-taint end-to-end check: all assertions passed"
    return 0
  (← IO.getStdout).flush
  IO.eprintln s!"sorry-taint end-to-end check: {failures.size} assertion(s) failed:"
  for f in failures do IO.eprintln s!"  {f}"
  return 1
