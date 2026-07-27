# Testing

## Quick start

```bash
lake build tests
.lake/build/bin/tests
```

## Test layers

| Layer | Count | Location | Requires |
|-------|-------|----------|----------|
| Unit tests | 305 | `Tests/Main.lean` | Nothing |
| Integration tests (example JSON) | 26 | `Tests/Main.lean` | Nothing |
| **Total** | **331** | | |

All tests run without external tools.

## Unit tests

305 tests across 34 test functions in `Tests/Main.lean`:

| Test function | What it covers |
|---------------|---------------|
| `testConstants` | Schema version, tool name, directory constants |
| `testAnalysisHelpers` | Internal name filtering, display name derivation, substring matching, path stripping |
| `testSharedUtilities` | `probe:` prefix add/strip |
| `testTypeJsonSerialization` | `DeclKind`, `ToolInfo`, `SourceInfo`, `Envelope` JSON round-trips |
| `testAtomizeHelpers` | Suffix matching, docstring source extraction, source relevance, atom flag marking (hidden, artifact, ignored) |
| `testComputeSpecs` | Reverse edges from theorems to definitions, multiple specs, theorem-to-theorem exclusion |
| `testAtomsOutputJson` | Keyed-dict serialization, `probe:` prefixed dependencies, boolean flags |
| `testAtomSpecsJson` | Optional `specs` field presence/absence, round-trip |
| `testAtomLanguageField` | Default `"lean"` language in atom and output JSON |
| `testSorryDetection` | Sorry warning parsing (file, line, column), path normalization, path matching, `VerifyStatus` serialization, `atomToProofEntry` |
| `testProofsOutputJson` | Keyed-dict proofs format, round-trip |
| `testUnifiedAtomJson` | `WebVerificationStatus` round-trip, `UnifiedAtomsOutput` round-trip with optional fields (rustSource, verificationStatus), specs serialization |
| `testViewHelpers` | `getLastNamePart`, `parseLines` (ranges, L-prefix) |
| `testStubEntryJson` | `StubEntry` serialization with nullable fields |
| `testMoleculesOutputJson` | `MoleculesOutput` keyed-dict format, round-trip |
| `testEnvelopeAwareLoading` | Bare-dict and enveloped JSON loading, `unwrapEnvelope` with foreign schemas, `loadAtoms` end-to-end, `rustSource` preservation |
| `testMetadataHelpers` | TOML name/version parsing, output filename generation, atoms file matching |
| `testFindDefaultAtomsPath` | Exact path, fallback with alternative files, newest-file selection |
| `testTypedDependencies` | `type-dependencies` / `term-dependencies` serialization, backward compatibility with legacy JSON |
| `testPrimarySpecHeuristic` | `_spec` suffix heuristic, `@[primary_spec]` attribute override, no-match fallback |
| `testPrimarySpecKnownAttribute` | Known-attribute boost (`@[progress]`, `@[pspec]`, `@[step]`), ambiguity fallthrough, precedence vs `_spec` and `@[primary_spec]` |
| `testPrimarySpecSoleSpec` | Sole-spec inference, multiple-specs no-match, `_spec` beats sole-spec, invariant check |
| `testTrustedStatus` | `isTrustedAtom` (axiom, non-theorem `*External.lean`, negatives incl. theorem-in-External), `unifyAtom` trusted override (success/sorries/failure proof entries, no proof entry), theorem-in-External normal verification status |

## Integration tests (example JSON)

26 tests across 4 test functions that load
`examples/lean_Curve25519Dalek_0.1.0.json` and validate the real
extract output:

| Test function | Checks | What it validates |
|---------------|--------|-------------------|
| `testExampleJsonEnvelopeStructure` | 8 | Schema is `probe-lean/extract`, version `3.0`, non-empty timestamp, tool name/command, source package/language, data object present |
| `testExampleJsonLoadAtoms` | 4 | `loadAtoms` succeeds, >1000 atoms, all keys start with `probe:`, all atoms have language `"lean"` |
| `testExampleJsonAtomRequiredFields` | 8 | Non-empty `display-name`, `code-module`, `code-path`; valid `DeclKind`; has `def`, `theorem`, and `projection` atoms; all atoms have source location |
| `testExampleJsonVerificationStatus` | 6 | All atoms have valid `verification-status` (verified/unverified/failed/trusted); at least some `"verified"` and `"trusted"`; all trusted have valid `trusted-reason`; non-trusted have no `trusted-reason` |

## CI

`.github/workflows/ci.yml` runs on push/PR to `main`:

1. **Build** -- `leanprover/lean-action@v1` builds the main project
2. **Test** -- builds `tests` target, then runs `.lake/build/bin/tests`

The CI uses `lean-action` which automatically installs elan, sets up the
Lean toolchain from `lean-toolchain`, and caches the `.lake` directory.

## Adding tests

Tests live in `Tests/Main.lean`. To add a new test:

1. Define a `def testYourFeature (result : TestResult) : IO TestResult` function
2. Use the `test` helper: `result <- test "description" condition result`
3. Wire it into `main`: `result <- testYourFeature result`

## See also

- `docs/test-projects.md` -- Lean 4 test projects for manual validation
