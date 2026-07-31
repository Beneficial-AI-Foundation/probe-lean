# Usage Guide

## Prerequisites

- **Lean 4 toolchain** (`elan`, `lake`) -- install via [elan](https://github.com/leanprover/elan#installation)
- `~/.local/bin` in your `PATH` (for the installed binary)
- The target project must build with `lake build`

## Installation

No git clone required — the installer downloads a pre-built binary directly from GitHub releases.

**Option 1 -- auto-detect from target project (recommended):**
```bash
curl -sSfL https://raw.githubusercontent.com/Beneficial-AI-Foundation/probe-lean/main/tools/bash/install.sh \
  | bash -s -- --from-project ./my-lean-project
```

**Option 2 -- explicit version:**
```bash
curl -sSfL https://raw.githubusercontent.com/Beneficial-AI-Foundation/probe-lean/main/tools/bash/install.sh \
  | bash -s -- --lean-version v4.28.0
```

If you have the repository cloned (e.g., for development), you can run the scripts directly:
```bash
./tools/bash/install.sh --from-project ../my-lean-project
# or with Python:
uv run tools/python/install.py --from-project ../my-lean-project
```

The installer first tries to download a pre-built binary from GitHub Releases. If none is available for the requested Lean version, it falls back to building from source (auto-cloning the repo if needed).

Binaries are installed to `~/.local/bin/probe-lean-<version>` with a symlink at `~/.local/bin/probe-lean`. The required `.olean` files go to `~/.local/lib/probe-lean-<version>/`.

Verify the installation:
```bash
probe-lean --version
```

### Installer flags

| Flag | Description |
|------|-------------|
| `--from-project <path>` | Auto-detect the Lean version from the target project's `lean-toolchain`. If `<path>` has no top-level `lean-toolchain`, the installer searches recursively (excluding `.lake`) and uses the toolchain it finds — so pointing at a monorepo root works even when the Lean package is a subfolder (e.g. `cedar-spec/cedar-lean`). If multiple toolchains disagree on the version, it errors and lists them; pass `--lean-version` to disambiguate. |
| `--lean-version <ver>` | Explicit Lean version (e.g., `v4.28.0`) |
| `--force` | Reinstall even if the version is already installed |

### Toolchain version matching

probe-lean **must** be installed for the same Lean version as the target project. `.olean` files are version-specific and will not load across versions.

If your targets use different Lean versions, the installer handles this: it builds (or downloads) a versioned binary for each version. Multiple versions coexist under `~/.local/bin/probe-lean-v<version>`. The `probe-lean` symlink points to the most recently installed version.

### Pre-built binary availability

Pre-built binaries are published for `linux-x86_64` and `darwin-arm64` for every stable Lean release `≥ v4.28.0-rc1`, plus the latest release candidate of any line without a stable — restricted to versions that [`leanprover/lean4-cli`](https://github.com/leanprover/lean4-cli) has tagged (probe-lean pins `lean4-cli` to the Lean version, so a release without a matching `lean4-cli` tag, e.g. most patch releases, is skipped). A scheduled workflow builds artifacts for new Lean versions automatically (usually within a day of an upstream release), so a recent toolchain normally has a binary ready. If yours doesn't — a superseded RC, a Lean version `lean4-cli` hasn't tagged, or an unsupported version — the installer falls back to a source build. To raise the GitHub API rate limit during the lookup, set `GH_TOKEN` (or `GITHUB_TOKEN`).

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
| `--library <LIBS>` | `-l` | Comma-separated list of library names to build **and** restrict analysis to (modules are kept only if they belong to one of these library roots). When omitted, the build uses `defaultTargets` from `lakefile.toml` (falling back to all `[[lean_lib]]` entries) and **all** of the project's built modules are analyzed — auto-detected targets are not used as a module filter, since `defaultTargets` may name a `lean_exe` or a library may declare custom `roots`. |
| `--skip-verify` | | Skip the sorry detection step (graph structure only) |
| `--from-file <FILE>` | | Use existing build output for sorry detection instead of running lake |
| `--skip-enrich` | | Skip transitive verification enrichment (no `"transitively-verified"` status) |
| `--class <NAME>` | | Override the detected project class (e.g. `security-protocol`). Normally auto-detected from a VCVio dependency; this is for manual runs |

Before importing, `extract` runs a **co-importability preflight**: it reads each built module's own declarations from its `.olean` header and aborts with the list of duplicated names and their owning modules if two modules declare the same fully-qualified name (see [Troubleshooting](#co-importability-check-failed)).

For VCVio-based cryptographic projects, `extract` additionally classifies declarations into a
`scheme → construction → {correctness, security}` hierarchy and emits `source.class` plus a per-atom
`classification` object (see [SCHEMA.md](SCHEMA.md#security-protocol-classification)). Schemes not
named `*Scheme`/`*Alg` must carry `@[scheme_def]` (import `ProbeLean.Attrs`) to be detected.

`extract` also auto-flags Lean-generated code — `deriving`-generated instance clusters and
structure/class projections — as `is-hidden` + `is-lean-generated`, so `viewify` and the web UI
omit it. These atoms stay in the dependency graph, so transitive-verification remains sound.
After transitive enrichment, `is-hidden` is cleared on lean-generated atoms that are not
`transitively-verified`, so contaminated instances remain visible for tracing.

### `check-axioms`

Audit a Lean 4 project: report every declaration (of those `extract` would emit as an atom) whose
*complete* transitive closure reaches the `sorryAx` axiom.

```
probe-lean check-axioms <PROJECT_PATH> [OPTIONS]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--module <PREFIX>` | `-m` | Filter to specific module prefix |
| `--library <LIBS>` | `-l` | Comma-separated library names to build **and** restrict analysis to |

This is the kernel ground truth for "rests on a `sorry`", walked via `Lean`'s constant closure
(generated code included) and therefore independent of probe-lean's own dependency graph. Use it to
cross-check `extract`: no atom marked `"transitively-verified"` should appear in this list. The audit
walks each declaration's closure (`O(declarations × closure size)`), so on Mathlib-scale projects use
`-m`/`-l` to narrow scope.

---

## Walkthrough: Analyzing Real Projects

### Mathlib cache (auto-downloaded)

Most Lean verification projects depend on [Mathlib](https://github.com/leanprover-community/mathlib4). Compiling Mathlib from source is extremely slow and saturates all CPU cores. The Mathlib project publishes pre-built `.olean` caches that download in minutes.

**probe-lean automatically downloads the Mathlib cache** when it detects a Mathlib dependency without pre-built `.olean` files. You will see:

```
Mathlib dependency detected but no pre-built cache found.
Running `lake exe cache get` to download pre-built .olean files...

  ✓ Mathlib cache downloaded
```

If the automatic download fails (e.g. network issues), probe-lean prints a warning and continues (which will trigger a slow Mathlib compilation). In that case, run the cache download manually:

```bash
cd <target-project>
lake exe cache get
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
# 1. Install probe-lean (auto-detects v4.28.0-rc1 from lean-toolchain)
curl -sSfL https://raw.githubusercontent.com/Beneficial-AI-Foundation/probe-lean/main/tools/bash/install.sh \
  | bash -s -- --from-project ./curve25519-dalek-lean-verify

# 2. Run extract (Mathlib cache is auto-downloaded on first run)
cd curve25519-dalek-lean-verify
probe-lean extract .
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
# 1. Install probe-lean (auto-detects v4.28.0)
curl -sSfL https://raw.githubusercontent.com/Beneficial-AI-Foundation/probe-lean/main/tools/bash/install.sh \
  | bash -s -- --from-project ./VCV-io

# 2. Run extract (Mathlib cache is auto-downloaded on first run)
cd VCV-io
probe-lean extract .
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
# 1. Install probe-lean (skip if already done for VCV-io — same Lean version)
curl -sSfL https://raw.githubusercontent.com/Beneficial-AI-Foundation/probe-lean/main/tools/bash/install.sh \
  | bash -s -- --from-project ./ArkLib

# 2. Run extract (Mathlib cache is auto-downloaded on first run)
cd ArkLib
probe-lean extract .
```

If you've already built the project, probe-lean will detect that the build cache is up-to-date and skip the `lake build` step automatically (sorry detection still works using the cached build output).

### Example 4: [signal-shot-PQXDH](https://github.com/Beneficial-AI-Foundation/signal-shot-PQXDH)

Lean 4 formalization of the Signal PQXDH key agreement protocol. Depends on Mathlib and subverso.

| Property | Value |
|----------|-------|
| Toolchain | `v4.29.0-rc3` |
| Depends on Mathlib | Yes |
| Libraries | `PQXDHLean` |
| `defaultTargets` | `["PQXDHLean"]` |

```bash
# 1. Install probe-lean (auto-detects v4.29.0-rc3 — different from Examples 1–3)
curl -sSfL https://raw.githubusercontent.com/Beneficial-AI-Foundation/probe-lean/main/tools/bash/install.sh \
  | bash -s -- --from-project ./signal-shot-PQXDH

# 2. Run extract (Mathlib cache is auto-downloaded on first run)
cd signal-shot-PQXDH
probe-lean extract .
```

### Example 5: From-scratch setup on a fresh machine

Starting from nothing on Ubuntu/Debian:

```bash
# Install elan (Lean version manager)
curl https://elan-init.trycloudflare.com/elan-init.sh -sSf | sh
source ~/.profile

# Install probe-lean (auto-detects Lean version from target project, no clone needed)
curl -sSfL https://raw.githubusercontent.com/Beneficial-AI-Foundation/probe-lean/main/tools/bash/install.sh \
  | bash -s -- --from-project ./my-lean-project

# Ensure ~/.local/bin is in PATH
export PATH="$PATH:$HOME/.local/bin"

# Verify installation
probe-lean --version

# Prepare the target project
cd my-lean-project
# Run extraction (Mathlib cache auto-downloaded if needed)
probe-lean extract .
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

The `extract` command produces a JSON file wrapped in a Schema 4.0 metadata envelope:

```json
{
  "schema": "probe-lean/extract",
  "schema-version": "4.0",
  "tool": { "name": "probe-lean", "version": "0.8.0", "command": "extract" },
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
      "is-lean-generated": false,
      "is-aeneas-generated": false,
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

For the full atom field reference and verification-status mapping, see [SCHEMA.md](SCHEMA.md).

---

## Configuration

Atom filtering flags are populated from the project's `.verilib/probes/config.json`:

- `is-hidden`: `true` if the atom name (without `probe:` prefix) appears in `is-hidden`
- `is-aeneas-generated`: `true` if the atom name ends with any suffix in `extraction-artifact-suffixes`
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

You're almost certainly compiling Mathlib from source. probe-lean auto-downloads the cache on first run (see [Mathlib cache](#mathlib-cache-auto-downloaded)), but if that failed, run `lake exe cache get` in the target project manually.

### "Co-importability check failed"

Projects with modules that declare the same fully-qualified name build because Lake compiles each module independently, but `probe-lean` must import **all** built modules into a single Lean environment, and Lean forbids duplicate declarations in one environment (see the co-importability requirement under [Supported Projects](../README.md#supported-projects) in the README).

probe-lean detects this *before* importing and lists the duplicated names with their owning modules. Note that lakefile-level grouping does **not** avoid it: `defaultTargets` and `[[lean_lib]]` splits only affect what is *built* — probe-lean analyzes every built `.olean` on disk.

Fixes, in order of preference:

1. **Restructure the project** (the only fix that works for automated consumers like verilib, which cannot pass per-project flags): give each variant family its own namespace, or have the dependent module `import` the shared module instead of restating its definitions.
2. **Manual runs only**: extract a non-conflicting subset with `--module`, e.g. `probe-lean extract . --module H1.solution`. Note `--module` selects the named module *plus its submodules*, so for a root/submodule clash name the deepest module. (`--library` matches module-name roots, not lakefile library names, so it usually cannot select across this kind of split.)

### "environment already contains '...'" after renaming or deleting a file

A stale *orphan* `.olean` from the old module is still on disk (Lake never removes oleans for deleted/renamed sources) and re-declares a name now owned by another module. probe-lean drops orphan oleans automatically by checking each module against its backing `.lean` source — but it only knows `srcDir`s declared in `lakefile.toml`. If your project uses a Lean-DSL `lakefile.lean` with a custom `srcDir`, the orphan may slip through the source check *and* the co-importability preflight; the error message covers this case with a `lake clean` hint. Run `lake clean && lake build` in the target project, then re-run extract.

### "Failed to import modules"

The `.olean` files may be stale or from a different toolchain version. Clean and rebuild:

```bash
cd <target-project>
rm -rf .lake
lake exe cache get    # if Mathlib-dependent
lake build
```

### Toolchain mismatch

If you see `.olean` version errors, reinstall probe-lean for the target project:

```bash
curl -sSfL https://raw.githubusercontent.com/Beneficial-AI-Foundation/probe-lean/main/tools/bash/install.sh \
  | bash -s -- --force --from-project <target-project>
```

### Output directory

probe-lean writes to `<target-project>/.verilib/probes/lean_<pkg>_<ver>.json` by default:

```
.verilib/
└── probes/
    └── lean_<pkg>_<ver>.json     # extract output (unified atoms)
```

Override with `-o <path>` if needed.
