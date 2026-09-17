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
  /-- Names a project module declares whose other version the walk cannot see
      (`crossMergedNames`): treated as resting on `sorry`, never trusted. Sorted by
      name; reported as a warning. -/
  crossMerged : Array Name := #[]
  /-- |P|. -/
  pSize : Nat
  /-- Number of project modules imported. -/
  moduleCount : Nat

/-- Whether rule 2 of the trusted base can apply to a constant: it is a
    source-visible declaration (own range, not internal, not a constructor or
    recursor), not a generated companion and not a structure projection. Everything
    else cannot carry an `@[externally_verified]` mark of its own, however its source
    range reads — a projection of a one-line `structure` shares the structure's range
    *and* has its field name on the head line, which is why it is excluded by kind
    rather than left to `headerNamesDecl`. -/
def rule2Applies (env : Environment) (name : Name) (info : ConstantInfo) : Bool :=
  isSourceVisible env name info && !isCompanionName name && !env.isProjectionFn name

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

/-- Names a project module declares that the walk cannot see every body of, found
    after the import from the environment header alone (no dependence on the olean
    preflight): (a) a name in a project module's `constNames` that the environment
    attributes to another module — `finalizeImport` keeps the **first** owner's index
    and the **last** subsuming body, so this catches a same-statement restatement of
    a dependency theorem imported after it, and any project/project pair the
    preflight did not read (`knownMerged` are the ones it did, handled more precisely
    by `mergedChildren`); (b) a name declared by both a project module and a
    non-project module, whichever order they were imported in. In every case one of
    the two bodies is gone and it may be the one with the `sorry`, so the caller
    treats these names as direct carriers and trusts none of them. Sorted by name. -/
def crossMergedNames (env : Environment) (pFilter : ProjectFilter)
    (knownMerged : Std.HashSet Name) : Array Name := Id.run do
  let mods := env.header.moduleData
  let mut declared : Std.HashSet Name := {}
  let mut flagged : Std.HashSet Name := {}
  for i in [:mods.size] do
    if pFilter.moduleIdxs.contains i then
      for n in mods[i]!.constNames do
        declared := declared.insert n
        if env.getModuleIdxFor? n != some i && !knownMerged.contains n then
          flagged := flagged.insert n
  for i in [:mods.size] do
    if !pFilter.moduleIdxs.contains i then
      for n in mods[i]!.constNames do
        if declared.contains n then flagged := flagged.insert n
  flagged.toArray.qsort fun a b => a.toString < b.toString

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

