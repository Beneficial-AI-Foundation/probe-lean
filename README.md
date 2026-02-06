# probe-lean

A tool for analyzing Lean 4 projects and extracting dependency graphs.

## Installation

```bash
# Clone and build
git clone <repo-url>
cd probe-lean
lake build

# Install to ~/.local/bin
mkdir -p ~/.local/bin
ln -sf "$(pwd)/.lake/build/bin/probe-lean" ~/.local/bin/probe-lean
```

Make sure `~/.local/bin` is in your PATH:
```bash
echo 'export PATH="$PATH:$HOME/.local/bin"' >> ~/.bashrc
source ~/.bashrc
```

## Commands

### atomize

Analyze a Lean 4 project and output a dependency graph.

```bash
probe-lean atomize <PROJECT_PATH> [-o OUTPUT] [-m MODULE]
```

**Options:**
- `-o, --output` - Output file path (default: `PROJECT_PATH/atoms.json`)
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
- `-a, --with-atoms` - Path to atoms.json (default: `PROJECT_PATH/atoms.json`)
- `-o, --output` - Output file path (default: `PROJECT_PATH/specs.json`)

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
- `-a, --with-atoms` - Path to atoms.json (default: `PROJECT_PATH/atoms.json`)
- `-o, --output` - Output file path (default: `PROJECT_PATH/proofs.json`)
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

Filter atoms based on `functions.json` to produce `stubs.json`. This creates a curated subset of the dependency graph containing only the relevant functions.

```bash
probe-lean stubify <PROJECT_PATH> [-f FUNCTIONS] [-a ATOMS] [-o OUTPUT]
```

**Options:**
- `-f, --functions` - Path to functions.json (default: `PROJECT_PATH/functions.json`)
- `-a, --with-atoms` - Path to atoms.json (default: `PROJECT_PATH/atoms.json`)
- `-o, --output` - Output file path (default: `PROJECT_PATH/stubs.json`)

**Example:**
```bash
probe-lean atomize ./my-lean-project
probe-lean stubify ./my-lean-project
```

**Input format (functions.json):**
```json
{
  "functions": [
    {
      "lean_name": "MyModule.myFunction",
      "is_relevant": true
    }
  ]
}
```

Only entries where `is_relevant` is `true` (or missing) are included.

**Output format (stubs.json):**
Same format as `atoms.json` - filtered to only include atoms matching functions in `functions.json`.

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

## Testing

```bash
lake build tests
.lake/build/bin/tests
```

## Requirements

- Lean 4.25.2 or compatible version
- Lake build system
