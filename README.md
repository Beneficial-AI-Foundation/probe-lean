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
  "atoms": [
    {
      "name": "MyModule.myFunction",
      "display-name": "myFunction",
      "kind": "def",
      "dependencies": ["MyModule.helper"],
      "code-module": "MyModule",
      "code-path": "/path/to/MyModule.lean",
      "code-text": { "lines-start": 10, "lines-end": 15 }
    }
  ]
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
  "MyModule.myTheorem": {
    "specified": true,
    "code-path": "/path/to/MyModule.lean",
    "spec-text": { "lines-start": 10, "lines-end": 12 }
  }
}
```

## Output Fields

### atoms.json

| Field | Description |
|-------|-------------|
| `name` | Full qualified name |
| `display-name` | Last component of the name |
| `kind` | Declaration type: `def`, `theorem`, `abbrev`, `class`, `structure`, `inductive`, `instance`, `axiom`, `opaque` |
| `dependencies` | Array of qualified names this declaration depends on |
| `code-module` | Module name containing the declaration |
| `code-path` | Absolute path to source file |
| `code-text` | Source location with line numbers (null if unavailable) |

### specs.json

| Field | Description |
|-------|-------------|
| `specified` | Whether the declaration has a complete specification |
| `code-path` | Absolute path to source file |
| `spec-text` | Source location with line numbers (null if unavailable) |

## Testing

```bash
lake build tests
.lake/build/bin/tests
```

## Requirements

- Lean 4.15.0 or compatible version
- Lake build system
