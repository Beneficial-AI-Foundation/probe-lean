# Feature: specify

## Summary

The `specify` command extracts specification status from a Lean 4 project, indicating which declarations have complete type signatures (specifications). For theorems, this means checking if they have fully specified propositions. The output is a JSON file mapping declaration names to their specification status, compatible with the probe-verus format.

## Requirements

- [ ] Parse atoms.json to get list of project declarations
- [ ] For each declaration, determine if it has a complete specification:
  - Theorems/lemmas: Always considered "specified" (their type IS the spec)
  - Definitions: Check if type signature is fully explicit (no `_` placeholders)
  - Structures/classes: Always considered "specified"
- [ ] Output specs.json with specification status for each declaration
- [ ] Support `--with-atoms` flag to specify atoms.json path
- [ ] Support `-o/--output` flag for custom output path

## API / Interface Design

```bash
probe-lean specify <PROJECT_PATH> [OPTIONS]

Arguments:
  PROJECT_PATH    Path to the Lean 4 project

Options:
  -a, --with-atoms <FILE>   Path to atoms.json (default: PROJECT_PATH/atoms.json)
  -o, --output <FILE>       Output file path (default: PROJECT_PATH/specs.json)
```

## Output Format

```json
{
  "MyModule.myTheorem": {
    "specified": true,
    "code-path": "/path/to/MyModule.lean",
    "spec-text": {
      "lines-start": 10,
      "lines-end": 12
    }
  },
  "MyModule.myDef": {
    "specified": true,
    "code-path": "/path/to/MyModule.lean",
    "spec-text": {
      "lines-start": 20,
      "lines-end": 25
    }
  }
}
```

## Behavior

### Normal Operation
1. Load atoms.json from the specified path (or default location)
2. For each atom in atoms.json:
   - Extract the declaration name
   - Determine specification status based on kind:
     - `theorem`, `lemma`: `specified: true` (type is the specification)
     - `def`, `abbrev`: `specified: true` if type is explicit
     - `structure`, `class`, `inductive`: `specified: true`
     - `instance`: `specified: true`
   - Include source location from atoms.json
3. Write specs.json to output path

### Edge Cases
- Missing atoms.json: Error with message "atoms.json not found. Run 'probe-lean atomize' first."
- Empty atoms.json: Output empty specs.json `{}`
- Declaration without source location: Include with `spec-text: null`

### Error Handling
- Invalid JSON in atoms.json: Exit 1 with parse error message
- Cannot write output file: Exit 1 with permission/path error
- Invalid project path: Exit 1 with "Not a Lake project" error

## Non-Goals

- Does NOT verify proof completeness (that's `verify`)
- Does NOT run the Lean compiler
- Does NOT check for `sorry` in proofs
- Does NOT parse Lean source files directly (uses atoms.json)
- Does NOT support custom specification frameworks (e.g., pre/post conditions)

## Acceptance Criteria

- [ ] `probe-lean specify ./project` produces valid specs.json
- [ ] All declarations from atoms.json appear in specs.json
- [ ] Output format matches probe-verus specs.json structure
- [ ] Error cases produce helpful error messages
- [ ] Unit tests for specification status determination
- [ ] Integration test on sample project

---
Status: draft
