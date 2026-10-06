# Usage Guide

## Prerequisites

- A Lean 4 toolchain (`elan`, `lake`). Install it with [elan](https://github.com/leanprover/elan#installation).
- `~/.local/bin` in your `PATH` (the installer puts the binary there).
- A target project that builds with `lake build`.

## Installation

You do not need to clone the repository. The installer downloads a pre-built binary from GitHub Releases.

Detect the Lean version from the target project (recommended):

```bash
curl -sSfL https://raw.githubusercontent.com/Beneficial-AI-Foundation/probe-lean/main/tools/bash/install.sh \
  | bash -s -- --from-project ./my-lean-project
```

Give the Lean version explicitly:

```bash
curl -sSfL https://raw.githubusercontent.com/Beneficial-AI-Foundation/probe-lean/main/tools/bash/install.sh \
  | bash -s -- --lean-version v4.28.0
```

The version can also be a positional argument (`install.sh v4.28.0`). If you give no version and no `--from-project`, the installer lists recent Lean releases and asks you to pick one.

In a clone of the repository, run the scripts directly. The Python installer accepts the same flags and arguments:

```bash
./tools/bash/install.sh --from-project ../my-lean-project
uv run tools/python/install.py --from-project ../my-lean-project
```

The installer searches the probe-lean releases, newest first, and downloads the first asset that matches the Lean version and platform. If no release has a matching asset, or the download fails, it builds probe-lean from source. The source build uses the repository you run the script from, or a clone in `~/.local/src/probe-lean`. A source build needs `elan`.

The binary goes to `~/.local/bin/probe-lean-<version>`, with a symlink at `~/.local/bin/probe-lean`. The `.olean` files probe-lean needs go to `~/.local/lib/probe-lean-<version>/`.

Check the installation:

```bash
probe-lean --version
```

### Installer flags

| Flag | Description |
|------|-------------|
| `--from-project <path>` | Detect the Lean version from the project's `lean-toolchain`. If `<path>` has no top-level `lean-toolchain`, the installer searches below it (excluding `.lake`) and uses the toolchain it finds. When the Lean package is in a subfolder (for example `cedar-spec/cedar-lean`), you can point at the monorepo root. If the toolchain files disagree on the version, the installer lists them and stops. Use `--lean-version` in that case. |
| `--lean-version <ver>` | Explicit Lean version (for example `v4.28.0`). Same as the positional `VERSION` argument. |
| `--force` | Reinstall an installed version. |
| `-h`, `--help` | Show the help message. |

### Toolchain version matching

You must install probe-lean for the same Lean version as the target project. `.olean` files are version-specific and do not load across versions.

Each Lean version gets its own binary, `~/.local/bin/probe-lean-<version>`, so several versions can coexist. The `probe-lean` symlink points to the version of the last installer run.

### Pre-built binary availability

The release workflows publish binaries for `linux-x86_64` and `darwin-arm64`. They cover these Lean versions:

- every stable release from `v4.28.0-rc1` on
- the latest release candidate of each line that has no stable release
- each version pinned in [`tools/lean-version-extras.txt`](../tools/lean-version-extras.txt)

Each version also needs a compatible tag in [`leanprover/lean4-cli`](https://github.com/leanprover/lean4-cli).

`lean4-cli` does not tag every patch release, so probe-lean builds against the highest tag in the same `major.minor` line. For example, Lean `v4.32.2` builds against `lean4-cli v4.32.0`. If a Lean `major.minor` line has no `lean4-cli` tag yet, the release workflows skip its versions. A daily workflow adds binaries for new Lean versions.

A superseded release candidate that is not pinned is not rebuilt. The installer then finds it only on an old probe-lean release, and installs that old probe-lean version. To get the current probe-lean for such a toolchain, add the version to `tools/lean-version-extras.txt`.

To raise the GitHub API rate limit during the release search, set `GH_TOKEN` or `GITHUB_TOKEN`.

---

## Commands

### `extract`

Analyze a Lean 4 project: extract atoms, compute specs, detect sorries, and write the unified output.

```
probe-lean extract <PROJECT_PATH> [OPTIONS]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--output <PATH>` | `-o` | Output file path (default: `.verilib/probes/lean_<pkg>_<ver>.json`). |
| `--module <PREFIX>` | `-m` | Filter to a module prefix. The kernel walk still imports every built project module, so a narrow selection is not faster than a full run. |
| `--library <LIBS>` | `-l` | Comma-separated library names to build and restrict analysis to. probe-lean keeps the modules whose names start with one of these library roots. Without the flag, the build uses `defaultTargets` from `lakefile.toml` (or all `[[lean_lib]]` entries), and all built modules are analyzed. The detected targets are not a module filter, because `defaultTargets` can name a `lean_exe` and a library can declare custom `roots`. |
| `--skip-verify` | | Omit `verification-status`. Trusted atoms keep it (`"trusted"`). |
| `--from-file <FILE>` | | Use existing build output for the build-log cross-check instead of the captured `lake build` output. |
| `--skip-enrich` | | No upgrade to `"transitively-verified"` (clean atoms read `"verified"`). The graph cross-check does not run. |

#### Co-importability preflight

Before the import, `extract` reads each built module's declarations from its `.olean` header. If two modules declare the same fully-qualified name, `extract` stops and lists the names and their modules (see "Co-importability check failed" under Troubleshooting).

With `--module` or `--library`, `extract` first tries to import all built project modules, because the kernel walk needs the whole project. If that fails, it imports the selection only and prints `Warning: <n> project module(s) not imported (full import failed); ...`. The modules left out are outside the selection's import closure, so no emitted status depends on them. `check-axioms` does not audit them.

Lean accepts two modules that restate a theorem with the same name and statement, and keeps one proof. `extract` and `check-axioms` print a `Warning:` or `Note:` line for such merged declarations. The policy is in [verification-status.md](verification-status.md), section "Merged declarations".

#### Verification status

A kernel walk over every constant of every built project module decides `verification-status`. The walk does not use the build log or the emitted dependency graph. It stops at the project boundary. For a member of the trusted base (axioms, the `externally_verified` tag set, and non-proofs in `*External` modules), it follows the statement and not the proof. A `sorry` in the proof of a trusted declaration does not taint its callers. A `sorry` behind its statement does. The walk prints its totals:

```
Project constants: 11293 in 231 module(s) | trusted: 149 | direct sorry carriers: 3 | tainted: 112
externally_verified tag set: 2 name(s) from externallyVerifiedAttr
```

Lean and every package in `lake-manifest.json` are trusted as a whole. This includes a second Lake package that holds the project's own code. Move such code into the main package to have it analyzed. Two cross-checks (build log and emitted graph) print `Divergence` and `Note` lines on stderr but never change a status.

[verification-status.md](verification-status.md) explains how the walk decides and what each stderr line means, including the section "Coverage of P". [schema.md](schema.md), section "Verification status and the trusted base", defines the status values. An atom that reads `"verified"` because a project `sorry` is reachable from it carries `"status-origin": "kernel-taint"`. A tool that recomputes statuses from the dependency arrays must not promote such an atom or its callers (see [schema.md](schema.md), section "Re-deriving statuses").

To check an artifact against the `check-axioms` report in both directions, run `tools/audit/check-status-consistency.py .verilib/probes/lean_*.json check-axioms.out`. See [tools/audit/README.md](../tools/audit/README.md).

#### Module-system and stale oleans

`extract` imports a module-system module (`module` header) from its `.olean.private` part, so it sees the proofs of its `public theorem`s. If such a module has no split parts, `extract` stops before the import and asks you to rebuild. `extract` ignores a stale `.olean` that has no backing `.lean` source. If a live module imports such an `.olean`, `extract` stops. In that case, run `lake clean` in the target project and rebuild.

#### Other atom fields

`extract` folds auxiliary dependency edges (`X._proof_N`, `X.match_N`, and similar) into the declaration that references them. It adds to `term-dependencies` only and prints an `Auxiliary fold: ...` summary on stdout. The contract is in [schema.md](schema.md), section "Auxiliary-dependency folding".

The codomain facts, `is-primary-spec`, and the hiding of generated code are also defined in [schema.md](schema.md).

### `check-axioms`

Audit a Lean 4 project. `check-axioms` runs the same kernel walk that `extract` uses for `verification-status`. It lists every project constant that rests on an unexcused project `sorry`, atoms and non-atoms alike.

```
probe-lean check-axioms <PROJECT_PATH> [OPTIONS]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--module <PREFIX>` | `-m` | Restrict which constants count as emitted (the `[not emitted]` marker). The walk always covers every built module it can import. |
| `--library <LIBS>` | `-l` | Comma-separated library names to build and restrict the emitted set to. |

Output on `tests/fixtures/aux-fold` (shortened, the full report has one line per listed constant):

```
Project constants: 126 in 9 module(s) | trusted: 13 | direct sorry carriers: 16 | tainted: 31
externally_verified tag set: 7 name(s) from externallyVerifiedAttr
31 constant(s) rest on an unexcused project sorry:
  admittedFact [direct]
  extThm [direct]
  instReprTagged
  loopy._unsafe_rec [direct] [not emitted]
  noRangeMid [direct] [not emitted]
  stmtAx
  tacticUse._proof_1 [not emitted]
  viaNoRange
  ...
13 trusted constant(s) (T):
  Box [externally_verified] Demo.Trust
  externalOp [external] Demo.FunsExternal : Nat
  externalPred [external] Demo.FunsExternal : Prop
  stmtAx [axiom] Demo.StmtTaint [statement tainted]
  vouched [externally_verified] Demo.Trust
  ...
```

`[direct]` means the constant's own type or value names `sorryAx`. For a trusted constant only its type counts. `[not emitted]` means the constant is not an atom. The listed atoms are exactly those that `extract` marks `"verified"` or `"unverified"`. No `"transitively-verified"` atom appears here.

The trusted base T follows as `<name> [<trusted-reason>] <module>`. A rule-3 (`external`) model also shows its statement. ` [statement tainted]` marks a member of T whose statement rests on a project `sorry`: it is also in the tainted list, and its atom does not read `"trusted"`. Use this list to review what the "clean modulo T" claim rests on. `extract` shows only the trusted constants that are atoms. Both commands also print a `Note(axiom): ...` line for generated project axioms, such as those from `native_decide`. [verification-status.md](verification-status.md), section "Kernel dependencies, not executable bodies", explains why they stay trusted.

The walk is memoized and stops at the project boundary and at the proofs of the trusted base. It takes about a second on a 230-module project that depends on Mathlib. `-m` and `-l` do not make it smaller.

### `viewify`

Filter an existing `extract` output into molecules for the web UI. No build or import runs.

```
probe-lean viewify <PROJECT_PATH> [OPTIONS]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--with-atoms <FILE>` | `-a` | Path to the `extract` output (default: auto-detected under `.verilib/probes/`). |
| `--output <PATH>` | `-o` | Output file path (default: `.verilib/views/molecules_all.json`). |

`viewify` keeps an atom as a molecule only when all of these are true:

- It is not hidden.
- It is not lean- or aeneas-generated.
- It is relevant.
- Its `code-path` ends with `Funs.lean`.

[schema.md](schema.md), section "Molecules (`probe-lean/viewify`)", lists the molecule fields.

---

## Mathlib cache

Most Lean verification projects depend on [Mathlib](https://github.com/leanprover-community/mathlib4). A Mathlib build from source takes hours. Mathlib publishes pre-built `.olean` files that download in minutes.

`extract` and `check-axioms` download this cache for you. Before they run `lake build`, they check for a Mathlib dependency in `lake-manifest.json` without a built `Mathlib.olean`. If they find one, they run `lake exe cache get` and print:

```
Mathlib dependency detected but no pre-built cache found.
Running `lake exe cache get` to download pre-built .olean files...

  ✓ Mathlib cache downloaded
```

If the download fails, probe-lean prints a warning and continues, and `lake build` then compiles Mathlib from source. To avoid that, stop the run and download the cache yourself:

```bash
cd <target-project>
lake exe cache get
```

---

## Walkthrough

### [curve25519-dalek-lean-verify](https://github.com/Beneficial-AI-Foundation/curve25519-dalek-lean-verify)

An Aeneas-generated Lean translation of the curve25519-dalek Rust crate, with Mathlib-based specifications and proofs. Its `lakefile.toml` declares the libraries `Curve25519Dalek` and `Utils`, with `defaultTargets = ["Curve25519Dalek"]`.

```bash
# 1. Install probe-lean for the project's Lean version
curl -sSfL https://raw.githubusercontent.com/Beneficial-AI-Foundation/probe-lean/main/tools/bash/install.sh \
  | bash -s -- --from-project ./curve25519-dalek-lean-verify

# 2. Run extract
cd curve25519-dalek-lean-verify
probe-lean extract .
```

With `--from-project`, the installer picks the binary from the project's `lean-toolchain`. `extract` reads `defaultTargets` and builds only `Curve25519Dalek`. The same two commands work for other projects.

### Projects with `lakefile.lean`

Some projects, such as [VCV-io](https://github.com/Verified-zkEVM/VCV-io), use `lakefile.lean` instead of `lakefile.toml`. probe-lean cannot read library names from `lakefile.lean`. It runs `lake build` with no explicit targets, which builds the project's `@[default_target]` targets.

### Fresh machine

On Ubuntu or Debian:

```bash
# Install elan (Lean version manager)
curl -sSf https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh | sh
source ~/.profile

# Install probe-lean for the target project's Lean version
curl -sSfL https://raw.githubusercontent.com/Beneficial-AI-Foundation/probe-lean/main/tools/bash/install.sh \
  | bash -s -- --from-project ./my-lean-project

# Put ~/.local/bin in PATH and check the installation
export PATH="$PATH:$HOME/.local/bin"
probe-lean --version

# Run extract on the target project
cd my-lean-project
probe-lean extract .
```

---

## Performance

### Build cache

If its saved build output is newer than every `.lean` file, `lean-toolchain`, `lakefile.toml` and `lakefile.lean` in the project, `extract` skips `lake build`. The kernel walk reads the `.olean` files, so it does not need a fresh build log. Only the build-log cross-check then uses the saved output.

### `--skip-verify`

`--skip-verify` leaves `verification-status` off every atom except the ones that read `"trusted"`. The kernel walk still runs and prints its summary, so the flag saves only the build-log cross-check. The flag is for consumers that must not see statuses. It does not make the run faster:

```bash
probe-lean extract ./my-project --skip-verify
```

### `nice` on shared machines

`lake build` for a Mathlib-dependent project can use all CPU cores for a long time. To keep the machine responsive, run at low priority:

```bash
nice -n 15 probe-lean extract <target-project>
```

`nice -n 19` is the lowest priority.

### One module

To iterate on one module:

```bash
probe-lean extract ./my-project -m MyProject.Core
```

The output then holds only atoms from that module prefix. The run is not faster, because the kernel walk imports every built module.

---

## Output format

[schema.md](schema.md) defines the output format and has an example envelope. [examples/lean_ExampleProject_0.1.0.json](../examples/lean_ExampleProject_0.1.0.json) is a complete example file.

---

## Configuration

probe-lean reads the atom filtering flags from the project's `.verilib/probes/config.json`:

- `is-hidden`: `true` if the atom name (without the `probe:` prefix) appears in `is-hidden`.
- `is-aeneas-generated`: `true` if the atom name ends with a suffix in `extraction-artifact-suffixes`. `extract` also sets it (with `is-hidden`) on the companion theorems that `@[step]` generates (`X.mvcgen_spec`).
- `is-ignored`: `true` if the atom name appears in `is-ignored`.

`is-relevant` comes from `relevant-crate` and the atom's `rust-source` field:

- If `relevant-crate` is not set: `true` for every atom.
- If `rust-source` exists: `true` if it contains the crate name, does not start with `/`, and does not contain `/cargo/registry/`.
- Otherwise: `false`.

Example `.verilib/probes/config.json`:

```json
{
  "relevant-crate": "my-crate-name",
  "extraction-artifact-suffixes": ["_body", "_loop", "_loop0", "_loop1"],
  "is-hidden": ["MyModule.internalHelper", "MyModule.derivedInstance"],
  "is-ignored": ["MyModule.testHelper", "MyModule.debugFunction"]
}
```

---

## Troubleshooting

### Build takes hours

If the automatic cache download fails (see "Mathlib cache" above), `lake build` compiles Mathlib from source. Run `lake exe cache get` in the target project.

### "Co-importability check failed"

Lake compiles each module on its own, so a project can build even if two modules declare the same fully-qualified name. probe-lean imports all built modules into one Lean environment, and Lean forbids duplicate declarations there.

probe-lean finds the duplicates before the import and lists them with their modules. Lakefile grouping does not help: `defaultTargets` and `[[lean_lib]]` splits change only what is built, and probe-lean analyzes every built `.olean` on disk.

Fixes, best first:

1. Restructure the project. Give each variant family its own namespace, or make the dependent module `import` the shared module instead of restating its definitions. This is the only fix for automated consumers such as verilib, which cannot pass per-project flags.
2. For manual runs only, extract a subset with no conflict using `--module`, for example `probe-lean extract . --module H1.solution`. `--module` selects the named module and its submodules, so for a clash between a root and its submodule, name the deepest module. `--library` matches module-name roots, not lakefile library names, so it usually cannot separate this kind of split.

### "environment already contains '...'" after you rename or delete a file

An orphan `.olean` from the old module is still on disk (Lake does not remove oleans of deleted or renamed sources). It declares a name that another module now owns. probe-lean drops orphan oleans by checking each module for its `.lean` source, but a live module can still import the orphan. Run `lake clean && lake build` in the target project, then run `extract` again.

### Live modules listed as orphans

probe-lean looks for a module's `.lean` source under the project root and under each `srcDir` declared in `lakefile.toml`. It does not read `lakefile.lean`. If a `lakefile.lean` library has a custom `srcDir`, probe-lean does not find the sources of its modules. It lists them under `Ignoring <n> orphan module(s)` and leaves them out of the analysis. If a kept module imports one of them, `extract` stops with `stale module(s) with no .lean source were imported by a live module`. `lake clean` does not fix this. Move the sources to the default root, or declare the library in `lakefile.toml` with its `srcDir`.

### "Failed to import modules"

The `.olean` files are stale or come from a different toolchain version. Clean and rebuild:

```bash
cd <target-project>
rm -rf .lake
lake exe cache get    # if the project depends on Mathlib
lake build
```

### Toolchain mismatch

If you see `.olean` version errors, reinstall probe-lean for the target project:

```bash
curl -sSfL https://raw.githubusercontent.com/Beneficial-AI-Foundation/probe-lean/main/tools/bash/install.sh \
  | bash -s -- --force --from-project <target-project>
```

### Output location

By default, `extract` writes `<target-project>/.verilib/probes/lean_<pkg>_<ver>.json`:

```
.verilib/
└── probes/
    └── lean_<pkg>_<ver>.json     # extract output (unified atoms)
```

Use `-o <path>` to write somewhere else.
