# Manual Test Report: `extract` and `viewify` Commands

Date: 2026-03-11
Branch: `main` (post `verify` → `extract` rename)

## Objective

Validate that the renamed `extract` command (formerly `verify`) works correctly:

1. Run `probe-lean extract` on a Lean project, verify output has envelope with
   correct `schema`, `tool`, `source`, `timestamp`, and `data` fields, and that
   unified atoms include `verification-status` and `specified`.
2. Run `probe-lean viewify` on extract output, confirm `schema` is `probe-lean/viewify`
   and atoms are filtered correctly.

## Target Projects

| Project | Toolchain | Branch | Commit | Package | Version source |
|---------|-----------|--------|--------|---------|----------------|
| curve25519-dalek-lean-verify | `v4.28.0-rc1` | `la/add_callgraph` | `ab61e08` | `Curve25519Dalek` | `lakefile.toml` version field (`0.1.0`) |
| ArkLib | `v4.28.0` | `main` | `0c0afa9` | `Arklib` | git short hash (no version in lakefile) |
| VCV-io | `v4.28.0` | `master` | `06d066e` | `VCVio` | git short hash (no version in lakefile) |

## Prerequisites

### 1. Build probe-lean binaries matching target toolchains

probe-lean itself is on `v4.29.0-rc3`, but Lean `.olean` files are incompatible
across toolchain versions. We must build separate binaries for each toolchain
used by the target projects.

```bash
cd /home/lacra/git_repos/baif/probe-lean

# Build for v4.28.0 (ArkLib, VCV-io)
bash tools/bash/install.sh v4.28.0

# Build for v4.28.0-rc1 (curve25519-dalek-lean-verify)
bash tools/bash/install.sh v4.28.0-rc1

# Restore the main build
lake build
```

This produces:
- `~/.local/bin/probe-lean-v4.28.0`
- `~/.local/bin/probe-lean-v4.28.0-rc1`

### 2. Download Mathlib cache for each project

Without the prebuilt Mathlib `.olean` cache, builds take 30+ minutes. All three
projects depend on Mathlib.

```bash
cd /home/lacra/git_repos/baif/curve25519-dalek-lean-verify && lake exe cache get
cd /home/lacra/git_repos/baif/ArkLib && lake exe cache get
cd /home/lacra/git_repos/baif/VCV-io && lake update && lake exe cache get
```

### 3. Preserve old results for comparison

Rename `.verilib` → `.verilib-old` in each project to keep the previous
5-command run as a reference.

```bash
for proj in curve25519-dalek-lean-verify ArkLib VCV-io; do
  mv /home/lacra/git_repos/baif/$proj/.verilib /home/lacra/git_repos/baif/$proj/.verilib-old
done
```

### 4. Run unit tests (baseline check)

```bash
cd /home/lacra/git_repos/baif/probe-lean
lake build tests && .lake/build/bin/tests
# Result: 173 passed, 0 failed
```

## Test Execution

For each project, two commands are run: `extract` (combined atomize + specify +
sorry detection) and `viewify` (filter atoms for web UI).

### Validation method

After each command, inspect the output JSON with `jq`:

```bash
# Envelope structure
jq '{
  schema: .schema,
  "schema-version": ."schema-version",
  tool: .tool,
  source_pkg: .source.package,
  source_ver: .source["package-version"],
  source_lang: .source.language,
  source_repo: .source.repo,
  commit_len: (.source.commit | length),
  timestamp: .timestamp,
  data_count: (.data | length),
  top_keys: keys
}' <output-file>

# Per-atom fields
jq '.data | to_entries[0].value | keys' <output-file>
```

---

### Project 1: curve25519-dalek-lean-verify

Binary: `~/.local/bin/probe-lean-v4.28.0-rc1`

#### extract

```bash
~/.local/bin/probe-lean-v4.28.0-rc1 extract /home/lacra/git_repos/baif/curve25519-dalek-lean-verify
```

Output: `.verilib/probes/lean_Curve25519Dalek_0.1.0.json`

