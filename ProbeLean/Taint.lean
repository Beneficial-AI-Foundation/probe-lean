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
  /-- `false` when the full project module set could not be co-imported and P is
      the selection's import closure only. Every emitted atom's dependency closure
      is still inside P (see `Atomize.loadedProjectModules`); what is lost is the
      `check-axioms` audit of the modules left out, and the caller has printed
      `formatFallbackWarning`. -/
  importedAll : Bool
  /-- |P|. -/
  pSize : Nat
  /-- Number of project modules imported. -/
  moduleCount : Nat

/-- Whether rule 2 of the trusted base can apply to a constant: it is a
    source-visible declaration (own range, not internal, not a constructor or
    recursor) and not a generated companion. Everything else cannot carry an
    `@[externally_verified]` mark of its own, however its source range reads. -/
def rule2Applies (env : Environment) (name : Name) (info : ConstantInfo) : Bool :=
  isSourceVisible env name info && !isCompanionName name

/-- Attribute lists for the constants of P that can carry attributes: every
    source-visible declaration. Constants absent from the map have no attributes.
    With no `--module`/`--library` selection this is exactly the emitted atom set, so
    the scan runs once and `declInfoToAtom` reuses the result.

    A generated companion (`X.mvcgen_spec`) shares its parent's range and therefore
    *shows* the parent's scanned attributes here, as it always has — the emitted
    `attributes` array is unchanged, and the primary-spec signals keep reading them
    (the companion of a `@[step]` axiom is that axiom's spec proxy). What the
    companion does **not** get is trust from them: `rule2Applies` is false for it, so
    `computeTrustBase` ignores a scanned `externally_verified` on a companion. -/
def computeAttributes (env : Environment) (projectPath : System.FilePath) (fileCache : FileCache)
    (pathCache : ModulePathCache) (consts : Array (Name × ConstantInfo))
    : IO (Std.HashMap Name (Array String)) := do
  let modNames := env.allImportedModuleNames
  let mut attrs : Std.HashMap Name (Array String) := {}
  for (name, info) in consts do
    if !isSourceVisible env name info then
      continue
    let moduleName := (moduleNameOf modNames env name).getD .anonymous
    let range := getDeclSourceLoc env name
    let a ← declAttributes env projectPath fileCache pathCache name moduleName range
      (scanSource := true)
    attrs := attrs.insert name a
  return attrs

/-- T over P: `Trust.trustedReason` applied to every project constant. Rules 1 and 3
    need only the kind and module; rule 2 is gated by `rule2Applies`. -/
def computeTrustBase (env : Environment) (consts : Array (Name × ConstantInfo))
    (attrs : Std.HashMap Name (Array String)) : Std.HashMap Name String := Id.run do
  let modNames := env.allImportedModuleNames
  let mut trust : Std.HashMap Name String := {}
  for (name, info) in consts do
    let kind := getDeclKind env name info
    let moduleName := (moduleNameOf modNames env name).getD .anonymous
    match trustedReason kind (attrs.getD name #[]) moduleName (rule2Applies env name info) with
    | some reason => trust := trust.insert name reason
    | none => pure ()
  return trust

/-- The walk over P with T blocked. -/
def runProjectTaint (env : Environment) (pFilter : ProjectFilter)
    (consts : Array (Name × ConstantInfo)) (trust : Std.HashMap Name String) : TaintResult :=
  projectTaint env (pFilter.contains env) trust.contains (consts.map (·.1))

/-- P, T and the walk in one call. Returns the attribute map too, so the atom builder
    does not scan the sources a second time. -/
def computeProjectTaint (env : Environment) (projectPath : System.FilePath)
    (pFilter : ProjectFilter) (fileCache : FileCache) (pathCache : ModulePathCache)
    (consts : Array (Name × ConstantInfo)) (importedAll : Bool) (moduleCount : Nat)
    : IO (ProjectTaint × Std.HashMap Name (Array String)) := do
  let attrs ← computeAttributes env projectPath fileCache pathCache consts
  let trust := computeTrustBase env consts attrs
  let taint := runProjectTaint env pFilter consts trust
  let constants := consts.foldl (init := ({} : Std.HashSet Name)) fun s (n, _) => s.insert n
  return ({ trust, taint, constants, importedAll, pSize := consts.size, moduleCount }, attrs)

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

/-- Print the type-taint warnings to stderr. -/
def reportTypeTainted (pt : ProjectTaint) : IO Unit := do
  for n in pt.taint.typeTainted do
    IO.eprintln (formatTypeTaintWarning n)

end ProbeLean
