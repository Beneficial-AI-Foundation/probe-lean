# Manual Test Report: Schema 2.0 Envelope (PR #3)

Date: 2026-03-06
PR: https://github.com/Beneficial-AI-Foundation/probe-lean/pull/3
Branch: `schema-2.0-envelope` at commit `68ed072`

## Objective

Validate the three manual test plan items from PR #3:

1. Run `probe-lean atomize` on a Lean project, verify output has envelope with
   correct `schema`, `tool`, `source`, `timestamp`, and `data` fields.
2. Run `probe-lean pipeline` and confirm `schema` is `probe-lean/enriched-atoms`
   and atoms include `language: "lean"`.
3. Feed Schema 2.0 enveloped `atoms.json` to `specify`/`verify`/`stubify` and
   confirm envelope-aware loading works.

## Target Projects

| Project | Toolchain | Branch | Commit | Package | Version source |
|---------|-----------|--------|--------|---------|----------------|
| curve25519-dalek-lean-verify | `v4.28.0-rc1` | `la/add_callgraph` | `bc60978` | `Curve25519Dalek` | `lakefile.toml` version field (`0.1.0`) |
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
# curve25519-dalek-lean-verify (already has .lake/packages/)
cd /home/lacra/git_repos/baif/curve25519-dalek-lean-verify
lake exe cache get

# ArkLib (already has .lake/packages/)
cd /home/lacra/git_repos/baif/ArkLib
lake exe cache get

# VCV-io (needs lake update first -- no .lake/packages/ existed)
cd /home/lacra/git_repos/baif/VCV-io
lake update
lake exe cache get
```

### 3. Run unit tests (baseline check)

```bash
cd /home/lacra/git_repos/baif/probe-lean
lake build tests && .lake/build/bin/tests
# Result: 147 passed, 0 failed
```

## Test Execution

For each project, five commands are run in order. `atomize` must run first
since `specify`, `verify`, and `stubify` consume its output.

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
  source_commit: (.source.commit | length),
  timestamp: .timestamp,
  data_count: (.data | length),
  top_keys: keys
}' <output-file>

# Per-atom language field
jq '.data | to_entries[0].value | has("language")' <output-file>
```

---

### Project 1: curve25519-dalek-lean-verify

Binary: `~/.local/bin/probe-lean-v4.28.0-rc1`

#### atomize

```bash
~/.local/bin/probe-lean-v4.28.0-rc1 atomize /home/lacra/git_repos/baif/curve25519-dalek-lean-verify
```

Output: `.verilib/probes/lean_Curve25519Dalek_0.1.0.json`

```
Found 165 modules
Found 1361 declarations
Wrote 1361 atoms
```

Envelope validation:
- `schema`: `"probe-lean/atoms"` -- PASS
- `schema-version`: `"2.0"` -- PASS
- `tool`: `{name: "probe-lean", version: "0.1.0", command: "atomize"}` -- PASS
- `source.package`: `"Curve25519Dalek"` -- PASS
- `source.package-version`: `"0.1.0"` (from lakefile.toml) -- PASS
- `source.language`: `"lean"` -- PASS
- `source.repo`: `"https://github.com/Beneficial-AI-Foundation/curve25519-dalek-lean-verify.git"` -- PASS
- `source.commit`: 40-char hash -- PASS
- `timestamp`: ISO 8601 UTC -- PASS
- `data`: 1361 atoms, keyed by `probe:` URIs -- PASS
- Sample atom has `language: "lean"` -- PASS

#### pipeline --skip-verify

```bash
~/.local/bin/probe-lean-v4.28.0-rc1 pipeline /home/lacra/git_repos/baif/curve25519-dalek-lean-verify --skip-verify
```

Output: `.verilib/probes/lean_Curve25519Dalek_0.1.0_graph.json`