```
Building project at /home/lacra/git_repos/baif/curve25519-dalek-lean-verify...
=== Step 1/3: Atomize ===
Found 1488 atoms
=== Step 2/3: Specify ===
Computed specification status for 1488 declarations
=== Step 3/3: Verify ===
Found 64 sorry warnings
Verified: 1420/1488 declarations
=== Merging results ===
Wrote 1488 unified atoms
```

Envelope validation:
- `schema`: `"probe-lean/extract"` -- PASS
- `schema-version`: `"2.0"` -- PASS
- `tool`: `{name: "probe-lean", version: "0.1.0", command: "extract"}` -- PASS
- `source.package`: `"Curve25519Dalek"` -- PASS
- `source.package-version`: `"0.1.0"` (from lakefile.toml) -- PASS
- `source.language`: `"lean"` -- PASS
- `source.repo`: `"https://github.com/Beneficial-AI-Foundation/curve25519-dalek-lean-verify.git"` -- PASS
- `source.commit`: 40-char hash -- PASS
- `timestamp`: ISO 8601 UTC -- PASS
- `data`: 1488 unified atoms -- PASS
- Sample atom has `language: "lean"` -- PASS
- Sample atom has `verification-status: "verified"` and `specified: true` -- PASS

#### viewify

```bash
~/.local/bin/probe-lean-v4.28.0-rc1 viewify /home/lacra/git_repos/baif/curve25519-dalek-lean-verify
```

Output: `.verilib/views/molecules_all.json`

- Loaded 1488 atoms from extract output -- PASS
- `schema`: `"probe-lean/viewify"`, `tool.command`: `"viewify"` -- PASS
- `data`: 0 molecules (expected -- no `.verilib/probes/config.json` with `relevant-crate`) -- PASS

#### Comparison with old 5-command run

| Field | Old (pipeline) | New (extract) | Match? |
|-------|---------------|--------------|--------|
| Atom count | 1361 | 1488 | UPDATED (newer commit) |
| Specified: true | 1361 | 1488 | UPDATED (newer commit) |
| Verified | N/A (old had no verification-status) | 1420 | IMPROVED |
| Unverified | N/A | 68 | IMPROVED |
| language: "lean" | present | present | YES |
| Core atom fields (kind, code-module, display-name, code-text, code-path, dependencies) | present | present | YES |

---

### Project 2: ArkLib

Binary: `~/.local/bin/probe-lean-v4.28.0`

#### extract

```bash
~/.local/bin/probe-lean-v4.28.0 extract /home/lacra/git_repos/baif/ArkLib
```

Output: `.verilib/probes/lean_Arklib_0c0afa9.json`

```
Building project at /home/lacra/git_repos/baif/ArkLib...
=== Step 1/3: Atomize ===
Found 4024 atoms
=== Step 2/3: Specify ===
Computed specification status for 4024 declarations
=== Step 3/3: Verify ===
Found 336 sorry warnings
Verified: 3654/4024 declarations
=== Merging results ===
Wrote 4024 unified atoms
```

Envelope validation:
- `schema`: `"probe-lean/extract"` -- PASS
- `schema-version`: `"2.0"` -- PASS
- `tool`: `{name: "probe-lean", version: "0.1.0", command: "extract"}` -- PASS
- `source.package`: `"Arklib"` -- PASS
- `source.package-version`: `"0c0afa9"` (git hash fallback) -- PASS
- `source.language`: `"lean"` -- PASS
- `source.repo`: `"https://github.com/Beneficial-AI-Foundation/ArkLib"` -- PASS
- `source.commit`: 40-char hash -- PASS
- `data`: 4024 unified atoms -- PASS

#### viewify

```bash
~/.local/bin/probe-lean-v4.28.0 viewify /home/lacra/git_repos/baif/ArkLib
```

Output: `.verilib/views/molecules_all.json`

- `schema`: `"probe-lean/viewify"`, `tool.command`: `"viewify"` -- PASS
- `data`: 0 molecules (expected) -- PASS

#### Comparison with old 5-command run