/-- Attributes for the constants of P that can carry attributes: every
    source-visible declaration. Constants absent from the map have no attributes.
    With no `--module`/`--library` selection this is exactly the emitted atom set, so
    the scan runs once and `declInfoToAtom` reuses the result.

    A constant that shares a tagged declaration's range — a generated companion
    (`X.mvcgen_spec`), a `deriving` instance or a projection of a one-line structure
    — *shows* the scanned attributes here, as it always has: the emitted `attributes`
    array is unchanged, and the primary-spec signals keep reading them (the companion
    of a `@[step]` axiom is that axiom's spec proxy). What it does **not** get is
    trust from them: `DeclAttrs.ownExternallyVerified` is false when the head line
    does not name the constant, and `rule2Applies` is false for companions and
    projections regardless, so `computeTrustBase` ignores the shown tag. -/
def computeAttributes (env : Environment) (projectPath : System.FilePath) (fileCache : FileCache)
    (pathCache : ModulePathCache) (consts : Array (Name × ConstantInfo))
    : IO (Std.HashMap Name DeclAttrs) := do
  let modNames := env.allImportedModuleNames
  let mut attrs : Std.HashMap Name DeclAttrs := {}
  for (name, info) in consts do
    if !isSourceVisible env name info then
      continue
    let moduleName := (moduleNameOf modNames env name).getD .anonymous
    let range := getDeclSourceLoc env name
    let a ← declAttributes env projectPath fileCache pathCache name moduleName range
      (scanSource := true) (isInstance := getDeclKind env name info == .instance)
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
    is reported and counted as a proof (fail closed). -/
def propTypedNames (env : Environment) (cands : Array (Name × ConstantInfo))
    : IO (Std.HashSet Name) := do
  if cands.isEmpty then return {}
  let act : MetaM (Std.HashSet Name × Array Name) := do
    let mut props : Std.HashSet Name := {}
    let mut failed : Array Name := #[]
    for (name, info) in cands do
      try
        if ← Meta.isProp info.type then props := props.insert name
      catch _ =>
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
    rule 2 needs `rule2Applies` and the declaration's own tag
    (`DeclAttrs.ownExternallyVerified`). A name in `merged` is decided by
    `mergedTrustedReason` over all of its versions instead, and a name in `excluded`
    (`crossMergedNames`) is never trusted. -/
def computeTrustBase (env : Environment) (consts : Array (Name × ConstantInfo))
    (attrs : Std.HashMap Name DeclAttrs)
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
        let ownTag := (attrs.getD name default).ownExternallyVerified
        trustedReason kind (rule2Applies env name info && ownTag) moduleName
          (kind == .theorem || propTyped.contains name)
    if let some r := reason then
      trust := trust.insert name r
  return trust

/-- The walk over P with T blocked; merged declarations follow every version's
    dependencies (`mergedChildrenMap`), and cross-merged names (`crossMergedNames`)
    count as project constants whatever module the environment attributes them to,
    with `sorryAx` added to their out-edges: the body the walk cannot see is taken to
    be the sorried one. -/
def runProjectTaint (env : Environment) (pFilter : ProjectFilter)
    (consts : Array (Name × ConstantInfo)) (trust : Std.HashMap Name String)
    (merged : Array MergedDecl := #[]) (crossMerged : Array Name := #[]) : TaintResult :=
  let crossSet := Std.HashSet.ofArray crossMerged
  let override := crossMerged.foldl (init := mergedChildrenMap merged) fun m n =>
    m.insert n ((m.getD n (constChildren env n)).push sorryAxiomName)
  projectTaint env (fun n => pFilter.contains env n || crossSet.contains n) trust.contains
    (consts.map (·.1)) (childrenOverride := override)

/-- P, T and the walk in one call. Returns the attribute map too, so the atom builder
    does not scan the sources a second time. `merged` is what the co-import preflight
    read for the imported modules (`Atomize.importProjectEnvWithFallback`); the
    cross-boundary merges are found here from the environment itself, and the names
    among them that the environment attributes to a non-project module are added to
    P so they are walked and reported. -/
def computeProjectTaint (env : Environment) (projectPath : System.FilePath)
    (pFilter : ProjectFilter) (fileCache : FileCache) (pathCache : ModulePathCache)
    (consts : Array (Name × ConstantInfo)) (moduleCount : Nat)
    (merged : Array MergedDecl := #[])
    : IO (ProjectTaint × Std.HashMap Name DeclAttrs) := do
  let mergedMap : Std.HashMap Name MergedDecl :=
    merged.foldl (init := {}) fun acc m => acc.insert m.declName m
  let crossMerged := crossMergedNames env pFilter
    (merged.foldl (init := {}) fun s m => s.insert m.declName)
  let consts := crossMerged.foldl (init := consts) fun acc n =>
    if pFilter.contains env n then acc
    else match env.find? n with
      | some ci => acc.push (n, ci)
      | none => acc
  let attrs ← computeAttributes env projectPath fileCache pathCache consts
  let propTyped ← propTypedNames env (externalRule3Candidates env consts)
  let trust := computeTrustBase env consts attrs mergedMap propTyped
    (Std.HashSet.ofArray crossMerged)
  let taint := runProjectTaint env pFilter consts trust merged crossMerged
  let constants := consts.foldl (init := ({} : Std.HashSet Name)) fun s (n, _) => s.insert n
  return ({ trust, taint, constants, merged := merged.map (·.declName), crossMerged,
            pSize := consts.size, moduleCount }, attrs)

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
    s!"Warning: {names.size} declaration name(s) are declared by a project module and by a \
      module the walk cannot see into (a dependency package, or a module the preflight could \
      not read), and Lean kept one body: {listNames names}; they are treated as resting on \
      `sorry` (unverified, every caller verified) and no trust rule applies to them"

/-- Print the type-taint, merged-declaration and cross-merge warnings to stderr. -/
def reportTaintWarnings (pt : ProjectTaint) : IO Unit := do
  for n in pt.taint.typeTainted do
    IO.eprintln (formatTypeTaintWarning n)
  if !pt.merged.isEmpty then
    IO.eprintln (formatMergedWarning pt.merged)
  if !pt.crossMerged.isEmpty then
    IO.eprintln (formatCrossMergedWarning pt.crossMerged)

end ProbeLean
