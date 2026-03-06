# probe-lean

A tool for analyzing Lean 4 projects and extracting dependency graphs.

## Schema 2.0 Envelope

All output files are wrapped in a Schema 2.0 metadata envelope:

```json
{
  "schema": "probe-lean/atoms",
  "schema-version": "2.0",
  "tool": {
    "name": "probe-lean",
    "version": "0.1.0",
    "command": "atomize"
  },
  "source": {
    "repo": "https://github.com/org/project",
    "commit": "abc123def456...",
    "language": "lean",
    "package": "MyProject",
    "package-version": "0.1.0"
  },
  "timestamp": "2026-03-05T14:30:00Z",
  "data": { ... }
}
```

| Envelope field | Description |
|---|---|
| `schema` | Identifies tool and data type (`probe-lean/atoms`, `probe-lean/specs`, `probe-lean/proofs`, `probe-lean/enriched-atoms`, `probe-lean/stubs`) |
| `schema-version` | Always `"2.0"` |
| `tool.name` | `"probe-lean"` |
| `tool.version` | Tool version string |
| `tool.command` | The command that produced this output (`atomize`, `specify`, `verify`, `pipeline`, `stubify`) |
| `source.repo` | Git remote URL of the analyzed project |
| `source.commit` | Full Git commit hash |
| `source.language` | `"lean"` |
| `source.package` | Package name from `lakefile.toml` |
| `source.package-version` | Version from `lakefile.toml`, or 7-char Git commit hash if not available |
| `timestamp` | ISO 8601 UTC creation time |
| `data` | The actual payload (see per-command formats below) |

When loading previously generated files, probe-lean auto-detects both bare (Schema 1.x) and enveloped (Schema 2.0) formats.

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
- `-o, --output` - Output file path (default: `PROJECT_PATH/.verilib/probes/lean_<pkg>_<ver>.json`)
- `-m, --module` - Filter to specific module prefix

**Example:**
```bash
probe-lean atomize ./my-lean-project
```

**Output format (atoms.json `data` payload):**
```json
{
  "probe:MyModule.myFunction": {
    "display-name": "myFunction",
    "kind": "def",
    "language": "lean",
    "dependencies": ["probe:MyModule.helper"],
    "code-module": "MyModule",
    "code-path": "MyModule.lean",
    "code-text": { "lines-start": 10, "lines-end": 15 },
    "is-hidden": false,
    "is-extraction-artifact": false,
    "is-ignored": false,
    "is-relevant": true,
    "rust-source": "my-crate/src/module.rs"
  }
}
```

The `is-hidden`, `is-extraction-artifact`, and `is-ignored` fields are populated from the project's `.verilib/config.json`:

- `is-hidden`: `true` if the atom name (without `probe:` prefix) appears in `user.is-hidden`
- `is-extraction-artifact`: `true` if the atom name (without `probe:` prefix) ends with any suffix in `user.extraction-artifact-suffixes`
- `is-ignored`: `true` if the atom name (without `probe:` prefix) appears in `user.is-ignored`

The `is-relevant` field is computed by checking if `user.relevant-crate` appears in the `rust-source` field:

- If `rust-source` exists: `true` if it contains the crate name AND doesn't start with `/` AND doesn't contain `/cargo/registry/`
- If no `rust-source`: `false`

Example config:

```json
{
  "user": {
    "is-hidden": ["MyModule.internalHelper", "MyModule.derivedInstance"],
    "extraction-artifact-suffixes": ["_body", "_loop", "_loop0", "_loop1"],
    "is-ignored": ["MyModule.testHelper", "MyModule.debugFunction"],
    "relevant-crate": "my-crate-name"
  }
}
```

### specify

Extract specification status from atoms.json.

```bash
probe-lean specify <PROJECT_PATH> [-a ATOMS] [-o OUTPUT]
```

**Options:**
- `-a, --with-atoms` - Path to atoms.json (default: `PROJECT_PATH/.verilib/probes/lean_<pkg>_<ver>.json`)
- `-o, --output` - Output file path (default: `PROJECT_PATH/.verilib/probes/lean_<pkg>_<ver>_specs.json`)

**Example:**
```bash
probe-lean atomize ./my-lean-project
probe-lean specify ./my-lean-project
```

**Output format (specs.json `data` payload):**
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
- `-a, --with-atoms` - Path to atoms.json (default: `PROJECT_PATH/.verilib/probes/lean_<pkg>_<ver>.json`)
- `-o, --output` - Output file path (default: `PROJECT_PATH/.verilib/probes/lean_<pkg>_<ver>_proofs.json`)
- `--no-cache` - Don't cache verification output
- `--from-file` - Analyze existing build output instead of running lake

**Example:**
```bash
probe-lean atomize ./my-lean-project
probe-lean verify ./my-lean-project
```

**Output format (proofs.json `data` payload):**
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

