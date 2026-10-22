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
| `--force` | Reinstall an installed version. Without it, the installer keeps the installed binary. If the newest release has a newer build, the installer warns. |
| `-h`, `--help` | Show the help message. |

### Toolchain version matching

You must install probe-lean for the same Lean version as the target project. `.olean` files are version-specific and do not load across versions.

Each Lean version gets its own binary, `~/.local/bin/probe-lean-<version>`, so several versions can coexist. The `probe-lean` symlink points to the version of the last installer run.

### Pre-built binary availability

The release workflows publish binaries for `linux-x86_64` and `darwin-arm64`. CI tries to build every Lean release and release candidate from `v4.28.0-rc1` on. Each version also needs a compatible tag in [`leanprover/lean4-cli`](https://github.com/leanprover/lean4-cli).

`lean4-cli` does not tag every patch release, so probe-lean builds against the highest tag in the same `major.minor` line. For example, Lean `v4.32.2` builds against `lean4-cli v4.32.0`. If a Lean `major.minor` line has no `lean4-cli` tag yet, the release workflows skip its versions. A daily workflow adds binaries for new Lean versions to the newest probe-lean release. It builds the source of that release, so a fix for a new Lean version gets a binary only with the next release.

A build attempt is not a promise. A Lean version has one of three outcomes:

- The build passes. The newest probe-lean release has the binary.
- The build fails. If an older release has a binary for that version, the installer installs that older probe-lean. Otherwise it builds from source.
- The version has no compatible `lean4-cli` tag. CI skips it.

The daily workflow lists failed builds in an open issue with the label `lean-build-failure`. That issue does not list skipped versions.

A GitHub Actions matrix holds at most 256 jobs, which is 128 Lean versions on two platforms. If the list grows past 128 versions, the release workflows stop with an error. To fix this, raise `LEAN_VERSION_FLOOR` in `tools/lean-versions.sh`.

The installers warn on stderr about an old probe-lean build. The warnings do not stop the installer and do not change its exit code.

- The downloaded binary can come from an older release than the newest release. Then the installer names both releases. It also gives the reason that the newest release has no binary.
- A binary for the Lean version can already be installed. If you do not set `--force`, the installer compares its version with the newest release. If the newest release has a binary for the Lean version, the warning tells you to rerun with `--force`. Otherwise the warning gives the reason that the newest release has no binary.
- If the release search cannot read the newest release, for example because of the rate limit, the installer prints no version warning. The newest release is on the first page of the release list. If a later page fails, the bash installer still warns, because the warning needs only the newest release. An HTTP error status on any page stops the Python installer search, and the Python installer then prints no warning.

For example, a rerun without `--force` over probe-lean 0.9.4 for Lean `v4.28.0-rc1` prints:

```text
Warning: the installed probe-lean-v4.28.0-rc1 is version 0.9.4. The newest release is v0.19.0.
         Rerun the installer with --force to update it.
```

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
| `--module <PREFIX>` | `-m` | Import and emit only the project modules whose name is `<PREFIX>` or starts with `<PREFIX>.` (compared by name component). The prefix filters every project module that the target modules import, not only the modules that the lakefile lists, so a submodule of a library with the default glob matches. The kernel walk covers the import closure of the matching modules. If no project module matches, the run fails. For a module of a library that no target imports, use `--library` or `--all-libraries`. |
| `--library <LIBS>` | `-l` | Comma-separated `lean_lib` names. probe-lean builds these libraries and emits the project modules that they own. An unknown name or a `lean_exe` name is an error. |
| `--all-libraries` | | Build every `lean_lib` of the root package and emit every project module that the import loads. Executables are not built. Cannot be used with `--library`. |
| `--skip-verify` | | Omit `verification-status` and `assumptions`. Trusted atoms keep their status (`"trusted"`). |
| `--skip-enrich` | | No upgrade to `"transitively-verified"` (clean atoms read `"verified"`). Generated atoms stay hidden. |

Without `--library` and `--all-libraries`, the targets are the `defaultTargets` of the lakefile. probe-lean skips a default target that is not a `lean_lib` or a `lean_exe`, and prints a note. Without `defaultTargets`, the targets are every `lean_lib`. A library that no target imports, for example a test or docs library, is not reported. Use `--all-libraries` or `--library` for it.

probe-lean builds the targets on every run, a library as `lake build <lib>:leanArts` and an executable as its root module, `lake build +<root>`. So the build does not depend on the library's `defaultFacets`, and no executable is linked. It reads the workspace with Lake's own loader, in a hidden subcommand under `lake env`, so it reads `lakefile.toml` and `lakefile.lean` the same way.

#### Co-importability preflight

Before the import, `extract` reads the declarations of each project module of the import closure from its `.olean` header. If two modules declare the same fully-qualified name, `extract` stops and lists the names and their modules (see "Co-importability check failed" under Troubleshooting).

Lean accepts two modules that restate a theorem with the same name and statement, and keeps one proof. `extract` and `check-axioms` print a `Warning:` or `Note:` line for such merged declarations. The policy is in [verification-status.md](verification-status.md), section "Merged declarations".

#### Verification status

A kernel walk over every constant of every project module that the import loads (the set P) decides `verification-status`. The walk does not use the build log or the emitted dependency graph. It stops at the project boundary. For a member of the trusted base (axioms, the `externally_verified` tag set, and non-proofs in `*External` modules), it follows the statement and not the proof. A `sorry` in the proof of a trusted declaration does not taint its callers. A `sorry` behind its statement does. The walk prints its totals:

```
Project constants: 11293 in 231 module(s) | trusted: 149 | direct sorry carriers: 3 | tainted: 112
externally_verified tag set: 2 name(s) from externallyVerifiedAttr
```

Lean and every package in `lake-manifest.json` are trusted as a whole. This includes a second Lake package that holds the project's own code. Move such code into the main package to have it analyzed.

To check that the emitted dependency graph explains every status, run the graph check on the artifact. It prints a `Divergence(graph)` line for each atom where a BFS over `dependencies` disagrees with the walk, and a `Warning:` line for each dependency that is not an atom. With `--fail-on-divergence`, exit 0 means that the graph and the walk agree on every atom with a status, not that every edge was emitted. Without the flag, the script exits 0 also on a divergence. The script reads enveloped artifacts from 0.16.0 on, and rejects input without a probe-lean version. If `extract` printed the duplicate-name warning, the report lacks the colliding atoms. Up to 0.20.0, `extract` printed these lines on stderr. The script is in the probe-lean repository, not in the release assets. You need a probe-lean checkout and Python 3. In the command, `<probe-lean>` is the checkout and `<project>` is the target project:

```bash
python3 <probe-lean>/tools/audit/check-graph.py --fail-on-divergence <project>/.verilib/probes/lean_<pkg>_<ver>.json
```

[verification-status.md](verification-status.md) explains how the walk decides and what each stderr line means, including the section "Coverage of P". [schema.md](schema.md), section "Verification status and the trusted base", defines the status values. An atom that reads `"verified"` because a project `sorry` is reachable from it carries `"status-origin": "kernel-taint"`. A tool that recomputes statuses from the dependency arrays must not promote such an atom or its callers (see [schema.md](schema.md), section "Re-deriving statuses").

Every atom with a status also has `assumptions`: the axioms and trusted constants that its proof rests on, other than `propext`, `Classical.choice` and `Quot.sound`. The field does not change the status. An atom that rests on `axiom bad : False` or on a `native_decide` axiom reads `"transitively-verified"`, and only `assumptions` names the axiom. [schema.md](schema.md), section "Assumptions", defines the field.

To check an artifact against the `check-axioms` report in both directions, run `tools/audit/check-status-consistency.py .verilib/probes/lean_*.json check-axioms.out`. For a `--skip-verify` artifact, add `--allow-missing`: the script then accepts atoms without a status and requires that no atom has `assumptions`. See [tools/audit/README.md](../tools/audit/README.md).

#### Module-system oleans

`extract` imports a module-system module (`module` header) from its `.olean.private` part, so it sees the proofs of its `public theorem`s. If such a module has no split parts, `extract` stops before the import and asks you to rebuild. For stale `.olean` files, see "Stale build outputs".

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
| `--module <PREFIX>` | `-m` | Import only the project modules under `<PREFIX>`, as for `extract`. The walk covers their import closure. The other constants of the closure carry the `[not emitted]` marker. |
| `--library <LIBS>` | `-l` | Comma-separated `lean_lib` names to build. The constants of other libraries carry the `[not emitted]` marker. |
| `--all-libraries` | | Build every `lean_lib` of the root package. |

Output on `tests/fixtures/aux-fold` (shortened, the full report has one line per listed constant):

```
Project constants: 214 in 9 module(s) | trusted: 26 | direct sorry carriers: 16 | tainted: 31
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
26 trusted constant(s) (T):
  Box [externally_verified] Demo.Trust
  ExtBundle [external] Demo.FunsExternal : Type
  externalOp [external] Demo.FunsExternal : Nat
  externalPred [external] Demo.FunsExternal : Prop
  stmtAx [axiom] Demo.StmtTaint [statement tainted]
  vouched [externally_verified] Demo.Trust
  ...
```

`[direct]` means the constant's own type or value names `sorryAx`. For a trusted constant only its type counts. `[not emitted]` means the constant is not an atom. The listed atoms are exactly those that `extract` marks `"verified"` or `"unverified"`. No `"transitively-verified"` atom appears here.

The trusted base T (see [Notation](verification-status.md#notation)) follows as `<name> [<trusted-reason>] <module>`. A rule-3 (`external`) model also shows its statement. ` [statement tainted]` marks a member of T whose statement rests on a project `sorry`: it is also in the tainted list, and its atom does not read `"trusted"`. Use this list to review what the "clean modulo T" claim rests on. `extract` shows only the trusted constants that are atoms. Both commands also print a `Note(axiom): ...` line for generated project axioms, such as those from `native_decide`. [verification-status.md](verification-status.md), section "Kernel dependencies, not executable bodies", explains why they stay trusted.

The report ends with the names in the assumption sets of P (see [Notation](verification-status.md#notation)), one line each, sorted by name. Each line gives the category and the number of constants of P (atoms or not) whose set holds the name. The last line counts the names per category, every category in this order, zeros included. On `tests/fixtures/assumptions` with Lean 4.33:

```
21 assumption name(s) in the sets of project constants:
  BadBox.casesOn [trusted (external)] 1
  BadBox.recOn [trusted (external)] 1
  T [universe-typed] 44
  add_spec [trusted (externally_verified)] 3
  bad [project axiom] 3
  bv._native.bv_decide.ax_1_5 [bv_decide] 2
  d [dependency axiom] 1
  dn._native.decide.ax_1_1 [native_decide] 2
  ...
  sorryAx [sorry] 43
  ...
Assumptions by category: sorry 1 | bv_decide 1 | native_decide 2 | universe-typed 1 | project axiom 5 | dependency axiom 3 | trusted 8
```

The first matching category applies:

| Category | Names |
|----------|-------|
| `sorry` | `sorryAx`. |
| `bv_decide` | An axiom whose type is `Std.Tactic.BVDecide.Reflect.verifyBVExpr … = true` or `Std.Tactic.BVDecide.Reflect.verifyCert … = true`. |
| `native_decide` | An axiom whose name ends in `_native.<tactic>.ax_<n>` (optionally followed by more `_<n>` parts), for any tactic, so `decide +native` too. Also `Lean.ofReduceBool`, `Lean.ofReduceNat` and `Lean.trustCompiler`, which compiled code rests on before Lean 4.31. |
| `universe-typed` | An axiom whose type, after its `∀` binders, is a `Sort`, such as `axiom T : Type`. |
| `project axiom`, `dependency axiom` | Any other axiom, or a name with an axiom version in any imported module, by membership in P. |
| `trusted (<reason>)` | A member of T that is not an axiom, with its `trusted-reason`. The summary line counts it under `trusted`. |

The status walk is memoized and stops at the project boundary and at the proofs of the trusted base. It takes about a second on a 230-module project that depends on Mathlib. The assumption-set walk also enters dependency packages. It added 4 to 6 s (11 to 15%) to a 34 to 42 s `extract` of PrimeNumberTheoremAnd, and about 2.5 s (25 to 30%) to a 9 s `extract` of curve25519-dalek-lean-verify. `-m` and `-l` do not make either walk smaller.

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

Some projects, such as [VCV-io](https://github.com/Verified-zkEVM/VCV-io), use `lakefile.lean` instead of `lakefile.toml`. probe-lean reads both with Lake's own loader. So the `@[default_target]` targets, a package or library `srcDir`, and names with `«»` quotes work as in `lakefile.toml`. Loading a `lakefile.lean` takes about one second longer than a `lakefile.toml`.

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

### Build on every run

`extract` and `check-axioms` run `lake build` on their targets on every run. A build with nothing to do takes a few seconds (3.2 s on curve25519-dalek), and the two workspace helper calls take about 2.5 s together (1.25 s each on curve25519-dalek, a `lakefile.toml` project). Each call is a `lake env` process, and `lake env` loads the workspace before the helper loads it again. probe-lean 0.22 and earlier skipped the build by file modification time and wrote `.lake/probe-lean/build_output.txt`. probe-lean no longer reads or writes that directory, and you can delete it.

Lake's artifact cache (`LAKE_ARTIFACT_CACHE=true` or `enableArtifactCache`) can keep the `.olean` files out of `.lake/build` after a cache hit. probe-lean needs them there. If a target module has no `.olean` after the build, the run fails with `Error: after the build, <n> target module(s) have no .olean in .lake/build/lib/lean` and names the modules. To fix it, set `LAKE_RESTORE_ARTIFACTS=true` (Lean 4.31 or later), or set `restoreAllArtifacts = true` in the lakefile. A package that sets `restoreAllArtifacts = false` overrides the variable.

### `--skip-verify`

`--skip-verify` leaves `verification-status` off every atom except the ones that read `"trusted"`, and `assumptions` off every atom. The status walk still runs and prints its summary. The flag saves the assumption-set walk, which takes about a tenth of the run on a Mathlib-sized project:

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

The output then holds only atoms from that module prefix. The import and the kernel walk cover the import closure of the selected modules only, so a module near the bottom of the import graph gives a faster run.

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

## Stale build outputs

Lean does not check the age of an `.olean` file when it imports it. So probe-lean imports only modules that Lake checked in the same run. It builds the targets on every run and imports only the target modules and their imports (the import closure). A `lean_lib` of the root package must own every project module of the closure. A project module is a module whose `.olean` is in `.lake/build/lib/lean` of the project. For a module that a `lean_lib` owns, Lake records each import in the importer's trace, so the target build rechecked the whole closure.

### What probe-lean detects

In each of these cases, the run fails or Lake rebuilds the module before the import:

| Case | What happens |
|------|--------------|
| A library outside the targets has a stale `.olean`. | The import does not load it, and no atom of it is emitted. |
| A source of a target module or of a module in its closure changed. | Lake rebuilds it in the target build. |
| A module that a target module imports was deleted. | `lake build` fails and names the missing file. |
| A module of the closure lost its `[[lean_lib]]` entry, but its source and `.olean` stay. | `Error: <n> module(s) in the import closure fail the ownership check`, with the reason `no lean_lib of the root package owns this module`. |
| A module of the closure is an executable root (`lean_exe`) that another project module imports. | The same error, with the reason `only a lean_exe owns this module, and another project module imports it`. Lake does not recheck such a module, and a fresh clone does not build this layout. Move the module into a `lean_lib`. |
| A module name is a `lean_lib` module and a `lean_exe` root. | The same error, with the reason `the name is both a lean_lib module and a lean_exe root`. |
| Lake's artifact cache kept a target `.olean` out of `.lake/build`. | `Error: after the build, <n> target module(s) have no .olean in .lake/build/lib/lean` (see "Build on every run"). |
| The project sets a custom `buildDir` or `leanLibDir`. | `Error: the build directory of the project is <dir>, not .lake/build/lib/lean`. |
| A target module resolves to an `.olean` outside `.lake/build/lib/lean`, for example because a dependency has a directory with the same root name. | `Error: <n> target module(s) do not resolve to an .olean in the build directory`. A symlinked `.lake` or `.lake/build` is supported. |
| Lake cannot list the modules of a target library, for example because a glob directory does not exist. | `Error: Lake could not list the modules of <n> target library(ies)`, with Lake's message for each library. A library that is not a target does not fail the run. |
| The project uses another Lean version than probe-lean. | `Error: the target project uses a different Lean than probe-lean`, with both Lean githashes, before any build. |

A failed run does not change an earlier output file.

### Limitations

probe-lean does not detect these cases:

- An edit to the project, or another `lake build` in it, while probe-lean runs.
- A failure while probe-lean writes the output file. The file can then be truncated.

Other unusual Lake layouts can exist in which probe-lean cannot detect a stale `.olean`. If a result looks wrong, run `lake clean` in the target project, then run `extract` again.

---

## Troubleshooting

### Build takes hours

If the automatic cache download fails (see "Mathlib cache" above), `lake build` compiles Mathlib from source. Run `lake exe cache get` in the target project.

### "Co-importability check failed"

Lake compiles each module on its own, so a project can build even if two modules declare the same fully-qualified name. probe-lean imports the target modules and their imports into one Lean environment, and Lean forbids duplicate declarations there.

probe-lean finds the duplicates before the import and lists them with their modules. Lakefile grouping helps: the import loads only the target modules and their imports, so two conflicting modules in different libraries do not collide unless one run targets both.

Fixes, best first:

1. Restructure the project. Give each variant family its own namespace, or make the dependent module `import` the shared module instead of restating its definitions. This is the only fix for automated consumers such as verilib, which cannot pass per-project flags.
2. Split the conflicting modules into separate `lean_lib` entries, and keep only one of them in `defaultTargets`.
3. For manual runs only, extract a subset with no conflict using `--module` or `--library`, for example `probe-lean extract . --module H1.solution`. `--module` selects the named module and its submodules, so for a clash between a root and its submodule, name the deepest module.

If two modules of the module system (`module` header) export the same `public def`, the preflight does not see the conflict, and the import fails with `environment already contains '<name>'`. probe-lean then names the modules that declare it. The fixes are the same.

### "Lake build failed" after you rename or delete a file

A module that a target module imports has no source anymore, so `lake build` fails and names the missing file. Lake does not remove the `.olean` of a deleted or renamed source, but probe-lean imports only the closure of the target modules, so an `.olean` that nothing imports does not matter. Fix the import, then run `extract` again.

### "fail the ownership check"

A module of the import closure has no `lean_lib` owner in the root package, or it is an executable root. See "Stale build outputs" for each reason and its fix.

### "Failed to import modules"

The `.olean` files are stale or come from a different toolchain version. Clean and rebuild:

```bash
cd <target-project>
rm -rf .lake
lake exe cache get    # if the project depends on Mathlib
lake build
```

### Toolchain mismatch

If you see `Error: the target project uses a different Lean than probe-lean` or `.olean` version errors, reinstall probe-lean for the target project:

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
