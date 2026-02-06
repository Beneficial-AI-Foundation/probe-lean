# Feature: atomize

## Summary

Implement `probe-lean` command line tool in Lean 4, with `atomize` as a subcommand. The subcommand analyzes a Lean 4 project using Lake and the Lean compiler's environment, then outputs `atoms.json` - a call graph where keys are declaration names and values contain dependency and location information. Output format is compatible with probe-verus tooling.

Reference implementations:
- https://github.com/Beneficial-AI-Foundation/probe-verus (Verus/Rust)
- https://github.com/Beneficial-AI-Foundation/probe-blueprint (Lean via LaTeX Blueprint)

Sample projects for testing:
- https://github.com/Beneficial-AI-Foundation/curve25519-dalek-lean-verify

## Requirements

- [ ] Create a Lean 4 Lake project named `probe-lean`
- [ ] Implement CLI with `atomize` subcommand
- [ ] Accept a path to a Lean 4 project as input
- [ ] Use Lake to build/load the target project's environment
- [ ] Extract all declarations (def, theorem, lemma, etc.) from the project
- [ ] For each declaration, extract its dependencies (what it calls/uses)
- [ ] For each declaration, extract source location (file path, line range)
- [ ] Output atoms.json in probe-verus compatible format
- [ ] Handle projects with multiple modules/files

## API / Interface Design

### CLI
```
probe-lean atomize <PROJECT_PATH> [OPTIONS]

Arguments:
  <PROJECT_PATH>    Path to Lean 4 project root (containing lakefile.lean)

Options:
  -o, --output <FILE>    Output file path (default: atoms.json)
  --module <MODULE>      Only analyze specific module (optional)
  --help                 Show help
```

### Output Format (atoms.json)
```json
{
  "probe:Mathlib.Algebra.Group.Basic.mul_one": {
    "display-name": "mul_one",
    "dependencies": [
      "probe:Mathlib.Algebra.Group.Defs.Monoid.one",
      "probe:Mathlib.Algebra.Group.Defs.Monoid.mul"
    ],
    "code-module": "Mathlib.Algebra.Group.Basic",
    "code-path": "Mathlib/Algebra/Group/Basic.lean",
    "code-text": {
      "lines-start": 42,
      "lines-end": 45
    },
    "kind": "theorem"
  }
}
```

### Key Format
Prefixed fully qualified Lean name: `probe:<Namespace>.<Name>`

All atom names and dependencies use the `probe:` prefix for namespace consistency with other probe tools.

### Atom Object Fields
| Field | Type | Description |
|-------|------|-------------|
| `display-name` | string | Short name without namespace |
| `dependencies` | string[] | Prefixed fully qualified names (`probe:...`) of declarations this depends on |
| `code-module` | string | Module name (dot-separated) |
| `code-path` | string | Relative file path from project root (no leading `./`) |
| `code-text` | object | `{ "lines-start": int, "lines-end": int }` |
| `kind` | string | One of: `def`, `theorem`, `lemma`, `abbrev`, `instance`, `structure`, `inductive`, `class` |

## Behavior

### Normal Operation
1. Validate PROJECT_PATH contains `lakefile.lean`
2. Run `lake build` (or load existing build) to get compiled environment
3. Iterate through all modules in the project
4. For each declaration in the environment:
   - Skip internal/compiler-generated declarations (names starting with `_`)
   - Skip declarations from dependencies (only include project's own code)
   - Extract dependencies by analyzing the declaration's value/type
   - Look up source location from position info
5. Write atoms.json to output path

### Edge Cases
- Project fails to build: Exit with error, show Lake's error output
- Declaration has no source position: Omit `code-text` field (still include declaration)
- Circular dependencies: Include all edges (cycles are valid in the graph)
- Mutually recursive definitions: Each gets its own entry with cross-references

### Error Handling
- Missing lakefile.lean: Exit 1 with "Error: Not a Lake project (missing lakefile.lean)"
- Lake build fails: Exit 1 with Lake's stderr
- Invalid output path: Exit 1 with "Error: Cannot write to <path>"

## Non-Goals

- Lean 3 support (Lean 4 only)
- Incremental updates (always regenerates full atoms.json)
- Proof term analysis (only tracks declaration-level dependencies)
- Type-level dependency analysis beyond direct references
- Integration with Blueprint LaTeX (that's probe-blueprint's job)
- GUI or interactive mode

## Acceptance Criteria

- [ ] `probe-lean atomize .` works on a simple Lean 4 project with 3+ files
- [ ] Output atoms.json is valid JSON
- [ ] All project declarations appear in output (none missing)
- [ ] Dependencies are accurate (verified against manual inspection)
- [ ] Line numbers match actual source locations
- [ ] Works on Mathlib (or a subset) without crashing
- [ ] Exit codes are correct (0 for success, 1 for errors)

---
Status: draft
