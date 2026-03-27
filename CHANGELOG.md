# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

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
