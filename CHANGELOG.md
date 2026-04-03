# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

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