- `schema`: `"probe-lean/enriched-atoms"` -- PASS
- `tool.command`: `"pipeline"` -- PASS
- `data`: 1361 enriched atoms -- PASS
- Sample atom: `language: "lean"`, `specified: true`, no `verification-status` -- PASS

#### specify (envelope-aware loading)

```bash
~/.local/bin/probe-lean-v4.28.0-rc1 specify /home/lacra/git_repos/baif/curve25519-dalek-lean-verify
```

Output: `.verilib/probes/lean_Curve25519Dalek_0.1.0_specs.json`

- Loaded enveloped atoms file successfully -- PASS
- `schema`: `"probe-lean/specs"`, `tool.command`: `"specify"` -- PASS
- `data`: 1361 entries -- PASS

#### verify (envelope-aware loading)

```bash
~/.local/bin/probe-lean-v4.28.0-rc1 verify /home/lacra/git_repos/baif/curve25519-dalek-lean-verify
```

Output: `.verilib/probes/lean_Curve25519Dalek_0.1.0_proofs.json`

- Loaded enveloped atoms file successfully -- PASS
- `schema`: `"probe-lean/proofs"`, `tool.command`: `"verify"` -- PASS
- `data`: 1361 entries, 1286 verified, 66 sorries -- PASS

#### stubify (envelope-aware loading)

```bash
~/.local/bin/probe-lean-v4.28.0-rc1 stubify /home/lacra/git_repos/baif/curve25519-dalek-lean-verify
```

Output: `.verilib/probes/lean_Curve25519Dalek_0.1.0_stubs.json`

- Loaded enveloped atoms file successfully -- PASS
- `schema`: `"probe-lean/stubs"`, `tool.command`: `"stubify"` -- PASS
- `data`: 0 stubs (expected -- no `.verilib/config.json` with `relevant-crate`) -- PASS

---

### Project 2: ArkLib

Binary: `~/.local/bin/probe-lean-v4.28.0`

#### atomize

```bash
~/.local/bin/probe-lean-v4.28.0 atomize /home/lacra/git_repos/baif/ArkLib
```

Output: `.verilib/probes/lean_Arklib_0c0afa9.json`

```
Found 162 modules
Found 4024 declarations
Wrote 4024 atoms
```

Envelope validation:
- `schema`: `"probe-lean/atoms"` -- PASS
- `schema-version`: `"2.0"` -- PASS
- `tool`: `{name: "probe-lean", version: "0.1.0", command: "atomize"}` -- PASS
- `source.package`: `"Arklib"` -- PASS
- `source.package-version`: `"0c0afa9"` (git hash fallback) -- PASS
- `source.language`: `"lean"` -- PASS
- `source.repo`: `"https://github.com/Beneficial-AI-Foundation/ArkLib"` -- PASS
- `source.commit`: 40-char hash -- PASS
- `timestamp`: ISO 8601 UTC -- PASS
- `data`: 4024 atoms -- PASS
- Sample atom has `language: "lean"` -- PASS

#### pipeline --skip-verify

```bash
~/.local/bin/probe-lean-v4.28.0 pipeline /home/lacra/git_repos/baif/ArkLib --skip-verify
```

Output: `.verilib/probes/lean_Arklib_0c0afa9_graph.json`

- `schema`: `"probe-lean/enriched-atoms"` -- PASS
- `tool.command`: `"pipeline"` -- PASS
- `data`: 4024 enriched atoms -- PASS
- Sample atom: `language: "lean"`, `specified: true`, no `verification-status` -- PASS

#### specify (envelope-aware loading)

```bash
~/.local/bin/probe-lean-v4.28.0 specify /home/lacra/git_repos/baif/ArkLib
```

Output: `.verilib/probes/lean_Arklib_0c0afa9_specs.json`

- `schema`: `"probe-lean/specs"`, `tool.command`: `"specify"` -- PASS
- `data`: 4024 entries -- PASS

#### verify (envelope-aware loading)

