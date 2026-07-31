# Feature: Extract VCVio security-protocol classification into a standalone `probe-vcvio`

## Summary

The VCVio / security-protocol classifier currently lives inside probe-lean
(`ProbeLean/Classify/`, classification schema types, `--class`, drift
diagnostics, ~25 tests). This makes probe-lean carry domain-specific knowledge
about one target ecosystem. This feature moves all VCVio-specific logic out into
a new standalone tool, **probe-vcvio**, mirroring the `probe-leanblueprint` /
`probe-aeneas` pattern: a Rust crate that consumes probe-lean's JSON envelope,
enriches atoms with a `classification`, and emits its own envelope — **without a
second `lake build`**. probe-lean is left VCVio-agnostic, emitting only neutral
per-declaration facts the classifier needs.

The classifier is already pure (`Classify.classify : Array DeclInfo → …` takes
no `Environment`). The only reason it currently must live inside probe-lean is
that three of its inputs (`codomainHead`, `codomainShape`, `classAttributes`)
are computed during probe-lean's environment walk and are **not** emitted in the
atom JSON. Once probe-lean emits neutral primitives for these, the classifier
can run entirely from JSON in a separate process.

## Requirements

### probe-lean (make it VCVio-agnostic)
- [ ] Emit three neutral per-atom facts, computed in the existing single
      environment walk (no new build):
  - `codomain-head : Option String` (fully-qualified head constant of the result
    type; already computed as `codomainHeadOf`)
  - `codomain-is-prop : Bool` (result type is `Sort 0`)
  - `codomain-last-arg-is-bool : Bool` (final application arg of the result type
    is `Bool`)
- [ ] Keep the existing generic source-scan `attributes` emission unchanged so
      `@[scheme_def]` / `@[construction_def]` / `@[correctness_spec]` /
      `@[security_spec]` continue to appear in `attributes` when written inline.
- [ ] Remove all VCVio-specific code:
  - Delete `ProbeLean/Classify/Catalogue.lean` and
    `ProbeLean/Classify/SecurityProtocol.lean` (and imports in `ProbeLean.lean`,
    `ProbeLean/Atomize.lean`).
  - Remove the classification schema types from `ProbeLean/Types.lean`:
    `Classification`, `SecurityProtocolCategory`, `ClassVia`,
    `normalizeClassLink`, `classLinkToJson`, `classLinkFromJson`,
    `UnifiedAtom.classification`, `SourceInfo.sourceClass`.
  - **Keep** the four `@[scheme_def]`-style tag registrations in
    `ProbeLean/Attrs.lean` as inert hooks (no classifier logic references them),
    so target projects importing `ProbeLean.Attrs` keep compiling `@[scheme_def]`
    etc. with zero migration and the tags keep flowing into the generic emitted
    `attributes` array that probe-vcvio reads. No separate Lean shim is needed.
  - Remove from `ProbeLean/Analysis.lean`: `detectClassAttrs`,
    `moduleListIndicatesSecurityProtocol`, `detectClass`,
    `detectClassFromManifest`, `defaultGameHeads`, and the VCVio coupling in
    `classifyCodomain`. Keep `codomainHeadOf`, `lastArgIsBool`, and an is-prop
    check as the neutral primitives above. Drop the `codomainShape` /
    `classAttributes` fields from `DeclInfo`; keep `codomainHead` and add the two
    new bool primitives.
  - Remove from `ProbeLean/Atomize.lean`: `isSecurityProtocolClass`,
    `classifyProject`, the `gameHeads` threading, and shrink
    `runAnalysisViaLakeEnv`'s return tuple back to `(Array Atom × …)` with no
    classification component and no project-class detection.
  - Remove from `ProbeLean/Extract.lean`: the `classification` param on
    `unifyAtom`, `buildClassMap`, `ExtractConfig.classOverride`, and the
    `sourceClass` assignment.
  - Remove the `--class` flag from `ProbeLean/Main.lean`.
  - Delete the ~25 classification tests from `Tests/Main.lean` (list in
    Acceptance Criteria) and their runner registrations.
