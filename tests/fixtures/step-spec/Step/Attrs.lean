import Lean

/-! A stub of `@[primary_spec]`, so the fixture needs no probe-lean dependency.
`registerTagAttribute` names its environment extension after the declaration
(`ref := decl_name%`). This stub has the same declaration name and attribute name as
`ProbeLean.primarySpecAttr` in `ProbeLean/Attrs.lean`, so the `.olean` entries are
the same as with the real attribute. It must be declared in a module that the
theorem modules import. -/

namespace ProbeLean

initialize primarySpecAttr : Lean.TagAttribute ←
  Lean.registerTagAttribute `primary_spec "Stub of the probe-lean primary_spec tag."

end ProbeLean
