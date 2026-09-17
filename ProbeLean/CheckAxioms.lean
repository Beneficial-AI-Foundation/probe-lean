/-
  `check-axioms` command: a standalone `sorry` audit.

  Builds and imports a target project (via the shared `prepareProject` +
  `importProjectEnvWithFallback` used by `extract`) and runs the same kernel taint
  pass (`Taint.computeProjectTaint`) that decides `verification-status`, then lists
  every project constant that rests on an unexcused project `sorry` — atoms and
  non-atoms alike. Because the pass is shared, the listed set is by construction the
  set `extract` refuses to mark `transitively-verified`.
-/
import ProbeLean.Extract
import ProbeLean.Analysis
import ProbeLean.Taint

namespace ProbeLean

open Lean

/-- Print the report for a computed pass. `emitted` is the set of constants
    `extract` publishes as atoms (the selected, source-visible declarations). -/
def printTaintReport (pt : ProjectTaint) (emitted : Std.HashSet Name) : IO Unit := do
  IO.println (formatTaintSummary pt)
  IO.println (formatTagSetLine pt.tagSet)
  let sorted := pt.taint.tainted.toArray.qsort (·.toString < ·.toString)
  IO.println s!"{sorted.size} constant(s) rest on an unexcused project sorry:"
  for n in sorted do
    IO.println (formatTaintedLine n (pt.taint.direct.contains n) (emitted.contains n))

/-- Build, import, and report declarations that rest on an unexcused project `sorry`.
    Returns a process exit code. -/
def runCheckAxiomsInProject (projectPath : System.FilePath)
    (libraries : Option (Array String) := none) (moduleFilter : Option String := none)
    : IO UInt32 := do
  let prepared ← match ← prepareProject projectPath libraries moduleFilter with
    | .error code => return code
    | .ok r => pure r

  let (env, imported, pre) ← match ← importProjectEnvWithFallback projectPath
      prepared.allModules prepared.selectedModules prepared.nixMode prepared.orphans with
    | .error msg => IO.eprintln s!"Import failed: {msg}"; return 1
    | .ok r => pure r

  let pFilter := mkProjectFilter env (imported.map (·.name))
  let selFilter := mkProjectFilter env (prepared.selectedModules.map (·.name))
  let consts := projectConstants env pFilter
  let fileCache : FileCache ← IO.mkRef {}
  let pathCache : ModulePathCache ← IO.mkRef {}
  let (pt, _) ← computeProjectTaint env projectPath pFilter fileCache pathCache consts
    (moduleCount := imported.size) (merged := pre.merged) (owned := pre.owned)
  reportTaintWarnings pt
  let emitted := (getProjectDeclsFrom env consts selFilter).foldl
    (init := ({} : Std.HashSet Name)) fun s d => s.insert d.name
  printTaintReport pt emitted
  return 0

end ProbeLean
