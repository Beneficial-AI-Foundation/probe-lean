# Feature: stubify

## Summary

Implement `stubify` subcommand for `probe-lean`. The command filters atoms from `atoms.json` to only include those functions listed in `functions.json`, producing `stubs.json` with a custom output format that maps Lean functions to their Rust counterparts.

## Requirements

- [ ] Add `stubify` subcommand to CLI
- [ ] Read `functions.json` containing function entries with Lean/Rust mapping info
- [ ] Read `atoms.json` containing the full atom data
- [ ] Filter atoms to only those whose names (without `probe:` prefix) match entries in `functions.json`
- [ ] Generate keys using `<source>/<lean_name_1>` format with clash resolution
- [ ] Output `stubs.json` with the new field format
- [ ] Handle missing files gracefully with clear error messages

## API / Interface Design

### CLI
```
probe-lean stubify <PROJECT_PATH> [OPTIONS]

Arguments:
  <PROJECT_PATH>    Path to Lean 4 project root

Options:
  -f, --functions <FILE>   Path to functions.json (default: PROJECT_PATH/.verilib/functions.json)
  -a, --with-atoms <FILE>  Path to atoms.json (default: PROJECT_PATH/.verilib/atoms.json)
  -o, --output <FILE>      Output file path (default: PROJECT_PATH/.verilib/stubs.json)
  --help                   Show help
```

### Input: functions.json
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

Only entries where `is_relevant` is `true` (or field is missing) are included.

### Output: stubs.json

**Key format:**
- Default: `<source>/<lean_name_1>` where `<lean_name_1>` is the last dot-separated part of `<lean_name>`
- On clash: `<source>/<lean_name_1>#<lean_name_2>` where `<lean_name_2>` is the second-last part

**Example without clash:**
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

**Example with clash (two functions with same last name part from same source file):**
```json
{
  "src/crypto/field.rs/add#FieldElement": {
    "lean-path": null,
    "lean-lines": null,
    "lean-name": "probe:Crypto.FieldElement.add",
    "rust-path": "src/crypto/field.rs",
    "rust-lines": { "lines-start": 10, "lines-end": 20 },
    "rust-name": "FieldElement::add",
    "code-path": null,
    "code-lines": null,
    "code-name": null
  },
  "src/crypto/field.rs/add#Scalar": {
    "lean-path": null,
    "lean-lines": null,
    "lean-name": "probe:Crypto.Scalar.add",
    "rust-path": "src/crypto/field.rs",
    "rust-lines": { "lines-start": 50, "lines-end": 60 },
    "rust-name": "Scalar::add",
    "code-path": null,
    "code-lines": null,
    "code-name": null
  }
}
```

**Field descriptions:**

| Field | Description |
|-------|-------------|
| `lean-path` | Always `null` (placeholder) |
| `lean-lines` | Always `null` (placeholder) |
| `lean-name` | `probe:<lean_name>` from functions.json |
| `rust-path` | `<source>` from functions.json |
| `rust-lines` | `<lines>` converted to `{"lines-start": N, "lines-end": M}` |
| `rust-name` | `<rust_name>` from functions.json |
| `code-path` | `<spec_file>` if it exists, otherwise `null` |
| `code-lines` | Always `null` (placeholder) |
| `code-name` | `probe:<lean_name>_spec` if `<spec_file>` exists, otherwise `null` |

## Behavior

### Normal Operation
1. Validate PROJECT_PATH exists
2. Load `functions.json` and extract entries where `is_relevant` is not false
3. Load `atoms.json`
4. Filter to only functions with matching atom in atoms.json
5. Generate output keys with clash resolution:
   a. Group functions by `<source>/<lean_name_1>`
   b. For groups with >1 entry, use `<source>/<lean_name_1>#<lean_name_2>` for all in group
6. Build output with new field format
7. Write to `stubs.json`
8. Print summary: "Filtered X atoms from Y total to stubs.json"

### Lines Format Conversion
The `lines` field in functions.json uses format `"start-end"` (e.g., `"42-58"`).
Convert to: `{"lines-start": 42, "lines-end": 58}`

### Edge Cases
- Function in `functions.json` has no matching atom: Skip silently (function may not exist in Lean code)
- Atom has no matching function: Excluded from output
- Empty functions list: Output empty object `{}`
- `is_relevant` field missing: Treat as `true`
- `spec_file` field missing or empty: Use `-` for `code-path` and `code-name`
- `lines` field missing: Use `{"lines-start": 0, "lines-end": 0}`

### Error Handling
- Missing `functions.json`: Exit 1 with "Error: Cannot read functions.json: <path>"
- Missing `atoms.json`: Exit 1 with "Error: Cannot read atoms.json: <path>. Run 'probe-lean atomize' first."
- Invalid JSON: Exit 1 with "Error: Invalid JSON in <file>"
- Invalid output path: Exit 1 with "Error: Cannot write to <path>"

## Non-Goals

- Modifying the atom data (only filtering and reformatting)
- Validating function specifications
- Running verification
- Generating functions.json (that's external tooling)

## Acceptance Criteria

- [ ] `probe-lean stubify .` filters atoms based on functions.json
- [ ] Output stubs.json uses `<source>/<lean_name_1>` key format
- [ ] Clashing keys are resolved with `#<lean_name_2>` suffix
- [ ] Only atoms with matching lean_name in functions.json are included
- [ ] Respects `is_relevant` field (false = excluded)
- [ ] Output fields match the new format specification
- [ ] Exit codes are correct (0 for success, 1 for errors)
- [ ] Works with the curve25519-dalek-lean-verify project

---
Status: draft
