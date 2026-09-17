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
| `testSorryDetection` | Sorry warning parsing (file, line, column), path normalization, path matching, `findSorriesForAtom` range matching |
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
| `testTrustedStatus` | `Trust.trustedReason` rules 1–3 and precedence (axiom, the declaration's own `@[externally_verified]`, non-proof in a `*External` module — Prop-typed `def`/`opaque` excluded, negatives incl. theorem-in-External and `External` as a non-final component), `isCompanionName`, `isExternalModule` |
| `testAxiomReachability` | `reaches`/`reachingNames` on a fabricated graph: transitive hit, cycles, diamond; the #103 case `f → {g, SORRY}, g → f` in both root orders |
| `testReachabilityBlocked` | The blocked set: blocked node not expanded, blocked direct carrier shields its caller, target reached although blocked (target-before-block), target outside P reached through a P chain, cycle with a blocked sibling, root-order independence |
| `testApplyTaintStatus` | `applyTaintStatus` verdict matrix (trusted / trusted direct carrier / direct / tainted / clean / unknown name), `--skip-enrich` cap, `--skip-verify` shape, `unifyAtom` carries `leanName` and no status, `leanName` not serialised |
| `testDivergenceLines` | Graph-vs-oracle divergence text in both directions, `demoteTransitive`, `statusCounts` |
| `testTaintFormatting` | Fallback / type-taint / unknown-atom warnings, the proofless abort text, the cross-boundary note, `check-axioms` report lines, summary line, `Divergence(log):` lines (aux-carried sorry is agreement; generated and trusted atoms skipped) |
| `testAttributeScan` | Header-only `@[…]` scan: the `stripLine` lexer (nested block comments, docstrings, strings across lines, escaped quotes, raw strings, interpolated strings, char literals, `«…»`, `stripLines` from the top), head-line detection, no look-back above the range, 1-based range conversion (the old scan read the *next* declaration's tag) |
| `testAttributeScanNegatives` | Fabricated-trust shapes yield nothing: tag quoted in a docstring, body comment or string literal; tagged one-line neighbour above; a neighbour's attribute line then its head; block comment / module docstring / multi-line string opened above the window; raw string, char literal, guillemet identifier spelling the tag; the declaration's own tag still survives. `headerNamesDecl`: dotted names, private names, anonymous instances, range-sharers (derived instance, companion) not named |
| `testLoadedProjectModules` | Fallback P: `all` restricted to the modules the environment loaded |
| `testLoadedOrphans` | Orphan oleans the import loaded anyway (`loadedOrphans`): none, disjoint, one hit, sorted; the abort message |
| `testMergedDecls` | `mergedChildren` is the union over versions, deduplicated; `mergedChildrenMap`; `formatMergedWarning` text and cap; `formatRealisedMergedNote` |
| `testHeaderMerges` | `classifyHeaderVersions` over fabricated header data: project/project → merged with both versions sorted by module; project + dependency → cross with the project's versions only (dependency `constants` never read); a name the environment attributes outside the project → cross; an un-duplicated name → nothing; two project owners plus a dependency → cross with both versions; both outputs sorted by name; `isRealisedTheoremName` positives (`eq_N`, `eq_def`, `eq_unfold`, `congr_simp`, `hcongr_N`, `congr_N`, `match_1.congr_eq_N`) and negatives |
| `testProjectTaintEnv` | Environment-backed (`run_cmd` + `addDecl`): direct carriers, range-less carrier taints its caller, trusted sorried lemma shields caller and companion, `typeTainted`, `computeTrustBase` (a range-sharer that only *shows* a neighbour's tag is not trusted; a name in the tag set is), `propTypedNames`, `headerMerges` on a clean environment (nothing merged, nothing cross), and agreement with `Lean.collectAxioms` on every root |

## Integration tests (example JSON)

26 tests across 4 test functions that load
`examples/lean_ExampleProject_0.1.0.json` and validate real extract output.

That fixture is **generated, not hand-written**: `tools/gen-fixture.sh` builds it
through probe-lean's own `Envelope` / `UnifiedAtomsOutput` serializers, so the
committed file is genuine tool output and stays meaningful to the
`probe-extract-check` job in CI. Output is byte-deterministic, and the `test` job
regenerates it and fails on any diff — so **any output-format change (a new atom
field, a renamed key, a version bump) requires re-running the script and
committing the result.** Do not edit the file by hand; the fixture it replaced was
hand-patched and sat at tool version `0.4.5` while the real format moved on.

| Test function | Checks | What it validates |
|---------------|--------|-------------------|
| `testExampleJsonEnvelopeStructure` | 8 | Schema is `probe-lean/extract`, version `3.0`, non-empty timestamp, tool name/command, source package/language, data object present |
| `testExampleJsonLoadAtoms` | 4 | `loadAtoms` succeeds, fixture is non-empty, all keys start with `probe:`, all atoms have language `"lean"` |
| `testExampleJsonAtomRequiredFields` | 8 | Non-empty `display-name`, `code-module`, `code-path`; valid `DeclKind`; has `def`, `theorem`, and `projection` atoms; all atoms have source location |
| `testExampleJsonVerificationStatus` | 6 | All atoms have valid `verification-status` (verified/unverified/failed/trusted); at least some `"verified"` and `"trusted"`; all trusted have valid `trusted-reason`; non-trusted have no `trusted-reason` |

## CI

`.github/workflows/ci.yml` runs on push/PR to `main`:

1. **Build** -- `leanprover/lean-action@v1` builds the main project
2. **Test** -- builds `tests` target, then runs `.lake/build/bin/tests`
3. **End-to-end** -- builds `tests/fixtures/aux-fold`, runs `probe-lean extract` and
   `probe-lean check-axioms` on it, then `AuxFoldCheck.lean` (recovered auxiliary edges)
   and `TaintCheck.lean` (kernel-backed statuses, the `Divergence(graph):` line, the
   `check-axioms` report) and `tools/audit/check-status-consistency.py` (artifact and
   report agree on every atom in both directions); then builds `tests/fixtures/collision`,
   whose two colliding modules force the import fallback under `--module`, and runs
   `check.py` (a transitively loaded sorried module still taints the selected caller);
   then builds `tests/fixtures/merge`, where two modules restate one theorem and the
   importer keeps one proof, and runs its `check.py` (the merged name reads `unverified`,
   both callers `verified`, the warning is printed); then builds
   `tests/fixtures/cross-merge`, where four project modules restate a path dependency's
   theorems (sorried and proved, dependency-wins-the-name and project-wins-the-name), and
   runs its `check.py` (the sorried restatements' callers `verified` and `shared4`
   `unverified` although the environment holds the dependency's proof under its name, the
   proved ones' callers `transitively-verified`, the cross-boundary note names all four,
   `shared` listed `[direct] [not emitted]`); then `tests/fixtures/module-merge` (two `module` files
   export the same `public theorem`, one sorried; the private-level import keeps both bodies
   in the environment header); then `tests/fixtures/module-collision` (the collision fixture
   with `module` headers: the exported level shows both `public def dup` as axioms, which the
   base-olean preflight tolerates, so the full import itself fails and the fallback takes
   over); then
   `tests/fixtures/orphan` (`extract`, delete a source, `extract` and `check-axioms` again:
   both must abort with the stale-module message); repeated on the newest supported Lean by
   the `test-newest` job

The CI uses `lean-action` which automatically installs elan, sets up the
Lean toolchain from `lean-toolchain`, and caches the `.lake` directory.

## Adding tests

Tests live in `Tests/Main.lean`. To add a new test:

1. Define a `def testYourFeature (result : TestResult) : IO TestResult` function
2. Use the `test` helper: `result <- test "description" condition result`
3. Wire it into `main`: `result <- testYourFeature result`

## See also

- `docs/test-projects.md` -- Lean 4 test projects for manual validation
