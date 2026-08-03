# Feature: Resolve lean4-cli tags for Lean patch releases

## Summary

probe-lean depends on `leanprover/lean4-cli` (the `Cli` package), pinned by git
tag in `lakefile.toml`. Both the source-build installer and the release/version
machinery assume lean4-cli publishes a tag for *every* Lean version. It does
not: lean4-cli tags `major.minor` lines and RCs (`v4.32.0`, `v4.32.0-rc1`) but
not patch releases (`v4.32.1`, `v4.32.2`). Consequently, for any target project
on a Lean patch release:

- `install.sh --from-project` correctly detects the version and falls back to a
  source build, but the build rewrites the `Cli` rev to the exact Lean version
  (e.g. `v4.32.2`) and `lake update Cli` fails with `revision not found`.
- No prebuilt binary is published either, because `tools/lean-versions.sh` drops
  any Lean version lacking an *exact* lean4-cli tag, so the release workflow and
  `lean-watch.yml` never build it.

This change decouples the lean4-cli pin from the exact Lean version: resolve to
the highest **stable** lean4-cli tag in the same `major.minor` line that is `<=`
the target (an exact tag wins automatically). This is what the maintainer already
did by hand — see commit `84d6320`, where Lean `v4.25.2` was paired with lean4-cli
`v4.25.1`.

**Compatibility is best-effort, not proven.** Pairing a patch-release Lean
toolchain with its minor's lean4-cli tag assumes lean4-cli is source-compatible
across a Lean minor line. That has held in practice but is not guaranteed by
upstream. The safety net is that resolution feeds a real `lake build`: an
incompatible pairing fails the build (locally: a clear installer error; in CI:
the watcher records the version in its tracking issue and retries later) rather
than shipping a broken binary. No version is published without a successful
build.

### Terminology (two distinct groupings — do not conflate)

- **Release selection** (`tools/lean-versions.sh` policy) groups by
  `major.minor.patch` "version line": each of `4.32.0`, `4.32.1` is its own line,
  and the latest RC of a line without a stable is emitted. Unchanged here.
- **Cli compatibility** (this change) groups by `major.minor` line: a Lean
  version resolves to a lean4-cli tag sharing its `major.minor`.

Related: `specs/done/auto-release-lean-versions.md` (the release/watcher machinery
this modifies), issue #38. Tracked by #79.

## Requirements

- [ ] `install.sh` source build resolves the lean4-cli tag for the target Lean
      version instead of using the version verbatim.
- [ ] **Resolution rule:** highest lean4-cli tag in the same `major.minor` line
      with version `<=` target, subject to the stable/RC constraint below; an
      exact match wins; empty result if no compatible tag exists.
- [ ] **Stable/RC constraint:** a **stable** Lean target (no `-rc`) resolves only
      to a **stable** lean4-cli tag; an **RC** Lean target may resolve to an RC
      lean4-cli tag (or a stable one). A stable Lean release is never paired with
      a prerelease `Cli`.
- [ ] **Input validation:** the resolver rejects any target not matching
      `^v[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?$` with a distinct error, *before* any
      source-tree mutation. (`--from-project` strips the `leanprover/lean4:`
      prefix upstream; the resolver still validates its input.)
- [ ] **Mutation ordering:** `fetch_cli_tags` and `resolve_cli_rev` run, and their
      result is validated, **before** `install.sh` writes `lean-toolchain`, edits
      `lakefile.toml`, or removes `.lake`. A failed fetch/resolve aborts with the
      source tree untouched.
- [ ] **Crash-safe restore:** `build_from_source` restores `lean-toolchain`,
      `lakefile.toml`, and `lake-manifest.json` via a `trap` so *any* mid-build
      failure (not just the happy path) leaves the shared
      `~/.local/src/probe-lean` checkout clean. This also hardens the existing
      restore, which today only runs after a completed build.
- [ ] The lean4-cli tag list is injectable via the **existing** `LEAN_CLI_TAGS_FILE`
      env var (same name as `tools/lean-versions.sh`) so resolution is testable
      offline. No second env var is introduced.
- [ ] When no compatible tag exists, the installer fails with a clear message
      (naming the version and the `major.minor` line), not `revision not found`.
