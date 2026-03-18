# Usage Guide

## Commands

### `extract`

Analyze a Lean 4 project: extract atoms, detect sorries, compute specs, and
produce unified output. This is the primary command that combines atom
extraction and sorry-based verification into a single pass.

```
probe-lean extract <PROJECT_PATH> [OPTIONS]
```

**Arguments:**

- `PROJECT_PATH` -- Path to the Lean project root. Must contain a `lakefile.toml` or `lakefile.lean`.

**Options:**

| Flag | Short | Description |
|------|-------|-------------|
| `--output <PATH>` | `-o` | Output file path (default: `.verilib/probes/lean_<pkg>_<ver>.json`) |
| `--module <PREFIX>` | `-m` | Filter to specific module prefix |
| `--skip-verify` | | Skip the sorry detection step (graph structure only) |
| `--skip-build` | | Skip `lake build` (assumes `.olean` files already exist) |
| `--from-file <FILE>` | | Use existing build output for sorry detection instead of running lake |

### Examples

**Basic extraction:**

```bash
probe-lean extract ./my-lean-project
```

**Skip sorry detection (faster, graph only):**

```bash
probe-lean extract ./my-lean-project --skip-verify
```

**With pre-built .olean files (e.g. after `lake exe cache get`):**

```bash
probe-lean extract ./my-lean-project --skip-build
```

**Filter to a specific module:**

```bash
probe-lean extract ./my-lean-project -m MyProject.Core
```

**Custom output path:**

```bash
probe-lean extract ./my-lean-project -o output.json
```

---

## Output Format

For the complete JSON schema specification, see [SCHEMA.md](SCHEMA.md).

The `extract` command produces a JSON file wrapped in a Schema 2.0 metadata
envelope:

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

## Prerequisites

- **Lean 4 toolchain** (`elan`, `lake`) -- install via [elan](https://github.com/leanprover/elan#installation)
- The target project must build with `lake build`
- For large projects using Mathlib, run `lake exe cache get` first to download pre-built `.olean` files

## Directory Structure

probe-lean outputs are organized under `.verilib/`:

```
.verilib/
└── probes/
    └── lean_<pkg>_<ver>.json     # extract output (unified atoms)
```
