import Lean

/-!
The SPQR `impl_def` shape: a `sorry` carrier added with `addDecl` and no declaration
range. `extract` never emits it as an atom, so the emitted dependency graph cannot
see the edge from `viaNoRange` to it and the graph-BFS reports `viaNoRange` clean;
the kernel walk sees the constant like any other and reports it tainted. That
disagreement is the `Divergence:` line the end-to-end check asserts on.
-/

open Lean Elab Command Term in
set_option warn.sorry false in
run_cmd do
  let (type, value) ← liftTermElabM do
    let v ← elabTerm (← `((sorry : (0 : Nat) < 5))) none
    Term.synthesizeSyntheticMVarsNoPostponing
    let v ← instantiateMVars v
    pure (← instantiateMVars (← Meta.inferType v), v)
  liftCoreM <| addDecl (.thmDecl { name := `noRangeMid, levelParams := [], type, value })

/-- Rests on a carrier `extract` never emits: `verified` (locally sorry-free, rests
on an unexcused project `sorry`), never `transitively-verified`. -/
theorem viaNoRange : (0 : Nat) < 5 := noRangeMid
