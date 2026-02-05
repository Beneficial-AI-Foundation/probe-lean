# Feature: verify

## Summary

The `verify` command checks proof completeness in a Lean 4 project by detecting declarations that contain `sorry` (incomplete proofs). It builds the project with Lean and analyzes compiler output for sorry warnings, then outputs a JSON file mapping declaration names to their verification status. The output format is compatible with probe-verus.

## Requirements

- [ ] Build the project with `lake build` to trigger Lean compilation
- [ ] Parse Lean compiler output for `sorry` warnings
- [ ] Match warnings to declarations using file path and line numbers
- [ ] Cross-reference with atoms.json for declaration names
- [ ] Output proofs.json with verification status for each declaration
- [ ] Support `--with-atoms` flag to specify atoms.json path
- [ ] Support `-o/--output` flag for custom output path
- [ ] Cache build output to avoid re-running on unchanged projects

## API / Interface Design

```bash
probe-lean verify <PROJECT_PATH> [OPTIONS]

Arguments:
  PROJECT_PATH    Path to the Lean 4 project

Options:
  -a, --with-atoms <FILE>   Path to atoms.json (default: PROJECT_PATH/atoms.json)
  -o, --output <FILE>       Output file path (default: PROJECT_PATH/proofs.json)
      --no-cache            Don't cache verification output
      --from-file <FILE>    Analyze existing build output instead of running lake
```

## Output Format

```json
{
  "MyModule.myTheorem": {
    "verified": true,
    "status": "success",
    "code-path": "/path/to/MyModule.lean",
    "code-line": 42
  },
  "MyModule.incompleteProof": {
    "verified": false,
    "status": "sorries",
    "code-path": "/path/to/MyModule.lean",
    "code-line": 100,
    "sorries": [
      {
        "line": 105,
        "message": "declaration uses 'sorry'"
      }
    ]
  }
}
```

### Status Values
- `success`: Proof is complete, no sorry
- `sorries`: Proof contains one or more sorry
- `failure`: Compilation/type error (not a sorry)

## Behavior

### Normal Operation
1. Load atoms.json from the specified path (or default location)
2. Run `lake build` on the project (or use cached/provided output)
3. Parse compiler output for sorry-related warnings:
   - Look for "declaration uses 'sorry'" messages
   - Extract file path and line number from each warning
4. For each declaration in atoms.json:
   - Check if any sorry warnings fall within its line range
   - Set `verified: true` if no sorries, `verified: false` otherwise
   - Set appropriate status string
5. Write proofs.json to output path
6. Cache build output for future runs (unless `--no-cache`)

### Lean Sorry Detection
Lean outputs warnings like:
```
MyModule.lean:42:0: warning: declaration uses 'sorry'
```

The verify command parses these warnings to identify incomplete proofs.

### Matching Sorries to Declarations
1. Parse warning to extract file path and line number
2. Find declaration in atoms.json where:
   - `code-path` matches the warning file path
   - Warning line is within `code-text.lines-start` to `code-text.lines-end`
3. If no match found, report as unmatched sorry (still a warning)

### Caching
- Cache location: `PROJECT_PATH/.lake/probe-lean/`
- Cache files: `build_output.txt`, `build_config.json`
- Cache invalidation: Check if any .lean file is newer than cache

### Edge Cases
- Missing atoms.json: Error with message "atoms.json not found. Run 'probe-lean atomize' first."
- Build failure (not sorry-related): Report error, still output partial results
- Sorry in dependency (not project code): Ignore (filter by project modules)
- Declaration without source location: Cannot match sorries, assume `verified: true`

### Error Handling
- Invalid JSON in atoms.json: Exit 1 with parse error message
- Lake build fails completely: Exit 1, show build error
- Cannot write output file: Exit 1 with permission/path error
- Invalid project path: Exit 1 with "Not a Lake project" error

## Non-Goals

- Does NOT check specification completeness (that's `specify`)
- Does NOT run formal verification beyond Lean's type checker
- Does NOT integrate with external provers
- Does NOT generate proofs or suggest fixes
- Does NOT analyze proof complexity or quality

## Acceptance Criteria

- [ ] `probe-lean verify ./project` produces valid proofs.json
- [ ] Correctly detects sorry in theorem proofs
- [ ] Correctly reports verified theorems without sorry
- [ ] Output format matches probe-verus proofs.json structure
- [ ] Caching works and speeds up repeated runs
- [ ] `--from-file` works with saved build output
- [ ] Error cases produce helpful error messages
- [ ] Unit tests for sorry detection parsing
- [ ] Integration test with project containing both complete and incomplete proofs

---
Status: draft
