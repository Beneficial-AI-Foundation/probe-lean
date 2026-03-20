/-
  Shared attributes for probe-lean.
  Target projects import this module to use `@[primary_spec]` and
  `@[externally_verified]`.
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

/-- `@[externally_verified]` marks a theorem whose proof uses `sorry` but has
been verified externally (e.g., in Verus or another prover). Consumed by
`probe-lean extract` to populate the `attributes` field on atoms. -/
initialize externallyVerifiedAttr : TagAttribute ←
  registerTagAttribute `externally_verified
    "Marks a theorem as externally verified (sorry is intentional)."

end ProbeLean
