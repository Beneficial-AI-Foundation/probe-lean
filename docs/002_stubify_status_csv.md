# Comparison: syncstatus vs probe-lean stubify

## syncstatus (curve25519-dalek-lean-verify)

**Input**: Lean environment (loaded directly from compiled modules)

**Process**:
1. Loads Lean environment from `Curve25519Dalek` module
2. Enumerates all definitions from `Curve25519Dalek.Funs`
3. Parses docstrings to extract Rust metadata (source, lines, rust_name)
4. Analyzes Lean expression tree for dependencies
5. Computes verification status (`specified`, `verified`, `fully_verified`)

**Output**: `functions.json` + `status.csv`

## probe-lean stubify

**Input**: `functions.json` (pre-existing)

**Process**:
1. Reads `functions.json`
2. Filters to `is_relevant` entries
3. Transforms to stub format with clash detection for keys

**Output**: `stubs.json`

## Key Differences

| Aspect | syncstatus | stubify |
|--------|------------|---------|
| Input | Lean environment | functions.json |
| Analysis | Full (deps, verification) | None (just transforms) |
| Computes | specified/verified/fully_verified | Nothing new |
| Purpose | Extract all metadata from Lean | Reformat for different use case |

**Stubify is a downstream transformer** - it consumes functions.json that syncstatus produces. It doesn't do any Lean analysis itself.