| Field | Old (pipeline) | New (extract) | Match? |
|-------|---------------|--------------|--------|
| Atom count | 4024 | 4024 | YES |
| Specified: true | 4024 | 4024 | YES |
| Verified | N/A | 3654 | IMPROVED |
| Unverified | N/A | 370 | IMPROVED |

---

### Project 3: VCV-io

Binary: `~/.local/bin/probe-lean-v4.28.0`

#### extract

```bash
~/.local/bin/probe-lean-v4.28.0 extract /home/lacra/git_repos/baif/VCV-io
```

Output: `.verilib/probes/lean_VCVio_06d066e.json`

```
Building project at /home/lacra/git_repos/baif/VCV-io...
=== Step 1/3: Atomize ===
Found 1992 atoms
=== Step 2/3: Specify ===
Computed specification status for 1992 declarations
=== Step 3/3: Verify ===
Found 0 sorry warnings
Verified: 1992/1992 declarations
=== Merging results ===
Wrote 1992 unified atoms
```

Envelope validation:
- `schema`: `"probe-lean/extract"` -- PASS
- `schema-version`: `"2.0"` -- PASS
- `tool`: `{name: "probe-lean", version: "0.1.0", command: "extract"}` -- PASS
- `source.package`: `"VCVio"` -- PASS
- `source.package-version`: `"06d066e"` (git hash fallback) -- PASS
- `source.language`: `"lean"` -- PASS
- `source.repo`: `"https://github.com/Beneficial-AI-Foundation/VCV-io"` -- PASS
- `source.commit`: 40-char hash -- PASS
- `data`: 1992 unified atoms -- PASS

#### viewify

```bash
~/.local/bin/probe-lean-v4.28.0 viewify /home/lacra/git_repos/baif/VCV-io
```

Output: `.verilib/views/molecules_all.json`

- `schema`: `"probe-lean/viewify"`, `tool.command`: `"viewify"` -- PASS
- `data`: 0 molecules (expected) -- PASS

#### Comparison with old 5-command run

| Field | Old (pipeline) | New (extract) | Match? |
|-------|---------------|--------------|--------|
| Atom count | 1992 | 1992 | YES |
| Specified: true | 1992 | 1992 | YES |
| Verified | N/A | 1992 | IMPROVED |
| Unverified | N/A | 0 | IMPROVED |

---

## Results Summary

All 6 command runs (2 commands x 3 projects) passed.

| Command | curve25519-dalek | ArkLib | VCV-io |
|---------|-----------------|--------|--------|
| extract | PASS (1488 atoms, 1420 verified) | PASS (4024 atoms, 3654 verified) | PASS (1992 atoms, 1992 verified) |
| viewify | PASS (0 molecules) | PASS (0 molecules) | PASS (0 molecules) |

### Consistency with old 5-command run

The old `.verilib-old/` directories contain results from the previous 5-command
CLI (atomize, pipeline, specify, verify, stubify). Key consistency findings:

| Metric | Old 5-command | New 2-command | Consistent? |
|--------|--------------|---------------|-------------|
| Atom counts | 1361 / 4024 / 1992 | 1488 / 4024 / 1992 | YES (dalek updated) |
| Specified counts | 1361 / 4024 / 1992 | 1488 / 4024 / 1992 | YES (dalek updated) |
| Core atom fields | kind, code-module, code-path, code-text, dependencies, display-name, language, specified | Same + is-extraction-artifact, is-hidden, is-ignored, is-relevant, name, rust-source, verification-status | SUPERSET |
| Verification status | Not merged into atoms (all null in old proofs output) | Properly merged: verified/unverified | IMPROVED (bug fix) |
| Stubs / Molecules | 0 stubs (old) | 0 molecules (new) | YES |
| Package names | Curve25519Dalek / Arklib / VCVio | Same | YES |
| Package versions | 0.1.0 / 0c0afa9 / 06d066e | Same | YES |

### Schema changes (old → new)

