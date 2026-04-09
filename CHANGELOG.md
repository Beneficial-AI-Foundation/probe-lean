# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

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
