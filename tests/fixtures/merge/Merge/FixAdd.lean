import Lean

/-!
A merged `.mutual` name (issue #135). This module adds `Merge.Fix.mutual` with
`addDecl` and no declaration range, the shape of a generated `partial_fixpoint` body.
`Merge.FixRestate` states the same theorem in source, with a range. In the merged
environment this module owns the name, but `extract` emits the atom from
`Merge.FixRestate`. So an edge to it does not dangle and must stay. Lean's importer
merges only theorems, so the constant is a theorem here.
-/

open Lean Elab Command in
run_cmd liftCoreM <| addDecl (.thmDecl
  { name := `Merge.Fix.mutual, levelParams := [], type := mkConst ``True,
    value := mkConst ``True.intro })
