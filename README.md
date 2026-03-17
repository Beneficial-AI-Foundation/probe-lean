# probe-lean

A tool for analyzing Lean 4 projects and extracting dependency graphs with verification status.

## Schema 2.0 Envelope

All output files are wrapped in a Schema 2.0 metadata envelope:

```json
{
  "schema": "probe-lean/extract",
  "schema-version": "2.0",
  "tool": {
    "name": "probe-lean",
    "version": "0.1.0",
    "command": "extract"
  },
  "source": {
    "repo": "https://github.com/org/project",
    "commit": "abc123d",
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
| `schema` | Identifies tool and data type (`probe-lean/extract`, `probe-lean/viewify`) |
| `schema-version` | Always `"2.0"` |
| `tool.name` | `"probe-lean"` |
| `tool.version` | Tool version string |
| `tool.command` | The command that produced this output (`extract`, `viewify`) |
| `source.repo` | Git remote URL of the analyzed project (empty string if unavailable) |
| `source.commit` | Short Git commit hash (empty string if unavailable) |
| `source.language` | `"lean"` |
| `source.package` | Package name from `lakefile.toml` |
| `source.package-version` | Version from `lakefile.toml`, or short Git commit hash if not available |
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

## Directory Structure

probe-lean outputs are organized under `.verilib/`:

```
.verilib/
├── probes/
│   └── lean_<pkg>_<ver>.json     # extract output (unified atoms)
└── views/
    └── molecules_all.json         # viewify output (filtered molecules)
```

## Commands

### extract

Analyze a Lean 4 project: extract atoms, detect sorries, compute specs, and produce unified output. This is the primary command that combines the former `atomize` and `verify` steps into a single pass.

```bash
probe-lean extract <PROJECT_PATH> [-o OUTPUT] [-m MODULE] [--skip-verify] [--skip-build] [--from-file FILE]
```

**Options:**
- `-o, --output` - Output file path (default: `.verilib/probes/lean_<pkg>_<ver>.json`)
- `-m, --module` - Filter to specific module prefix
- `--skip-verify` - Skip the sorry detection step (only graph structure)
- `--skip-build` - Skip the lake build step (assumes .olean files already exist)
- `--from-file` - Use existing build output for sorry detection instead of running lake

**Example:**
```bash
probe-lean extract ./my-lean-project
probe-lean extract ./my-lean-project --skip-verify
probe-lean extract ./my-lean-project -o output.json
```

**Output format (`data` payload):**

Each atom includes all fields plus `verification-status` and `specs`:

```json
{
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
  },
  "probe:MyModule.helper_spec": {
    "display-name": "helper_spec",
    "kind": "theorem",
    "language": "lean",
    "dependencies": ["probe:MyModule.helper", "probe:MyModule.MyType"],
    "type-dependencies": ["probe:MyModule.helper", "probe:MyModule.MyType"],
    "term-dependencies": ["probe:MyModule.helper"],
    "code-module": "MyModule",
    "code-path": "MyModule/Specs.lean",
    "code-text": { "lines-start": 10, "lines-end": 15 },
    "is-hidden": false,
    "is-extraction-artifact": false,
    "is-ignored": false,
    "is-relevant": true,
    "rust-source": null,
    "verification-status": "verified"
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

### viewify

Generate molecules output from extract results, filtering for the web UI. Reads the extract output from `.verilib/probes/` and filters atoms to include only those where:
- `is-hidden` is `false`
- `is-extraction-artifact` is `false`
- `is-relevant` is `true`
- `code-path` ends with `Funs.lean`

```bash
probe-lean viewify <PROJECT_PATH> [-a ATOMS] [-o OUTPUT]
```

**Options:**
- `-a, --with-atoms` - Path to extract output (default: auto-detect from `.verilib/probes/`)
- `-o, --output` - Output file path (default: `.verilib/views/molecules_all.json`)

**Example:**
```bash
probe-lean extract ./my-lean-project
probe-lean viewify ./my-lean-project
```

**Output format (`data` payload):**

Keys use `<code-path>/<name_last>` format where `<name_last>` is the last dot-separated part of the atom name. If multiple atoms would have the same key, the full atom name (without `probe:` prefix) is used instead.

```json
{
  "MyModule/Funs.lean/myFunction": {
    "code-path": "MyModule/Funs.lean",
    "code-lines": "10-15",
    "code-name": "probe:MyModule.myFunction",
    "rust-path": "",
    "rust-lines": { "lines-start": 0, "lines-end": 0 },
    "rust-name": "",
    "spec-path": "MyModule/Funs.lean",
    "spec-lines": null,
    "spec-name": "probe:MyModule.myFunction"
  }
}
```

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

## Output Fields

### extract output (unified atoms)

| Field | Type | Description |
|-------|------|-------------|
| `display-name` | string | Last component of the name |
| `kind` | string | `def`, `theorem`, `abbrev`, `class`, `structure`, `inductive`, `instance`, `axiom`, `opaque` |
| `language` | string | Always `"lean"` |
| `dependencies` | array | `probe:`-prefixed names this declaration depends on (union of type + term) |
| `type-dependencies` | array | `probe:`-prefixed names referenced in the declaration's type signature |
| `term-dependencies` | array | `probe:`-prefixed names referenced in the declaration's body/proof |
| `code-module` | string | Module name containing the declaration |
| `code-path` | string | Relative path to source file from project root |
| `code-text` | object or null | `{ "lines-start": N, "lines-end": N }` |
| `is-hidden` | bool | From config's `user.is-hidden` list |
| `is-extraction-artifact` | bool | Name ends with suffix from `user.extraction-artifact-suffixes` |
| `is-ignored` | bool | From config's `user.is-ignored` list |
| `is-relevant` | bool | Rust source is from the target crate |
| `rust-source` | string or null | Rust source path from Aeneas docstring |
| `specs` | array or absent | Code-names of theorem atoms that depend on this atom. Absent when empty. Whether an atom is "specified" can be inferred from `specs` being non-empty. |
| `primary-spec` | string or absent | Code-name of the primary specification theorem for this atom. Absent when none. Set by `@[primary_spec]` attribute, or inferred when `<name>_spec` exists in `specs`. |
| `verification-status` | string or absent | `"verified"`, `"unverified"`, `"failed"`, or absent if skipped |

### viewify output (molecules)

| Field | Type | Description |
|-------|------|-------------|
| `code-path` | string or null | Source file path |
| `code-lines` | string or null | Line range as string (e.g., "10-15") |
| `code-name` | string | Atom name with `probe:` prefix |
| `rust-path` | string | Empty string (no Rust mapping) |
| `rust-lines` | object | `{"lines-start": 0, "lines-end": 0}` |
| `rust-name` | string | Empty string (no Rust mapping) |
| `spec-path` | string or null | Source file path |
| `spec-lines` | string or null | Always `null` |
| `spec-name` | string or null | Atom name with `probe:` prefix |

## Testing

```bash
lake build tests
.lake/build/bin/tests
```

## Requirements

- Lean 4.25.2 or compatible version
- Lake build system
