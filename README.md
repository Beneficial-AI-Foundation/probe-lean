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

## Usage

```bash
probe-lean atomize <PROJECT_PATH> [-o OUTPUT] [-m MODULE]
```

### Options

- `-o, --output` - Output file path (default: `PROJECT_PATH/atoms.json`)
- `-m, --module` - Filter to specific module prefix

### Examples

```bash
# Analyze a project, output to atoms.json in the project directory
probe-lean atomize ./my-lean-project

# Custom output path
probe-lean atomize ./my-lean-project -o ./output/atoms.json

# Filter to specific module
probe-lean atomize ./my-lean-project -m MyModule
```

## Output Format

The tool outputs a JSON file with the following structure:

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
      "code-text": {
        "lines-start": 10,
        "lines-end": 15
      }
    }
  ]
}
```

### Fields

| Field | Description |
|-------|-------------|
| `name` | Full qualified name |
| `display-name` | Last component of the name |
| `kind` | Declaration type: `def`, `theorem`, `abbrev`, `class`, `structure`, `inductive`, `instance`, `axiom`, `opaque` |
| `dependencies` | Array of qualified names this declaration depends on |
| `code-module` | Module name containing the declaration |
| `code-path` | Absolute path to source file |
| `code-text` | Source location with line numbers (null if unavailable) |

## Testing

```bash
lake build tests
.lake/build/bin/tests
```

## Requirements

- Lean 4.15.0 or compatible version
- Lake build system
