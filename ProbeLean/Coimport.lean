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
  involving dependency modules, module-system split parts (`.olean.private`),
  or oleans the scan had to skip — are under-detection only: the import then
  fails as before and lands on the fallback hint in `Atomize.lean`.
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
    (same `all`), thm/axiom, or axiom/axiom. The importer additionally
    requires axiom/axiom types to be cheaply-Prop, but that check needs the
    full imported constant map (the type's head may live in a dependency),
    which the preflight doesn't have. We are deliberately lenient there:
    leniency only under-detects, and a missed collision still fails at import
    time and hits the fallback hint — whereas strictness could falsely abort
    a project the importer accepts. -/
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
    hygienic names. They are still part of detection (which keys on the raw
    `Name`, exactly like the importer) — but private/hygienic names are
    module-qualified by the compiler, so a genuine collision on them always
    accompanies a user-facing one and displaying them adds only noise. -/
def isDisplayableCollisionName (n : Name) : Bool :=
  !n.isInternal && !n.hasMacroScopes

/-- Pure core of the preflight: given each module's own declarations as
    `(declared name, constant info)` pairs — the positional pairing of
    `ModuleData.constNames` with `ModuleData.constants`, which is exactly how
    the importer iterates them — return the names owned by more than one
    module where some owner pair is not mutually subsumable. Detection keys
    on the raw declared `Name` from the olean — display filtering happens in
    `formatCoimportError`, never here. Result and per-collision module lists
    are sorted for deterministic output (P14). -/
def findCoimportCollisions (moduleDecls : Array (Name × Array (Name × ConstantInfo))) :
    Array DeclCollision := Id.run do
  let mut owners : Std.HashMap Name (Array (Name × ConstantInfo)) := {}
  for (modName, decls) in moduleDecls do
    for (cname, cinfo) in decls do
      owners := owners.insert cname ((owners.getD cname #[]).push (modName, cinfo))
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
        let mods := (os.map (·.1)).qsort fun a b => a.toString < b.toString
        collisions := collisions.push { declName, modules := mods }
  return collisions.qsort fun a b => a.declName.toString < b.declName.toString

/-- Run the preflight over the (already filtered) project modules: read each
    module's base `.olean` and detect collisions. A module whose olean cannot
    be read is skipped with a stderr warning and returned in the second
    component, so callers can surface that the scan was partial — a skip
    alone must never fail the extraction. -/
def detectCoimportCollisions (modules : Array ProjectModule) :
    IO (Array DeclCollision × Array ProjectModule) := do
  let mut moduleDecls : Array (Name × Array (Name × ConstantInfo)) := #[]
  let mut skipped : Array ProjectModule := #[]
  for m in modules do
    try
      -- The CompactedRegion backing the ModuleData is deliberately not freed:
      -- the ConstantInfo values point into it, and extract is short-lived.
      -- Only the project's own (small) modules are read here — dependency
      -- oleans, which dominate memory, are never touched by the preflight.
      let (data, _) ← readModuleData m.oleanPath
      moduleDecls := moduleDecls.push (m.name, data.constNames.zip data.constants)
    catch e =>
      IO.eprintln s!"Warning: co-importability preflight could not read {m.oleanPath} (module {m.name}): {e}"
      IO.eprintln "  The module is skipped, so the preflight may be incomplete."
      skipped := skipped.push m
  return (findCoimportCollisions moduleDecls, skipped)

/-- How many duplicated names are listed individually in the diagnostic. -/
def maxDisplayedCollisions : Nat := 10

/-- One-line note listing modules the preflight could not scan (empty string
    when none were skipped). Shared by the preflight abort message and the
    post-import fallback hint. -/
def skippedModulesNote (skipped : Array ProjectModule) : String :=
  if skipped.isEmpty then ""
  else
    let names := skipped.map (·.name.toString) |>.qsort (· < ·)
    s!"\nNote: {skipped.size} module(s) could not be scanned (unreadable .olean): " ++
      ", ".intercalate names.toList ++
      "\nThe check may be incomplete."

/-- Pick the module suggested in the `--module` example: `--module` selects
    the named module *plus its submodules* (prefix semantics), so prefer a
    collision member that is not a proper prefix of another member — naming a
    root that also covers its colliding submodule would re-select both. -/
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
