# Usage Guide

## Prerequisites

- **Lean 4 toolchain** (`elan`, `lake`) -- install via [elan](https://github.com/leanprover/elan#installation)
- `~/.local/bin` in your `PATH` (for the installed binary)
- The target project must build with `lake build`

## Installation

```bash
git clone https://github.com/Beneficial-AI-Foundation/probe-lean
cd probe-lean
```

**Option 1: Bash**
```bash
./tools/bash/install.sh [VERSION]
```

**Option 2: Python (using uv)**
```bash
uv run tools/python/install.py [VERSION]
```

Both scripts build the project and install the binary to `~/.local/bin/probe-lean-<version>` (with a symlink at `~/.local/bin/probe-lean`) and the required interpreter `.olean` files to `~/.local/lib/probe-lean/`.

If no version is specified, the script shows a menu of available versions.

### Toolchain version matching

probe-lean **must** be installed for the same Lean version as the target project. `.olean` files are version-specific and will not load across versions.

Check what version the target project needs:

```bash
cat ../my-lean-project/lean-toolchain
# e.g. leanprover/lean4:v4.28.0
```

Then install probe-lean for that version:

```bash
./tools/bash/install.sh v4.28.0
```

If your targets use different Lean versions, the install script temporarily switches the toolchain, builds, and installs a versioned binary (`probe-lean-v4.28.0`). The `probe-lean` symlink points to the most recently installed version.

---

## Commands

### `extract`

Analyze a Lean 4 project: extract atoms, detect sorries, compute specs, and produce unified output.

```
probe-lean extract <PROJECT_PATH> [OPTIONS]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--output <PATH>` | `-o` | Output file path (default: `.verilib/probes/lean_<pkg>_<ver>.json`) |
| `--module <PREFIX>` | `-m` | Filter to specific module prefix |
| `--library <LIBS>` | `-l` | Comma-separated list of library names to build (default: `defaultTargets` from `lakefile.toml`, falling back to all `[[lean_lib]]` entries) |
| `--skip-verify` | | Skip the sorry detection step (graph structure only) |
| `--from-file <FILE>` | | Use existing build output for sorry detection instead of running lake |

---

## Walkthrough: Analyzing Real Projects

### Mathlib cache (critical for performance)

Most Lean verification projects depend on [Mathlib](https://github.com/leanprover-community/mathlib4). Compiling Mathlib from source is extremely slow and saturates all CPU cores. The Mathlib project publishes pre-built `.olean` caches that download in minutes.

**Always run this before building a Mathlib-dependent project for the first time:**

```bash
cd <target-project>
lake exe cache get
```

If you skip this step, `probe-lean extract` will trigger a full Mathlib compilation. probe-lean warns you if it detects a missing cache:

```
⚠ Warning: This project depends on Mathlib but no pre-built .olean cache was found.
  Building Mathlib from source can take hours. Run this first:
    cd <target-project> && lake exe cache get
```

### Example 1: [curve25519-dalek-lean-verify](https://github.com/Beneficial-AI-Foundation/curve25519-dalek-lean-verify)

Aeneas-generated Lean translation of the curve25519-dalek Rust crate, with Mathlib-based specifications and proofs.

| Property | Value |
|----------|-------|
| Toolchain | `v4.28.0-rc1` |
| Depends on Mathlib | Yes |
| Libraries | `Curve25519Dalek`, `Utils` (utilities/scripts) |
| `defaultTargets` | `["Curve25519Dalek"]` |

```bash
# 1. Install probe-lean for the matching toolchain
cd probe-lean
./tools/bash/install.sh v4.28.0-rc1

# 2. Download Mathlib cache (first time only — ~5 min)
cd ../curve25519-dalek-lean-verify
lake exe cache get

# 3. Run extract
probe-lean extract ../curve25519-dalek-lean-verify/
```

probe-lean reads `defaultTargets = ["Curve25519Dalek"]` and builds only that library (the `Utils` library contains standalone scripts and is not part of the main verification target).

### Example 2: [VCV-io](https://github.com/Verified-zkEVM/VCV-io)

Lean 4 library for verified cryptographic protocols. Uses `lakefile.lean` (not `.toml`).

| Property | Value |
|----------|-------|
| Toolchain | `v4.28.0` |
| Depends on Mathlib | Yes |
| Default targets | `VCVio`, `Examples` (via `@[default_target]` in lakefile.lean) |
| Other libraries | `ToMathlib`, `LibSodium` |

```bash
# 1. Install probe-lean for v4.28.0
cd probe-lean
./tools/bash/install.sh v4.28.0

# 2. Download Mathlib cache
cd ../VCV-io
lake exe cache get

# 3. Run extract
probe-lean extract ../VCV-io/
```

Since VCV-io uses `lakefile.lean` (not `.toml`), probe-lean cannot auto-detect library names and falls back to `lake build` with no explicit targets, which uses the project's `@[default_target]` annotations.

### Example 3: [ArkLib](https://github.com/Verified-zkEVM/ArkLib)

Lean 4 library for formally verified zkSNARK components. Depends on Mathlib and VCV-io.

| Property | Value |
|----------|-------|
| Toolchain | `v4.28.0` |
| Depends on Mathlib | Yes (transitively via VCV-io) |
| Libraries | `ArkLib` |
| `defaultTargets` | `["ArkLib"]` |

```bash
# 1. Install probe-lean for v4.28.0 (skip if already done for VCV-io)
cd probe-lean
./tools/bash/install.sh v4.28.0

# 2. Download Mathlib cache
cd ../ArkLib
lake exe cache get

# 3. Run extract (builds ArkLib and its deps, then analyzes)
probe-lean extract ../ArkLib/
```

If you've already built the project, probe-lean will detect that the build cache is up-to-date and skip the `lake build` step automatically (sorry detection still works using the cached build output).

Since VCV-io uses `lakefile.lean` (not `.toml`), probe-lean cannot auto-detect library names and falls back to `lake build` with no explicit targets, which uses whatever the project defines as defaults.

### Example 4: [signal-shot-PQXDH](https://github.com/Beneficial-AI-Foundation/signal-shot-PQXDH)

Lean 4 formalization of the Signal PQXDH key agreement protocol. Depends on Mathlib and subverso.

| Property | Value |
|----------|-------|
| Toolchain | `v4.29.0-rc3` |
| Depends on Mathlib | Yes |
| Libraries | `PQXDHLean` |
| `defaultTargets` | `["PQXDHLean"]` |

```bash
# 1. Install probe-lean for the matching toolchain
cd probe-lean
./tools/bash/install.sh v4.29.0-rc3

# 2. Download Mathlib cache (first time only — ~5 min)
cd ../signal-shot-PQXDH
lake exe cache get

# 3. Run extract
probe-lean extract ../signal-shot-PQXDH/
```

### Example 5: From-scratch setup on a fresh machine

Starting from nothing on Ubuntu/Debian:

```bash
# Install elan (Lean version manager)
curl https://elan-init.trycloudflake.com/elan-init.sh -sSf | sh
source ~/.profile

# Clone probe-lean
git clone https://github.com/Beneficial-AI-Foundation/probe-lean
cd probe-lean

# Check what version the target project needs
cat ../my-lean-project/lean-toolchain
# leanprover/lean4:v4.28.0

# Install probe-lean for that version
./tools/bash/install.sh v4.28.0

# Ensure ~/.local/bin is in PATH
export PATH="$PATH:$HOME/.local/bin"

# Prepare the target project
cd ../my-lean-project
lake exe cache get    # download Mathlib cache (if applicable)

# Run extraction
probe-lean extract ../my-lean-project/
```

---

## Performance Tips

### Automatic build caching

probe-lean automatically skips `lake build` when the build cache is up-to-date (no `.lean` file has been modified since the last build). Sorry detection still works using the cached build output.

### Use `--skip-verify` for faster iteration

Sorry detection requires build output. If you only need the dependency graph:

```bash
probe-lean extract ./my-project --skip-verify
```

### Use `nice` for long builds on shared machines

`lake build` for Mathlib-dependent projects can saturate all CPU cores for 10--30 minutes (longer on first build). On shared machines or when you need the system responsive, build at low priority:

```bash
cd <target-project>
lake exe cache get
nice -n 15 probe-lean extract <target-project>
```

This keeps the build running but yields CPU to interactive tasks. `nice -n 19` is the lowest priority; `nice -n 10` is a reasonable middle ground.

### Filter to a single module

For quick iteration on a specific module:

```bash
probe-lean extract ./my-project -m MyProject.Core
```

---

## Output Format

For the complete JSON schema specification, see [SCHEMA.md](SCHEMA.md).

The `extract` command produces a JSON file wrapped in a Schema 2.0 metadata envelope:

```json
{
  "schema": "probe-lean/extract",
  "schema-version": "2.0",
  "tool": { "name": "probe-lean", "version": "0.2.0", "command": "extract" },
  "source": {
    "repo": "https://github.com/org/project",
    "commit": "abc123d",
    "language": "lean",
    "package": "MyProject",
    "package-version": "0.1.0"
  },
  "timestamp": "2026-03-17T12:00:00Z",
  "data": {
    "probe:MyModule.helper": {
      "display-name": "helper",
      "kind": "def",
      "language": "lean",
      "dependencies": ["probe:MyModule.MyType"],
      "type-dependencies": ["probe:MyModule.MyType"],
      "term-dependencies": [],
      "code-module": "MyModule",
      "code-path": "MyModule.lean",
      "code-text": { "lines-start": 5, "lines-end": 8 },
      "is-hidden": false,
      "is-extraction-artifact": false,
      "is-ignored": false,
      "is-relevant": true,
      "rust-source": null,
      "specs": ["probe:MyModule.helper_spec"],
      "primary-spec": "probe:MyModule.helper_spec",
      "verification-status": "verified"
    }
  }
}
```

### Atom Fields

| Field | Type | Description |
|-------|------|-------------|
| `display-name` | string | Last component of the name |
| `kind` | string | `def`, `theorem`, `abbrev`, `class`, `structure`, `inductive`, `instance`, `axiom`, `opaque`, `quot` |
| `language` | string | Always `"lean"` |
| `dependencies` | array | Code-names this declaration depends on (union of type + term) |
| `type-dependencies` | array | Code-names referenced in the declaration's type signature |
| `term-dependencies` | array | Code-names referenced in the declaration's body/proof |
| `code-module` | string | Module name containing the declaration |
| `code-path` | string | Relative path to source file |
| `code-text` | object or null | `{ "lines-start": N, "lines-end": N }` |
| `is-hidden` | bool | From config's `is-hidden` list |
| `is-extraction-artifact` | bool | Name ends with suffix from `extraction-artifact-suffixes` |
| `is-ignored` | bool | From config's `is-ignored` list |
| `is-relevant` | bool | Rust source is from the target crate (Aeneas projects only) |
| `rust-source` | string or null | Rust source path from Aeneas docstring |
| `specs` | array or absent | Code-names of theorem atoms that spec this atom. Absent when empty. |
| `primary-spec` | string or absent | Code-name of the primary specification theorem. Set by `@[primary_spec]` attribute, or inferred when `<name>_spec` exists in `specs`. Absent when none. |
| `verification-status` | string or absent | `"verified"`, `"unverified"`, `"failed"`, or absent if skipped |

### Verification Status Mapping

| Lean status | `verification-status` | Meaning |
|-------------|----------------------|---------|
| No sorry | `"verified"` | Proof is complete |
| Has sorry | `"unverified"` | Proof deliberately incomplete |
| Build failure | `"failed"` | Compilation error |
| (skipped) | absent | Verification was skipped (`--skip-verify`) |

---

## Configuration

Atom filtering flags are populated from the project's `.verilib/probes/config.json`:

- `is-hidden`: `true` if the atom name (without `probe:` prefix) appears in `is-hidden`
- `is-extraction-artifact`: `true` if the atom name ends with any suffix in `extraction-artifact-suffixes`
- `is-ignored`: `true` if the atom name appears in `is-ignored`

The `is-relevant` field is computed from `relevant-crate` and the `rust-source` field:
- If `rust-source` exists: `true` if it contains the crate name AND doesn't start with `/` AND doesn't contain `/cargo/registry/`
- If no `rust-source`: `false`

Example config (`.verilib/probes/config.json`):

```json
{
  "relevant-crate": "my-crate-name",
  "extraction-artifact-suffixes": ["_body", "_loop", "_loop0", "_loop1"],
  "is-hidden": ["MyModule.internalHelper", "MyModule.derivedInstance"],
  "is-ignored": ["MyModule.testHelper", "MyModule.debugFunction"]
}
```

---

## Troubleshooting

### Build takes hours

You're almost certainly compiling Mathlib from source. Run `lake exe cache get` in the target project first (see [Mathlib cache](#mathlib-cache-critical-for-performance)).

### "environment already contains 'main'"

The project has multiple modules that define `main`. This typically happens with utility scripts included as `[[lean_lib]]`. Use `--library` to target only the main library, or ensure the project's `defaultTargets` excludes conflicting libraries.

### "Failed to import modules"

The `.olean` files may be stale or from a different toolchain version. Clean and rebuild:

```bash
cd <target-project>
rm -rf .lake
lake exe cache get    # if Mathlib-dependent
lake build
```

### Toolchain mismatch

If you see `.olean` version errors, check that probe-lean was installed for the right version:

```bash
cat <target-project>/lean-toolchain
# Reinstall probe-lean for that version
cd probe-lean
./tools/bash/install.sh <version>
```

### Output directory

probe-lean writes to `<target-project>/.verilib/probes/lean_<pkg>_<ver>.json` by default:

```
.verilib/
└── probes/
    └── lean_<pkg>_<ver>.json     # extract output (unified atoms)
```

Override with `-o <path>` if needed.