- [ ] Bump the schema version in `ProbeLean/Types.lean` (breaking: `class` and
      `classification` fields are removed; `codomain-*` fields are added).
      Update `docs/SCHEMA.md`, `docs/USAGE.md`, `README.md`, `CHANGELOG.md`,
      `CLAUDE.md` to drop classification and document the new neutral fields.
- [ ] Add tests for the three new `codomain-*` fields (round-trip + a few
      representative decls: a `Prop`, a `… → Bool` def, a `Real`-valued def).

### probe-vcvio (new Rust crate, sibling repo under baif)
- [ ] New crate mirroring `probe-leanblueprint` / `probe-aeneas`: pinned `probe`
      hub git dep, `clap`, `serde`, cargo-dist release setup, `dist-workspace.toml`,
      `.github/workflows/{ci,release}.yml`, README, CHANGELOG.
- [ ] Single `extract` subcommand:
  - Obtain the atom base by spawning `probe-lean extract <project>` (single
    incremental build) **or** reading a pre-existing envelope via `--lean <file>`.
  - Reject its own output (`probe-vcvio/*`) as an atom base.
  - Run the ported classifier over the atoms, attach a `classification` to each
    matched atom, and emit a `probe-vcvio/extract` envelope (Schema 3.0 atoms
    category) plus a `probe-vcvio/summary` file, under
    `<project>/.verilib/probes/`.
- [ ] Port the classifier + catalogue from Lean to Rust:
  - The VCVio anchor catalogue (`vcvioSchemeTypes`, `gameHeads`,
    `correctnessAnchors`, `securityAnchors`, `mathlibAlgebraGuard`, family guards),
    pinned to the same VCVio commit (`ebea2fa`).
  - Reconstruct `CodomainShape` in Rust from the emitted `codomain-head` /
    `codomain-is-prop` / `codomain-last-arg-is-bool` fields plus the Rust
    `gameHeads`/`advantageHeads` sets.
  - Read the four class tags from each atom's generic `attributes` array
    (`scheme_def` etc.).
  - Reproduce the five-stage dependency-ordered classifier
    (`schemes → constructions → prop-attr-naming → prop-reach-fixpoint →
    theorems → resolveLinks`), the bounded BFS reachability walk
    (`maxWalkDepth = 16`), and the `Classification` output
    (`category`, `via`, `construction`, `scheme` links with `probe:` prefixes).
  - Emit the drift diagnostic (VCVio anchors absent from the atom set) to stderr.
- [ ] Project-class detection: detect `security-protocol` from the target's
      `lake-manifest.json` (`"VCVio"` / `VCV-io`) or an explicit `--class`
      override. Re-emit the detected class as `source.class` on the
      `probe-vcvio/extract` envelope (probe-lean drops it in PR 1; probe-vcvio
      owns it now). When VCVio anchors appear but no manifest signal is found, do
      not silently pass through — warn and record `classification-skipped` in the
      summary; require explicit `--class security-protocol` to force it. When
      genuinely not a security-protocol project, emit atoms unchanged (no
      classification, no `source.class`).
- [ ] No Lean attrs shim: the four tag attributes stay registered in
      `ProbeLean.Attrs` (target projects import it unchanged); probe-vcvio reads
      the tags from each atom's generic `attributes` array.
- [ ] Port the classifier unit tests to Rust (hand-built atom fixtures →
      `classify` → expected categories/links), covering the cases currently in
      `Tests/Main.lean` (schemes, constructions, promotion walk, tie/bound,
      links, conflicts, fixpoint order, attr/shape/instance, via-weakest, walk
      edges, link edges, misuse-ignored, attr-authority).

## API / Interface Design

```
# probe-vcvio CLI (mirrors probe-leanblueprint)
probe-vcvio extract <PROJECT>            # spawn probe-lean extract, classify, emit
probe-vcvio extract <PROJECT> --lean <extract.json>   # reuse existing envelope, no build
probe-vcvio extract <PROJECT> --class security-protocol   # force class
probe-vcvio extract <PROJECT> -o <out.json>
```