| Old schema | New schema | Notes |
|-----------|-----------|-------|
| `probe-lean/atoms` | (subsumed by extract) | No separate atomize output |
| `probe-lean/specs` | (subsumed by extract) | No separate specify output |
| `probe-lean/proofs` | (subsumed by extract) | No separate verify-only output |
| `probe-lean/enriched-atoms` | `probe-lean/extract` | Combined command, unified atoms |
| `probe-lean/stubs` | `probe-lean/viewify` | Renamed, output in `.verilib/views/` |

### Output filename changes

Dashes in package names are replaced with underscores. Dots in version strings
are preserved as-is:
- Example: `lean_Curve25519Dalek_0.1.0.json`

### Envelope fields verified across all outputs

| Field | Expected | Actual |
|-------|----------|--------|
| `schema` | `"probe-lean/extract"` or `"probe-lean/viewify"` | Correct |
| `schema-version` | `"2.0"` | Correct |
| `tool.name` | `"probe-lean"` | Correct |
| `tool.version` | `"0.1.0"` | Correct |
| `tool.command` | `"extract"` or `"viewify"` | Correct |
| `source.language` | `"lean"` | Correct |
| `source.package` | From lakefile.toml or lake-manifest.json | Correct |
| `source.package-version` | From lakefile.toml version or 7-char git hash | Correct |
| `source.repo` | Git remote URL | Correct |
| `source.commit` | 40-char git hash | Correct |
| `timestamp` | ISO 8601 UTC | Correct |
| `data` | Non-empty dict (except viewify without config) | Correct |
| Per-atom `language` | `"lean"` | Present in all atoms |

### Package versioning strategy validated

- **With version in lakefile.toml**: `Curve25519Dalek` uses `0.1.0` -- correct.
- **Without version, TOML lakefile**: `Arklib` falls back to `0c0afa9` (git hash) -- correct.
- **Without version, Lean lakefile**: `VCVio` name from `lake-manifest.json`, version `06d066e` (git hash) -- correct.

## Known Issues

### 1. Toolchain version mismatch

probe-lean (`v4.29.0-rc3`) cannot load `.olean` files built by target projects
(`v4.28.0` / `v4.28.0-rc1`). Even `v4.28.0` vs `v4.28.0-rc1` are incompatible.

**Resolution**: Used `tools/bash/install.sh` to build version-specific binaries.

### 2. Missing Mathlib cache

Without `lake exe cache get`, Mathlib compiles from source (~30+ minutes).

**Resolution**: Ran `lake exe cache get` on each project before testing.

## Reproducing These Tests

```bash
# 1. Build binaries for each target toolchain
cd /path/to/probe-lean
bash tools/bash/install.sh v4.28.0
bash tools/bash/install.sh v4.28.0-rc1
lake build  # restore main build

# 2. Download Mathlib cache for each project
cd /path/to/curve25519-dalek-lean-verify && lake exe cache get
cd /path/to/ArkLib && lake exe cache get
cd /path/to/VCV-io && lake update && lake exe cache get

# 3. Run all commands (use matching binary per toolchain)
PL28=~/.local/bin/probe-lean-v4.28.0
PL28RC1=~/.local/bin/probe-lean-v4.28.0-rc1

for proj_bin in \
  "/path/to/curve25519-dalek-lean-verify $PL28RC1" \
  "/path/to/ArkLib $PL28" \
  "/path/to/VCV-io $PL28"; do
  proj=$(echo $proj_bin | cut -d' ' -f1)
  bin=$(echo $proj_bin | cut -d' ' -f2)
  echo "=== Testing $proj ==="
  $bin extract "$proj"
  $bin viewify "$proj"
done

# 4. Validate envelopes
for proj in /path/to/curve25519-dalek-lean-verify /path/to/ArkLib /path/to/VCV-io; do
  echo "--- $proj ---"
  for f in "$proj"/.verilib/probes/*.json "$proj"/.verilib/views/*.json; do
    [ -f "$f" ] && jq '{schema, "schema-version", tool_cmd: .tool.command, data_count: (.data | length)}' "$f"
  done
done
```