- [ ] `tools/lean-versions.sh` keeps a Lean version when a *compatible* lean4-cli
      tag exists (same rule + stable/RC constraint), not only when an exact tag
      exists. A resolver/tag-fetch/parse **error** still exits the script loudly;
      only a successful "no compatible tag" result drops the version.
- [ ] A Lean version whose `major.minor` line has no compatible lean4-cli tag is
      dropped (preserves the "wait out the window" behavior for fresh releases).
- [ ] Provenance: the resolved `Cli` rev is logged during the build. If cheap,
      surface it alongside the Lean version in `probe-lean --version` /
      build metadata so patch-specific failures stay diagnosable.
- [ ] Tests exercise the **real** resolver code (see Non-Goals on code duplication)
      and the relaxed policy.

## API / Interface Design

```sh
# tools/bash/install.sh (self-contained — runs via `curl | bash`, cannot source
# tools/lean-versions.sh, so the resolver is duplicated here and kept in sync).
# Guard the top-level main body behind `[ -n "${INSTALL_SH_LIB:-}" ] && return 0`
# so tests can `source` the script to get the functions without running main.

fetch_cli_tags()            # lists lean4-cli tags; honors $LEAN_CLI_TAGS_FILE for tests
resolve_cli_rev <version>   # validates input; prints resolved tag; empty + non-zero
                            #   exit if no compatible tag; distinct non-zero exit on
                            #   malformed input or fetch failure

# build_from_source: call resolve_cli_rev BEFORE mutating the tree; install a trap
# that restores lean-toolchain/lakefile.toml/lake-manifest.json on any exit; then
# rewrite the lakefile awk with the resolved `cli_rev` instead of `ver="$version"`.

# tools/lean-versions.sh
resolve_cli_tag <version>   # same awk resolver, reads lean4-cli tags on stdin;
                            #   exits non-zero on malformed tag/parse error
# Filter step (lines ~219-224): replace exact `grep -qxF "$v"` with a call that
# distinguishes three outcomes:
#   - resolver prints a tag           -> keep v
#   - resolver runs, prints nothing   -> drop v
#   - resolver/fetch errors (exit!=0,1) -> abort the whole script (do not drop)
```

Resolution ordering reuses the 5-digit fixed-width `key()` from
`tools/lean-versions.sh` (`maj|min|pat|1-isrc|rc`), so a stable tag outranks its
own RCs and comparisons are exact rather than lexical. The stable/RC constraint
is applied by filtering RC tags out of the candidate set when the target is
stable.

## Behavior

Normal operation:
- Target Lean `v4.32.0` (exact lean4-cli tag exists) → `v4.32.0`.
- Target Lean `v4.32.2` (no patch tag, stable minor tag exists) → `v4.32.0`.
- Target Lean `v4.32.0-rc1` (exact RC tag exists) → `v4.32.0-rc1`.
- Target Lean RC, minor line has only earlier RCs → highest RC `<=` target.

Edge cases / errors:
- **Stable target, minor line has only RC tags** (e.g. Lean `v4.32.1`, lean4-cli
  has only `v4.32.0-rc*`): resolver prints nothing. The stable/RC constraint
  forbids pairing a stable release with a prerelease `Cli`, so the version is
  dropped / the install errors — it is *not* silently built against an RC.
- **`major.minor` line entirely untagged** (e.g. Lean `v4.33.0`, no lean4-cli
  `v4.33.x`): resolver prints nothing. `install.sh` exits non-zero with a clear
  message; `lean-versions.sh` drops the version (so `release.yml`/`lean-watch.yml`
  skip it until lean4-cli tags the line — unchanged behavior).
- **Malformed target** (`4.32.2` without `v`, `v4.32`, `nightly-*`, trailing
  newline): resolver exits with a distinct error *before* any mutation; the
  installer surfaces it as an input error, not "untagged minor line."
- **lean4-cli tag list cannot be fetched:** both scripts abort loudly (no silent
  drop of every version).

## Non-Goals

