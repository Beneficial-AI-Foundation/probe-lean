# Feature: stubify

## Summary

Implement `stubify` subcommand for `probe-lean`. The command filters atoms from `atoms.json` to only include those functions listed in `functions.json`, producing `stubs.json`. This creates a curated subset of the dependency graph containing only the relevant functions for verification.

## Requirements

- [ ] Add `stubify` subcommand to CLI
- [ ] Read `functions.json` containing a list of function entries with `lean_name` field
- [ ] Read `atoms.json` containing the full atom data
- [ ] Filter atoms to only those whose names (without `probe:` prefix) match entries in `functions.json`
- [ ] Output `stubs.json` with the filtered atoms in the same format as `atoms.json`
- [ ] Handle missing files gracefully with clear error messages

## API / Interface Design

### CLI
```
probe-lean stubify <PROJECT_PATH> [OPTIONS]

Arguments:
  <PROJECT_PATH>    Path to Lean 4 project root

Options:
  -f, --functions <FILE>   Path to functions.json (default: PROJECT_PATH/functions.json)
  -a, --with-atoms <FILE>  Path to atoms.json (default: PROJECT_PATH/atoms.json)
  -o, --output <FILE>      Output file path (default: PROJECT_PATH/stubs.json)
  --help                   Show help
```

### Input: functions.json
```json
{
  "functions": [
    {
      "lean_name": "MyModule.myFunction",
      "is_relevant": true,
      ...
    }
  ]
}
```

Only entries where `is_relevant` is `true` (or field is missing) are included.

### Output: stubs.json
Same format as `atoms.json` - an object keyed by `probe:`-prefixed atom names:
```json
{
  "probe:MyModule.myFunction": {
    "display-name": "myFunction",
    "dependencies": ["probe:MyModule.helper"],
    "code-module": "MyModule",
    "code-path": "MyModule.lean",
    "code-text": { "lines-start": 10, "lines-end": 15 },
    "kind": "def"
  }
}
```

## Behavior

### Normal Operation
1. Validate PROJECT_PATH exists
2. Load `functions.json` and extract `lean_name` values where `is_relevant` is not false
3. Load `atoms.json`
4. Filter atoms to only those matching function names (matching `probe:<lean_name>`)
5. Write filtered atoms to `stubs.json`
6. Print summary: "Filtered X atoms from Y total to stubs.json"

### Edge Cases
- Function in `functions.json` has no matching atom: Skip silently (function may not exist in Lean code)
- Atom has no matching function: Excluded from output
- Empty functions list: Output empty object `{}`
- `is_relevant` field missing: Treat as `true`

### Error Handling
- Missing `functions.json`: Exit 1 with "Error: Cannot read functions.json: <path>"
- Missing `atoms.json`: Exit 1 with "Error: Cannot read atoms.json: <path>. Run 'probe-lean atomize' first."
- Invalid JSON: Exit 1 with "Error: Invalid JSON in <file>"
- Invalid output path: Exit 1 with "Error: Cannot write to <path>"

## Non-Goals

- Modifying the atom data (only filtering)
- Validating function specifications
- Running verification
- Generating functions.json (that's external tooling)

## Acceptance Criteria

- [ ] `probe-lean stubify .` filters atoms based on functions.json
- [ ] Output stubs.json is valid JSON in the same format as atoms.json
- [ ] Only atoms with matching lean_name in functions.json are included
- [ ] Respects `is_relevant` field (false = excluded)
- [ ] Exit codes are correct (0 for success, 1 for errors)
- [ ] Works with the curve25519-dalek-lean-verify project

---
Status: draft
