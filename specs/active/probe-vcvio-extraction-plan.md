# Implementation plan: extract `probe-vcvio` (two PRs)

Companion to [`probe-vcvio-extraction.md`](./probe-vcvio-extraction.md). This
plan splits the work into two PRs across two repos and pins the ordering,
fixtures, and coordination points.

## Sequencing overview

```
Step 0  (probe-lean, main, no PR)   Capture parity fixture from current HEAD
   │                                 (current classification output — the port's oracle)
   ▼
PR 1    (probe-lean repo)           VCVio-ectomy + emit neutral codomain facts + schema bump
   │                                 Closes probe-lean issue A
   ▼   (merge, tag, release probe-lean)
PR 2    (probe-vcvio repo, new)     New Rust crate consuming the new probe-lean format
                                     Closes probe-vcvio issue B
```

**Why this order.** PR 2 depends on PR 1's new `codomain-*` fields and on
probe-lean no longer producing classification. The window between PR 1 merge and
PR 2 ship where no tool emits classification **breaks nothing**: VeriLib is the
only consumer and it does not read `classification` today (verified against
VeriLib-Docs + verilib-cli; see coordination #1). So the sequencing is *not* a
safety concern — two PRs, no transitional release.

**The only real constraint is validating the port.** The Rust classifier must be
proven to reproduce the Lean one. That requires an oracle built from a single
atomization that carries *both* the classifier inputs and its outputs — see
Step 0, which captures it from a local build that has `codomain-*` added but the
classifier still present. This is a local capture step, not a shipped
transitional release.

Per repo conventions: open both PRs as **drafts**, and create the closing
GitHub issue first in each repo.

---

## Step 0 — Capture the single-build oracle (do first, on a local branch)

The oracle must come from **one atomization** so that the Rust classifier's
inputs and the Lean classifier's outputs are provably consistent — otherwise a
parity failure can't be attributed (Codex #2). Do this on a *local* branch that
has PR 1's `codomain-*` additions (step 1a) applied **but the classifier still
present** (before step 1b's deletions). No release, no PR.

1. On that branch, temporarily also emit, per atom, the current internal
   `codomainShape` and `classAttributes` (a debug side-channel — a `--debug-facts`
   flag or a scratch dump), so the capture contains everything the Rust port
   both consumes and must reproduce.
2. Target: **`baif/secure-messaging`** (genuine VCVio project — `require VCVio`
   in `lakefile.toml`; ~277 `.lean` files, not small but representative). Warm
   the Mathlib cache: `lake exe cache get`. Three preconditions/caveats:
   - **Toolchain (not a blocker):** secure-messaging is on
     `leanprover/lean4:v4.30.0`; probe-lean's source default is `v4.28.0-rc1` but
     it is multi-toolchain by design — the release matrix builds a binary per
     Lean version (v4.30.0/v4.31.0 binaries already ship, v0.9.1). Extract needs
     a probe-lean built for the target's toolchain. Since Step 0 needs the
     *unreleased* `codomain-*` changes, build the feature branch against v4.30.0
     (set `lean-toolchain` to `v4.30.0` locally for the capture, as `release.yml`
     does per matrix row) rather than using a stock released binary. No permanent
     change to probe-lean's source default is required.
   - **Catalogue-pin mismatch:** secure-messaging pins VCVio at
     `8f5dc4f2923cc47e39bc6ce21f71563cf7d19193`, not the plan's `ebea2fa`. This
     target therefore exercises the drift path; reconcile the catalogue pin
     (coordination #4) so classification is correct, and record the observed
     drift in the oracle.
   - **Attribute path unexercised:** secure-messaging uses **no** inline
     `@[scheme_def]`/etc. tags (0 hits), so its classification relies on the
     type/naming signals only. The attribute-`via` path must be covered by the
     ported unit tests (2g), not this corpus. Consider a second tiny tagged
     target if attribute-`via` corpus coverage is wanted.
3. Run `probe-lean extract <target> -o oracle-<name>.json` on that branch. From
   one run this yields, per atom: `name`/`display-name`/`kind`,
   `type-`/`term-dependencies`, `attributes`, `codomain-head`,
   `codomain-is-prop`, `codomain-last-arg-is-bool`, the debug `codomainShape` +
   `classAttributes`, the `classification` object, and `source.class`.
4. Derive two golden files from it:
   - `classification-golden-<name>.json` — the per-atom `classification` +
     `source.class` outputs (the port's output oracle).
   - `codomain-shape-golden-<name>.json` — per-atom `codomain-*` → expected
     `codomainShape` (the shape-reconstruction oracle for Codex #3).
5. Stash both where PR 2 vendors them into `probe-vcvio/tests/fixtures/`. Also
   snapshot the ~25 Lean classifier test cases as neutral fixtures now, before
   PR 1 deletes them (Codex #13 — cheap reference preservation).

Output of Step 0: `classification-golden-<name>.json` +
`codomain-shape-golden-<name>.json` + snapshotted classifier test cases.

**DONE (2026-07-31).** Captured at `baif/probe-vcvio-oracle/` from probe-lean ref
`d5739e7` (branch `feat/remove-vcvio-classification`, classifier present) built
at Lean v4.30.0, target `secure-messaging` (1280 atoms, 165 classified). Files:
`oracle-secure-messaging.full.json`, `classification-golden-secure-messaging.json`
(165 + source-class), `codomain-shape-golden-secure-messaging.json` (1280),
`lean-classifier-snapshot/` (SecurityProtocol/Catalogue/Attrs + 21 test fns),
`README.md`. **Pre-validated:** neutral primitives + catalogue reconstruct
`expected-shape` for all 1280 decls, 0 mismatches (Codex #3 cleared). Observed
real catalogue drift (`ebea2fa` vs target VCVio `8f5dc4f`) — feeds coord #4.

**Note:** the debug `codomainShape`/`classAttributes` emission is scaffolding for
capture only; it is *not* part of PR 1's shipped output and is dropped before
1b's deletions (or gated behind an undocumented `--debug-facts` flag).

---

## PR 1 — probe-lean: remove VCVio, emit neutral codomain facts

**Repo:** probe-lean. **Branch:** `feat/remove-vcvio-classification`.
**Issue A (create first):** "Move VCVio security-protocol classification out of
probe-lean into probe-vcvio". **Draft PR** closing issue A.

### 1a. Add neutral per-atom facts (do before deletions, keeps build green)
- `ProbeLean/Analysis.lean`: keep `codomainHeadOf`, `lastArgIsBool`; add an
  is-prop check. Replace the `codomainShape` field on `DeclInfo` with two bool
  primitives (`codomainIsProp`, `codomainLastArgIsBool`) and keep `codomainHead`.
  Remove `classifyCodomain`'s `gameHeads` coupling (`defaultGameHeads`,
  `advantageHeads` move to probe-vcvio).
- `ProbeLean/Types.lean` + `Extract.lean`: emit `codomain-head` (Option, omit
  when none), `codomain-is-prop`, `codomain-last-arg-is-bool` on `UnifiedAtom`.
- Keep `extractAttributesFromSource` and the generic `attributes` emission
  untouched (this is how probe-vcvio reads `scheme_def` etc.).
- Tests: add `testCodomainFacts` — round-trip + representative decls (a `Prop`
  theorem, a `… → Bool` def, a `Real`-valued def, a plain def). Register in the
  `main` runner chain.

### 1b. Delete VCVio surface
- Delete `ProbeLean/Classify/Catalogue.lean`, `ProbeLean/Classify/SecurityProtocol.lean`;
  drop their imports from `ProbeLean.lean` and `ProbeLean/Atomize.lean`.
- `ProbeLean/Types.lean`: remove `Classification`, `SecurityProtocolCategory`,
  `ClassVia`, `normalizeClassLink`, `classLinkToJson`, `classLinkFromJson`,
  `UnifiedAtom.classification`, `SourceInfo.sourceClass` (JSON key `class`).
- `ProbeLean/Attrs.lean`: **keep** the four tag registrations (`schemeDefAttr`,
  `constructionDefAttr`, `correctnessSpecAttr`, `securitySpecAttr`) as inert
  hooks — no classifier logic references them anymore, but leaving them
  registered means target projects that already `import ProbeLean.Attrs` keep
  compiling `@[scheme_def]` etc. with zero migration, and the tags keep flowing
  into the generic emitted `attributes` array that probe-vcvio reads. This is the
  low-churn choice (Codex #4/#5); no `ProbeVcvioAttrs` Lake shim is needed.
  Document these four as "generic classification tag hooks (semantics live in
  probe-vcvio)". Keep `primarySpecAttr`, `externallyVerifiedAttr`.
- `ProbeLean/Analysis.lean`: remove `detectClassAttrs`,
  `moduleListIndicatesSecurityProtocol`, `detectClass`,
  `detectClassFromManifest`, and the `classAttributes` field on `DeclInfo` (the
  four tags still reach probe-vcvio via the generic source-scanned `attributes`).
- `ProbeLean/Atomize.lean`: remove `isSecurityProtocolClass`, `classifyProject`,
  the `gameHeads` threading; shrink `runAnalysisViaLakeEnv`'s return type back to
  `IO (Except String (Array Atom × …))` with no classification / project-class.
- `ProbeLean/Extract.lean`: remove the `classification` param on `unifyAtom`,
  `buildClassMap`, `ExtractConfig.classOverride`, and the `sourceClass`
  assignment.
- `ProbeLean/Main.lean`: remove the `--class` flag and its command declaration.
- `Tests/Main.lean`: delete the classification tests and their runner
  registrations — `testClassificationJson`, `testCodomainShape`,
  `testDetectClass`, `testDrift`, `testClassifySchemes`,
  `testClassifyConstructions`, `testClassifyPromotionWalk`,
  `testClassifyWalkTieAndBound`, `testClassifyLinks`, `testClassifyConflicts`,
  `testClassifyFixpointOrder`, `testClassifyAttrShapeAndInstance`,
  `testClassifyViaWeakest`, `testClassifyWalkEdges`, `testClassifyLinkEdges`,
  `testClassifyMisuseIgnored`, `testClassifyAttrAuthority`,
  `testUnifyClassification`, `testBuildClassMap`,
  `testEnrichPreservesClassification`, plus the build-time `@[scheme_def]`
  assertion and the drift/`resolveAnchors` block, and helpers `mkDeclI`, `clsOf`
  if now unused.

### 1c. Schema + docs + version
- Bump `Constants.schemaVersion` (breaking: `classification` + `class` removed,
  `codomain-*` added). **Decide major vs minor** — removal is breaking →
  recommend a major bump.
- Bump the tool version in `lakefile.toml`, run `./tools/gen-version.sh`, commit
  both files (CI checks sync).
- Update `docs/SCHEMA.md` (drop classification/`source.class`, document the three
  `codomain-*` fields), `docs/USAGE.md` (drop `--class` + classification
  overview), `README.md` (same), `CHANGELOG.md` (new version entry noting the
  breaking removal), `CLAUDE.md` (remove the `Classify/` architecture entries).
  Move `docs/classification-security-protocol*.md` to probe-vcvio (or leave a
  stub pointer).

### 1d. Verify
- `lake build && lake build tests && .lake/build/bin/tests` green.
- **Targeted removal checks** (Codex #12), not a blunt `grep vcvio`: no
  `ProbeLean.Classify` import remains; no `Classification`/`ClassVia`/
  `SecurityProtocolCategory` type; no `classification` or `class` field in any
  probe-lean output test; no `--class` CLI option; no `gameHeads`/`defaultGameHeads`/
  anchor tables. (The four attr *names* legitimately remain in `Attrs.lean` per
  1b, so a bare `grep scheme_def` is expected to hit — scope checks to the
  removed symbols above.)
- Measure `lake build` time before/after per CLAUDE.md (deletion should not
  regress; watch the `do`-block depth in `runAnalysisViaLakeEnv` after the
  return-tuple change).

---

## PR 2 — probe-vcvio: new Rust crate

**Repo:** new `probe-vcvio` (create under baif, mirror `probe-aeneas` /
`probe-leanblueprint`). **Issue B (create first):** "probe-vcvio: standalone
VCVio security-protocol classifier consuming probe-lean envelopes". **Draft PR**
closing issue B. Depends on PR 1 merged + probe-lean released (so the pinned
`probe-lean` binary emits `codomain-*`).

### 2a. Scaffold from the sibling template
- `cargo new`; copy the shape of `probe-leanblueprint`: `Cargo.toml` with pinned
  `probe` hub git dep, `clap`/`serde`/`serde_json`/`anyhow`/`thiserror`,
  `[profile.release]` + `[profile.dist]`.
- `dist-workspace.toml` (cargo-dist, same 5 targets), `.github/workflows/{ci,release}.yml`,
  `LICENSE`, `README.md`, `CHANGELOG.md`, `.gitignore`.

### 2b. CLI + orchestration (`src/main.rs`)
- `extract <PROJECT>` subcommand with `--lean <file>`, `--class`, `-o`.
- `load_atoms`: `--lean` → read envelope; else spawn `probe-lean extract <proj>
  -o <known-path>` once and read that file (mirror probe-leanblueprint's
  `.verilib/probes/probe-lean-extract.json` pattern — do **not** parse stdout).
  On spawn failure, propagate probe-lean's stderr verbatim (Codex #9).
- **Spawn/version handshake** (Codex #8): before consuming, check the envelope
  `schema`/`schema-version`; when spawning, also check `probe-lean --version`.
  A crate-pinned `probe` hub dep does **not** pin the installed `probe-lean`
  binary, so fail with a precise message on version/schema mismatch (missing
  `codomain-*` ⇒ "installed probe-lean too old").
- **Input acceptance** (Codex #10): accept only an envelope whose `schema`
  begins with `probe-lean/` at a supported version; hard-reject any other prefix
  (including `probe-vcvio/`). If the input already carries `classification`,
  reject (it's a re-classification of enriched output, not a base).
- **`--lean`/`<PROJECT>` consistency** (Codex #16, cheap): warn/refuse if the
  `--lean` envelope's `source` path doesn't correspond to `<PROJECT>`, so results
  aren't written into an unrelated project.
- Emit `probe-vcvio/extract` + `probe-vcvio/summary` under
  `<project>/.verilib/probes/` via **atomic write** (write temp + rename), fixed
  filenames, overwriting prior probe-vcvio output; never leave partial JSON
  (Codex #15).

### 2c. Port the catalogue (`src/catalogue.rs`)
- Translate `vcvioSchemeTypes`, `gameHeads`, `correctnessAnchors`,
  `securityAnchors`, `mathlibAlgebraGuard`, `guardOf` family guards, `allAnchors`
  to Rust const sets. Pin the VCVio commit (confirm `ebea2fa`).
- `advantageHeads = {Real, ENNReal, NNReal}`.

### 2d. Port the classifier (`src/classify.rs`)
- `DeclInfo`-equivalent built from atom JSON: name, display-name, kind,
  type/term-dependencies, `codomain-head`, and `codomainShape` reconstructed from
  `codomain-is-prop` / `codomain-last-arg-is-bool` / `codomain-head` + the Rust
  `gameHeads`/`advantageHeads`.
- Class tags read from the atom's `attributes` array.
- Five stages (`schemes → constructions → prop-attr-naming → prop-reach-fixpoint
  → theorems → resolveLinks`), bounded BFS (`maxWalkDepth = 16`; add a global
  visited-node bound, Codex #16), `Classification { category, via, construction,
  scheme }` with `probe:` links.
- **Deterministic data structures** (Codex #11): use `BTreeMap`/`BTreeSet` or
  sorted `Vec`s — never `HashMap`/`HashSet` iteration — so stage order, tie-break,
  link resolution, "weakest via", and conflict resolution match the Lean side's
  deterministic ordering (Lean uses `RBMap`/arrays). Add explicit tie-break unit
  tests keyed on both fixture order and lexical order.
- Drift diagnostic (catalogue anchors absent from the atom set) → stderr.

### 2e. Enrich + emit (`src/enrich.rs`, `src/emit.rs`)
- Attach `classification` to matched atoms. **Pin the exact JSON contract**
  (Codex #19) from the current Lean serialization, don't just say "same shape":
  category/via enum string casing, link singular-string-vs-array
  (`classLinkToJson`), `probe:` prefix normalization, dedupe + stable sort
  (`normalizeClassLink`), unknown-category handling. Lock it with golden JSON +
  serde round-trip tests.
- **`source.class`** (Codex #20): probe-lean drops `SourceInfo.sourceClass` in
  PR 1. **Decision:** probe-vcvio re-emits the detected project class as
  `source.class` on its own `probe-vcvio/extract` envelope (so the project-level
  signal survives in the ecosystem, just relocated to the tool that owns it).
  The Step 0 golden captures `source.class` precisely to validate this.
- Class detection (Codex #6): `--class` override > `lake-manifest.json`
  (`VCVio` / `VCV-io`) > none. If the manifest signal is **absent but VCVio
  anchors appear in the atom set**, do not silently pass through — warn loudly
  and record `classification-skipped` with a reason in the summary; require
  explicit `--class security-protocol` to force classification in that ambiguous
  case.
- Output is a standalone `probe-vcvio/extract` envelope. **Wiring it into
  VeriLib ingestion is out of scope** for these PRs and folded into coordination
  point #3 (VeriLib doesn't consume `classification` today, so nothing needs it
  yet).

### 2f. Attrs — no shim needed
- The four tag attributes stay registered in `ProbeLean.Attrs` (PR 1 step 1b),
  so target projects keep compiling `@[scheme_def]` etc. unchanged and probe-vcvio
  reads them from the generic `attributes` array. No `ProbeVcvioAttrs` Lake
  package, no target migration, no deployment/toolchain-matching problem
  (resolves Codex #4/#5).

### 2g′. Summary schema (`src/emit.rs`)
- Specify `probe-vcvio/summary` contents (Codex #17, #14): input envelope
  schema/version/path; spawned `probe-lean` version (if any); classification mode
  / `--class`; total atoms; per-category counts; missing-anchor (drift) count;
  the pinned VCVio catalogue commit; warnings; and whether classification was
  skipped (+ reason). Makes drift/skip visible in CI, not just ephemeral stderr.

### 2g. Tests
- Vendor Step 0's goldens into `tests/fixtures/`.
- `tests/shape_parity.rs` (Codex #3): for **every** decl in
  `codomain-shape-golden-<name>.json`, assert the Rust reconstruction of
  `codomainShape` from `codomain-*` equals the captured Lean `codomainShape`.
  This is corpus-level, not a handful of examples — it is the proof that three
  neutral fields suffice. Any mismatch means probe-lean must emit an additional
  primitive (revisit PR 1 step 1a).
- `tests/parity.rs`: run the port over the oracle envelope's inputs and assert
  the resulting `classification` + `source.class` equal
  `classification-golden-<name>.json` field-for-field. Because inputs and
  outputs came from one atomization (Step 0), a failure unambiguously indicts the
  Rust port (Codex #2).
- Port the classifier unit tests (hand-built atom fixtures) covering all cases
  from the Step-0-snapshotted set (schemes, constructions, promotion walk,
  tie/bound, links, conflicts, fixpoint order, attr/shape/instance, via-weakest,
  walk edges, link edges, misuse-ignored, attr-authority) + explicit
  determinism/tie-break tests (2d).
- A `--lean <fixture>` e2e test asserting **no** build/probe-lean spawn (mirror
  probe-leanblueprint `tests/*_e2e.rs`).
- Serde round-trip tests locking the `classification` JSON contract (2e).

### 2h. Release
- cargo-dist tag → GitHub release, like the sibling probes.

---

## Open coordination points (resolve during the PRs)

1. **`classification` field placement — RESOLVED (safe).** VeriLib does **not**
   consume `classification` today: it is absent from VeriLib's documented atom
   schema (`VeriLib-Docs/.../json-mapping.md`) and from canonical
   `probe/docs/SCHEMA.md`; verilib-cli passes atoms through untyped; the frontend
   rule engine's CEL field list is closed and has no `classification`/`category`.
   The only reference is one unimplemented prose sentence about border colour
   (`atom-statuses-and-colours.md:37`). So removing it from probe-lean and having
   probe-vcvio re-emit it breaks nothing, and we are free to keep the field name
   `classification` or namespace it. **Decision: keep the name `classification`**
   (established in the ecosystem docs; no collision) and carry it as a
   tool-emitted atom field on the `probe-vcvio/extract` envelope.
2. **VeriLib ingestion + display of classification — deferred follow-up (out of
   scope for both PRs).** VeriLib ingests by **`schema`-prefix + language plugin
   + `.verilib/probes/<lang>_*.json` path**, *never* by `tool`, so a fresh
   `probe-vcvio/extract` schema is ignored today — and it doesn't matter yet,
   because VeriLib doesn't consume `classification` at all. When VeriLib should
   actually *show* classification (border colours), a single follow-up handles
   both halves: (a) recognise the `probe-vcvio` envelope (register a
   plugin/schema-prefix, or route it through `probe merge`/`project` into the
   unified file), and (b) expose a CEL field + `.verilib/config.json` colour
   rule. User accepts backend changes; track as its own issue.
3. **Schema-version coordination** between probe-lean (Lean `Types.lean`) and the
   `probe` hub (Rust). Pin the hub `rev` in probe-vcvio to a commit compatible
   with probe-lean's bumped schema. Define exactly which probe-lean schema
   versions probe-vcvio accepts and the absent/null/empty `codomain-head`
   deserialization rule (Codex #8).
4. **VCVio commit pin** — the plan/catalogue currently references `ebea2fa`, but
   the Step 0 target `secure-messaging` pins VCVio at `8f5dc4f…`. Reconcile:
   either bump the catalogue to `8f5dc4f…` (and re-derive anchor FQNs against it)
   or confirm `ebea2fa`'s anchors are a superset that still classifies
   `8f5dc4f…`. Whatever is chosen, report the pinned commit in the summary (2g′)
   so classifications are traceable to a catalogue version.

## Risk register

| Risk | Mitigation |
|---|---|
| Rust port diverges from Lean classifier semantics | Single-build oracle (Step 0) → `parity.rs` field-for-field; ported unit tests; deterministic `BTree*` structures + tie-break tests (2d) |
| `codomain-*` primitives insufficient to rebuild `codomainShape` | Corpus-level `shape_parity.rs` over *every* decl vs captured Lean `codomainShape` (2g); mismatch ⇒ emit another primitive in 1a |
| Wrong/older `probe-lean` binary on PATH (crate pin ≠ binary pin) | Version/schema handshake + precise error (2b, coord #3) |
| Ambiguous project (VCVio anchors but no manifest signal) silently unclassified | Require `--class`; record `classification-skipped` + reason in summary (2e) |
| Non-deterministic Rust output breaks parity | `BTreeMap`/`BTreeSet`/sorted vecs only; tie-break tests (2d) |
| `classification` JSON contract drift on the port | Pin contract from Lean serialization; golden + serde round-trip tests (2e, 2g) |
| Partial/corrupt output poisons CI | Atomic write (temp + rename), fixed filenames, overwrite (2b) |
| `lake build` time regression in probe-lean | Measure before/after (CLAUDE.md); watch `runAnalysisViaLakeEnv` do-depth |
| Losing the classifier's executable reference on deletion | Snapshot the ~25 Lean test cases as fixtures in Step 0 before 1b deletes them |

## Definition of done

- [ ] Step 0: single-build oracle captured (`classification-golden` +
      `codomain-shape-golden`) and Lean test cases snapshotted.
- [ ] PR 1 merged: probe-lean classifier removed (targeted checks pass), four
      attr hooks retained in `Attrs.lean`, `codomain-*` emitted, schema bumped,
      docs updated, tests green, released.
- [ ] PR 2 merged: probe-vcvio reproduces `classification` + `source.class`
      field-for-field, corpus `shape_parity` passes, deterministic structures,
      version handshake, atomic writes, summary specified, unit tests ported,
      `--lean` path does zero builds, released.
