/-
  Shared attributes for probe-lean.
  Target projects import this module to use `@[primary_spec]`.
-/
import Lean

namespace ProbeLean

open Lean

/-- `@[primary_spec]` marks a theorem as the primary specification for the
definition it specifies. Consumed by `probe-lean extract` to populate the
`primary-spec` field on definition atoms. -/
initialize primarySpecAttr : TagAttribute ←
  registerTagAttribute `primary_spec
    "Marks a theorem as the primary specification for its subject definition."

end ProbeLean
