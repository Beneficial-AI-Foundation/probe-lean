# Usage Guide

## Prerequisites

- **Lean 4 toolchain** (`elan`, `lake`) -- install via [elan](https://github.com/leanprover/elan#installation)
- `~/.local/bin` in your `PATH` (for the installed binary)
- The target project must build with `lake build`

## Installation

No git clone required — the installer downloads a pre-built binary directly from GitHub releases.

**Option 1 -- auto-detect from target project (recommended):**
```bash
curl -sSfL https://raw.githubusercontent.com/Beneficial-AI-Foundation/probe-lean/main/tools/bash/install.sh \
  | bash -s -- --from-project ./my-lean-project
```

**Option 2 -- explicit version:**
```bash
curl -sSfL https://raw.githubusercontent.com/Beneficial-AI-Foundation/probe-lean/main/tools/bash/install.sh \
  | bash -s -- --lean-version v4.28.0
```

If you have the repository cloned (e.g., for development), you can run the scripts directly:
```bash
./tools/bash/install.sh --from-project ../my-lean-project
# or with Python:
uv run tools/python/install.py --from-project ../my-lean-project
```

The installer first tries to download a pre-built binary from GitHub Releases. If none is available for the requested Lean version, it falls back to building from source (auto-cloning the repo if needed).

Binaries are installed to `~/.local/bin/probe-lean-<version>` with a symlink at `~/.local/bin/probe-lean`. The required `.olean` files go to `~/.local/lib/probe-lean-<version>/`.

Verify the installation:
```bash
probe-lean --version
```

### Installer flags

| Flag | Description |
|------|-------------|
| `--from-project <path>` | Auto-detect the Lean version from the target project's `lean-toolchain`. If `<path>` has no top-level `lean-toolchain`, the installer searches recursively (excluding `.lake`) and uses the toolchain it finds — so pointing at a monorepo root works even when the Lean package is a subfolder (e.g. `cedar-spec/cedar-lean`). If multiple toolchains disagree on the version, it errors and lists them; pass `--lean-version` to disambiguate. |
| `--lean-version <ver>` | Explicit Lean version (e.g., `v4.28.0`) |
| `--force` | Reinstall even if the version is already installed |

### Toolchain version matching

probe-lean **must** be installed for the same Lean version as the target project. `.olean` files are version-specific and will not load across versions.

If your targets use different Lean versions, the installer handles this: it builds (or downloads) a versioned binary for each version. Multiple versions coexist under `~/.local/bin/probe-lean-v<version>`. The `probe-lean` symlink points to the most recently installed version.

### Pre-built binary availability

Pre-built binaries are published for `linux-x86_64` and `darwin-arm64` for every stable Lean release `≥ v4.28.0-rc1`, plus the latest release candidate of any line without a stable, plus any version pinned in [`tools/lean-version-extras.txt`](../tools/lean-version-extras.txt) (superseded RCs that tracked target projects still use — e.g. `v4.29.0-rc8` for Mathlib-pinned projects on that toolchain) — restricted to versions for which [`leanprover/lean4-cli`](https://github.com/leanprover/lean4-cli) has a *compatible* tag. `lean4-cli` tags `major.minor` lines and RCs but not every patch, so probe-lean resolves the `lean4-cli` dependency to the highest tag in the target's `major.minor` line (e.g. Lean `v4.32.2` builds against `lean4-cli v4.32.0`); patch releases are therefore supported. A version is skipped only when `lean4-cli` has *no* tag in its `major.minor` line — typically a brand-new Lean minor `lean4-cli` hasn't tagged yet, which the next scheduled build picks up. That scheduled workflow adds artifacts for new Lean versions automatically (usually within a day of an upstream release), so a recent toolchain normally has a binary ready. If yours doesn't — a superseded RC, an untagged new minor, or an unsupported version — the installer falls back to a source build (which applies the same `lean4-cli` resolution). To raise the GitHub API rate limit during the lookup, set `GH_TOKEN` (or `GITHUB_TOKEN`).

---

## Commands

### `extract`

Analyze a Lean 4 project: extract atoms, detect sorries, compute specs, and produce unified output.

```
probe-lean extract <PROJECT_PATH> [OPTIONS]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--output <PATH>` | `-o` | Output file path (default: `.verilib/probes/lean_<pkg>_<ver>.json`) |
| `--module <PREFIX>` | `-m` | Filter to specific module prefix |
| `--library <LIBS>` | `-l` | Comma-separated list of library names to build **and** restrict analysis to (modules are kept only if they belong to one of these library roots). When omitted, the build uses `defaultTargets` from `lakefile.toml` (falling back to all `[[lean_lib]]` entries) and **all** of the project's built modules are analyzed — auto-detected targets are not used as a module filter, since `defaultTargets` may name a `lean_exe` or a library may declare custom `roots`. |
| `--skip-verify` | | Skip status stamping: atoms carry no `verification-status`, except trusted ones (`"trusted"`) |
| `--from-file <FILE>` | | Use existing build output for the build-log cross-check instead of the captured `lake build` output |
| `--skip-enrich` | | No upgrade to `"transitively-verified"` (clean atoms read `"verified"`); the graph-BFS cross-check is not run |

Before importing, `extract` runs a **co-importability preflight**: it reads each built module's own declarations from its `.olean` header and aborts with the list of duplicated names and their owning modules if two modules declare the same fully-qualified name (see [Troubleshooting](#co-importability-check-failed)). With `--module`/`--library`, `extract` first tries to import **all** built project modules — the kernel walk below needs the whole project — and falls back to the selection if the full set cannot be co-imported. The walk then covers the selected modules and every project module they import transitively, which is every module an emitted atom can depend on; the modules left out are announced with `Warning: <n> project module(s) not imported (full import failed); they are outside the selection's import closure, so no emitted status depends on them, but check-axioms does not audit them`.

The preflight tolerates exactly what Lean's importer tolerates: two modules restating a theorem with the same name and statement (a problem file and its solution file, say). The importer then keeps **one** proof without comparing the bodies, so the name no longer identifies one project proof. `extract` and `check-axioms` fail closed on such *merged* declarations: the walk follows the union of every version's dependencies — a `sorry` in any version makes the name `unverified` and every caller `verified` — no `@[externally_verified]` on them is honoured, and they are announced with `Warning: <n> declaration name(s) are declared by more than one project module with the same statement, and Lean kept one proof: <names>`. Give each variant its own namespace if the proved version's callers should read clean.

The preflight reads project modules only, so a restatement of a **dependency's** theorem (or a pair involving a module whose `.olean` it could not read) is found after the import instead, from the environment header: a name a project module declares that the environment attributes to another module, or that a non-project module declares too. The preflight keeps a copy of every project constant it read, so normally the walk follows the **project's own version(s)** of such a name, under the merged-declaration policy: a `sorry` in any of them makes the name `unverified` (or `[not emitted]` in `check-axioms`, when the importer attributed it to the dependency) and every caller `verified`, whichever body the environment kept; a proved restatement of a proved dependency theorem stays clean, the other body being a dependency's and already trusted; no `@[externally_verified]` on it is honoured. Announced with `Note: <n> declaration name(s) are declared by a project module and by a module outside the project (a dependency), and Lean kept one body: <names>; …`. Only when a declaring project module's olean could not be read is its body invisible; such a name is treated as resting on `sorry` with no trust rule applied, and announced with `Warning: <n> declaration name(s) are declared by a project module whose olean the preflight could not read and by another module, and Lean kept one body: <names>; …`.

`verification-status` is decided by a **kernel walk**, not by the build log or the emitted
dependency graph. `sorry` elaborates to the `sorryAx` axiom; `extract` walks the constant graph
of every constant of every built project module — including constants it never emits as atoms
(auxiliaries, constructors, range-less `addDecl`/`impl_def` constants) — stopping at the project
boundary (Lean and every dependency package are trusted wholesale) and at the **trusted base**:
axioms, declarations in the `externally_verified` **tag set** (read from the environment, however
the tag was attached), and non-proofs in `*External` modules (theorems and Prop-typed declarations get their normal
status there; every other declaration in such a module is trusted as a model, whatever its type). A `sorry` inside or below a trusted declaration does not taint its
callers. See [SCHEMA.md](SCHEMA.md) for the exact meaning of each status value. The pass prints
its totals:

```
Project constants: 11293 in 231 module(s) | trusted: 150 | direct sorry carriers: 4 | tainted: 112
externally_verified tag set: 2 name(s) from externallyVerifiedAttr
```

Two cross-checks run alongside it and print lines on stderr, never changing a status: the
build log's `sorry` warnings against the walk's direct carriers (`Divergence(log): <atom>
build log says sorry, kernel says clean modulo trust`, or `… kernel says sorry, no warning
in the log`; trusted atoms are skipped, since a `sorry` under them is excused, not missed;
a `partial def` whose `sorry` sits in its compiled `X._unsafe_rec` body gets `Note(log): …`
instead — the status covers kernel dependencies, not executable bodies, see SCHEMA),
and the old reverse-BFS over the emitted graph against the walk's verdicts
(`Divergence(graph): <atom> graph says clean, oracle says tainted`, or the reverse, followed
by a `Graph cross-check: <n> atom(s) …` summary). A graph divergence localises a node or edge
the emitted graph is missing (typically a carrier with no declaration range, which is never
an atom). A trusted declaration whose *statement* names `sorry` directly is reported with
`Warning: trusted declaration <n> names \`sorry\` directly in its statement`. An atom the walk
did not cover (its Lean name is not a project constant — a bug, since every emitted atom is
one) gets no status and `Warning: atom <name> is not a project constant the kernel walk
covered; no verification-status assigned`.

`@[externally_verified]` is read from the **environment**, not from source text: the target's
`registerTagAttribute` stores the tagged names in each module's olean, and probe-lean reads
that set (plus its own handle, for targets that import `ProbeLean.Attrs`). A tag is a tag,
whatever syntax attached it — `@[…]` on the declaration or an `attribute [externally_verified]
foo` command — and whatever the constant is. Nothing that merely shares a tagged declaration's
source range (a `deriving` instance, a projection, a generated companion or helper) is in the
set, and nothing the source scan could be fooled by (a tag in a docstring, a comment, a string,
an interpolated string, a neighbouring command on the same line) reaches trust. The source scan
still fills the `attributes` array for attributes probe-lean does not register; the pass prints
where it got the set from (`externally_verified tag set: <n> name(s) from <extension>`) and,
on stderr, every disagreement between the scan and the set (`Divergence(tag): … the source
text does not decide trust` for a header the scan would have trusted, `Note(tag): … the tag
set decides trust` for a tag the header does not show; both report set membership, the
status is in `trusted-reason`). A tag a registration the reader does not understand attaches
with no header to scan — an `attribute` command, a range-less constant — is untrusted
without a line.

A module built under the module system (`module` header) is read from its `.olean.private`
part, as the importer does; a module-system olean without its split parts aborts the
extraction, because the exported level shows a `public theorem` as a proof-less axiom.
A stale `.olean` with no backing `.lean` source is dropped from the inventory (`Ignoring
<n> orphan module(s) …`); if a live module still imports it, the extraction aborts with
`<n> stale module(s) with no .lean source were imported by a live module: …`, because its
constants would otherwise sit outside the project boundary and be trusted like a
dependency's — run `lake clean` in the target project and rebuild. After the import, every
imported project module's olean as the search path resolves it (`Lean.findOLean`) must be the
file the preflight read; otherwise the extraction aborts with `module <m> was imported from <a>,
but the co-import preflight read <b> …` (a `LEAN_PATH` entry shadowing the project's build
directory, or a rebuild between the two reads).

To check an artifact against the `check-axioms` report in both directions (every `unverified`
atom is a listed direct carrier *and* every listed emitted carrier is `unverified`, likewise for
`verified` and the clean statuses), run
`tools/audit/check-status-consistency.py .verilib/probes/lean_*.json check-axioms.out`.

`extract` folds **auxiliary dependency edges** into the declaration that references them.
Lean abstracts non-atomic embedded proofs and match arms into constants probe-lean does not
emit as atoms (`X._proof_N`, `X.match_N`, …); before this, a dependency reached only through
one of them disappeared from the graph, so a `sorry`-carrying lemma used inside a tactic
block left its caller looking clean. The pass is strictly additive, and adds only to
`term-dependencies` — see
[SCHEMA.md](SCHEMA.md#auxiliary-dependency-folding) for what is and is not folded, and for
the two limits worth repeating: folding fixes edges, not `verification-status` soundness, and
a zero in-degree is still not a licence to delete a declaration.

The step reports its accounting on stdout, e.g.

```
Auxiliary fold: recovered 2 dependency edge(s) (2 expansions, 22 edges scanned, 0 cycle suppression(s), cache 2 entr(ies) / 1 name(s))
```

`cycle suppression(s)` counts revisits the traversal skipped because the node was already
visited in the same query and had no cached complete closure. A run reporting 0 — as
curve25519-dalek-lean-verify does — never exercised the cycle-handling rules at all.

If a dependency name cannot be resolved in the imported environment, `extract` lists it on
stderr rather than dropping it silently: edges underneath such a name are not recovered.

Every atom carries neutral `codomain-head` / `codomain-is-prop` / `codomain-last-arg-is-bool`
facts about its result type (see [SCHEMA.md](SCHEMA.md)). These are domain-agnostic primitives;
probe-lean does not classify declarations itself, but a downstream tool can reconstruct a
declaration's codomain shape from them plus its own catalogue.

Every atom also carries `is-primary-spec`, recording whether the declaration is tagged
`@[primary_spec]` — *tagged*, not *won*, so a theorem the heuristic signals pick as some
target's `primary-spec` reads `false` unless it is tagged too. When two or more tagged
theorems resolve to the same target, the winner is an arbitrary tie-break and `extract`
prints one stderr warning per affected target naming the chosen theorem and the rejected
candidates (exit code unchanged). Intersecting a target's `specs` with `is-primary-spec`
recovers the same candidate set from the artifact.

`extract` also auto-flags generated code as `is-hidden` plus an origin flag, so `viewify` and
the web UI omit it: `deriving`-generated instance clusters and structure/class projections are
core-Lean output (`is-lean-generated`), while attribute-machinery companion theorems (the
`X.mvcgen_spec` that Aeneas's `@[step]` adds next to a tagged `theorem X`) exist only because
of Aeneas (`is-aeneas-generated`). These atoms stay in the dependency graph, so
transitive-verification remains sound. Generated theorems (either flag) are additionally
excluded from `specs` lists and the heuristic primary-spec signals: a machine-generated
companion is not a user spec, and counting it would make the real spec ambiguous. Two
deliberate exceptions: the companion of a tagged **axiom** stays visible (axioms are never
collected into `specs`, so the companion is the axiom's only spec proxy), and an explicit
`@[primary_spec]` tag still wins even on a generated theorem — and re-admits it into `specs` —
as the escape hatch.
After transitive enrichment, `is-hidden` is cleared on *contaminated* generated atoms —
locally verified but not `transitively-verified`, or `unverified`/`failed` — so they remain
visible for tracing. Clean (`transitively-verified`) and `trusted` generated atoms stay hidden.

### `check-axioms`

Audit a Lean 4 project: run the same kernel walk `extract` uses for `verification-status` and list
every project constant that rests on an unexcused project `sorry` — atoms and non-atoms alike.

```
probe-lean check-axioms <PROJECT_PATH> [OPTIONS]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--module <PREFIX>` | `-m` | Restrict which constants count as *emitted* (the `[not emitted]` marker); the walk always covers every built module it can import |
| `--library <LIBS>` | `-l` | Comma-separated library names to build **and** restrict the emitted set to |

On `tests/fixtures/aux-fold` (abridged; the full report has one line per listed constant):

```
Project constants: 102 in 7 module(s) | trusted: 9 | direct sorry carriers: 19 | tainted: 24
externally_verified tag set: 7 name(s) from externallyVerifiedAttr
24 constant(s) rest on an unexcused project sorry:
  admittedFact [direct]
  extThm [direct]
  instReprTagged
  loopy._unsafe_rec [direct] [not emitted]
  noRangeMid [direct] [not emitted]
  tacticUse._proof_1 [not emitted]
  viaNoRange
  ...
9 trusted constant(s) (T):
  Box [externally_verified] Demo.Trust
  externalOp [external] Demo.FunsExternal : Nat
  externalPred [external] Demo.FunsExternal : Prop
  vouched [externally_verified] Demo.Trust
  ...
```

`[direct]`: the constant's own type or value names `sorryAx`. `[not emitted]`: not an atom.
Because the walk is shared with `extract`, the listed atoms are exactly those `extract` marks
`"verified"` or `"unverified"`, and nothing `"transitively-verified"` can appear here. The trusted
base T is listed next — `<name> [<trusted-reason>] <module>`, with the statement appended for a
rule-3 (`external`) model — so the constants the "clean modulo T" claim rests on can be reviewed;
`extract` shows only the trusted constants that are atoms. Generated axioms among them (a
`native_decide` proof on Lean ≥ 4.31 adds `X._native.native_decide.ax_N`, trusted by rule 1) are
also announced on stderr, one `Note(axiom): <n> is a generated project axiom (not a source-visible
declaration, e.g. from native_decide); trusted by rule 1` each, by both commands. The walk is
memoized and stops at the project boundary and the trusted base, so it costs milliseconds even on
a 230-module Mathlib-backed project; `-m`/`-l` no longer narrow it.

---

## Walkthrough: Analyzing Real Projects

### Mathlib cache (auto-downloaded)

Most Lean verification projects depend on [Mathlib](https://github.com/leanprover-community/mathlib4). Compiling Mathlib from source is extremely slow and saturates all CPU cores. The Mathlib project publishes pre-built `.olean` caches that download in minutes.

**probe-lean automatically downloads the Mathlib cache** when it detects a Mathlib dependency without pre-built `.olean` files. You will see:

```
Mathlib dependency detected but no pre-built cache found.
Running `lake exe cache get` to download pre-built .olean files...

  ✓ Mathlib cache downloaded
```

If the automatic download fails (e.g. network issues), probe-lean prints a warning and continues (which will trigger a slow Mathlib compilation). In that case, run the cache download manually:

```bash
cd <target-project>
lake exe cache get
```

### Example 1: [curve25519-dalek-lean-verify](https://github.com/Beneficial-AI-Foundation/curve25519-dalek-lean-verify)

Aeneas-generated Lean translation of the curve25519-dalek Rust crate, with Mathlib-based specifications and proofs.

| Property | Value |
|----------|-------|
| Toolchain | `v4.28.0-rc1` |
| Depends on Mathlib | Yes |
| Libraries | `Curve25519Dalek`, `Utils` (utilities/scripts) |
| `defaultTargets` | `["Curve25519Dalek"]` |

```bash
# 1. Install probe-lean (auto-detects v4.28.0-rc1 from lean-toolchain)
curl -sSfL https://raw.githubusercontent.com/Beneficial-AI-Foundation/probe-lean/main/tools/bash/install.sh \
  | bash -s -- --from-project ./curve25519-dalek-lean-verify

# 2. Run extract (Mathlib cache is auto-downloaded on first run)
cd curve25519-dalek-lean-verify
probe-lean extract .
```

probe-lean reads `defaultTargets = ["Curve25519Dalek"]` and builds only that library (the `Utils` library contains standalone scripts and is not part of the main verification target).

### Example 2: [VCV-io](https://github.com/Verified-zkEVM/VCV-io)

Lean 4 library for verified cryptographic protocols. Uses `lakefile.lean` (not `.toml`).

| Property | Value |
|----------|-------|
| Toolchain | `v4.28.0` |
| Depends on Mathlib | Yes |
| Default targets | `VCVio`, `Examples` (via `@[default_target]` in lakefile.lean) |
| Other libraries | `ToMathlib`, `LibSodium` |

```bash
# 1. Install probe-lean (auto-detects v4.28.0)
curl -sSfL https://raw.githubusercontent.com/Beneficial-AI-Foundation/probe-lean/main/tools/bash/install.sh \
  | bash -s -- --from-project ./VCV-io

# 2. Run extract (Mathlib cache is auto-downloaded on first run)
cd VCV-io
probe-lean extract .
```

Since VCV-io uses `lakefile.lean` (not `.toml`), probe-lean cannot auto-detect library names and falls back to `lake build` with no explicit targets, which uses the project's `@[default_target]` annotations.

### Example 3: [ArkLib](https://github.com/Verified-zkEVM/ArkLib)

Lean 4 library for formally verified zkSNARK components. Depends on Mathlib and VCV-io.

| Property | Value |
|----------|-------|
| Toolchain | `v4.28.0` |
| Depends on Mathlib | Yes (transitively via VCV-io) |
| Libraries | `ArkLib` |
| `defaultTargets` | `["ArkLib"]` |

```bash
# 1. Install probe-lean (skip if already done for VCV-io — same Lean version)
curl -sSfL https://raw.githubusercontent.com/Beneficial-AI-Foundation/probe-lean/main/tools/bash/install.sh \
  | bash -s -- --from-project ./ArkLib

# 2. Run extract (Mathlib cache is auto-downloaded on first run)
cd ArkLib
probe-lean extract .
```

If you've already built the project, probe-lean will detect that the build cache is up-to-date and skip the `lake build` step automatically (sorry detection still works using the cached build output).

### Example 4: [signal-shot-PQXDH](https://github.com/Beneficial-AI-Foundation/signal-shot-PQXDH)

Lean 4 formalization of the Signal PQXDH key agreement protocol. Depends on Mathlib and subverso.

| Property | Value |
|----------|-------|
| Toolchain | `v4.29.0-rc3` |
| Depends on Mathlib | Yes |
| Libraries | `PQXDHLean` |
| `defaultTargets` | `["PQXDHLean"]` |

```bash
# 1. Install probe-lean (auto-detects v4.29.0-rc3 — different from Examples 1–3)
curl -sSfL https://raw.githubusercontent.com/Beneficial-AI-Foundation/probe-lean/main/tools/bash/install.sh \
  | bash -s -- --from-project ./signal-shot-PQXDH

# 2. Run extract (Mathlib cache is auto-downloaded on first run)
cd signal-shot-PQXDH
probe-lean extract .
```

### Example 5: From-scratch setup on a fresh machine

Starting from nothing on Ubuntu/Debian:

```bash
# Install elan (Lean version manager)
curl https://elan-init.trycloudflare.com/elan-init.sh -sSf | sh
source ~/.profile

# Install probe-lean (auto-detects Lean version from target project, no clone needed)
curl -sSfL https://raw.githubusercontent.com/Beneficial-AI-Foundation/probe-lean/main/tools/bash/install.sh \
  | bash -s -- --from-project ./my-lean-project

# Ensure ~/.local/bin is in PATH
export PATH="$PATH:$HOME/.local/bin"

# Verify installation
probe-lean --version

# Prepare the target project
cd my-lean-project
# Run extraction (Mathlib cache auto-downloaded if needed)
probe-lean extract .
```

---

## Performance Tips

### Automatic build caching

probe-lean automatically skips `lake build` when the build cache is up-to-date (no `.lean` file has been modified since the last build). Sorry detection still works using the cached build output.

### Use `--skip-verify` for faster iteration

Sorry detection requires build output. If you only need the dependency graph:

```bash
probe-lean extract ./my-project --skip-verify
```

### Use `nice` for long builds on shared machines

`lake build` for Mathlib-dependent projects can saturate all CPU cores for 10--30 minutes (longer on first build). On shared machines or when you need the system responsive, build at low priority:

```bash
nice -n 15 probe-lean extract <target-project>
```

This keeps the build running but yields CPU to interactive tasks. `nice -n 19` is the lowest priority; `nice -n 10` is a reasonable middle ground.

### Filter to a single module

For quick iteration on a specific module:

```bash
probe-lean extract ./my-project -m MyProject.Core
```

---

## Output Format

For the complete JSON schema specification, see [SCHEMA.md](SCHEMA.md).

The `extract` command produces a JSON file wrapped in a Schema 3.0 metadata envelope:

```json
{
  "schema": "probe-lean/extract",
  "schema-version": "3.0",
  "tool": { "name": "probe-lean", "version": "0.8.0", "command": "extract" },
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
      "is-lean-generated": false,
      "is-aeneas-generated": false,
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

For the full atom field reference and verification-status mapping, see [SCHEMA.md](SCHEMA.md).

---

## Configuration

Atom filtering flags are populated from the project's `.verilib/probes/config.json`:

- `is-hidden`: `true` if the atom name (without `probe:` prefix) appears in `is-hidden`
- `is-aeneas-generated`: `true` if the atom name ends with any suffix in `extraction-artifact-suffixes`; also auto-set (with `is-hidden`) for `@[step]`'s attribute-machinery companion theorems (`X.mvcgen_spec`)
- `is-ignored`: `true` if the atom name appears in `is-ignored`

The `is-relevant` field is computed from `relevant-crate` and the `rust-source` field:
- If `rust-source` exists: `true` if it contains the crate name AND doesn't start with `/` AND doesn't contain `/cargo/registry/`
- If no `rust-source`: `false`

Example config (`.verilib/probes/config.json`):

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

You're almost certainly compiling Mathlib from source. probe-lean auto-downloads the cache on first run (see [Mathlib cache](#mathlib-cache-auto-downloaded)), but if that failed, run `lake exe cache get` in the target project manually.

### "Co-importability check failed"

Projects with modules that declare the same fully-qualified name build because Lake compiles each module independently, but `probe-lean` must import **all** built modules into a single Lean environment, and Lean forbids duplicate declarations in one environment (see the co-importability requirement under [Supported Projects](../README.md#supported-projects) in the README).

probe-lean detects this *before* importing and lists the duplicated names with their owning modules. Note that lakefile-level grouping does **not** avoid it: `defaultTargets` and `[[lean_lib]]` splits only affect what is *built* — probe-lean analyzes every built `.olean` on disk.

Fixes, in order of preference:

1. **Restructure the project** (the only fix that works for automated consumers like verilib, which cannot pass per-project flags): give each variant family its own namespace, or have the dependent module `import` the shared module instead of restating its definitions.
2. **Manual runs only**: extract a non-conflicting subset with `--module`, e.g. `probe-lean extract . --module H1.solution`. Note `--module` selects the named module *plus its submodules*, so for a root/submodule clash name the deepest module. (`--library` matches module-name roots, not lakefile library names, so it usually cannot select across this kind of split.)

### "environment already contains '...'" after renaming or deleting a file

A stale *orphan* `.olean` from the old module is still on disk (Lake never removes oleans for deleted/renamed sources) and re-declares a name now owned by another module. probe-lean drops orphan oleans automatically by checking each module against its backing `.lean` source — but it only knows `srcDir`s declared in `lakefile.toml`. If your project uses a Lean-DSL `lakefile.lean` with a custom `srcDir`, the orphan may slip through the source check *and* the co-importability preflight; the error message covers this case with a `lake clean` hint. Run `lake clean && lake build` in the target project, then re-run extract.

### "Failed to import modules"

The `.olean` files may be stale or from a different toolchain version. Clean and rebuild:

```bash
cd <target-project>
rm -rf .lake
lake exe cache get    # if Mathlib-dependent
lake build
```

### Toolchain mismatch

If you see `.olean` version errors, reinstall probe-lean for the target project:

```bash
curl -sSfL https://raw.githubusercontent.com/Beneficial-AI-Foundation/probe-lean/main/tools/bash/install.sh \
  | bash -s -- --force --from-project <target-project>
```

### Output directory

probe-lean writes to `<target-project>/.verilib/probes/lean_<pkg>_<ver>.json` by default:

```
.verilib/
└── probes/
    └── lean_<pkg>_<ver>.json     # extract output (unified atoms)
```

Override with `-o <path>` if needed.
