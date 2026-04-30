# Feature: Stale build cache detection and better incompatibility hints

## Summary

When `.olean` files are missing or stale (e.g., after `lake clean` or a toolchain switch), probe-lean either silently skips the build (returning "No modules found") or prints a misleading "Toolchain mismatch" hint even when versions nominally match. This spec improves both the cache validity check and the incompatible-header error message.

## Requirements

- [x] `isCacheValid` must verify that the project's `.olean` build directory exists, not just that the cache file is newer than `.lean` sources
- [ ] When `incompatible header` occurs but the toolchain versions match, suggest `lake clean` instead of "update probe-lean's lean-toolchain"
- [ ] The bash install script's cleanup bug (local variables in EXIT trap) must be fixed

## Behavior

### Cache validity (Environment.lean)

Current: `isCacheValid` only checks whether any `.lean` file is newer than `.lake/probe-lean/build_output.txt`.

Fixed: additionally check that `.lake/build/lib/` (or `.lake/build/lib/lean/`) exists and contains at least one `.olean` file. If the build output directory is missing, the cache is invalid regardless of timestamps.

### Incompatible-header hint (Atomize.lean)

Current: always says "Toolchain mismatch: probe-lean was built with Lean X, but the target project uses Y".

Fixed: compare the parsed version from the target's `lean-toolchain` with `Lean.versionString`. If they match (after stripping the `v` prefix and `leanprover/lean4:` prefix), the hint should instead say the `.olean` files are stale and suggest running `lake clean` on the target project, then re-running extract.

### Bash install script (tools/bash/install.sh)

Current: `trap cleanup EXIT` references local variables that go out of scope after `build_from_source` returns, causing `unbound variable` errors with `set -u`.

Fixed: restore files immediately after `lake build` within the function, remove the EXIT trap.

## Non-Goals

- Moving the cache directory location (`.lake/probe-lean/` is fine)
- Automatic `lake clean` — we just suggest it
- Detecting which specific dependency has stale oleans

## Acceptance Criteria

- [ ] After `lake clean`, `probe-lean extract` rebuilds instead of using stale cache
- [ ] When oleans are from a different toolchain but `lean-toolchain` matches probe-lean's version, the error suggests `lake clean`
- [ ] When oleans are from a different toolchain and `lean-toolchain` differs, the error shows the version mismatch
- [ ] Bash install script no longer errors on cleanup after source builds
- [ ] Tests cover cache validity with missing build directory
- [ ] Tests cover both branches of the incompatible-header hint

---
Status: in-progress
