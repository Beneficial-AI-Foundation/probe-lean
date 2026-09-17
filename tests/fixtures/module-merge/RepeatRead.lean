/-
  Regression for the split-part reader, `Coimport.readImportedModuleData`.

  A module-system module's `.olean`, `.olean.server` and `.olean.private` are one
  incremental compacted region split over three files; Lean's `saveModuleDataParts`
  says they "cannot be loaded with individual `readModuleData` calls". Separate calls
  happened to work for the first read in a process and segfaulted on the second read of
  the same module — which `extract`'s import fallback performs, preflighting the same
  modules up to three times. The reader now loads the parts with one
  `readModuleDataParts` call, and only when the base part's header says `module`
  (the importer's `getData?` rule), so stale part files next to a rebuilt non-`module`
  base are never opened.

  Run from the **probe-lean root** (its `lake env` sees `ProbeLean.Coimport`), after
  `lake build` in `tests/fixtures/module-merge` and `tests/fixtures/merge`:

      lake env lean --run tests/fixtures/module-merge/RepeatRead.lean
-/
import ProbeLean.Coimport

open ProbeLean Lean

def check (fs : IO.Ref (Array String)) (name : String) (ok : Bool) : IO Unit := do
  IO.println s!"  {if ok then "✓" else "✗"} {name}"
  if !ok then fs.modify (·.push name)

/-- Three reads of the same module-system module in one process. -/
def repeatedReads (fs : IO.Ref (Array String)) : IO Unit := do
  IO.println "Repeated reads of a module-system module's parts"
  let base : System.FilePath :=
    "tests/fixtures/module-merge/.lake/build/lib/lean/ModMerge/Bad.olean"
  let m : ProjectModule := { name := `ModMerge.Bad, oleanPath := base }
  for i in [0:3] do
    let (data, fromPrivate) ← readImportedModuleData m
    check fs s!"pass {i}: read from the private part" fromPrivate
    check fs s!"pass {i}: the base is a module" data.isModule
    check fs s!"pass {i}: the private level's constants are there" (data.constNames.contains `shared)

/-- A non-`module` base with (empty) stale part files next to it: the parts must not be
    opened. The files are created here and removed afterwards. -/
def staleParts (fs : IO.Ref (Array String)) : IO Unit := do
  IO.println "A non-module base next to stale part files"
  let base : System.FilePath := "tests/fixtures/merge/.lake/build/lib/lean/Merge/Bad.olean"
  let server := base.addExtension "server"
  let priv := base.addExtension "private"
  let hadServer ← server.pathExists
  let hadPriv ← priv.pathExists
  if !hadServer then IO.FS.writeFile server ""
  if !hadPriv then IO.FS.writeFile priv ""
  let (data, fromPrivate) ← readImportedModuleData { name := `Merge.Bad, oleanPath := base }
  if !hadServer then IO.FS.removeFile server
  if !hadPriv then IO.FS.removeFile priv
  check fs "read from the base part" (!fromPrivate)
  check fs "the base is not a module" (!data.isModule)
  check fs "the base's constants are there" (data.constNames.contains `shared)

def main : IO UInt32 := do
  let fs ← IO.mkRef (#[] : Array String)
  repeatedReads fs
  staleParts fs
  let failures ← fs.get
  if failures.isEmpty then
    IO.println "split-part read check: all assertions passed"
    return 0
  IO.eprintln s!"split-part read check: {failures.size} assertion(s) failed:"
  for f in failures do
    IO.eprintln s!"  {f}"
  return 1
