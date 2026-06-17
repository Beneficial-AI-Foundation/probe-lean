/-
  Classification catalogue for VCVio-based security-protocol projects.

  Fully-qualified VCVio anchor names consumed by the security-protocol
  classifier (Commit 4). Enumerated against **VCVio commit `ebea2fa`**; target
  repos may pin a newer, divergent VCVio (e.g. secure-messaging pins `1e984d2`),
  against which these FQNs were re-verified to resolve cleanly. Names are
  baked as Lean literals (no external config file). FQNs were verified by reading
  the pinned source (`section`s are transparent; only `namespace` affects names).

  These are illustrative *anchors*, not an exhaustive census: project theorems
  are usually anchored on project-own games (classified by naming and promoted),
  so the catalogue is a secondary safety net. The drift diagnostic
  (`driftWarnings`) surfaces catalogue staleness against a different VCVio
  version. See docs/classification-security-protocol.md.
-/
import Lean

namespace ProbeLean.Catalogue

open Lean

-- ============================================================
-- Anchor sets (VCVio @ ebea2fa)
-- ============================================================

/-- VCVio scheme *interface* types (structures/abbrevs bundling algorithm
operations). A project `def` whose return-type head is one of these is a
**construction**. `PKE_Alg` is an `abbrev` for `AsymmEncAlg`; because the naive
`codomainHeadOf` does not unfold aliases, both the alias head and the underlying
structure are listed so a `def … : PKE_Alg …` still matches. -/
def vcvioSchemeTypes : Array Name := #[
  `SymmEncAlg, `AsymmEncAlg, `AsymmEncAlg.ExplicitCoins, `PKE_Alg,
  `SignatureAlg, `KEMScheme, `PRFScheme, `PRGScheme,
  `CommitmentScheme, `SigmaProtocol, `OneWay.TrapdoorPermutation, `GenerableRelation
]

/-- Probabilistic-computation head constants: a `… → Bool` result headed by one
of these is a *game*. Base monads only — monad-transformer stacks over these
(`StateT`/`OptionT`/`WriterT`, e.g. `AddWriterT ℕ m (Bool × ℕ)` in
`Fischlin.lean`) are handled by the recognizer/naming path, not by adding
transformer heads here (which would misclassify `StateT σ Id Bool`). -/
def gameHeads : Array Name := #[`OracleComp, `ProbComp, `SPMF, `PMF]

/-- VCVio **correctness** anchors — walk targets for the correctness category. -/
def correctnessAnchors : Array Name := #[
  `SymmEncAlg.Complete, `SymmEncAlg.CompleteExp,
  `AsymmEncAlg.CorrectExp, `AsymmEncAlg.PerfectlyCorrect,
  `SignatureAlg.PerfectlyComplete,
  `KEMScheme.CorrectExp, `KEMScheme.PerfectlyCorrect,
  `CommitmentScheme.PerfectlyCorrect,
  `SigmaProtocol.PerfectlyComplete,
  `OneWay.TrapdoorPermutation.Correct
]

