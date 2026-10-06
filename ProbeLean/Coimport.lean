/-
  Coimport: preflight co-importability check.

  Atomize imports the union of a project's built modules into one Lean
  environment, so two modules declaring the same fully-qualified name make
  `importModules` abort — a layout that builds fine under Lake (which
  compiles modules independently) and is common in benchmark-style repos with
  parallel problem/solution files. This module detects that situation BEFORE
  the expensive import by reading each module's own constants from its
  `.olean` header (`Lean.readModuleData`), and formats an actionable
  diagnostic listing the duplicated names and their owning modules.

  Exactness: the check replicates the importer's duplicate-tolerance rule
  (`subsumesInfo` in core `Lean.Environment`, a private def) so it never
  rejects a project the importer would accept. Known misses — collisions
  involving dependency modules, oleans the scan had to skip, or duplicates
  inside module-system modules that the exported level hides — are
  under-detection only: the import then fails as before and lands on the
  fallback hint in `Atomize.lean`. Only the base `.olean` of each module is
  read. For a module-system module that is the exported level: a `public
  theorem` appears as an axiom of the same type (tolerated exactly as the
  importer tolerates the pair), but so does a non-exposed `public def`, and two
  same-type axioms are tolerated here while the importer's `isPropCheap` rejects
  them (`constSubsumes`), so a def/def collision between module-system modules
  is found at import time (the `module-collision` fixture). The split parts are
  checked for existence only (`CoimportPreflight.proofless`).

  This is a diagnostic, nothing more: the bodies it reads are not used by the
  taint pass. The tolerated duplicates — a name two modules declare with the
  same statement, of which the importer keeps one body — are found after the
  import from the environment header (`Taint.headerMerges`), which keeps every
  module's own constants.
-/
import Lean
import ProbeLean.Environment

namespace ProbeLean

open Lean

/-- A declaration name declared by more than one project module and not
    exempt under the importer's subsumption rule (a co-import collision). -/
structure DeclCollision where
  declName : Name
  modules  : Array Name   -- sorted, ≥ 2 entries
  deriving Inhabited

/-- Pure replica of the importer's duplicate-tolerance rule (`subsumesInfo`,
    private in core `Lean.Environment`): a duplicate is tolerated when name,
    type, and levelParams are syntactically equal AND the pair is thm/thm
    (same `all`), thm/axiom, or axiom/axiom. The importer also requires
    axiom/axiom types to be cheaply-Prop. That check needs the full imported
    constant map, because the type's head can live in a dependency, and the
    preflight does not have that map. So this replica is lenient there.
    Leniency only under-detects: a missed collision still fails at import time
    and hits the fallback hint. Strictness instead can falsely abort a project
    that the importer accepts. -/
def constSubsumes (a b : ConstantInfo) : Bool :=
  a.name == b.name &&
    a.type == b.type &&
    a.levelParams == b.levelParams &&
    match a, b with
    | .thmInfo t₁, .thmInfo t₂ => t₁.all == t₂.all
    | .thmInfo t₁, .axiomInfo a₂ => t₁.all == [a₂.name] && !a₂.isUnsafe
    | .axiomInfo a₁, .axiomInfo a₂ => a₁.isUnsafe == a₂.isUnsafe
    | _, _ => false

/-- Names skipped in the *displayed* collision list: internal machinery and
    hygienic names. They are still part of detection, which keys on the raw
    `Name` like the importer. But the compiler module-qualifies private and
    hygienic names. So a genuine collision on them always comes with a
    user-facing one, and displaying them adds only noise. -/
def isDisplayableCollisionName (n : Name) : Bool :=
  !n.isInternal && !n.hasMacroScopes

/-- Pure core of the preflight. The input is each module's own declarations as
    `(declared name, constant info)` pairs. Each pair zips `ModuleData.constNames`
    with `ModuleData.constants` by position, the same way the importer iterates
    them. The result is the names owned by more than one module where some owner
    pair is not mutually subsumable, so the import will fail. The importer
    tolerates a duplicated name whose every owner pair *is* subsumable (it keeps
    one version), so such a name is not a collision. Detection keys on the raw
    declared `Name` from the olean. Display filtering happens in
    `formatCoimportError`, never here. The result and its module lists are sorted
    for deterministic output (P14). -/
