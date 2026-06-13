# probe-lean

Analyze Lean 4 projects: extract dependency graphs with verification status and spec relationships.

`probe-lean` walks the Lean environment of a built project and produces structured JSON describing every declaration, its dependencies (type and term), source locations, sorry-based verification status, and spec relationships. Output follows the Schema 2.0 envelope format; see [docs/SCHEMA.md](docs/SCHEMA.md) for the full specification.

## Prerequisites

- **Lean 4 toolchain** (`elan`, `lake`) -- install via [elan](https://github.com/leanprover/elan#installation)
- The target project must build with `lake build`
- **Toolchain match**: probe-lean must be installed for the same Lean version as the target project (`.olean` files are version-specific). Check with `cat <target-project>/lean-toolchain`.
- For large projects using Mathlib, run `lake exe cache get` in the target project first to download pre-built `.olean` files

## Supported Projects

probe-lean can analyze any Lean 4 project that meets these requirements:

| Requirement | Detail |
|-------------|--------|
| **Lean version** | **≥ v4.28.0-rc1** — the `.olean` binary format is not compatible across Lean versions, and probe-lean cannot be built for older toolchains |
| **Buildable Lean libraries** | probe-lean only needs the `.olean` files from `lake build <lib>`. If the Lean library targets compile but the final executable linking fails (e.g., missing GPU drivers), extraction can still succeed — use `--library <lib>` to build only the library |

### Projects with native dependencies

Some Lean projects depend on system-level C/C++ libraries (Vulkan, CUDA, OpenSSL, etc.) via FFI. probe-lean does not manage these dependencies — **the project's own build must succeed before probe-lean can analyze it.**

- **Check the project's docs first.** Look for a `shell.nix`, `flake.nix`, `Dockerfile`, or README section listing required system packages. These are the authoritative source for what needs to be installed.
- **Nix environments are auto-detected.** If the target project ships a `shell.nix` or `flake.nix`, probe-lean wraps `lake` commands inside the Nix shell so that system dependencies are available automatically. This requires `nix-shell` or `nix` to be installed on your system.
- **Without Nix, install deps manually.** You'll need to install the project's system dependencies yourself (e.g., `apt install libvulkan-dev`). If `lake build` fails with missing headers or libraries, those errors come from the project's build system, not from probe-lean.
- **Pre-build the project separately.** For complex projects, run `lake build` (or `lake build <lib>`) inside the target project directory first. Once the Lean modules are compiled, `probe-lean extract` will detect the up-to-date build cache and skip the build step.

### What won't work

- **Projects on Lean < v4.28.0-rc1** — probe-lean uses stdlib APIs introduced in v4.28; there are no pre-built binaries for older versions, and source builds will fail
- **Projects whose Lean libraries don't compile** — if `lake build <lib>` can't produce `.olean` files, extraction cannot proceed. Note: linking failures for executables don't matter if the library targets succeed
- **Toolchain mismatches** — even a patch-level difference (e.g., v4.28.0-rc1 vs v4.29.0) requires a matching probe-lean build. Use the installer's `--from-project` flag to auto-install the right version

## Installation

No git clone required — the installer downloads a pre-built binary directly from GitHub releases.

### Quick install (recommended)

Auto-detect the Lean version from a target project:

```bash
curl -sSfL https://raw.githubusercontent.com/Beneficial-AI-Foundation/probe-lean/main/tools/bash/install.sh \
  | bash -s -- --from-project ./my-lean-project
```

Or specify a Lean version explicitly:

```bash
curl -sSfL https://raw.githubusercontent.com/Beneficial-AI-Foundation/probe-lean/main/tools/bash/install.sh \
  | bash -s -- --lean-version v4.28.0-rc1
```

Ensure `~/.local/bin` is in your `PATH`:
```bash
export PATH="$PATH:$HOME/.local/bin"
```

For all installer options (`--force`, `--lean-version`, cloned-repo usage, etc.), see **[docs/USAGE.md](docs/USAGE.md#installer-flags)**.

### Docker

```bash
docker build --build-arg LEAN_VERSION=v4.28.0-rc1 -t probe-lean .
docker run --rm -v /path/to/project:/project probe-lean extract /project
```

The Docker image downloads the pre-built binary during build — no repository clone needed.

### GitHub Actions

For CI integration in downstream repos:

```yaml
- uses: Beneficial-AI-Foundation/probe-lean/action@main
  with:
    project-path: .
```

The action auto-detects the Lean version, builds probe-lean, and runs extraction. See [action/action.yml](action/action.yml) for all options.

## Quick Start

```bash
# Analyze a Lean project (builds with lake, extracts atoms, detects sorries)
probe-lean extract ./my-lean-project

# Skip sorry detection (faster, graph structure only)
probe-lean extract ./my-lean-project --skip-verify

# Multi-library project: build only specific libraries
probe-lean extract ./my-lean-project --library "Extraction,Spqr"
```

Output lands in `<target-project>/.verilib/probes/lean_<pkg>_<ver>.json` by default.

For Mathlib cache setup, Nix/FFI projects, and real-project walkthroughs, see **[docs/USAGE.md](docs/USAGE.md)**.

## Commands

| Command | Description |
|---------|-------------|
| `extract` | Analyze a Lean 4 project: extract atoms, detect sorries, compute specs |

### `extract`

```bash
probe-lean extract <PROJECT_PATH> [OPTIONS]
```

| Option | Description |
|--------|-------------|
| `-o, --output <PATH>` | Output file path (default: `.verilib/probes/lean_<pkg>_<ver>.json`) |
| `-m, --module <PREFIX>` | Filter to specific module prefix |
| `-l, --library <LIBS>` | Comma-separated list of library names to build (default: `defaultTargets` from `lakefile.toml`, falling back to all `[[lean_lib]]` entries) |
| `--skip-verify` | Skip sorry detection (graph structure only) |
| `--from-file <FILE>` | Use existing build output for sorry detection |
| `--skip-enrich` | Skip transitive verification enrichment (no `"transitively-verified"` status) |

For the full command reference with examples, see **[docs/USAGE.md](docs/USAGE.md)**. For the complete JSON schema specification, see **[docs/SCHEMA.md](docs/SCHEMA.md)**.

## Example Output

Running `probe-lean extract` produces a JSON envelope. Each entry in `data` describes a declaration and its dependencies:

```json
{
  "schema": "probe-lean/extract",
  "schema-version": "2.0",
  "tool": { "name": "probe-lean", "version": "0.7.0", "command": "extract" },
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

## How It Works

1. **Build** -- reads `defaultTargets` from `lakefile.toml` (falling back to all `[[lean_lib]]` entries) and runs `lake build <lib1> ...` to produce `.olean` files (automatically skipped when build cache is up-to-date; overridable via `--library`)
2. **Atomize** -- walks the Lean environment, extracts declarations with type and term dependencies
3. **Filter** -- applies config-based flags (`is-hidden`, `is-extraction-artifact`, `is-ignored`, `is-relevant`)
4. **Specs** -- computes reverse theorem edges (`specs`, `primary-spec`) for each atom using a multi-signal precedence chain:
    1. `@[primary_spec]` attribute (always wins; requires `import ProbeLean.Attrs` in the target project)
    2. Known verification-framework attributes (`@[progress]`, `@[pspec]`, `@[step]`) — if exactly one spec theorem carries one of these, it becomes primary spec; ambiguous when multiple match
    3. `_spec` suffix — a theorem named `<def>_spec` is assigned as primary spec
    4. Sole spec — if a definition has exactly one spec theorem, it is used as primary spec
5. **Verify** -- parses sorry warnings from build output to determine verification status (shallow: checks only the declaration's own body, not its dependencies); axioms, declarations tagged `@[externally_verified]`, and non-theorem `*External.lean` declarations are marked `"trusted"` with a `trusted-reason` (`"axiom"`, `"externally_verified"`, or `"external"`) for trust-base classification; theorems in `*External.lean` without `@[externally_verified]` carry real proofs and receive their normal verification status; declarations without source location (kernel-synthesized) are filtered from output (skippable via `--skip-verify`)
6. **Enrich** -- upgrades `"verified"` atoms to `"transitively-verified"` when all transitive dependencies are verified or trusted, using reverse-BFS contamination (matching `probe-verus`/`probe-aeneas`; skippable via `--skip-enrich`)
7. **Schema 2.0 output** -- wraps atoms in a metadata envelope with git commit, package info, and timestamps

## How probe-lean decides what to analyze

probe-lean never reads your `.lean` source files to decide what to extract — it
works entirely from the **lakefile and the compiled `.olean` build artifacts**.
Knowing this is the difference between a correct run and a silently incomplete
one.

**Where the library list comes from** (in priority order):

1. `--library <L1,L2,...>` if you pass it (explicit override).
2. otherwise `defaultTargets` from `lakefile.toml`.
3. otherwise all `[[lean_lib]]` entries in `lakefile.toml`.

probe-lean then runs `lake build <those libs>`, collects **every `.olean` under
`.lake/build/lib/lean`**, keeps the modules that **belong to the selected
libraries** (a module `A.B` belongs to library `A`), optionally narrows further
with `--module <prefix>`, and imports all surviving modules into a **single Lean
environment** before atomizing.

**Assumptions this bakes in — and how they bite:**

- **A library you want extracted must be *selected*, not merely *built*.** If
  library `A` is a default target and depends on library `B`, `lake build A`
  compiles `B` too — but `B`'s modules are filtered out of the output because
  `B` isn't in the selected set. **If a needed library is only a dependency of a
  default target, list it in `defaultTargets` or pass it via `--library`.**
  (Example: a project that moves Aeneas-generated code into its own `lean_lib`
  for linting must still add that lib to `defaultTargets`, or its atoms vanish
  from the output with no error.)
- **All selected modules must be mutually importable.** Two modules may not
  declare the same fully-qualified name, or the import aborts with
  `environment already contains '<name>' from <module>`.
- **Module discovery trusts the build directory, not git.** Because it scans
  `.olean` files on disk, **orphan artifacts from modules you deleted or renamed
  are still picked up until you `lake clean`.** An orphan that re-declares a
  symbol is the most common cause of the duplicate-declaration import failure
  above. When in doubt after a refactor, `lake clean` first.

> Improving the first and third points (auto-including the dependency closure of
> the selected libraries, and ignoring stale orphan oleans) is tracked in
> [#40](https://github.com/Beneficial-AI-Foundation/probe-lean/issues/40).

## Testing

```bash
lake build tests
.lake/build/bin/tests
```

## Versioning

The version is defined once in `lakefile.toml` and propagated everywhere via `ProbeLean/Version.lean`:

```
lakefile.toml  →  tools/gen-version.sh  →  ProbeLean/Version.lean
                                              ↓
                                         Constants.toolVersion  (JSON output)
                                         CLI --version          (Main.lean)
```

After bumping the version in `lakefile.toml`, run:

```bash
./tools/gen-version.sh
```

CI verifies the generated file stays in sync.

## License

Apache-2.0