- Changing the committed default `Cli` pin in `lakefile.toml` (it matches the
  repo's own toolchain; the resolver only matters when switching versions).
- Un-pinning `Cli` to a branch or floating rev.
- Cross-minor resolution (never use a lean4-cli tag from a different
  `major.minor` than the target Lean version).
- Backfilling prebuilt binaries for historical patch releases (the watcher will
  pick up currently-supported versions on its next run once the policy is
  relaxed).
- Replacing the awk `lakefile.toml` rewrite with a TOML-aware parser: the
  installer must stay dependency-free for `curl | bash`. The risk of a bad
  rewrite is covered by an acceptance check that inspects the rewritten
  `lakefile.toml` and resulting `lake-manifest.json` instead.
- A lock around the shared `~/.local/src/probe-lean` source checkout: concurrent
  installs racing on that directory is a pre-existing issue independent of tag
  resolution and belongs in its own change. Noted here as a known limitation.
- A hard cap on the release matrix: the watcher builds incrementally and skips
  existing assets, so a one-time larger matrix after the policy relaxes is
  self-limiting. Blast radius is measured (below) but not capped.

## Acceptance Criteria

Resolver unit tests exercise the **real** `install.sh` function (sourced via the
`INSTALL_SH_LIB` guard, not a copy), driven by `LEAN_CLI_TAGS_FILE`, offline:

| Target        | lean4-cli tags available             | Expected                    |
|---------------|--------------------------------------|-----------------------------|
| `v4.32.0`     | `…, v4.32.0`                         | `v4.32.0` (exact)           |
| `v4.32.2`     | `…, v4.32.0` (no patch tag)          | `v4.32.0` (minor stable)    |
| `v4.32.0-rc1` | `…, v4.32.0-rc1, v4.32.0-rc2`        | `v4.32.0-rc1` (exact RC)    |
| `v4.32.1`     | only `v4.32.0-rc2`, `v4.32.0-rc10`   | *(empty)* — stable≠RC pair  |
| `v4.33.0`     | nothing in `4.33.x`                  | *(empty, exit 1)*           |
| `v4.32`       | any                                  | *(error, distinct exit)*    |
| `leanprover/lean4:v4.32.2` | any                     | *(error, distinct exit)*    |

`tests/lean-versions/run.sh`:
- "default policy" now includes `v4.31.1` (untagged patch on a tagged stable
  minor → kept). Update expected newline and JSON assertions accordingly.
- New assertion: a stable release in a minor line with no compatible lean4-cli
  tag (add `v4.33.0` to `fixtures/releases.json`, absent from
  `fixtures/cli-tags.txt`) is dropped from the output.
- New assertion: a `fetch_cli_tags`/resolver error aborts the script (non-zero
  exit), rather than dropping versions silently.

Rewrite integrity: an acceptance check confirms that after `build_from_source`
the `Cli` rev in `lakefile.toml` **and** in the generated `lake-manifest.json`
equals the resolved `cli_rev` (not the target Lean version, not the stale
committed rev).

Crash-safe restore: a test that forces a mid-build failure (e.g. resolver returns
empty, or `lake` stubbed to fail) verifies the shared source checkout is restored
to its committed `lean-toolchain`/`lakefile.toml`/`lake-manifest.json`.

Blast radius: during implementation, run `tools/lean-versions.sh --json` against
live release/tag data and record how many *new* versions the relaxed filter
admits, so the first watcher run's matrix size is known before merge.

Manual: `install.sh --from-project <v4.32.2 project>` builds probe-lean from
source without a prebuilt binary and produces a working `probe-lean --version`
reporting Lean `v4.32.2`.

## Implementation sequencing

Two commits on one branch, one draft PR closing the tracking issue:
1. `install.sh`: `INSTALL_SH_LIB` source guard + `fetch_cli_tags`
   (`LEAN_CLI_TAGS_FILE`) + `resolve_cli_rev` (validation + stable/RC constraint)
   + pre-mutation ordering + `trap` restore + `build_from_source` rewrite, with
   `test_install_helpers.sh` sourcing the real functions. (Self-contained
   correctness fix.)
2. `tools/lean-versions.sh`: `resolve_cli_tag` + relaxed filter with loud-error
   preservation, `usage()` documenting `LEAN_CLI_TAGS_FILE`, and
   `tests/lean-versions/run.sh` updates.

---
Status: ready
