/-
  The kernel taint pass: the trusted base T over the project's constants P, and the
  `sorryAx` reachability walk that decides `verification-status`.

  Shared by `extract` (`Atomize.runAnalysisViaLakeEnv`) and `check-axioms`
  (`CheckAxioms.runCheckAxiomsInProject`), so the two report the same set by
  construction. The pure core lives in `AxiomCheck` (the walk) and `Trust` (the
  rules); this module supplies P, computes T, and formats the diagnostics.
-/
import Lean
import ProbeLean.Analysis
import ProbeLean.AxiomCheck
import ProbeLean.Trust
import ProbeLean.Coimport
import ProbeLean.TagSet

namespace ProbeLean

open Lean

/-- Everything `verification-status` is derived from. -/
structure ProjectTaint where
  /-- T: trusted project constants with their `trusted-reason`. -/
  trust : Std.HashMap Name String
  /-- The walk's result over P. -/
  taint : TaintResult
  /-- P itself: the constants the walk covered. An atom whose name is not here was
      never assessed and must not receive a status (`Transitive.taintVerdict`). -/
  constants : Std.HashSet Name
  /-- Names declared by more than one imported project module with the same
      statement (`Coimport.MergedDecl`): the importer kept one proof, the walk
      followed the union of all of them. Sorted by name; reported as a warning. -/
  merged : Array Name := #[]
  /-- Names a project module declares that another module declares too
      (`crossMergedDecls`) where some declaring project module's olean the preflight
      could not read (`splitCrossMerged`): the project body is invisible, so they are
      treated as resting on `sorry` and never trusted. Sorted by name; reported as a
      warning. -/
  crossMerged : Array Name := #[]
  /-- Names a project module declares that a module outside the project declares too,
      every declaring project module read by the preflight: walked from the project's
      own version(s) like a merged declaration (`splitCrossMerged`). Sorted by name;
      reported as a note. -/
  crossWalked : Array Name := #[]
  /-- The `externally_verified` tag set rule 2 was decided from (`TagSet`). -/
  tagSet : TagSet := {}
  /-- Tag audit (`tagAudit`): source-visible constants whose header shows the tag
      naming them — what the source scan would have trusted — while the tag set does
      not contain them. Sorted by name; each is reported. -/
  scanOnlyTags : Array Name := #[]
  /-- Tag audit: constants in the tag set whose header does not show the tag (an
      `attribute [externally_verified] foo` command, a macro). Sorted; reported as a
      note. -/
  tagOnly : Array Name := #[]
  /-- Trusted project axioms (rule 1) that are not source-visible declarations — an
      internal name or no declaration range — so not written by a human and never an
      atom. Since Lean 4.31 `native_decide` adds one per proof
      (`X._native.native_decide.ax_N`, which *does* carry the theorem's range) instead
      of referencing `Lean.ofReduceBool`, so the proof rests on compiled code behind a
      trusted, otherwise invisible constant (`generatedTrustedAxioms`). Sorted; each is
      reported as a note. -/
  generatedAxioms : Array Name := #[]
  /-- |P|. -/
  pSize : Nat
  /-- Number of project modules imported. -/
  moduleCount : Nat

/-- The out-edges of a merged declaration: the union of `constInfoChildren` over
    every version the preflight read. The environment holds only one version's
    body; a caller that was built against the other one still rests on *that*
    body's `sorry`, so the walk must follow all of them. -/
def mergedChildren (m : MergedDecl) : Array Name := Id.run do
  let mut out : Array Name := #[]
  for (_, ci) in m.versions do
    for c in constInfoChildren ci do
      if !out.contains c then out := out.push c
  return out

/-- `projectTaint`'s `childrenOverride` for a set of merged declarations. -/
def mergedChildrenMap (merged : Array MergedDecl) : Std.HashMap Name (Array Name) :=
  merged.foldl (init := {}) fun acc m => acc.insert m.declName (mergedChildren m)

/-- What the preflight read per merged name: the owning modules of the versions it
    has (`MergedDecl.versions`). A coverage record, not a name set — a discrepancy is
    exempted only when both modules involved were read. -/
def mergedOwners (merged : Array MergedDecl) : Std.HashMap Name (Array Name) :=
  merged.foldl (init := {}) fun acc m => acc.insert m.declName (m.versions.map (·.1))

/-- Names a project module declares that the environment collapsed with another
    module's version, found after the import from the environment header alone (no
    dependence on the olean preflight), each with the sorted project modules that
    declare it: (a) a name in a project module's `constNames` that the environment
    attributes to another module — `finalizeImport` keeps the **first** owner's index
    and the **last** subsuming body, so this catches a same-statement restatement of
    a dependency theorem imported after it, and any project/project pair the
    preflight did not read; (b) a name declared by both a project module and a
    non-project module, whichever order they were imported in. In every case the
    environment holds one body and it need not be the project's; `splitCrossMerged`
    decides whether the project's own version(s) can be walked instead. Sorted by
    name.

    `knownMerged` (`mergedOwners`) exempts a project/project discrepancy only when
    the preflight read **both** the declaring module and the module the environment
    attributes the name to — those two versions are the ones `mergedChildren` walks.
    A third declaring module whose olean the preflight skipped is not covered and
    stays flagged: its discarded body was never walked. -/
