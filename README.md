# probe-lean

Analyze Lean 4 projects: extract dependency graphs with verification status and spec relationships.

`probe-lean` walks the Lean environment of a built project and produces structured JSON describing every declaration, its dependencies (type and term), source locations, sorry-based verification status, and spec relationships. Output follows the Schema 2.0 envelope format; see [docs/SCHEMA.md](docs/SCHEMA.md) for the full specification.

## Prerequisites

- **Lean 4 toolchain** (`elan`, `lake`) -- install via [elan](https://github.com/leanprover/elan#installation)
- The target project must build with `lake build`
- **Toolchain match**: probe-lean must be installed for the same Lean version as the target project (`.olean` files are version-specific). Check with `cat <target-project>/lean-toolchain`.
- For large projects using Mathlib, run `lake exe cache get` in the target project first to download pre-built `.olean` files

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

Install for a specific Lean version to match the target project:
```bash
# Check target project's Lean version
cat ../my-lean-project/lean-toolchain
# Install probe-lean for that version
./tools/bash/install.sh v4.28.0-rc1
```

If no version is specified, the script shows a menu of available versions from GitHub.

Ensure `~/.local/bin` is in your `PATH`:
```bash
export PATH="$PATH:$HOME/.local/bin"
```

## Quick Start

```bash
# Analyze a Lean project (builds with lake, extracts atoms, detects sorries)
probe-lean extract ./my-lean-project

# Skip sorry detection (faster, graph structure only)
probe-lean extract ./my-lean-project --skip-verify

# With pre-built .olean files
probe-lean extract ./my-lean-project --skip-build
```

Output lands in `<target-project>/.verilib/probes/lean_<pkg>_<ver>.json` by default.

### Analyzing a project with Mathlib dependencies

For large projects (e.g., those depending on Mathlib), download pre-built `.olean` caches first to avoid hours of compilation:

```bash
cd ../my-lean-project
lake exe cache get   # download pre-built Mathlib .olean files
lake build           # build the project itself
cd ../probe-lean
probe-lean extract ../my-lean-project --skip-build --skip-verify
```

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
| `--skip-verify` | Skip sorry detection (graph structure only) |
| `--skip-build` | Skip `lake build` (assumes `.olean` files exist) |
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

1. **Build** -- runs `lake build` to produce `.olean` files (skippable via `--skip-build`)
2. **Atomize** -- walks the Lean environment, extracts declarations with type and term dependencies
3. **Filter** -- applies config-based flags (`is-hidden`, `is-extraction-artifact`, `is-ignored`, `is-relevant`)
4. **Verify** -- parses sorry warnings from build output to determine verification status (skippable via `--skip-verify`)
5. **Specs** -- computes reverse theorem edges (`specs`, `primary-spec`) for each atom
6. **Schema 2.0 output** -- wraps atoms in a metadata envelope with git commit, package info, and timestamps

## Testing

```bash
lake build tests
.lake/build/bin/tests
```

## License

Apache-2.0
