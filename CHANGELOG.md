# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.11.0]

### Added

- `check-axioms` command: audits a project and reports every declaration (of those
  `extract` emits as atoms) whose transitive closure reaches the `sorryAx` axiom —
  the kernel ground truth for "rests on a `sorry`", independent of the extract
  dependency graph. Supports `-m`/`-l` scoping. New `ProbeLean/AxiomCheck.lean`.
- Neutral per-atom codomain facts, emitted for every atom: `codomain-head`
  (result-type head constant), `codomain-is-prop`, `codomain-last-arg-is-bool`.
  A downstream tool reconstructs the codomain shape from these plus its own catalogue.
- Neutral per-atom `type-dependencies-external` / `term-dependencies-external`
  fields (non-project deps, absent when empty). The existing `type-dependencies` /
  `term-dependencies` are project-filtered; these carry the external edges a
  downstream classifier needs to reconstruct the full reachability graph.

### Removed

- **Security-protocol (VCVio) classification moved out of probe-lean** into the
  standalone `probe-vcvio` tool. Removed from the `extract` output: the per-atom
  `classification` object and the envelope `source.class` field. Removed from the
  CLI: the `--class` flag. Removed internally: `ProbeLean/Classify/` (the anchor
  catalogue + classifier), the `Classification`/`SecurityProtocolCategory`/`ClassVia`
  types, and project-class/manifest detection. These fields were never part of a
  released schema and had no consumers, so their removal is not a schema break (the
  schema-version stays 3.0). probe-vcvio consumes probe-lean's envelope and
  reproduces the same `classification` shape from the emitted `codomain-*` facts.

### Changed

- **Split `is-extraction-artifact` into `is-lean-generated` + `is-aeneas-generated`.**
  The old field conflated two distinct origins: Lean-generated code
  (derived instances, projections) and Aeneas-generated scaffolding (`_body`, `_loop`
  suffixes). Each now has its own field with accurate naming. No interchange break:
  no other probe consumes these fields (probe-aeneas computes its own
  `is-extraction-artifact` from a name heuristic), so this is an additive payload
  change, not an envelope-schema change.
- **Conditional `is-hidden` for lean-generated atoms.** After transitive enrichment,
  `is-hidden` is cleared on *contaminated* lean-generated atoms — those that are
  locally verified but not transitively verified, or are themselves unverified/failed —
  so consumers that read `extract` output directly (e.g. the web UI) can trace why
  downstream atoms aren't dark green (fully verified). Clean (`transitively-verified`)
  and `trusted` lean-generated atoms stay hidden. `viewify` molecules omit all generated
  atoms regardless of `is-hidden`.
- Schema-version stays 3.0: the envelope structure is unchanged. The
  `is-extraction-artifact` → `is-lean-generated`/`is-aeneas-generated` rename and the
  updated `is-hidden` semantics affect only probe-lean's own payload, which is absorbed
  by consumers' passthrough `extensions`, so no shared version bump is warranted.
- The config key `extraction-artifact-suffixes` in `.verilib/probes/config.json` now
  feeds the `is-aeneas-generated` field (backward compatible, no config migration).
- `extract` auto-flags Lean-generated code — `deriving`-generated instance clusters and
  structure/class projections — as `is-hidden` + `is-lean-generated`, so it is omitted
  from the presented graph (`viewify` drops all generated atoms; `extract` consumers honor
  `is-hidden`). These atoms remain in the dependency graph, so transitive-verification
  stays sound.
- `markAtomFlags` now ORs the `is-hidden` / `is-aeneas-generated` flags with any
  already set, so config-based flagging adds to (rather than overwrites) the automatic
  detection above.
- The four classification tag hooks (`@[scheme_def]`, `@[construction_def]`,
  `@[correctness_spec]`, `@[security_spec]`) remain **registered** in
  `ProbeLean.Attrs` (so target projects need no migration) but are no longer
  interpreted by probe-lean; probe-vcvio reads them from the emitted `attributes` array.

### Fixed