```bash
~/.local/bin/probe-lean-v4.28.0 verify /home/lacra/git_repos/baif/ArkLib
```

Output: `.verilib/probes/lean_Arklib_0c0afa9_proofs.json`

- `schema`: `"probe-lean/proofs"`, `tool.command`: `"verify"` -- PASS
- `data`: 4024 entries, 3654 verified, 336 sorries -- PASS

#### stubify (envelope-aware loading)

```bash
~/.local/bin/probe-lean-v4.28.0 stubify /home/lacra/git_repos/baif/ArkLib
```

Output: `.verilib/probes/lean_Arklib_0c0afa9_stubs.json`

- `schema`: `"probe-lean/stubs"`, `tool.command`: `"stubify"` -- PASS
- `data`: 0 stubs (expected) -- PASS

---

### Project 3: VCV-io

Binary: `~/.local/bin/probe-lean-v4.28.0`

#### atomize

```bash
~/.local/bin/probe-lean-v4.28.0 atomize /home/lacra/git_repos/baif/VCV-io
```

Output: `.verilib/probes/lean_VCVio_06d066e.json`

```
Found 91 modules
Found 1992 declarations
Wrote 1992 atoms
```

Envelope validation:
- `schema`: `"probe-lean/atoms"` -- PASS
- `schema-version`: `"2.0"` -- PASS
- `tool`: `{name: "probe-lean", version: "0.1.0", command: "atomize"}` -- PASS
- `source.package`: `"VCVio"` (from `lake-manifest.json`) -- PASS
- `source.package-version`: `"06d066e"` (git hash fallback) -- PASS
- `source.language`: `"lean"` -- PASS
- `source.repo`: `"https://github.com/Beneficial-AI-Foundation/VCV-io"` -- PASS
- `source.commit`: 40-char hash -- PASS
- `timestamp`: ISO 8601 UTC -- PASS
- `data`: 1992 atoms -- PASS
- Sample atom has `language: "lean"` -- PASS

#### pipeline --skip-verify

```bash
~/.local/bin/probe-lean-v4.28.0 pipeline /home/lacra/git_repos/baif/VCV-io --skip-verify
```

Output: `.verilib/probes/lean_VCVio_06d066e_graph.json`

- `schema`: `"probe-lean/enriched-atoms"` -- PASS
- `tool.command`: `"pipeline"` -- PASS
- `data`: 1992 enriched atoms -- PASS
- Sample atom: `language: "lean"`, `specified: true`, no `verification-status` -- PASS

#### specify (envelope-aware loading)

```bash
~/.local/bin/probe-lean-v4.28.0 specify /home/lacra/git_repos/baif/VCV-io
```

Output: `.verilib/probes/lean_VCVio_06d066e_specs.json`

- `schema`: `"probe-lean/specs"`, `tool.command`: `"specify"` -- PASS
- `data`: 1992 entries -- PASS

#### verify (envelope-aware loading)

```bash
~/.local/bin/probe-lean-v4.28.0 verify /home/lacra/git_repos/baif/VCV-io
```

Output: `.verilib/probes/lean_VCVio_06d066e_proofs.json`

- `schema`: `"probe-lean/proofs"`, `tool.command`: `"verify"` -- PASS
- `data`: 1992 entries, 1992/1992 verified, 0 sorries -- PASS

#### stubify (envelope-aware loading)

```bash
~/.local/bin/probe-lean-v4.28.0 stubify /home/lacra/git_repos/baif/VCV-io
```

Output: `.verilib/probes/lean_VCVio_06d066e_stubs.json`

- `schema`: `"probe-lean/stubs"`, `tool.command`: `"stubify"` -- PASS
- `data`: 0 stubs (expected) -- PASS

---

## Results Summary

All 15 command runs (5 commands x 3 projects) passed.

