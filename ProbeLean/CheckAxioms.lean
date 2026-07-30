/-
  `check-axioms` command: a standalone `sorry` audit.

  Builds and imports a target project (via the shared `prepareProject` +
  `importProjectEnv` used by `extract`), then reports every declaration that
  `extract` would emit as an atom whose *complete* transitive closure depends on
  the `sorryAx` axiom — the kernel ground truth for "rests on a sorry", independent
  of probe-lean's own dependency graph (see `AxiomCheck`).
-/
import ProbeLean.Extract
import ProbeLean.Analysis
import ProbeLean.AxiomCheck

namespace ProbeLean

open Lean

/-- Build, import, and report declarations that transitively depend on `sorryAx`.
    Returns a process exit code. -/
def runCheckAxiomsInProject (projectPath : System.FilePath)
    (libraries : Option (Array String) := none) (moduleFilter : Option String := none)
    : IO UInt32 := do
  let (filteredModules, nixMode, _) ←
    match ← prepareProject projectPath libraries moduleFilter with
    | .error code => return code
    | .ok r => pure r

  let env ← match ← importProjectEnv projectPath filteredModules nixMode with
    | .error msg => IO.eprintln s!"Import failed: {msg}"; return 1
    | .ok env => pure env

  -- Audit exactly the declarations extract emits as atoms: `getProjectDecls` applies
  -- the same isInternalName / project / ctor-rec / no-source-location filtering, so
  -- this is a faithful cross-check of the emitted atom set.
  let moduleNames := filteredModules.map (·.name)
  let names := (getProjectDecls env moduleNames).map (·.name)
  let flagged := sorryReachingNames env names        -- one shared-memo pass
  let sorted := (names.filter flagged.contains).qsort (·.toString < ·.toString)
  IO.println s!"Checked {names.size} declaration(s); {sorted.size} depend on `sorryAx`:"
  for n in sorted do
    IO.println s!"  {n}"
  return 0

end ProbeLean