def findCoimportCollisions (moduleDecls : Array (Name × Array (Name × ConstantInfo))) :
    Array DeclCollision := Id.run do
  let owners : Std.HashMap Name (Array (Name × ConstantInfo)) :=
    moduleDecls.foldl (init := {}) fun owners (modName, decls) =>
      decls.foldl (init := owners) fun owners (cname, cinfo) =>
        owners.insert cname ((owners.getD cname #[]).push (modName, cinfo))
  let mut collisions : Array DeclCollision := #[]
  for (declName, os) in owners.toList do
    if os.size > 1 then
      let mut fatal := false
      for i in [0:os.size] do
        for j in [i+1:os.size] do
          let a := os[i]!.2
          let b := os[j]!.2
          if !(constSubsumes a b || constSubsumes b a) then
            fatal := true
      if fatal then
        let sorted := os.qsort fun a b => a.1.toString < b.1.toString
        collisions := collisions.push { declName, modules := sorted.map (·.1) }
  return collisions.qsort fun a b => a.declName.toString < b.declName.toString

/-- What the preflight found. -/
structure CoimportPreflight where
  /-- Names that make the import fail. -/
  collisions : Array DeclCollision := #[]
  /-- Modules whose olean is unreadable. The scan is partial for them. -/
  skipped : Array ProjectModule := #[]
  /-- Module-system modules (`module` header) whose `.olean.server` or
      `.olean.private` part is missing. `importModules` at `OLeanLevel.private`
      loads the private part only when both exist (`findOLeanParts`). Otherwise it
      fails with "missing data file" for the module. The abort here is the readable
      form of that failure, with the remedy. -/
  proofless : Array ProjectModule := #[]
  deriving Inhabited

/-- Whether a module-system module's split parts are both next to its base olean.
    Mirrors `findOLeanParts`: the private part is used only when `.olean.server`
    and `.olean.private` both exist. -/
def hasOLeanParts (m : ProjectModule) : IO Bool := do
  let server := m.oleanPath.addExtension "server"
  let priv := m.oleanPath.addExtension "private"
  return (← server.pathExists) && (← priv.pathExists)

/-- Run the preflight over the (already filtered) project modules: read each
    module's base olean and classify duplicated names into collisions. If a
    module's olean is unreadable, the preflight skips it with a stderr warning and
    returns it in `skipped`. Callers can then report that the scan was partial. A
    skip alone must never fail the extraction. A module-system module without its
    split parts goes into `proofless`. It fails the import of *these* modules,
    because Lean stops on the missing part. The caller decides whether the
    extraction then aborts or retries a narrower selection
    (`importProjectEnvSelecting`). -/
def detectCoimportCollisions (modules : Array ProjectModule) : IO CoimportPreflight := do
  let mut moduleDecls : Array (Name × Array (Name × ConstantInfo)) := #[]
  let mut skipped : Array ProjectModule := #[]
  let mut proofless : Array ProjectModule := #[]
  for m in modules do
    try
      -- The CompactedRegion backing the ModuleData is deliberately not freed:
      -- the ConstantInfo values point into it, and extract is short-lived.
      -- Only the project's own (small) modules are read here — dependency
      -- oleans, which dominate memory, are never touched by the preflight.
      let (data, _) ← readModuleData m.oleanPath
      if data.isModule && !(← hasOLeanParts m) then
        proofless := proofless.push m
      else
        moduleDecls := moduleDecls.push (m.name, data.constNames.zip data.constants)
    catch e =>
      IO.eprintln s!"Warning: co-importability preflight could not read {m.oleanPath} (module {m.name}): {e}"
      IO.eprintln "  The module is skipped, so the preflight may be incomplete."
      skipped := skipped.push m
  return { collisions := findCoimportCollisions moduleDecls, skipped, proofless }

/-- The abort message for `CoimportPreflight.proofless`. -/
def formatProoflessError (proofless : Array ProjectModule) : String :=
  let names := (proofless.map (·.name.toString)).qsort (· < ·)
  s!"{proofless.size} module-system module(s) have no `.olean.private`/`.olean.server` part next to \
    their `.olean`: {", ".intercalate names.toList}.\n\
    Lean loads a `module` file's proofs from its private part and fails the import without it \
    (\"missing data file\"). Rebuild the project (`lake build`) so the split parts exist, or \
    remove the stale oleans."

/-- How many duplicated names are listed individually in the diagnostic. -/
def maxDisplayedCollisions : Nat := 10

/-- One-line note listing modules the preflight did not scan (empty string
    when none were skipped). Shared by the preflight abort message and the
    post-import fallback hint. -/
def skippedModulesNote (skipped : Array ProjectModule) : String :=
  if skipped.isEmpty then ""
  else
    let names := skipped.map (·.name.toString) |>.qsort (· < ·)
    s!"\nNote: {skipped.size} module(s) could not be scanned (unreadable .olean): " ++
      ", ".intercalate names.toList ++
      "\nThe check may be incomplete."

/-- Pick the module suggested in the `--module` example. `--module` selects
    the named module *plus its submodules* (prefix semantics). So prefer a
    collision member that is not a proper prefix of another member. A root that
    also covers its colliding submodule re-selects both. -/
def pickExampleModule (c : DeclCollision) : Option Name :=
  let notPrefixOfOther := c.modules.find? fun m =>
    !c.modules.any fun other => other != m && other.toString.startsWith (m.toString ++ ".")
  notPrefixOfOther <|> c.modules[0]?

/-- Format the preflight abort message: the capped collision list, the
    co-importability requirement, structural fixes, and the `--module`
    escape hatch for manual runs. -/
def formatCoimportError (collisions : Array DeclCollision)
    (skipped : Array ProjectModule) : String := Id.run do
  let displayable := collisions.filter fun c => isDisplayableCollisionName c.declName
  -- Internal names are hidden from the list as noise — unless they are the
  -- ONLY evidence, in which case hiding them would leave the message with no
  -- names at all.
  let listed := if displayable.isEmpty then collisions else displayable
  let shown := listed.extract 0 maxDisplayedCollisions
  let mut lines : Array String := #[]
  lines := lines.push s!"Co-importability check failed: {collisions.size} declaration name(s) are declared by more than one module."
  lines := lines.push ""
  for c in shown do
    lines := lines.push s!"  {c.declName} — declared in: {", ".intercalate (c.modules.map (·.toString)).toList}"
  if listed.size > shown.size then
    lines := lines.push s!"  … and {listed.size - shown.size} more duplicated name(s)"
  if !displayable.isEmpty && collisions.size > displayable.size then
    lines := lines.push s!"  (plus {collisions.size - displayable.size} internal/auxiliary duplicated name(s) not shown)"
  lines := lines.push ""
  lines := lines.push "probe-lean imports all built modules into a single Lean environment. Lake"
  lines := lines.push "compiles each module independently, so the project builds — but Lean forbids"
  lines := lines.push "duplicate declarations in one environment, so extraction cannot proceed."
  lines := lines.push ""
  lines := lines.push "Fix the project structure: give each variant family its own namespace, or"
  lines := lines.push "have the dependent module `import` the shared module instead of restating"
  lines := lines.push "its definitions."
  if let some c := collisions[0]? then
    if let some m := pickExampleModule c then
      lines := lines.push ""
      lines := lines.push "For a manual run, a non-conflicting subset can be extracted with --module,"
      lines := lines.push s!"e.g.: probe-lean extract . --module {m}"
      lines := lines.push "(--module also selects submodules of the named module; --library matches module-name roots, not lakefile library names)."
  lines := lines.push ""
  lines := lines.push "See README \"Supported Projects\" for the co-importability requirement."
  return "\n".intercalate lines.toList ++ skippedModulesNote skipped

end ProbeLean
