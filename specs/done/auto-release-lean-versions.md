# Feature: Auto-release probe-lean artifacts for new Lean versions

Tracking issue: [#38](https://github.com/Beneficial-AI-Foundation/probe-lean/issues/38)

## Summary

Automatically produce `probe-lean` release artifacts when upstream `leanprover/lean4`
publishes a new Lean version, instead of requiring a human to edit a hardcoded version
matrix and cut a release. A scheduled "watcher" workflow polls the Lean releases API,
computes the set of Lean versions probe-lean should support, builds probe-lean against any
version not already present on the latest release, and appends the resulting tarballs to
that release. When probe-lean fails to build against a new Lean version (expected
periodically, given Lean's breaking changes and the `lean4-cli` rev coupling), the watcher
reports it in a single tracking issue instead of failing silently or marking the run red.

## Motivation

The Lean version matrix was hardcoded in [`.github/workflows/release.yml`](../../.github/workflows/release.yml)
(8 versions × 2 runner OSes). When Lean shipped a new version, no `probe-lean-<lean-version>-*`
artifact existed until someone manually appended to that list and cut a release. The
installer ([`tools/bash/install.sh`](../../tools/bash/install.sh), `tools/python/install.py`)
locates artifacts by filename across GitHub releases, so the probe-lean release tag is already
decoupled from which Lean versions live inside it — meaning new artifacts can be appended
without a probe-lean version bump.

Three realities shape the design:

1. **Lean has frequent breaking API changes.** probe-lean's source may not compile against a
   brand-new Lean version unmodified. Automation must treat a build failure as an expected,
   *reportable* outcome — distinct from an infrastructure/auth/upload failure, which must fail
   loudly.
2. **The `lean4-cli` dependency is rev-coupled to the Lean version.** The build rewrites the
   `Cli` `rev` in `lakefile.toml` to match the Lean version tag. A new Lean release will not
   build until `leanprover/lean4-cli` publishes a matching tag, so "Lean released" does not
   imply "buildable yet."
3. **`lake-manifest.json` independently pins `Cli`.** Rewriting only `lakefile.toml` and
   running `lake build` against a stale manifest can build the *wrong* `Cli` revision — a
   latent correctness bug `release.yml` had, which this feature fixes in every build path.

## Spec workflow

The feature has four parts: a shared policy script, the watcher (the new automation), the
hardened tagged-release workflow, and the installer lookup.

### 1. Version policy — `tools/lean-versions.sh`

The single source of truth for "which Lean versions does probe-lean support." It fetches the
`leanprover/lean4` releases (via `gh api --paginate`, `curl`, or a fixture file for tests),
validates the response, and applies the policy:

> every **stable** release at/above the floor (`LEAN_VERSION_FLOOR`, default `v4.28.0-rc1`),
> plus the **latest release candidate** of any version line that has not yet shipped a stable.

It compares versions with a bounded numeric sort key, so RCs order numerically (`rc10 > rc2`)
and below their own stable (`v4.29.0-rc8 < v4.29.0`). `--json` emits an array for a GitHub
Actions matrix. Fixture-based tests live in `tests/lean-versions/`.

### 2. The watcher — `.github/workflows/lean-watch.yml` (the feature)

Runs daily on a schedule (and on manual dispatch); a `lean-watch` concurrency group keeps two
runs from overlapping. Three jobs:

- **compute** — resolves the **latest published release** (`releases/latest`, which excludes
  drafts/prereleases) as the target. For each supported version it checks whether an artifact
  exists for every expected platform (`linux-x86_64`, `darwin-arm64`); versions missing one go
  into the matrix. No
  published release ⇒ the run no-ops.
- **build** — a matrix of `(missing version × {ubuntu-latest, macos-latest})`. Each job: detect
  its platform → skip if that exact `probe-lean-<version>-<platform>.tar.gz` already exists →
  rewrite `lean-toolchain` + the `Cli` rev and remove `.lake`/`lake-manifest.json` → build (the
  build step is `continue-on-error`) → on a clean build only: `--version` smoke test, package
  the tarball with a `BUILDINFO` provenance file and a `.sha256`, then upload (sidecar first
  with `--clobber`, tarball **without** `--clobber`).
- **report** — recomputes coverage from the release's current assets and opens / updates /
  closes the single `lean-build-failure` tracking issue.

End to end: a new Lean version → an artifact appears on the latest release within ~a day; an
unbuildable one → it shows up in the tracking issue and is retried each run until probe-lean
(or `lean4-cli`) catches up.

### 3. Tagged releases — `.github/workflows/release.yml`

Fires on a probe-lean version tag (`v*`). Rebuilds the **full** supported set from the tagged
source: `compute` (derives the matrix from `tools/lean-versions.sh`) → `ensure-release`
(creates the release once) → `build` (same rewrite + manifest-cleanup + smoke-test recipe as
the watcher, `continue-on-error` per version, uploads with `--clobber` since it owns its tag's
release) → `verify` (fails the run if the release has no artifacts). A per-tag
concurrency group serializes reruns.

### 4. Installer lookup — `tools/bash/install.sh`, `tools/python/install.py`

When installing, the installer searches the releases for `probe-lean-<version>-<platform>.tar.gz`,
requesting `per_page=100` (one call covers every probe-lean release for the foreseeable future)
with an optional `GH_TOKEN`/`GITHUB_TOKEN`. If no prebuilt is found it falls back to a source
build — so a toolchain without a published artifact still works, just slower.

## Things to note

- **Both workflows derive the version set live; there is no committed version-pin file.** A
  tagged release builds whatever the policy yields at the moment it runs, so the exact artifact
  set is not reproducible from the tag alone. This is accepted: a single unbuildable version is
  skipped (warning), and `verify` only fails the run if the release has no artifacts at all.
- **Support policy / floor.** Floor is `v4.28.0-rc1` (the documented minimum and probe-lean's
  own toolchain). A superseded RC (a line that has since shipped stable) is *not* actively
  rebuilt, but its already-published artifact is **never deleted**, so existing consumers are
  unaffected. Raising the floor later is a deliberate decision that must update the docs.
- **`lean4-cli` coupling.** A brand-new Lean version often cannot build until `lean4-cli`
  publishes the matching tag; the watcher treats this like any build failure and retries.
- **Stale-manifest bug fixed.** Every build path now removes `.lake` + `lake-manifest.json`
  after the rewrite. The macOS-incompatible `sed -i''` was also replaced with portable
  `sed -i.bak` — together these likely affected past macOS release artifacts.
- **Platforms.** Only `linux-x86_64` and `darwin-arm64` (what `ubuntu-latest`/`macos-latest`
  yield). Coverage is checked against the exact expected platform names; the build job asserts
  its detected platform is one of them, so a runner-arch change fails loudly instead of looping.
  Adding more arches is out of scope.
- **Provenance.** Watcher artifacts (built from `main`) carry a `BUILDINFO` (commit SHA, ref,
  Lean version, build time) and a `.sha256`. Tagged-release artifacts do not (the tag is their
  provenance); coverage is keyed on the tarball, so the asymmetry is fine.
- **No-clobber boundary.** The watcher never overwrites a tarball; `release.yml` uses
  `--clobber` because it owns its tag's release. The two workflows are not in a shared
  concurrency group (their group keys can't statically match) — no-clobber + the idempotency
  check are the cross-workflow protection.
- **Failure classification.** Only the `lean-action` build step soft-fails. A breaking Lean
  change or un-tagged `lean4-cli` keeps the run green and is reported; a broken token, API
  outage, or failed upload turns the run red.
- **Tracking issue.** One issue identified by the `lean-build-failure` label, body regenerated
  each run, auto-closed when coverage is complete — no duplicate-issue spam.
