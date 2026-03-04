# probe-lean

A tool for analyzing Lean 4 projects and extracting dependency graphs.

## Installation

```bash
git clone <repo-url>
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

Both scripts build the project and install to `~/.local/bin/probe-lean-<version>` with a symlink at `~/.local/bin/probe-lean`.

To install for a specific Lean version (e.g., to match a project you want to analyze):
```bash
./tools/bash/install.sh v4.28.0-rc1
```

If no version is specified, the script shows a menu of available versions from GitHub.

## Commands

### atomize

Analyze a Lean 4 project and output a dependency graph.

```bash
probe-lean atomize <PROJECT_PATH> [-o OUTPUT] [-m MODULE]
```

**Options:**
- `-o, --output` - Output file path (default: `PROJECT_PATH/.verilib/atoms.json`)
- `-m, --module` - Filter to specific module prefix

**Example:**
```bash
probe-lean atomize ./my-lean-project
```

**Output format (atoms.json):**
```json
{
  "probe:MyModule.myFunction": {
    "display-name": "myFunction",
    "kind": "def",
    "dependencies": ["probe:MyModule.helper"],
    "code-module": "MyModule",
    "code-path": "MyModule.lean",
    "code-text": { "lines-start": 10, "lines-end": 15 }
  }
}
```

### specify

Extract specification status from atoms.json.

```bash
probe-lean specify <PROJECT_PATH> [-a ATOMS] [-o OUTPUT]
```

**Options:**
- `-a, --with-atoms` - Path to atoms.json (default: `PROJECT_PATH/.verilib/atoms.json`)
- `-o, --output` - Output file path (default: `PROJECT_PATH/.verilib/specs.json`)

**Example:**
```bash
probe-lean atomize ./my-lean-project
probe-lean specify ./my-lean-project
```

**Output format (specs.json):**
```json
{
  "probe:MyModule.myTheorem": {
    "specified": true,
    "code-path": "MyModule.lean",
    "spec-text": { "lines-start": 10, "lines-end": 12 }
  }
}
```

### verify

Check proof completeness by detecting `sorry` in Lean compiler output.

```bash
probe-lean verify <PROJECT_PATH> [-a ATOMS] [-o OUTPUT] [--no-cache] [--from-file FILE]
```

**Options:**
- `-a, --with-atoms` - Path to atoms.json (default: `PROJECT_PATH/.verilib/atoms.json`)
- `-o, --output` - Output file path (default: `PROJECT_PATH/.verilib/proofs.json`)
- `--no-cache` - Don't cache verification output
- `--from-file` - Analyze existing build output instead of running lake

**Example:**
```bash
probe-lean atomize ./my-lean-project
probe-lean verify ./my-lean-project
```

**Output format (proofs.json):**
```json
{
  "probe:MyModule.myTheorem": {
    "verified": true,
    "status": "success",
    "code-path": "MyModule.lean",
    "code-line": 42
  },
  "probe:MyModule.incompleteProof": {
    "verified": false,
    "status": "sorries",
    "code-path": "MyModule.lean",
    "code-line": 100,
    "sorries": [{ "line": 105, "message": "declaration uses 'sorry'" }]
  }
}
```

### stubify

Generate `stubs.json` from `functions.json`. This creates a mapping of Lean functions to their Rust counterparts.

```bash
probe-lean stubify <PROJECT_PATH> [-f FUNCTIONS] [-o OUTPUT]
```

**Options:**
- `-f, --functions` - Path to functions.json (default: `PROJECT_PATH/functions.json`)
- `-o, --output` - Output file path (default: `PROJECT_PATH/.verilib/stubs.json`)

**Example:**
```bash
probe-lean stubify ./my-lean-project
```

**Input format (functions.json):**
```json
{
  "functions": [
    {
      "lean_name": "MyModule.SubModule.myFunction",
      "source": "src/crypto/field.rs",
      "lines": "42-58",
      "rust_name": "my_function",
      "spec_file": "specs/field_spec.lean",
      "is_relevant": true
    }
  ]
}
```

Only entries where `is_relevant` is `true` (or missing) are included.

**Output format (stubs.json):**

Keys use `<source>/<lean_name_1>` format where `<lean_name_1>` is the last dot-separated part of the Lean name. If there's a clash, keys become `<source>/<lean_name_1>#<lean_name_2>` where `<lean_name_2>` is the second-last part.

```json
{
  "src/crypto/field.rs/myFunction": {
    "lean-path": null,
    "lean-lines": null,
    "lean-name": "probe:MyModule.SubModule.myFunction",
    "rust-path": "src/crypto/field.rs",
    "rust-lines": { "lines-start": 42, "lines-end": 58 },
    "rust-name": "my_function",
    "code-path": "specs/field_spec.lean",
    "code-lines": null,
    "code-name": "probe:MyModule.SubModule.myFunction_spec"
  }
}
```

## Output Fields

All output files use `probe:` prefixed names as keys (e.g., `probe:MyModule.myFunction`).

### atoms.json

| Field | Description |
|-------|-------------|
| `display-name` | Last component of the name |
| `kind` | Declaration type: `def`, `theorem`, `abbrev`, `class`, `structure`, `inductive`, `instance`, `axiom`, `opaque` |
| `dependencies` | Array of `probe:`-prefixed names this declaration depends on |
| `code-module` | Module name containing the declaration |
| `code-path` | Relative path to source file from project root |
| `code-text` | Source location with line numbers (null if unavailable) |

### specs.json

| Field | Description |
|-------|-------------|
| `specified` | Whether the declaration has a complete specification |
| `code-path` | Relative path to source file from project root |
| `spec-text` | Source location with line numbers (null if unavailable) |

### proofs.json

| Field | Description |
|-------|-------------|
| `verified` | Whether the proof is complete (no sorry) |
| `status` | `success`, `sorries`, or `failure` |
| `code-path` | Relative path to source file from project root |
| `code-line` | Line number of declaration |
| `sorries` | Array of sorry locations (only if status is `sorries`) |

### stubs.json

| Field | Description |
|-------|-------------|
| `lean-path` | Always `null` (placeholder) |
| `lean-lines` | Always `null` (placeholder) |
| `lean-name` | `probe:<lean_name>` from functions.json |
| `rust-path` | `<source>` from functions.json |
| `rust-lines` | Line range as `{"lines-start": N, "lines-end": M}` |
| `rust-name` | `<rust_name>` from functions.json |
| `code-path` | `<spec_file>` if it exists, otherwise `null` |
| `code-lines` | Always `null` (placeholder) |
| `code-name` | `probe:<lean_name>_spec` if spec_file exists, otherwise `null` |

## Testing

```bash
lake build tests
.lake/build/bin/tests
```

## Requirements

- Lean 4.25.2 or compatible version
- Lake build system