- **Support Lean patch releases when installing and releasing.** `lean4-cli` tags
  `major.minor` lines and RCs but not every patch, so probe-lean previously failed
  to build for a patch-release toolchain (e.g. `v4.32.2`): the source build pinned
  `lean4-cli` to the exact Lean version (`revision not found`) and no pre-built
  binary was published. Both paths now resolve `lean4-cli` to the highest
  compatible tag in the target's `major.minor` line (stable targets pair only with
  stable tags), matching what was previously done by hand. Newly supported:
  patch releases such as `v4.28.1`, `v4.29.1`, `v4.32.1`, `v4.32.2`. (#79)

## [0.10.2] - 2026-08-03

### Fixed

- **Revert extract envelope schema-version to 3.0.** v0.10.1 emitted `4.0` for a
  payload-only change (the `is-extraction-artifact` split and updated `is-hidden`
  semantics), but the shared probe crate gates envelopes on a schema-version starting
  with `3.`, so `4.0` output was rejected by consumers at load time (`probe-aeneas
  extract` failed). The field rename and `is-hidden` behavior are kept; only the
  envelope version marker returns to `3.0`. (#81)

## [0.10.1] - 2026-08-03

### Fixed

- **Support Lean patch releases when installing and releasing.** `lean4-cli` tags
  `major.minor` lines and RCs but not every patch, so probe-lean previously failed
  to build for a patch-release toolchain (e.g. `v4.32.2`): the source build pinned
  `lean4-cli` to the exact Lean version (`revision not found`) and no pre-built
  binary was published. Both paths now resolve `lean4-cli` to the highest
  compatible tag in the target's `major.minor` line (stable targets pair only with
  stable tags), matching what was previously done by hand. Newly supported:
  patch releases such as `v4.28.1`, `v4.29.1`, `v4.32.1`, `v4.32.2`. (#79)

## [0.9.6] - 2026-07-17

### Changed

- `extract` enrichment now separates benign references to constructors/fields of
  extracted types (`inductive`/`structure`/`class`) from genuine orphan
  dependencies. Such type-member references are summarised in a single note
  instead of emitting one "not found in atom map" warning each, so real missing
  dependencies are no longer drowned out. Genuine orphans (e.g. instance
  projections, trait-impl references) are still reported individually. New
  `partitionMissingDeps` helper in `ProbeLean/Transitive.lean`.

## [0.9.5] - 2026-07-08

### Fixed

- **Duplicate-declaration failures are now caught by a preflight check with an
  accurate, actionable diagnostic** (issues #61, #62). Projects where two built
  modules declare the same fully-qualified name (e.g. parallel
  `problem.lean`/`solution.lean` files restating definitions without namespaces)
  build fine under Lake but cannot be imported into probe-lean's single analysis
  environment. Previously the mid-import abort blamed a stale orphan `.olean`
  and suggested `lake clean` — a dead end for this case. `extract` now reads each
  module's own declarations from its `.olean` header before importing and, on a
  collision, aborts with the duplicated names and their owning modules, the
  structural fixes, and the exact `--module` escape hatch for manual runs. The
  check replicates the importer's duplicate-tolerance rule (identical-statement
  theorem/axiom restatements are exempt), so it never rejects a project the
  importer would accept; collisions it cannot see (dependency modules,
  module-system split parts, unreadable oleans) still fail at import time with a
  hint that now covers both causes. Module discovery returns `ProjectModule`
  records (name + olean path) so filters preserve the pairing. The
  co-importability requirement is documented under README "Supported Projects".

## [0.9.4] - 2026-06-24

### Fixed

- **`extract` no longer crashes on orphan `.olean` files.** Module discovery scanned
  `.lake/build/lib/lean` for every `.olean` on disk and imported them all into one
  environment. Lake never garbage-collects oleans, so after a `.lean` file was renamed or
  deleted its stale "orphan" olean lingered and — when it re-declared a name now owned by
  the module that replaced it — made the import abort with `environment already contains
  '...'` (issue #51). `getProjectModules` now keeps only modules with a backing `.lean`
  source, resolving each module against `"."` plus every `srcDir` declared in
  `lakefile.toml`. The check is conservative (a module is dropped only when *no* source
  root has its source, so an unknown `srcDir` can't silently drop a live module) and any
  dropped orphans are reported. As a safety net, an `already contains` import failure now
  prints an actionable `lake clean` hint instead of a raw error.

## [0.9.3] - 2026-06-23

### Changed

- **Installer `--from-project` auto-detects the toolchain recursively.** When the given
  directory has no top-level `lean-toolchain` (common in monorepos where the Lean package
  lives in a subfolder, e.g. `cedar-spec/cedar-lean`), both `tools/bash/install.sh` and
  `tools/python/install.py` now search recursively (excluding `.lake`) and use the toolchain
  they find, so the installer works unattended when handed a repo root. If the found files
  disagree on the version, it errors and lists them rather than guessing. Bad paths
  (nonexistent, a file, or a directory with no toolchain anywhere) now give distinct,
  actionable errors instead of the previous terse `lean-toolchain not found`.

## [0.9.2] - 2026-06-22

### Fixed

- **`extract` no longer drops every module when `defaultTargets` names a non-library
  target.** The module filter was derived from auto-detected build targets, but
  `defaultTargets` may name a `lean_exe` and a `lean_lib` may declare custom `roots` that
  differ from its name. Treating those as module-name roots filtered out every built module,
  silently producing `0 atoms`. The library filter is now applied only when the user
  explicitly passes `--library`; otherwise all of the project's built modules (which is
  exactly what `.lake/build/lib/lean` contains) are analyzed. As a safety net, `extract` now
  exits with an actionable error — listing the available top-level module roots — if
  `--library`/`--module` filters out every built module, instead of writing an empty result.

## [0.9.1] - 2026-06-18

### Added

- **Pre-built binaries for Lean `v4.30.0` and `v4.31.0`** in the release matrix.

## [0.9.0] - 2026-06-18

### Fixed

- **Human-written private declarations are no longer filtered out.** Lean stores a
  `private def Bar.foo` as `_private.<module>.0.Bar.foo`, which the internal-name filter
  dropped along with compiler-generated noise. `extract` now recovers the user-facing name
  (`Bar.foo`) before filtering, so private lemmas/defs appear as atoms and dependency edges
  from public declarations to private helpers are preserved. This also fixes
  `transitively-verified` contamination silently skipping `sorry`s carried by private helpers.
  Private compiler-generated helpers (e.g. `...match_1`) remain filtered. Private declarations
  in different modules whose user-facing names coincide (e.g. two top-level `private theorem aux`)
  now emit a duplicate-name warning. (#43)

## [0.8.0] - 2026-06-16

### Added

- **Security-protocol classification**: for VCVio-based cryptographic projects, `extract` now
  classifies each declaration into a `scheme → construction → {correctness, security}` hierarchy
  so a consumer can render an accordion. Two additive, optional fields:
  - envelope **`source.class`** (`"security-protocol"`), resolved by precedence: `--class` override
    > Lake manifest (package-level VCVio dependency) > imported-module signal;
  - per-atom **`classification`** — `{ category, via, scheme?, construction? }`, where `category`
    is `scheme`/`construction`/`correctness`/`security`/`ambiguous`, `via` records the signal tier
    (`attribute`/`type`/`naming`), and the `scheme`/`construction` links are resolved fail-closed.
  Detection cascade is attribute > type > naming; project-own property definitions are promoted to
  anchors; theorems are classified by a bounded reachability walk. `ambiguous` flags a property
  whose correctness-vs-security axis is undecided (equal-depth tie or conflicting tags).
  See [docs/classification-security-protocol.md](docs/classification-security-protocol.md).
- **Classification attributes** (`ProbeLean.Attrs`): `@[scheme_def]`, `@[construction_def]`,
  `@[correctness_spec]`, `@[security_spec]` — authoritative overrides for projects whose schemes or
  properties are not conventionally named.
- **`--class <name>` flag** on `extract`: override the detected project class for manual runs.

### Unchanged

- Non-security-protocol projects are unchanged from 0.7.0 apart from `tool.version`/timestamp
  metadata (no class detected → neither `source.class` nor `classification` is emitted).

## [0.7.0] - 2026-05-22

### Added

- **`transitively-verified` status**: Verified atoms whose transitive dependencies
  are all verified or trusted are now upgraded to `"transitively-verified"` via
  reverse-BFS contamination (matching `probe-verus`/`probe-aeneas`). Atoms that
  are locally sorry-free but have at least one unverified or failed transitive
  dependency remain `"verified"`.
- **`--skip-enrich` flag**: Skip the transitive verification enrichment step.
  When passed, no atoms will be upgraded to `"transitively-verified"`.
- **`ProbeLean/Transitive.lean`**: New module implementing the enrichment algorithm
  using `Lean.RBMap` for deterministic iteration and an `Array`-backed BFS queue.

## [0.6.3] - 2026-04-30

### Fixed

- **Stale build cache hit after `lake clean`** ([#15](https://github.com/Beneficial-AI-Foundation/probe-lean/issues/15)):
  `isCacheValid` now requires at least one `.olean` file in the project's build
  directory, not just that the directory exists. Previously, after `lake clean`
  removed `.olean` artifacts (while the cache file at `.lake/probe-lean/build_output.txt`
  and the `.lake/build/lib/` directory survived), `probe-lean extract` would skip
  `lake build` and then fail with "No modules found in project". Added a
  `hasAnyOlean` helper that short-circuits on the first `.olean` found.

## [0.6.2] - 2026-04-16

### Fixed

- **`@[externally_verified]` attribute now recognized by trust-base classification**:
  The attribute was already registered in `ProbeLean/Attrs.lean` but was not wired
  into `trustedReason`, so theorems carrying `@[externally_verified]` (e.g., proofs
  discharged outside Lean in Verus) were reported as `"unverified"` when they
  contained the expected `sorry`. They now get `verification-status: "trusted"`
  with `trusted-reason: "externally_verified"`. Precedence when multiple signals
  apply: (1) `axiom`, (2) `externally_verified`, (3) `external`.

## [0.6.1] - 2026-04-15

### Fixed

- **Theorems in `*External.lean` no longer overridden to trusted**: Previously,
  all declarations in Aeneas `*External.lean` files were blanket-marked as
  `"trusted"` with `trusted-reason: "external"`. This was incorrect for theorems,
  which carry real Lean proofs checked by the kernel. Theorems in these files now
  receive their normal verification status from sorry detection (`"verified"`,
  `"unverified"`, or `"failed"`). Axioms and non-theorem declarations (defs,
  instances, etc.) remain `"trusted"` as before.

## [0.6.0] - 2026-04-15

### Added

- **Improved primary-spec detection**: `computeSpecs` now uses a multi-signal
  precedence chain instead of just the `_spec` suffix heuristic:
  1. `@[primary_spec]` attribute (always wins)
  2. Known verification-framework attributes (`@[progress]`, `@[pspec]`,
     `@[step]`) — if exactly one spec theorem carries one of these, it
     becomes primary spec
  3. `_spec` suffix naming convention (existing heuristic)
  4. Sole-spec inference — if a definition has exactly one spec theorem, it
     is used as primary spec

  A centralized `primarySpecAttributes` constant in `ProbeLean/Atomize.lean`
  lists the known spec-indicating attributes, making it easy to extend for
  future verification frameworks.

## [0.5.0] - 2026-04-13

### Added

- **Nix environment auto-detection**: When a target Lean project ships a
  `shell.nix` or `flake.nix`, probe-lean automatically wraps all `lake`
  invocations inside the Nix environment so that FFI system dependencies
  (zlib, OpenSSL, etc.) are available without manual installation. If the
  Nix file is present but `nix` / `nix-shell` is not installed, a warning
  is printed and `lake` runs directly.
  Fixes [#24](https://github.com/Beneficial-AI-Foundation/probe-lean/issues/24).

## [0.4.8] - 2026-04-10

### Added

- **`projection` declaration kind**: Structure field projections and class method
  projections are now classified as `kind: "projection"` instead of `"abbrev"`,
  using Lean's built-in `env.isProjectionFn` API. This distinguishes compiler-
  generated accessors (e.g., `EdwardsPoint.X`, `Add.add`) from genuine user-written
  abbreviations. Fixes [#19](https://github.com/Beneficial-AI-Foundation/probe-lean/issues/19).

### Changed

- **No-source declarations filtered entirely**: Declarations without source
  location (kernel-synthesized congruence lemmas, mutual recursion helpers, etc.)
  are now filtered from output entirely instead of being marked `"trusted"` with
  `trusted-reason: "auto-generated"`. The `"auto-generated"` trusted reason is
  removed from the schema. Refines the v0.4.6 fix for [#16](https://github.com/Beneficial-AI-Foundation/probe-lean/issues/16).

## [0.4.7] - 2026-04-10

### Fixed

- **Instance kind detection**: Auto-named type class instances (e.g.,
  `instAddNat`, `instDecidableValidLengths`) were incorrectly classified as
  `"def"` or `"abbrev"`. They are now reported as `"instance"` in the JSON
  output. Detection uses a naming heuristic (`inst` prefix) since Lean's
  instance extension state is not preserved in `.olean` files after
  `importModules`. User-named instances (without `inst` prefix) are not
  detected. Fixes [#17](https://github.com/Beneficial-AI-Foundation/probe-lean/issues/17).

## [0.4.6] - 2026-04-09

### Fixed

- **False "unverified" atoms for auto-generated declarations**: Declarations
  without source location (kernel-synthesized congruence lemmas, mutual recursion
  helpers, etc.) were incorrectly marked `"unverified"`. They are now marked
  `"trusted"` with `trusted-reason: "auto-generated"` since they are
  kernel-checked and guaranteed sound. Additionally, `.elim`, `.ctorIdx`, and
  `.toCtorIdx` suffixes are now filtered out as internal noise (like `.casesOn`,
  `.rec`, etc. already were). Fixes [#16](https://github.com/Beneficial-AI-Foundation/probe-lean/issues/16).

## [0.4.5] - 2026-04-07

### Added

- **`trusted-reason` field**: Each trusted atom now carries a `trusted-reason`
  field (`"axiom"` or `"external"`) so downstream tools can classify the trust
  base directly from the extract JSON without inspecting `kind` or `code-path`.

## [0.4.4] - 2026-04-07

### Added

- **Deterministic output (P14)**: `extract` now produces byte-identical JSON
  (ignoring `timestamp`) for the same project, commit, and toolchain.
  Declarations are sorted by name, dependency/specs/attributes arrays are
  sorted lexicographically, sorries are sorted by line number, and module
  discovery is sorted before import. Verified by running extract twice and
  confirming byte-identical output.

## [0.4.3] - 2026-04-07

### Added

- **`trusted` verification status**: Axiom declarations (`kind: "axiom"`) and
  all declarations in `*External.lean` files (Aeneas convention for hand-written
  external function/type models) are now marked `"trusted"` instead of
  `"verified"`. This distinguishes the trust base — definitions assumed correct
  without formal proof — from genuinely verified code. Previously these were
  indistinguishable from proven declarations.

## [0.4.2] - 2026-04-03

### Added

- **Toolchain version diagnostic**: `extract` now prints the Lean version
  probe-lean was built with and the target project's toolchain version at
  startup (e.g. `probe-lean built with Lean 4.28.0-rc1, target project uses v4.28.0`).
  Makes toolchain mismatches immediately visible in logs.

## [0.4.1] - 2026-04-02

### Fixed

- **Auto-download Mathlib cache**: `ensureMathlibCache` (formerly
  `warnIfMathlibCacheMissing`) now runs `lake exe cache get` automatically
  when a project depends on Mathlib but no pre-built `.olean` cache is
  found. Previously, probe-lean only printed a warning and then proceeded
  to build Mathlib from source, which takes hours. Falls back gracefully
  if the download fails.

## [0.4.0] - 2026-03-31

### Added

- Build cache now checks `lean-toolchain` and `lakefile.toml` mtimes, so
  changing the toolchain properly invalidates the cache without needing
  manual cleanup.
- `checkFilesNewerThan` skips dot-directories (`.lake/`, `.git/`), avoiding
  slow walks through dependency sources and false cache invalidations after
  `lake exe cache get`.
- `isCacheValid` verifies the build output directory (`.lake/build/lib/`)
  exists, catching `lake clean` scenarios where the cache file survives but
  build artifacts are gone.
- Smarter `incompatible header` error hint: when probe-lean and the target
  project use the same Lean version, suggests `lake clean` (stale oleans)
  instead of a misleading "toolchain mismatch" message.
- `parseToolchainVersion` helper extracted for reuse and testing.

### Fixed

- Bash installer (`tools/bash/install.sh`): replaced `trap cleanup EXIT`
  with inline restore after build, fixing `unbound variable` errors when
  building for a non-default Lean version.

## [0.3.0] - 2026-03-26

### Added

- Automated toolchain version detection: installer scripts read `lean-toolchain`
  from the target project and install the matching `probe-lean` binary.
- Hybrid installation: pre-built binary download from GitHub Releases with
  automatic source-build fallback.
- Per-version binary and `.olean` storage (`~/.local/bin/probe-lean-v<version>`,
  `~/.local/lib/probe-lean-v<version>/`) so multiple Lean versions can coexist.
- `probe-lean --version` CLI flag (also works on subcommands).
- Single source of truth versioning: version defined in `lakefile.toml`,
  propagated via `tools/gen-version.sh` to `ProbeLean/Version.lean`.
- GitHub composite action (`action/action.yml`) for downstream CI integration.
- GitHub release workflow (`.github/workflows/release.yml`) for publishing
  pre-built binaries on tag push.
- Multi-stage `Dockerfile` for containerized `probe-lean` usage.
- CI job to verify `Version.lean` stays in sync with `lakefile.toml`.
- Installer flags: `--from-project`, `--lean-version`, `--force`.

### Changed

- Installer scripts (`tools/bash/install.sh`, `tools/python/install.py`)
  rewritten with full feature parity: platform detection, version-aware
  installation, and `PATH` setup guidance.

### Fixed

- Python installer: added `filter="data"` to `tarfile.extractall` for security.
- GitHub Action: fixed cache ordering (restore before build) and ensured
  `elan`/`lake` are always available regardless of cache state.
- GitHub Action: replaced unsafe `eval $CMD` with direct command execution.

## [0.2.0] - 2026-03-16

### Added

- `specs` field on atoms: lists the code-names of theorem atoms whose
  dependencies include the atom. Computed as a reverse-edge pass on the
  call graph after atomization. The field is omitted from JSON output
  when the list is empty. ([#11](https://github.com/Beneficial-AI-Foundation/probe-lean/issues/11))

## [0.1.0] - 2025-01-01

Initial release.
