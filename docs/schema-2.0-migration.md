# Schema 2.0 Migration Guide

## CLI Changes

### Before (Schema 1.x / early 2.0)

```bash
probe-lean atomize <PATH>   # → atoms.json
probe-lean specify <PATH>   # → specs.json  (depends on atomize output)
probe-lean verify <PATH>    # → proofs.json (depends on atomize output)
probe-lean pipeline <PATH>  # → graph.json  (combined, but schema "probe-lean/enriched-atoms")
probe-lean stubify <PATH>   # → stubs.json  (depends on atomize output)
```

### After (Schema 2.0)

```bash
probe-lean verify <PATH>    # → .verilib/probes/lean_<pkg>_<ver>.json  (unified atoms)
probe-lean view <PATH>      # → .verilib/views/molecules_all.json      (filtered molecules)
```

## Command Mapping

| Old command | New equivalent | Notes |
|-------------|---------------|-------|
| `atomize` | `verify` | Atom extraction is the first step of `verify` |
| `specify` | `verify` | Specification status is computed inline |
| `verify` (old) | `verify` | Sorry detection is the final step of `verify` |
| `pipeline` | `verify` | Direct replacement; same combined pipeline logic |
| `stubify` | `view` | Same filtering logic, renamed output format |

## Schema Identifier Changes

| Old schema | New schema |
|------------|-----------|
| `probe-lean/atoms` | `probe-lean/verify` |
| `probe-lean/specs` | (internal to `verify`) |
| `probe-lean/proofs` | (internal to `verify`) |
| `probe-lean/enriched-atoms` | `probe-lean/verify` |
| `probe-lean/stubs` | `probe-lean/view` |

## Output Path Changes

| Old default path | New default path |
|-----------------|-----------------|
| `.verilib/probes/lean_<pkg>_<ver>.json` | `.verilib/probes/lean_<pkg>_<ver>.json` (same) |
| `.verilib/probes/lean_<pkg>_<ver>_specs.json` | (internal to verify) |
| `.verilib/probes/lean_<pkg>_<ver>_proofs.json` | (internal to verify) |
| `.verilib/probes/lean_<pkg>_<ver>_graph.json` | `.verilib/probes/lean_<pkg>_<ver>.json` |
| `.verilib/probes/lean_<pkg>_<ver>_stubs.json` | `.verilib/views/molecules_all.json` |

## Type Renames

| Old name | New name |
|----------|----------|
| `EnrichedAtom` | `UnifiedAtom` |
| `EnrichedAtomsOutput` | `UnifiedAtomsOutput` |
| `StubsOutput` | `MoleculesOutput` |
| `ProjectMetadata` | `SourceInfo` (from Types.lean) |

## Source Field Changes

`SourceInfo.repo` and `SourceInfo.commit` changed from `Option String` to `String`
(empty string when unavailable). This conforms to the `probe` repository's JSON schema
which declares these fields as required.

## Bug Fixes

- **`markAtomFlags` now called in the combined pipeline**: The old `pipeline` command
  skipped the `markAtomFlags` step, so `is-hidden`, `is-extraction-artifact`, and
  `is-ignored` were always `false` in pipeline output. The new `verify` command correctly
  applies these flags.
