# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Spec-Driven Development Workflow

This project uses spec-driven development. Follow this workflow:

### When the user asks you to implement a feature:

1. **Check for a spec first**: Look in `specs/active/` for a spec file
2. **If no spec exists**: Ask the user to write one, or offer to draft one together
3. **If spec exists**: Read it completely before proceeding
4. **Enter plan mode**: Create an implementation plan based on the spec
5. **Wait for approval**: Do not implement until the user approves the plan
6. **Implement**: Follow the spec strictly - do not add unrequested features

### When reviewing or drafting specs:

- Ensure requirements are testable and unambiguous
- Identify missing edge cases
- Flag any contradictions or unclear points
- Keep scope minimal - specs should describe one coherent feature

### Spec file locations:

- `specs/TEMPLATE.md` - Template for new specs
- `specs/active/` - Specs currently being worked on
- `specs/done/` - Completed specs (reference only)

## Documentation

- **README.md must be updated after each change** (new features, commands, options, defaults, etc.)
- **docs/USAGE.md must be updated** when commands, flags, installation steps, or walkthroughs change
- **docs/SCHEMA.md must be updated** when output format, fields, or envelope structure changes
- Include usage examples and option descriptions
- Update docs before committing

## Commands

```bash
lake build                 # Build the project
lake build tests           # Build tests
.lake/build/bin/tests      # Run tests
probe-lean extract <PATH>  # Combined atomize+sorry detection → unified atoms
probe-lean viewify <PATH>  # Filter extract output → molecules for web UI
```

## Testing

- Tests are in `Tests/Main.lean`
- **Tests must be added** for each new feature
- Run tests before committing
- All tests must pass before merging

## Build Performance

Lean 4's `do` notation desugars each monadic bind (`x ← ...`) into a nested `>>= fun ... =>` call. The elaborator's type-checking cost grows superlinearly with nesting depth — a single function with 100+ binds can take **10+ minutes** to compile, while the same tests split across small functions compile in **under 2 seconds**.

**Rules for fast builds:**

1. **Never put more than ~30 monadic binds in a single `do` block.** If a function is growing past this, extract a helper.
2. **Tests/Main.lean uses one function per test section.** When adding tests, either add to an existing section function or create a new `testXxx` function and call it from `main`.
3. **`main` must stay flat** — just a chain of `result ← testXxx result` calls, not inline test logic.
4. **Never add `set_option maxRecDepth`** to work around slow compilation. If you need it, the `do` block is too deep — split it instead.

## Running extract on target projects

When running `probe-lean extract` on a target project (e.g., `curve25519-dalek-lean-verify`):

1. **Download Mathlib cache first**: `cd <target-project> && lake exe cache get` — this downloads pre-built `.olean` files for Mathlib and saves hours of compilation.
2. **Run extract**: `probe-lean extract <target-project>` — builds, extracts atoms, detects sorries. The build step is automatically skipped when the cache is up-to-date.

The toolchain versions must match between probe-lean and the target project (both currently use `v4.28.0-rc1`).

## Versioning

The version is defined **once** in `lakefile.toml` and generated into `ProbeLean/Version.lean` by `tools/gen-version.sh`. After bumping the version in `lakefile.toml`, run `./tools/gen-version.sh` and commit both files. CI checks they stay in sync.

Do **not** hardcode version strings anywhere else — use `ProbeLean.version` (or `Constants.toolVersion` which references it).

**When to bump the version:** Bump the minor version in `lakefile.toml` (and regenerate) when a release includes new features, changed output format, or breaking changes to the CLI or installer. Patch bumps are for bug fixes only. Update `CHANGELOG.md` with the new version entry before committing. Tag the commit with `v<version>` to trigger the release workflow.

## Architecture

### Extract pipeline

`probe-lean extract` runs: **build → atomize → specs → sorry detection → merge → enrich → envelope → write**

- `ProbeLean/Analysis.lean` — Core analysis: walks Lean environment, extracts dependencies (type vs term)
- `ProbeLean/Atomize.lean` — Converts declarations to `Atom` structs, applies filtering flags
- `ProbeLean/NixEnv.lean` — Nix environment detection (`NixMode`, `detectNixShell`, `isNixAvailable`)
- `ProbeLean/Environment.lean` — Lake project detection, subprocess commands (`runCmd`, `runLakeCmd`), build cache
- `ProbeLean/VerifyInternal.lean` — Parses sorry warnings from build output
- `ProbeLean/Extract.lean` — Orchestrates the pipeline, produces `UnifiedAtom` output
- `ProbeLean/Transitive.lean` — Reverse-BFS contamination for `transitively-verified` status enrichment
- `ProbeLean/Version.lean` — Single version constant, generated from `lakefile.toml`
- `ProbeLean/Types.lean` — All data structures and JSON serialization
- `ProbeLean/View.lean` — `viewify` command (filters atoms → molecules for web UI)

### Key design decisions

- **No `specified` field**: Whether an atom has specifications is inferred from `specs != []` (aligns with probe-verus v5.0.0)
- **`dependencies` = union of `type-dependencies` + `term-dependencies`**: Kept for backward compatibility
- **`specs`**: Reverse dependency — for a non-theorem atom, lists theorem atoms that depend on it