```
# probe-lean neutral per-atom fields (added to UnifiedAtom JSON)
"codomain-head": "VCVio.OracleComp",     # Option String, omitted when none
"codomain-is-prop": false,
"codomain-last-arg-is-bool": true,

# Removed from probe-lean output (breaking):
#   atom "classification" object, source "class" field
```

```
# Data contract: probe-vcvio consumes a probe-lean/extract envelope,
# joins on atom key "probe:<decl>", and emits a probe-vcvio/extract envelope
# whose atoms carry the same "classification" object shape as before, plus a
# re-emitted source.class. The exact classification JSON contract (enum casing,
# link string-vs-array, probe: prefix, dedupe+sort) is pinned from the current
# Lean serialization and locked with golden + serde tests.
```

## Behavior

- **Normal operation**: `probe-vcvio extract <vcvio-project>` runs probe-lean
  once, reads the envelope, computes `codomainShape` from the neutral fields,
  reads class tags from `attributes`, runs the classifier, and writes classified
  atoms + summary. Idempotent: `--lean <file>` reruns with zero builds.
- **Non-VCVio project**: class detection returns none; probe-vcvio passes atoms
  through with no `classification` and warns that no security-protocol signal was
  found.
- **Drift**: VCVio anchors that the pinned catalogue expects but that are absent
  from the atom set are reported to stderr (diagnostic only, non-fatal).
- **Error handling**: missing `probe-lean` on PATH, unreadable/again-probe-vcvio
  input envelope, and schema-version mismatch are hard errors with clear messages.

## Non-Goals

- No second `lake build` of the target: probe-vcvio never invokes lake; it relies
  on probe-lean's single build (or a pre-supplied envelope).
- No change to the `classification` object *shape* consumed downstream — only its
  producer moves from probe-lean to probe-vcvio.
- No handle-based (`hasTag`) attribute detection in probe-vcvio: it reads the
  four tags from probe-lean's generic source-scanned `attributes` array. Forms
  the source scan misses (separate `attribute [scheme_def] foo` statements,
  macro-generated tags) are out of scope; inline `@[scheme_def]` is the supported
  convention.
- No migration shim in probe-lean for the removed `classification` field beyond
  the schema-version bump.

## Acceptance Criteria

- probe-lean builds, all remaining tests pass, and `Classify/` +
  classification types/wiring/tests are gone. Verified by targeted checks: no
  `ProbeLean.Classify` import, no `Classification`/`ClassVia`/
  `SecurityProtocolCategory` type, no `classification`/`class` output field, no
  `--class` flag, no `gameHeads`/anchor tables. (The four attr *names* remain in
  `Attrs.lean` by design.)
- probe-lean output includes `codomain-head` / `codomain-is-prop` /
  `codomain-last-arg-is-bool`, verified by new round-trip tests, and no longer
  includes `classification` or `source.class`. Schema version bumped and docs
  updated.
- `probe-vcvio extract` on a VCVio target reproduces, byte-for-relevant-field,
  the `classification` objects the current probe-lean produces on the same target
  (regression fixture captured from current HEAD before the probe-lean removal).
- Running probe-vcvio with `--lean <envelope>` performs **zero** lake/probe-lean
  invocations (assert no build in the test path, as probe-leanblueprint's
  `tests/*_e2e.rs` do).
- Ported Rust classifier unit tests pass and cover the enumerated cases.
- probe-vcvio releases via cargo-dist like the sibling probes.

## Open questions

- Exact VCVio commit pin for the Rust catalogue — confirm `ebea2fa` is still the
  intended anchor, or bump to current.
- Whether the regression fixture should live in probe-vcvio's `tests/fixtures/`
  (captured from current probe-lean HEAD) — recommended, to lock behavioral
  parity across the port.

---
Status: ready
