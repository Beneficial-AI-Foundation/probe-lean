/-
  Shared attributes for probe-lean.
  Target projects import this module to use `@[primary_spec]`,
  `@[externally_verified]`, and the security-protocol classification tags
  (`@[scheme_def]`, `@[construction_def]`, `@[correctness_spec]`,
  `@[security_spec]`).
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

-- ============================================================
-- Security-protocol classification tag hooks.
--
-- These four tags are *registered* here so target projects that
-- `import ProbeLean.Attrs` can annotate declarations with them, but probe-lean
-- itself no longer interprets them: the security-protocol classifier lives in
-- the standalone `probe-vcvio` tool, which reads the tags back off the generic
-- `attributes` array that `probe-lean extract` emits. Kept here (rather than in
-- a separate shim) so existing target projects need no migration.
-- ============================================================

/-- `@[scheme_def]` marks a declaration as a cryptographic *scheme* — the
abstract interface (a `structure`/`class` bundling operations). -/
initialize schemeDefAttr : TagAttribute ←
  registerTagAttribute `scheme_def
    "Marks a declaration as a cryptographic scheme (abstract interface)."

/-- `@[construction_def]` marks a declaration as a concrete *construction* —
a definition realising a scheme. -/
initialize constructionDefAttr : TagAttribute ←
  registerTagAttribute `construction_def
    "Marks a declaration as a concrete construction of a scheme."

/-- `@[correctness_spec]` marks a declaration (game, predicate, or theorem) as
a *correctness* property of a construction or scheme. -/
initialize correctnessSpecAttr : TagAttribute ←
  registerTagAttribute `correctness_spec
    "Marks a declaration as a correctness property."

/-- `@[security_spec]` marks a declaration (game, advantage, or theorem) as a
*security* property of a construction or scheme. -/
initialize securitySpecAttr : TagAttribute ←
  registerTagAttribute `security_spec
    "Marks a declaration as a security property."

end ProbeLean
