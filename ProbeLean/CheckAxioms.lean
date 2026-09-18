/-
  `check-axioms` command: a standalone `sorry` audit.

  Builds and imports a target project (via the shared `prepareProject` +
  `importProjectEnvWithFallback` used by `extract`) and runs the same kernel taint
  pass (`Taint.computeProjectTaint`) that decides `verification-status`, then lists
  every project constant that rests on an unexcused project `sorry` — atoms and
  non-atoms alike, followed by the trusted base T itself. Because the pass is shared,
  the listed set is by construction the set `extract` refuses to mark
  `transitively-verified`.
-/
import ProbeLean.Extract
import ProbeLean.Analysis
import ProbeLean.Taint

namespace ProbeLean

open Lean

/-- The statements of the rule-3 entries of T, pretty-printed on one line each: a
    hand-written model in a `*External` module is trusted once its type is not a
    proposition, with nothing checked about what that type says, so the type is what
    a reviewer has to judge. -/
def externalStatements (env : Environment) (names : Array Name) : IO (Std.HashMap Name String) := do
  if names.isEmpty then return {}
  let act : MetaM (Std.HashMap Name String) := do
    let mut out : Std.HashMap Name String := {}
    for n in names do
      if let some ci := env.find? n then
        let fmt ← Meta.ppExpr ci.type
        out := out.insert n ((fmt.pretty (width := 10000)).replace "\n" " ")
    return out
  let ctx : Core.Context := { fileName := "<probe-lean>", fileMap := default }
  let (out, _) ← (act.run' {} {}).toIO ctx { env }
  return out

/-- Print the report for a computed pass. `emitted` is the set of constants
    `extract` publishes as atoms (the selected, source-visible declarations). The
    tainted list comes first, then T: every trusted constant with its
    `trusted-reason` and module, and the statement of each rule-3 entry — the
    soundness claim ("clean modulo T") rests on exactly those constants, and
    `extract` shows only the ones that are atoms. -/
def printTaintReport (env : Environment) (pt : ProjectTaint) (emitted : Std.HashSet Name)
    : IO Unit := do
  IO.println (formatTaintSummary pt)
  IO.println (formatTagSetLine pt.tagSet)
  let sorted := pt.taint.tainted.toArray.qsort (·.toString < ·.toString)
  IO.println s!"{sorted.size} constant(s) rest on an unexcused project sorry:"
  for n in sorted do
    IO.println (formatTaintedLine n (pt.taint.direct.contains n) (emitted.contains n))
  let trusted := pt.trust.toArray.qsort (·.1.toString < ·.1.toString)
  let modNames := env.allImportedModuleNames
  let types ← externalStatements env
    (trusted.filterMap fun (n, r) => if r == "external" then some n else none)
  IO.println (formatTrustHeader trusted.size)
  for (n, reason) in trusted do
    IO.println (formatTrustedLine n reason ((moduleNameOf modNames env n).getD .anonymous) types[n]?)

/-- Build, import, and report declarations that rest on an unexcused project `sorry`.
    Returns a process exit code. -/
def runCheckAxiomsInProject (projectPath : System.FilePath)
    (libraries : Option (Array String) := none) (moduleFilter : Option String := none)
    : IO UInt32 := do
  let prepared ← match ← prepareProject projectPath libraries moduleFilter with
    | .error code => return code
    | .ok r => pure r

  let (env, imported) ← match ← importProjectEnvWithFallback projectPath
      prepared.allModules prepared.selectedModules prepared.nixMode prepared.orphans with
    | .error msg => IO.eprintln s!"Import failed: {msg}"; return 1
    | .ok r => pure r

  let pFilter := mkProjectFilter env (imported.map (·.name))
  let selFilter := mkProjectFilter env (prepared.selectedModules.map (·.name))
  let consts := projectConstants env pFilter
  let fileCache : FileCache ← IO.mkRef {}
  let pathCache : ModulePathCache ← IO.mkRef {}
  let (pt, _) ← computeProjectTaint env projectPath pFilter fileCache pathCache consts
    (moduleCount := imported.size)
  reportTaintWarnings pt
  let emitted := (getProjectDeclsFrom env consts selFilter).foldl
    (init := ({} : Std.HashSet Name)) fun s d => s.insert d.name
  printTaintReport env pt emitted
  return 0

end ProbeLean