def crossMergedDecls (env : Environment) (pFilter : ProjectFilter)
    (knownMerged : Std.HashMap Name (Array Name)) : Array (Name × Array Name) := Id.run do
  let mods := env.header.moduleData
  let modNames := env.header.moduleNames
  let mut declared : Std.HashSet Name := {}
  let mut flagged : Std.HashSet Name := {}
  for i in [:mods.size] do
    if pFilter.moduleIdxs.contains i then
      for n in mods[i]!.constNames do
        declared := declared.insert n
        match env.getModuleIdxFor? n with
        | some j =>
          if j.toNat != i then
            let covered := match knownMerged[n]? with
              | some owners =>
                owners.contains modNames[i]! && owners.contains (modNames[j.toNat]?.getD .anonymous)
              | none => false
            if !covered then flagged := flagged.insert n
        | none => flagged := flagged.insert n
  for i in [:mods.size] do
    if !pFilter.moduleIdxs.contains i then
      for n in mods[i]!.constNames do
        if declared.contains n then flagged := flagged.insert n
  -- Second pass: which project modules declare each flagged name. A module can be the
  -- environment's owner (not flagged at its own index) and still be one of them.
  let mut declaring : Std.HashMap Name (Array Name) := {}
  for i in [:mods.size] do
    if pFilter.moduleIdxs.contains i then
      for n in mods[i]!.constNames do
        if flagged.contains n then
          declaring := declaring.insert n ((declaring.getD n #[]).push modNames[i]!)
  let names := flagged.toArray.qsort fun a b => a.toString < b.toString
  names.map fun n => (n, (declaring.getD n #[]).qsort fun a b => a.toString < b.toString)

/-- The names of `crossMergedDecls`. -/
def crossMergedNames (env : Environment) (pFilter : ProjectFilter)
    (knownMerged : Std.HashMap Name (Array Name)) : Array Name :=
  (crossMergedDecls env pFilter knownMerged).map (·.1)

/-- Decide, per cross-boundary name, what the walk follows. `owned` is what the
    preflight read for every project-declared name (`Coimport.ownersByName`). If every
    project module declaring the name has a version there, the project's own bodies are
    all visible and the name is walked like a merged declaration from exactly those
    versions (the other body is a dependency's, already in the trusted base) — first
    component. Otherwise a project body is invisible (its module's olean could not be
    read) and the name is taken to rest on `sorry` — second component. Both keep the
    input's name order. -/
def splitCrossMerged (decls : Array (Name × Array Name))
    (owned : Std.HashMap Name (Array (Name × ConstantInfo)))
    : Array MergedDecl × Array Name := Id.run do
  let mut walked : Array MergedDecl := #[]
  let mut assumed : Array Name := #[]
  for (n, declaring) in decls do
    let versions := (owned.getD n #[]).filter fun (m, _) => declaring.contains m
    let allRead := !declaring.isEmpty && declaring.all fun m => versions.any (·.1 == m)
    if allRead then
      walked := walked.push
        { declName := n, versions := versions.qsort fun a b => a.1.toString < b.1.toString }
    else
      assumed := assumed.push n
  return (walked, assumed)

/-- Trust for a merged declaration: every version must be trusted on its own by
    rules 1 and 3 (kind and owning module). Rule 2 never applies — an
    `@[externally_verified]` sits in one file and vouches for one body, and the
    environment does not say which body survived. A theorem/axiom pair is
    therefore not trusted: the theorem version carries a proof the axiom version
    would excuse. `isProof` is the name's rule-3 input (`propTypedNames`); every
    version has the same statement, so it is shared. Returns the reason of the first
    version when all agree. -/
def mergedTrustedReason (env : Environment) (m : MergedDecl) (isProof : Bool := false)
    : Option String := do
  let reasons ← m.versions.mapM fun (owner, ci) =>
    let kind := getDeclKind env m.declName ci
    trustedReason kind false owner (kind == .theorem || isProof)
  reasons[0]?

/-- The `externally_verified` tag set over P: what the environment stores for the
    target's own registration(s) of the attribute (`externallyVerifiedTagSet`), plus
    probe-lean's handle for a target that imports `ProbeLean.Attrs`. -/
def externallyVerifiedNames (env : Environment) (pFilter : ProjectFilter)
    (consts : Array (Name × ConstantInfo)) : TagSet := Id.run do
  let ts := externallyVerifiedTagSet env pFilter
  let mut tagged := ts.tagged
  for (name, _) in consts do
    if externallyVerifiedAttr.hasTag env name then tagged := tagged.insert name
  return { ts with tagged }

/-- Attributes for the constants of P that can carry attributes: every
    source-visible declaration. Constants absent from the map have no attributes.
    With no `--module`/`--library` selection this is exactly the emitted atom set, so
    the scan runs once and `declInfoToAtom` reuses the result. `tagged` is the
    `externally_verified` tag set; it decides the `externally_verified` entry of the
    `attributes` array, the scan supplies every other name.

    A constant that shares a tagged declaration's range — a generated companion
    (`X.mvcgen_spec`), a `deriving` instance or a projection of a one-line structure
    — *shows* the scanned attributes here, as it always has: the emitted `attributes`
    array is unchanged, and the primary-spec signals keep reading them (the companion
    of a `@[step]` axiom is that axiom's spec proxy). It also shows
    `externally_verified` if its neighbour's header carries it — and is not trusted by
    it, since it is not in the tag set; `tagAudit` reports the ones whose head line
    names them, the shapes the scan used to trust. -/
def computeAttributes (env : Environment) (projectPath : System.FilePath) (fileCache : FileCache)
    (pathCache : ModulePathCache) (consts : Array (Name × ConstantInfo))
    (tagged : Std.HashSet Name := {}) : IO (Std.HashMap Name DeclAttrs) := do
  let modNames := env.allImportedModuleNames
  let mut attrs : Std.HashMap Name DeclAttrs := {}
  for (name, info) in consts do
    if !isSourceVisible env name info then
      continue
    let moduleName := (moduleNameOf modNames env name).getD .anonymous
    let range := getDeclSourceLoc env name
    let a ← declAttributes env projectPath fileCache pathCache name moduleName range
      (scanSource := true) (isInstance := getDeclKind env name info == .instance)
      (tagged := tagged.contains name)
    attrs := attrs.insert name a
  return attrs

/-- The constants rule 3 has to look at more closely: non-theorem, non-axiom
    constants of `*External` modules (`propTypedNames`). -/
def externalRule3Candidates (env : Environment) (consts : Array (Name × ConstantInfo))
    : Array (Name × ConstantInfo) :=
  let modNames := env.allImportedModuleNames
  consts.filter fun (name, info) =>
    let kind := getDeclKind env name info
    kind != .theorem && kind != .axiom &&
      isExternalModule ((moduleNameOf modNames env name).getD .anonymous)

/-- Of `cands`, those whose **type is a proposition** (`Meta.isProp` on the statement,
    run once per candidate) — rule 3's proof test for `externalRule3Candidates`. A
    `def admitted : False := by sorry` in an External module is a proof in disguise
    and must get its normal status, while a `def op : Nat := sorry` is the
    hand-written model the convention trusts. A candidate whose type cannot be checked
    — an elaboration error, or a heartbeat/recursion limit, which `Core.tryCatch`
    would rethrow and which `tryCatchRuntimeEx` catches — is reported and counted as
    a proof (fail closed). Each candidate gets its own heartbeat budget
    (`withCurrHeartbeats`), so one pathological statement cannot starve the rest. -/
def propTypedNames (env : Environment) (cands : Array (Name × ConstantInfo))
    : IO (Std.HashSet Name) := do
  if cands.isEmpty then return {}
  let act : MetaM (Std.HashSet Name × Array Name) := do
    let mut props : Std.HashSet Name := {}
    let mut failed : Array Name := #[]
    for (name, info) in cands do
      let verdict : Option Bool ← withCurrHeartbeats <|
        tryCatchRuntimeEx (do return some (← Meta.isProp info.type)) (fun _ => return none)
      match verdict with
      | some true => props := props.insert name
      | some false => pure ()
      | none =>
        props := props.insert name
        failed := failed.push name
    return (props, failed)
  let ctx : Core.Context := { fileName := "<probe-lean>", fileMap := default }
  let ((props, failed), _) ← (act.run' {} {}).toIO ctx { env }
  for n in failed do
    IO.eprintln s!"Warning: could not decide whether the type of {n} is a proposition; \
      it is not trusted by the External-module rule"
  return props

/-- T over P: `Trust.trustedReason` applied to every project constant. Rules 1 and 3
    need the kind, the module and whether the type is a proposition (`propTyped`);
    rule 2 is membership in `tagged`, the `externally_verified` tag set
    (`externallyVerifiedNames`). A name in `merged` is decided by
    `mergedTrustedReason` over all of its versions instead, and a name in `excluded`
    (`crossMergedNames`) is never trusted. -/
def computeTrustBase (env : Environment) (consts : Array (Name × ConstantInfo))
    (tagged : Std.HashSet Name)
    (merged : Std.HashMap Name MergedDecl := {}) (propTyped : Std.HashSet Name := {})
    (excluded : Std.HashSet Name := {}) : Std.HashMap Name String := Id.run do
  let modNames := env.allImportedModuleNames
  let mut trust : Std.HashMap Name String := {}
  for (name, info) in consts do
    if excluded.contains name then continue
    let reason := match merged[name]? with
      | some m => mergedTrustedReason env m (propTyped.contains name)
      | none =>
        let kind := getDeclKind env name info
        let moduleName := (moduleNameOf modNames env name).getD .anonymous
        trustedReason kind (tagged.contains name) moduleName
          (kind == .theorem || propTyped.contains name)
    if let some r := reason then
      trust := trust.insert name r
  return trust

/-- The tag audit: where the source scan and the tag set disagree about
    `externally_verified`. `scanOnly` — the header shows the tag and names the
    constant (`DeclAttrs.headerNamesTag`), yet the tag set lacks it: either a shape
    the scan gets wrong (a generated `instX.field` helper, two commands on one line)
    or a registration the tag-set reader does not understand; either way rule 2 does
    not apply to the constant (rules 1 and 3 still may, so the line reports membership,
    not a status). Projections and `.mvcgen_spec` companions are left out of that side,
    as the scan-based rule left them out by kind: a one-line structure's projection is
    named by its field on the head line, which is known and benign. `tagOnly` — the set
    has it, the header does not show it: an `attribute` command or a macro attached the
    tag. Both sorted by name. -/
def tagAudit (env : Environment) (attrs : Std.HashMap Name DeclAttrs) (tagged : Std.HashSet Name)
    : Array Name × Array Name := Id.run do
  let mut scanOnly : Array Name := #[]
  let mut tagOnly : Array Name := #[]
  for (name, a) in attrs do
    if a.headerNamesTag && !tagged.contains name && !isCompanionName name &&
        !env.isProjectionFn name then
      scanOnly := scanOnly.push name
    if tagged.contains name && !a.headerShowsTag then tagOnly := tagOnly.push name
  return (scanOnly.qsort (fun a b => a.toString < b.toString),
          tagOnly.qsort (fun a b => a.toString < b.toString))

/-- Of `consts`, the constants `trust` holds as `axiom` that are not source-visible
    declarations (`isSourceVisible`: an internal name such as
    `X._native.native_decide.ax_N`, or no declaration range as with `addDecl` from a
    macro) — generated axioms. Rule 1 trusts them like a written `axiom`; they are
    listed so a reviewer of the trust base can see them, since `extract` never emits
    them. Sorted by name. -/
def generatedTrustedAxioms (env : Environment) (consts : Array (Name × ConstantInfo))
    (trust : Std.HashMap Name String) : Array Name :=
  let axs := consts.filterMap fun (n, ci) =>
    if trust[n]? == some "axiom" && !isSourceVisible env n ci then some n else none
  axs.qsort fun a b => a.toString < b.toString

/-- The walk over P with T blocked; merged declarations — project/project pairs and
    the cross-boundary names walked from their project versions — follow every
    version's dependencies (`mergedChildrenMap`). Every cross-boundary name
    (`crossNames`) counts as a project constant whatever module the environment
    attributes it to, so it is expanded rather than blocked; those in `crossAssumed`
    get `sorryAx` added to their out-edges, since the project body the walk cannot see
    is taken to be the sorried one. -/
def runProjectTaint (env : Environment) (pFilter : ProjectFilter)
    (consts : Array (Name × ConstantInfo)) (trust : Std.HashMap Name String)
    (merged : Array MergedDecl := #[]) (crossNames : Array Name := #[])
    (crossAssumed : Array Name := #[]) : TaintResult :=
  let crossSet := Std.HashSet.ofArray crossNames
  let override := crossAssumed.foldl (init := mergedChildrenMap merged) fun m n =>
    m.insert n ((m.getD n (constChildren env n)).push sorryAxiomName)
  projectTaint env (fun n => pFilter.contains env n || crossSet.contains n) trust.contains
    (consts.map (·.1)) (childrenOverride := override)

/-- P, T and the walk in one call. Returns the attribute map too, so the atom builder
    does not scan the sources a second time. `merged` and `owned` are what the co-import
    preflight read for the imported modules (`Atomize.importProjectEnvWithFallback`);
    the cross-boundary merges are found here from the environment itself
    (`crossMergedDecls`), split by `splitCrossMerged` into names walked from their
    project versions (joined to `merged`) and names taken to rest on `sorry`, and the
    names among them that the environment attributes to a non-project module are added
    to P so they are walked and reported. -/
def computeProjectTaint (env : Environment) (projectPath : System.FilePath)
    (pFilter : ProjectFilter) (fileCache : FileCache) (pathCache : ModulePathCache)
    (consts : Array (Name × ConstantInfo)) (moduleCount : Nat)
    (merged : Array MergedDecl := #[])
    (owned : Std.HashMap Name (Array (Name × ConstantInfo)) := {})
    : IO (ProjectTaint × Std.HashMap Name DeclAttrs) := do
  let cross := crossMergedDecls env pFilter (mergedOwners merged)
  let (crossWalkedAll, crossAssumed) := splitCrossMerged cross owned
  -- A project/project pair that a dependency also declares is flagged by rule (b) of
  -- `crossMergedDecls`; `merged` already holds exactly its versions.
  let mergedNames := Std.HashSet.ofArray (merged.map (·.declName))
  let mergedAll := merged ++ crossWalkedAll.filter fun m => !mergedNames.contains m.declName
  let mergedMap : Std.HashMap Name MergedDecl :=
    mergedAll.foldl (init := {}) fun acc m => acc.insert m.declName m
  let crossNames := cross.map (·.1)
  let consts := crossNames.foldl (init := consts) fun acc n =>
    if pFilter.contains env n then acc
    else match env.find? n with
      | some ci => acc.push (n, ci)
      | none => acc
  let tagSet := externallyVerifiedNames env pFilter consts
  let attrs ← computeAttributes env projectPath fileCache pathCache consts tagSet.tagged
  let propTyped ← propTypedNames env (externalRule3Candidates env consts)
  let trust := computeTrustBase env consts tagSet.tagged mergedMap propTyped
    (Std.HashSet.ofArray crossAssumed)
  let taint := runProjectTaint env pFilter consts trust mergedAll crossNames crossAssumed
  let constants := consts.foldl (init := ({} : Std.HashSet Name)) fun s (n, _) => s.insert n
  let (scanOnlyTags, tagOnly) := tagAudit env attrs tagSet.tagged
  let generatedAxioms := generatedTrustedAxioms env consts trust
  return ({ trust, taint, constants, merged := merged.map (·.declName),
            crossMerged := crossAssumed, crossWalked := crossWalkedAll.map (·.declName),
            tagSet, scanOnlyTags, tagOnly, generatedAxioms, pSize := consts.size, moduleCount },
          attrs)

/-- A trusted declaration whose *statement* names `sorryAx` directly: its meaning is
    unknown. Blocking still applies; this is a warning, not a status change. Only a
    literal occurrence is detected — a statement that reaches `sorry` through another
    project constant (`axiom a : p` with `def p : Prop := sorry`) is not. -/
def formatTypeTaintWarning (n : Name) : String :=
  s!"Warning: trusted declaration {n} names `sorry` directly in its statement"

/-- Printed when the full project module set could not be co-imported. The modules
    left out are outside the selection's import closure, so no emitted status rests
    on them; the `check-axioms` audit does not cover them. -/
def formatFallbackWarning (notImported : Nat) : String :=
  s!"Warning: {notImported} project module(s) not imported (full import failed); they are \
    outside the selection's import closure, so no emitted status depends on them, but \
    check-axioms does not audit them"

/-- Printed for an atom whose Lean name is not in P: the walk never assessed it, so it
    gets no `verification-status`. Every emitted atom is a project constant by
    construction; this firing is a bug signal, never silently "clean". -/
def formatUnknownAtomWarning (atom : String) : String :=
  s!"Warning: atom {atom} is not a project constant the kernel walk covered; \
    no verification-status assigned"

/-- One-line summary of the pass, printed by `extract` and `check-axioms`. -/
def formatTaintSummary (pt : ProjectTaint) : String :=
  s!"Project constants: {pt.pSize} in {pt.moduleCount} module(s) | trusted: {pt.trust.size} | \
    direct sorry carriers: {pt.taint.direct.size} | tainted: {pt.taint.tainted.size}"

/-- One-line account of where rule 2 got its tag set from. -/
def formatTagSetLine (ts : TagSet) : String :=
  if ts.extensions.isEmpty then
    s!"externally_verified tag set: {ts.tagged.size} name(s); no registration of the attribute \
      found in the project modules' olean entries"
  else
    s!"externally_verified tag set: {ts.tagged.size} name(s) from \
      {", ".intercalate (ts.extensions.map (·.toString)).toList}"

/-- A `check-axioms` report line. `[direct]`: the constant's own type or value names
    `sorryAx`. `[not emitted]`: not an atom — a constant `extract` never publishes
    (no declaration range, internal name, constructor, unselected module), which is
    precisely the shape that used to be trusted silently. -/
def formatTaintedLine (n : Name) (direct emitted : Bool) : String :=
  s!"  {n}" ++ (if direct then " [direct]" else "") ++ (if emitted then "" else " [not emitted]")

/-- How many merged names the warning lists individually. -/
def maxListedMerged : Nat := 10

/-- `a, b, c, … and N more`, capped at `maxListedMerged`. -/
private def listNames (names : Array Name) : String :=
  let shown := names.extract 0 maxListedMerged
  let listed := ", ".intercalate (shown.map (·.toString)).toList
  let more := if names.size > shown.size then s!", … and {names.size - shown.size} more" else ""
  listed ++ more

/-- Printed when project modules restate a theorem with the same statement and the
    importer kept one proof (`ProjectTaint.merged`). Empty when there are none. -/
def formatMergedWarning (names : Array Name) : String :=
  if names.isEmpty then "" else
    s!"Warning: {names.size} declaration name(s) are declared by more than one project module \
      with the same statement, and Lean kept one proof: {listNames names}; the walk follows every \
      version's dependencies and no `@[externally_verified]` on them is honoured"

/-- Printed for `ProjectTaint.crossMerged`. Empty when there are none. -/
def formatCrossMergedWarning (names : Array Name) : String :=
  if names.isEmpty then "" else
    s!"Warning: {names.size} declaration name(s) are declared by a project module whose olean \
      the preflight could not read and by another module, and Lean kept one body: \
      {listNames names}; the project's body is invisible, so they are treated as resting on \
      `sorry` (unverified, every caller verified) and no trust rule applies to them"

/-- Printed for `ProjectTaint.crossWalked`. Empty when there are none. -/
def formatCrossWalkedNote (names : Array Name) : String :=
  if names.isEmpty then "" else
    s!"Note: {names.size} declaration name(s) are declared by a project module and by a module \
      outside the project (a dependency), and Lean kept one body: {listNames names}; the walk \
      follows the project's own version(s), the other body is in the trusted base, and no \
      `@[externally_verified]` on them is honoured"

/-- Printed per `ProjectTaint.scanOnlyTags` entry. The line states what the audit knows —
    set membership — not the final status: an `axiom` in this position is still trusted by
    rule 1. -/
def formatScanOnlyTagLine (n : Name) : String :=
  s!"Divergence(tag): {n} header shows @[externally_verified] naming it, but the attribute's \
    tag set does not contain it; the source text does not decide trust"

/-- Printed per `ProjectTaint.tagOnly` entry. Likewise membership only: a merged or
    cross-boundary name in the set is still not trusted by rule 2 (`mergedTrustedReason`). -/
def formatTagOnlyLine (n : Name) : String :=
  s!"Note(tag): {n} is tagged externally_verified by an `attribute` command or a macro; its \
    header does not show the tag; the tag set decides trust"

/-- Printed per `ProjectTaint.generatedAxioms` entry. Visibility only: the axiom is
    trusted by rule 1 like any other; whether a generated axiom should be is a spec
    decision not made here. -/
def formatGeneratedAxiomNote (n : Name) : String :=
  s!"Note(axiom): {n} is a generated project axiom (not a source-visible declaration, e.g. \
    from native_decide); trusted by rule 1"

/-- Header of the `check-axioms` listing of T. -/
def formatTrustHeader (n : Nat) : String :=
  s!"{n} trusted constant(s) (T):"

/-- A `check-axioms` T line: the constant, its `trusted-reason`, the module the
    environment attributes it to and, for a rule-3 entry (`external`), its statement —
    the type is what a reviewer of a hand-written model has to judge. -/
def formatTrustedLine (n : Name) (reason : String) (module : Name) (type : Option String) : String :=
  s!"  {n} [{reason}] {module}" ++ (match type with | some t => s!" : {t}" | none => "")

/-- Print the type-taint, merged-declaration, cross-merge, tag-audit and generated-axiom
    diagnostics to stderr. -/
def reportTaintWarnings (pt : ProjectTaint) : IO Unit := do
  for n in pt.taint.typeTainted do
    IO.eprintln (formatTypeTaintWarning n)
  if !pt.merged.isEmpty then
    IO.eprintln (formatMergedWarning pt.merged)
  if !pt.crossMerged.isEmpty then
    IO.eprintln (formatCrossMergedWarning pt.crossMerged)
  if !pt.crossWalked.isEmpty then
    IO.eprintln (formatCrossWalkedNote pt.crossWalked)
  for n in pt.scanOnlyTags do
    IO.eprintln (formatScanOnlyTagLine n)
  for n in pt.tagOnly do
    IO.eprintln (formatTagOnlyLine n)
  for n in pt.generatedAxioms do
    IO.eprintln (formatGeneratedAxiomNote n)

end ProbeLean