### pipeline

Run atomize, specify, and verify in a single pass and produce an enriched atom dict with verification status. This is the recommended command for generating call graph data for the [web viewer](https://github.com/Beneficial-AI-Foundation/scip-callgraph).

```bash
probe-lean pipeline <PROJECT_PATH> [-o OUTPUT] [-m MODULE] [--skip-verify] [--from-file FILE]
```

**Options:**
- `-o, --output` - Output file path (default: `PROJECT_PATH/.verilib/probes/lean_<pkg>_<ver>_graph.json`)
- `-m, --module` - Filter to specific module prefix
- `--skip-verify` - Skip the verification step (only graph structure, no sorry detection)
- `--from-file` - Use existing build output for verification instead of running lake

**Example:**
```bash
probe-lean pipeline ./my-lean-project
probe-lean pipeline ./my-lean-project --skip-verify
probe-lean pipeline ./my-lean-project -o graph.json
```

**Output format (graph.json `data` payload):**

Each atom includes all fields from `atoms.json` plus `verification-status` and `specified`:

```json
{
  "probe:MyModule.myTheorem": {
    "display-name": "myTheorem",
    "kind": "theorem",
    "language": "lean",
    "dependencies": ["probe:MyModule.helper"],
    "code-module": "MyModule",
    "code-path": "MyModule.lean",
    "code-text": { "lines-start": 10, "lines-end": 15 },
    "verification-status": "verified",
    "specified": true
  }
}
```

The `verification-status` field maps sorry detection results to the web viewer's status model:

| Lean status | `verification-status` | Meaning |
|-------------|----------------------|---------|
| No sorry | `"verified"` | Proof is complete |
| Has sorry | `"unverified"` | Proof deliberately incomplete |
| Build failure | `"failed"` | Compilation error |
| (skipped) | absent | Verification was skipped |

### stubify

Generate `stubs.json` from `atoms.json`, filtering to only include atoms where:
- `is-hidden` is `false`
- `is-extraction-artifact` is `false`
- `is-relevant` is `true`
- `code-path` ends with `Funs.lean`

```bash
probe-lean stubify <PROJECT_PATH> [-a ATOMS] [-o OUTPUT]
```

**Options:**
- `-a, --with-atoms` - Path to atoms.json (default: `PROJECT_PATH/.verilib/probes/lean_<pkg>_<ver>.json`)
- `-o, --output` - Output file path (default: `PROJECT_PATH/.verilib/probes/lean_<pkg>_<ver>_stubs.json`)

**Example:**
```bash
probe-lean atomize ./my-lean-project
probe-lean stubify ./my-lean-project
```

**Output format (stubs.json `data` payload):**

Keys use `<code-path>/<name_last>` format where `<name_last>` is the last dot-separated part of the atom name. If multiple atoms would have the same key, the full atom name (without `probe:` prefix) is used instead: `<code-path>/<full_name>`.

```json
{
  "MyModule.lean/myFunction": {
    "code-path": "MyModule.lean",
    "code-lines": "10-15",
    "code-name": "probe:MyModule.myFunction",
    "rust-path": "",
    "rust-lines": { "lines-start": 0, "lines-end": 0 },
    "rust-name": "",
    "spec-path": "MyModule.lean",
    "spec-lines": null,
    "spec-name": "probe:MyModule.myFunction"
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
| `language` | Source language of the atom (always `"lean"` for probe-lean) |
| `dependencies` | Array of `probe:`-prefixed names this declaration depends on |
| `code-module` | Module name containing the declaration |
| `code-path` | Relative path to source file from project root |
| `code-text` | Source location with line numbers (null if unavailable) |
| `is-hidden` | Whether the atom is in the config's `user.is-hidden` list |
| `is-extraction-artifact` | Whether the atom name ends with a suffix from `user.extraction-artifact-suffixes` |
| `is-ignored` | Whether the atom is in the config's `user.is-ignored` list |
| `is-relevant` | Whether the Rust source is from the target crate (not stdlib/external deps) |
| `rust-source` | Rust source path from Aeneas docstring (null if unavailable). Falls back to `_body` variant's docstring if needed. |

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
| `code-path` | Source file path from atoms.json |
| `code-lines` | Line range as string (e.g., "10-15") |
| `code-name` | Atom name with `probe:` prefix |
| `rust-path` | Empty string (no Rust mapping) |
| `rust-lines` | `{"lines-start": 0, "lines-end": 0}` (no Rust mapping) |
| `rust-name` | Empty string (no Rust mapping) |
| `spec-path` | Source file path from atoms.json |
| `spec-lines` | Always `null` |
| `spec-name` | Atom name with `probe:` prefix |

## Testing

```bash
lake build tests
.lake/build/bin/tests
```

## Requirements

- Lean 4.25.2 or compatible version
- Lake build system
