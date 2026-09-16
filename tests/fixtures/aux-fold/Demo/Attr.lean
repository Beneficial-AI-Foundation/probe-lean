import Lean

/-!
Target-side machinery the sorry-taint fixture needs.

- `externally_verified` registered **by the target** under its own extension name.
  probe-lean's handle lookup (`ProbeLean.externallyVerifiedAttr.hasTag`) cannot see
  it, so the source scan of the `@[…]` block is what must fire — the
  curve25519-dalek-lean-verify pattern.
- `step_theorem`, a stand-in for Aeneas's `@[step]`: one command that declares
  `theorem X` and a companion `theorem X.mvcgen_spec := X`. Both come from the same
  syntax node, so both carry the **same declaration range**, which is what makes the
  companion inherit the parent's attributes under a naive source scan.
-/

open Lean Elab Command

initialize externallyVerifiedAttr : TagAttribute ←
  registerTagAttribute `externally_verified "proof discharged outside Lean (fixture)"

syntax (name := stepTheorem) declModifiers "step_theorem " ident " : " term " := " term : command

macro_rules
  | `($mods:declModifiers step_theorem $id:ident : $ty := $val) => do
    let comp := mkIdentFrom id (id.getId ++ `mvcgen_spec)
    `($mods:declModifiers theorem $id : $ty := $val
      theorem $comp : $ty := $id)