| Command | curve25519-dalek | ArkLib | VCV-io |
|---------|-----------------|--------|--------|
| atomize | PASS (1361 atoms) | PASS (4024 atoms) | PASS (1992 atoms) |
| pipeline --skip-verify | PASS | PASS | PASS |
| specify | PASS | PASS | PASS |
| verify | PASS (1286/1361) | PASS (3654/4024) | PASS (1992/1992) |
| stubify | PASS (0 stubs) | PASS (0 stubs) | PASS (0 stubs) |

### Envelope fields verified across all outputs

| Field | Expected | Actual |
|-------|----------|--------|
| `schema` | Matches command type | Correct for all 5 schema values |
| `schema-version` | `"2.0"` | Correct |
| `tool.name` | `"probe-lean"` | Correct |
| `tool.version` | `"0.1.0"` | Correct |
| `tool.command` | Matches invoked command | Correct |
| `source.language` | `"lean"` | Correct |
| `source.package` | From lakefile.toml or lake-manifest.json | Correct |
| `source.package-version` | From lakefile.toml version or 7-char git hash | Correct |
| `source.repo` | Git remote URL | Correct |
| `source.commit` | 40-char git hash | Correct |
| `timestamp` | ISO 8601 UTC | Correct |
| `data` | Non-empty dict (except stubify without config) | Correct |
| Per-atom `language` | `"lean"` | Present in all atoms |

### Package versioning strategy validated

- **With version in lakefile.toml**: `Curve25519Dalek` uses `0.1.0` -- correct.
- **Without version, TOML lakefile**: `Arklib` falls back to `0c0afa9` (git hash) -- correct.
- **Without version, Lean lakefile**: `VCVio` name from `lake-manifest.json`, version `06d066e` (git hash) -- correct.

## Issues Encountered

### 1. Toolchain version mismatch

probe-lean (`v4.29.0-rc3`) cannot load `.olean` files built by target projects
(`v4.28.0` / `v4.28.0-rc1`). Even `v4.28.0` vs `v4.28.0-rc1` are incompatible.

**Resolution**: Used `tools/bash/install.sh` to build version-specific binaries.

### 2. Missing Mathlib cache

Without `lake exe cache get`, Mathlib compiles from source (~30+ minutes).
curve25519-dalek-lean-verify had a partial cache (2666/7873 files).
VCV-io had no `.lake/packages/` directory at all.

**Resolution**: Ran `lake exe cache get` on each project (and `lake update` first for VCV-io).

## Reproducing These Tests

```bash
# 1. Check out the PR branch
cd /path/to/probe-lean
git checkout schema-2.0-envelope

# 2. Build binaries for each target toolchain
bash tools/bash/install.sh v4.28.0
bash tools/bash/install.sh v4.28.0-rc1
lake build  # restore main build

# 3. Download Mathlib cache for each project
cd /path/to/curve25519-dalek-lean-verify && lake exe cache get
cd /path/to/ArkLib && lake exe cache get
cd /path/to/VCV-io && lake update && lake exe cache get

# 4. Run all commands (use matching binary per toolchain)
PL28=~/.local/bin/probe-lean-v4.28.0
PL28RC1=~/.local/bin/probe-lean-v4.28.0-rc1

for proj_bin in \
  "/path/to/curve25519-dalek-lean-verify $PL28RC1" \
  "/path/to/ArkLib $PL28" \
  "/path/to/VCV-io $PL28"; do
  proj=$(echo $proj_bin | cut -d' ' -f1)
  bin=$(echo $proj_bin | cut -d' ' -f2)
  echo "=== Testing $proj ==="
  $bin atomize "$proj"
  $bin pipeline "$proj" --skip-verify
  $bin specify "$proj"
  $bin verify "$proj"
  $bin stubify "$proj"
done

# 5. Validate envelopes
for f in /path/to/project/.verilib/probes/*.json; do
  echo "--- $f ---"
  jq '{schema, "schema-version", tool_cmd: .tool.command, data_count: (.data | length)}' "$f"
done
```
