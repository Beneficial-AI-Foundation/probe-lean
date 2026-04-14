# probe-lean

Analyze Lean 4 projects: extract dependency graphs with verification status and spec relationships.

`probe-lean` walks the Lean environment of a built project and produces structured JSON describing every declaration, its dependencies (type and term), source locations, sorry-based verification status, and spec relationships. Output follows the Schema 2.0 envelope format; see [docs/SCHEMA.md](docs/SCHEMA.md) for the full specification.

## Prerequisites

- **Lean 4 toolchain** (`elan`, `lake`) -- install via [elan](https://github.com/leanprover/elan#installation)
- The target project must build with `lake build`
- **Toolchain match**: probe-lean must be installed for the same Lean version as the target project (`.olean` files are version-specific). Check with `cat <target-project>/lean-toolchain`.
- For large projects using Mathlib, run `lake exe cache get` in the target project first to download pre-built `.olean` files

## Installation

No git clone required — the installer downloads a pre-built binary directly from GitHub releases.

### Quick install (recommended)

Auto-detect the Lean version from a target project:

```bash
curl -sSfL https://raw.githubusercontent.com/Beneficial-AI-Foundation/probe-lean/main/tools/bash/install.sh \
  | bash -s -- --from-project ./my-lean-project
```

Or specify a Lean version explicitly:

```bash
curl -sSfL https://raw.githubusercontent.com/Beneficial-AI-Foundation/probe-lean/main/tools/bash/install.sh \
  | bash -s -- --lean-version v4.28.0-rc1
```

Ensure `~/.local/bin` is in your `PATH`:
```bash
export PATH="$PATH:$HOME/.local/bin"
```

### How it works

The installer:
1. Detects the required Lean version (from `--from-project`, `--lean-version`, or interactive menu)
2. Checks if `probe-lean-<version>` is already installed (skips if so, unless `--force`)
3. Downloads a pre-built binary from GitHub releases
4. Falls back to building from source if no pre-built binary is available

The binary is installed to `~/.local/bin/probe-lean-<version>` with a symlink at `~/.local/bin/probe-lean`. Interpreter `.olean` files are installed to `~/.local/lib/probe-lean-<version>/` (per-version, so multiple versions can coexist).

### Installer options

| Option | Description |
|--------|-------------|
| `--from-project <path>` | Auto-detect Lean version from target project's `lean-toolchain` |
| `--lean-version <ver>` | Explicit Lean version (e.g., `v4.28.0-rc1`) |
| `--force` | Rebuild/reinstall even if already installed |
| `[VERSION]` | Positional version argument (same as `--lean-version`) |

### From a cloned repo

If you have the repository cloned (e.g., for development), you can run the scripts directly:

```bash
git clone https://github.com/Beneficial-AI-Foundation/probe-lean
cd probe-lean
./tools/bash/install.sh --from-project ../my-lean-project
# or with Python:
uv run tools/python/install.py --from-project ../my-lean-project
```

### Docker

```bash
docker build --build-arg LEAN_VERSION=v4.28.0-rc1 -t probe-lean .
docker run --rm -v /path/to/project:/project probe-lean extract /project
```

The Docker image downloads the pre-built binary during build — no repository clone needed.

### GitHub Actions

For CI integration in downstream repos:

```yaml
- uses: Beneficial-AI-Foundation/probe-lean/action@main
  with:
    project-path: .
```

The action auto-detects the Lean version, builds probe-lean, and runs extraction. See [action/action.yml](action/action.yml) for all options.

## Quick Start

```bash
# Analyze a Lean project (builds with lake, extracts atoms, detects sorries)
probe-lean extract ./my-lean-project

# Skip sorry detection (faster, graph structure only)
probe-lean extract ./my-lean-project --skip-verify

# Multi-library project: build only specific libraries
probe-lean extract ./my-lean-project --library "Extraction,Spqr"
```

Output lands in `<target-project>/.verilib/probes/lean_<pkg>_<ver>.json` by default.

### Analyzing a project with Mathlib dependencies

Most Lean verification projects depend on Mathlib. To check whether a target project uses Mathlib, look in its lakefile:

- **`lakefile.toml`**: a `[[require]]` block with `name = "mathlib"`
- **`lakefile.lean`**: a line like `require mathlib from git ...`

You can also check `lake-manifest.json` for a `"mathlib"` entry (this file is generated and lists all resolved dependencies).

If Mathlib is present, **always download the pre-built cache first** -- compiling Mathlib from source is extremely slow:

```bash
cd ../my-lean-project
lake exe cache get   # download pre-built Mathlib .olean files (~5 min)
cd ../probe-lean
probe-lean extract ../my-lean-project
```

probe-lean will warn you if it detects a missing Mathlib cache.

For detailed walkthroughs with real projects (curve25519-dalek-lean-verify, ArkLib, VCV-io), see **[docs/USAGE.md](docs/USAGE.md)**.

### Projects with FFI / system dependencies (Nix support)

Some Lean projects depend on C libraries via FFI (e.g., zlib, OpenSSL). These system dependencies are not managed by Lake and must be installed separately. If the target project ships a `shell.nix` or `flake.nix`, probe-lean **automatically detects** it and wraps all `lake` invocations inside the Nix environment, so system deps are available without manual installation.

**How it works:**

- probe-lean checks for `flake.nix` (preferred) or `shell.nix` in the project root
- If found and `nix` / `nix-shell` is installed, all `lake` commands run inside the Nix environment
- If the Nix file exists but `nix` is not installed, a warning is printed and `lake` runs directly (system deps must be installed manually)
- Projects without Nix files are unaffected

**Docker guidance:** The default probe-lean Docker image does not include Nix. If your target project requires Nix for system deps, you have two options:

1. **Install Nix in your Docker image** -- base on `nixos/nix` or add Nix to your image. probe-lean will then auto-detect and use the project's Nix environment.
2. **Install system deps directly** -- add `apt-get install` commands to your Dockerfile for the required libraries (check the project's `shell.nix` or README for the package list).

**CI guidance:** Use [`cachix/install-nix-action`](https://github.com/cachix/install-nix-action) in your GitHub Actions workflow to make Nix available. probe-lean will then wrap `lake` commands automatically.

## Commands

| Command | Description |
|---------|-------------|
| `extract` | Analyze a Lean 4 project: extract atoms, detect sorries, compute specs |

### `extract`

```bash
probe-lean extract <PROJECT_PATH> [OPTIONS]
```

| Option | Description |
|--------|-------------|
| `-o, --output <PATH>` | Output file path (default: `.verilib/probes/lean_<pkg>_<ver>.json`) |
| `-m, --module <PREFIX>` | Filter to specific module prefix |
| `-l, --library <LIBS>` | Comma-separated list of library names to build (default: `defaultTargets` from `lakefile.toml`, falling back to all `[[lean_lib]]` entries) |
| `--skip-verify` | Skip sorry detection (graph structure only) |
| `--from-file <FILE>` | Use existing build output for sorry detection |

For the full command reference with examples, see **[docs/USAGE.md](docs/USAGE.md)**. For the complete JSON schema specification, see **[docs/SCHEMA.md](docs/SCHEMA.md)**.

## Example Output

Running `probe-lean extract` produces a JSON envelope. Each entry in `data` describes a declaration and its dependencies:

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

## How It Works

1. **Build** -- reads `defaultTargets` from `lakefile.toml` (falling back to all `[[lean_lib]]` entries) and runs `lake build <lib1> ...` to produce `.olean` files (automatically skipped when build cache is up-to-date; overridable via `--library`)
2. **Atomize** -- walks the Lean environment, extracts declarations with type and term dependencies
3. **Filter** -- applies config-based flags (`is-hidden`, `is-extraction-artifact`, `is-ignored`, `is-relevant`)
4. **Verify** -- parses sorry warnings from build output to determine verification status; axioms and `*External.lean` declarations are marked `"trusted"` with a `trusted-reason` (`"axiom"` or `"external"`) for trust-base classification; declarations without source location (kernel-synthesized) are filtered from output (skippable via `--skip-verify`)
5. **Specs** -- computes reverse theorem edges (`specs`, `primary-spec`) for each atom. 
    - To identify the primary specification for a definition, tag the theorem with `@[primary_spec]` (requires `import ProbeLean.Attrs` in the target project). 
    - If no `@[primary_spec]` attribute is found, probe-lean falls back to a naming heuristic: a theorem named `<def>_spec` is automatically assigned as the primary spec.
    - Only one primary spec per definition. If multiple `@[primary_spec]` theorems reference the same definition, the last one encountered is used.
6. **Schema 2.0 output** -- wraps atoms in a metadata envelope with git commit, package info, and timestamps

## Testing

```bash
lake build tests
.lake/build/bin/tests
```

## Versioning

The version is defined once in `lakefile.toml` and propagated everywhere via `ProbeLean/Version.lean`:

```
lakefile.toml  →  tools/gen-version.sh  →  ProbeLean/Version.lean
                                              ↓
                                         Constants.toolVersion  (JSON output)
                                         CLI --version          (Main.lean)
```

After bumping the version in `lakefile.toml`, run:

```bash
./tools/gen-version.sh
```

CI verifies the generated file stays in sync.

## License

Apache-2.0