/-- VCVio **security** anchors — walk targets for the security category: the
security-experiment types, their advantages, and the per-primitive `*Advantage`,
game, and soundness definitions. -/
def securityAnchors : Array Name := #[
  -- generic experiment / advantage machinery
  `SecExp, `SecExp.advantage,
  `SecurityExp, `SecurityExp.secure, `SecurityGame, `SecurityGame.secureAgainst,
  `ProbComp.distAdvantage, `ProbComp.boolDistAdvantage,
  `ProbComp.guessAdvantage, `ProbComp.boolBiasAdvantage,
  -- asymmetric encryption: IND-CCA and IND-CPA families
  `AsymmEncAlg.IND_CCA_Advantage,
  `AsymmEncAlg.IND_CPA_advantage, `AsymmEncAlg.IND_CPA_signedAdvantageReal,
  `AsymmEncAlg.IND_CPA_experiment, `AsymmEncAlg.IND_CPA_LR_experiment,
  `AsymmEncAlg.IND_CPA_OneTime_Game, `AsymmEncAlg.IND_CPA_OneTime_Game_ProbComp,
  `AsymmEncAlg.IND_CPA_OneTime_biasAdvantage, `AsymmEncAlg.IND_CPA_OneTime_signedAdvantageReal,
  `AsymmEncAlg.ExplicitCoins.OW_CPA_Game, `AsymmEncAlg.ExplicitCoins.OW_CPA_Advantage,
  -- symmetric encryption secrecy
  `SymmEncAlg.perfectSecrecy, `SymmEncAlg.perfectSecrecyAt,
  -- KEM / PRF / PRG
  `KEMScheme.IND_CCA_Advantage, `PRFScheme.prfAdvantage, `PRGScheme.prgAdvantage,
  -- commitments
  `CommitmentScheme.hidingAdvantage, `CommitmentScheme.bindingAdvantage,
  `CommitmentScheme.PerfectlyHiding,
  -- signatures
  `SignatureAlg.unforgeableAdv.advantage,
  -- hardness assumptions
  `OneWay.owfAdvantage, `OneWay.tdpAdvantage,
  `DiffieHellman.ddhGuessAdvantage, `DiffieHellman.ddhDistAdvantage,
  `EntropySmoothing.advantage,
  `LearningWithErrors.advantage, `LearningWithErrors.searchAdvantage,
  -- sigma protocols
  `SigmaProtocol.SpeciallySound, `SigmaProtocol.SpeciallySoundAt,
  `SigmaProtocol.HVZK, `SigmaProtocol.UniqueResponses
]

/-- Mathlib names that contain `Alg` but are algebraic structures, **not** crypto
schemes. The scheme *naming* signal keys on `*Alg` (VCVio schemes are
`SymmEncAlg`, `MacAlg`, …), which collides lexically with these.

**Comparator contract (for Commit 4):** these are bare last-component names; the
classifier must exclude a project declaration whose **last name component**
(display name) matches one of these — *not* by full `Name` equality, since a
project's algebra type carries its own namespace. -/
def mathlibAlgebraGuard : Array Name := #[
  `Algebra, `Subalgebra, `AlgHom, `AlgEquiv, `AlgebraMap,
  `BoolAlg, `BooleanAlgebra, `FreeAlgebra, `TensorAlgebra,
  `MonoidAlgebra, `AddMonoidAlgebra, `LieAlgebra, `NonUnitalAlgebra
]

/-- Every catalogued anchor (for the drift diagnostic). -/
def allAnchors : Array Name :=
  vcvioSchemeTypes ++ gameHeads ++ correctnessAnchors ++ securityAnchors

-- ============================================================
-- Drift diagnostic
-- ============================================================

/-- Generic resolver: a warning string for each FQN **absent** from the
environment. Unconditional — exposed for manual audit and tests. -/
def resolveAnchors (env : Environment) (fqns : Array Name) : Array String :=
  fqns.filterMap fun n =>
    if env.contains n then none
    else some s!"classification catalogue: anchor not found in environment: {n}"

/-- The *guard* for an anchor: the symbol whose presence indicates the anchor's
family is loaded. We use the parent namespace — for a scheme-namespaced anchor
(`KEMScheme.IND_CCA_Advantage`) that is the scheme structure (`KEMScheme`),
which is loaded iff that primitive is imported. Top-level anchors (`SecExp`,
`OracleComp`) have no usable guard (`none`) and are therefore *not*
drift-checked — this is what avoids the false alarm for a project that imports
only a slice of VCVio (e.g. KVAC imports `ProbComp` but not `SecExp`). -/
def guardOf : Name → Option Name
  | .str p _ => if p.isAnonymous then none else some p
  | .num p _ => if p.isAnonymous then none else some p
  | .anonymous => none

/-- Family-conditional drift warnings: warn for an anchor only when its guard is
loaded but the anchor itself is absent — i.e. the primitive is present yet the
expected anchor name is not, the signature of an upstream rename.

Best-effort and **informational**, not an error. It can over-report when a
namespace spans several modules with optional imports (e.g. importing
`AsymmEncAlg` core but not its `IND_CPA` submodule leaves the `AsymmEncAlg`
guard satisfied while `AsymmEncAlg.IND_CPA_*` anchors are legitimately absent).
Commit 5 emits these as diagnostics only when a class is detected. -/
def driftWarnings (env : Environment) : Array String :=
  allAnchors.filterMap fun a =>
    match guardOf a with
    | some g =>
      if env.contains g && !env.contains a then
        some s!"classification catalogue: '{a}' missing though '{g}' is loaded (VCVio drift?)"
      else none
    | none => none

end ProbeLean.Catalogue
