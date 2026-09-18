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
| `--module <PREFIX>` | `-m` | Filter to specific module prefix. The kernel walk still imports every built project module, so a narrow selection is not faster than a full run (about 1.2 s slower on dalek than 0.14.0, which imported the selection only) |
| `--library <LIBS>` | `-l` | Comma-separated list of library names to build **and** restrict analysis to (modules are kept only if they belong to one of these library roots). When omitted, the build uses `defaultTargets` from `lakefile.toml` (falling back to all `[[lean_lib]]` entries) and **all** of the project's built modules are analyzed — auto-detected targets are not used as a module filter, since `defaultTargets` may name a `lean_exe` or a library may declare custom `roots`. |
| `--skip-verify` | | Skip status stamping: atoms carry no `verification-status`, except trusted ones (`"trusted"`) |
| `--from-file <FILE>` | | Use existing build output for the build-log cross-check instead of the captured `lake build` output |
| `--skip-enrich` | | No upgrade to `"transitively-verified"` (clean atoms read `"verified"`); the graph-BFS cross-check is not run |

Before importing, `extract` runs a **co-importability preflight**: it reads each built module's own declarations from its `.olean` header and aborts with the list of duplicated names and their owning modules if two modules declare the same fully-qualified name (see [Troubleshooting](#co-importability-check-failed)). With `--module`/`--library`, `extract` first tries to import **all** built project modules — the kernel walk below needs the whole project — and falls back to the selection if the full set cannot be co-imported. The walk then covers the selected modules and every project module they import transitively, which is every module an emitted atom can depend on; the modules left out are announced with `Warning: <n> project module(s) not imported (full import failed); they are outside the selection's import closure, so no emitted status depends on them, but check-axioms does not audit them`.

The preflight tolerates exactly what Lean's importer tolerates: two modules restating a theorem with the same name and statement (a problem file and its solution file, say). Lean keeps **one** proof, so `extract` and `check-axioms` fail closed on such *merged* declarations: a `sorry` in any version makes the name `unverified` and every caller `verified`, no `@[externally_verified]` on it is honoured, and `Warning: <n> declaration name(s) are declared by more than one project module with the same statement, and Lean kept one proof: <names>` is printed. Give each variant its own namespace if the proved version's callers should read clean. Two related cases are announced with `Note:` lines instead: a project restatement of a **dependency's** theorem (`… declared by a project module and by a module outside the project …`) and Lean's on-demand realisations (`f.eq_1`, `f.congr_simp`, …) realised in more than one module. The policy for each is in [verification-status.md](verification-status.md#merged-declarations).

`verification-status` is decided by a **kernel walk** over every constant of every built project
module, not by the build log or the emitted dependency graph. The walk stops at the project
boundary (Lean and every dependency package are trusted wholesale) and at the **trusted base**
(axioms, the `externally_verified` tag set, non-proofs in `*External` modules); a `sorry` inside
or below a trusted declaration does not taint its callers. [SCHEMA.md](SCHEMA.md#verification-status-and-the-trusted-base)
defines the status values and [verification-status.md](verification-status.md) the edge cases.
The pass prints its totals:

```
Project constants: 11293 in 231 module(s) | trusted: 150 | direct sorry carriers: 4 | tainted: 112
externally_verified tag set: 2 name(s) from externallyVerifiedAttr
```

and names the boundary it stopped at, once per run on stderr: `Note: <n> imported module
root(s) outside the project are trusted wholesale (Lean and dependency packages): Init, Lean,
Mathlib, …`. Every package `lake-manifest.json` lists is trusted wholesale, a second Lake
package holding the project's own code (a `path = "…"` require, a sibling repository) included;
move code into the main package to have it analysed.

Two cross-checks run alongside it and print lines on stderr, never changing a status: the
build log's `sorry` warnings against the walk's direct carriers (`Divergence(log): <atom>
build log says sorry, kernel says clean modulo trust`, or `… kernel says sorry, no warning
in the log`; trusted atoms are skipped, since a `sorry` under them is excused, not missed;
a `partial def` whose `sorry` sits in its compiled `X._unsafe_rec` body gets `Note(log): …`
instead — the status covers kernel dependencies, not executable bodies, see
[verification-status.md](verification-status.md#kernel-dependencies-not-executable-bodies)),
and the old reverse-BFS over the emitted graph against the walk's verdicts
(`Divergence(graph): <atom> graph says clean, oracle says tainted`, or the reverse, followed
by a `Graph cross-check: <n> atom(s) …` summary). A graph divergence localises a node or edge
the emitted graph is missing (typically a carrier with no declaration range, which is never
an atom). A trusted declaration whose *statement* names `sorry` directly is reported with
`Warning: trusted declaration <n> names \`sorry\` directly in its statement`. An atom the walk
did not cover (its Lean name is not a project constant — a bug, since every emitted atom is
one) gets no status and `Warning: atom <name> is not a project constant the kernel walk
covered; no verification-status assigned`.

`@[externally_verified]` is read from the **environment's tag set**, not from source text, so
nothing that merely shares a tagged declaration's source range and nothing quoted in a docstring,
comment or string reaches trust (the rule's exact scope and limits are in
[verification-status.md](verification-status.md#rule-2-externally_verified)). The pass prints
where it got the set from (`externally_verified tag set: <n> name(s) from <extension>`) and, on
stderr, every disagreement between the header scan that fills `attributes` and the set
(`Divergence(tag): … the source text does not decide trust` for a header the scan would have
trusted, `Note(tag): … the tag set decides trust` for a tag the header does not show; both report
set membership, the status is in `trusted-reason`).

A module built under the module system (`module` header) is imported from its `.olean.private`
part, as Lean requires, so its `public theorem`s are seen with their proofs; a module-system
olean without its split parts aborts the extraction before the import, which would fail on it
(`missing data file`). A stale `.olean` with no backing `.lean` source is dropped from the
inventory (`Ignoring <n> orphan module(s) …`); if a live module still imports it, the
extraction aborts with `<n> stale module(s) with no .lean source were imported by a live
module: …`, because its constants would otherwise sit outside the project boundary and be
trusted like a dependency's — run `lake clean` in the target project and rebuild.

To check an artifact against the `check-axioms` report in both directions (every `unverified`
atom is a listed direct carrier *and* every listed emitted carrier is `unverified`, likewise for
`verified` and the clean statuses), run
`tools/audit/check-status-consistency.py .verilib/probes/lean_*.json check-axioms.out`.

`extract` folds **auxiliary dependency edges** into the declaration that references them.
Lean abstracts non-atomic embedded proofs and match arms into constants probe-lean does not
emit as atoms (`X._proof_N`, `X.match_N`, …); before this, a dependency reached only through
one of them disappeared from the graph, so a `sorry`-carrying lemma used inside a tactic
block left its caller looking clean. The pass is strictly additive, and adds only to
`term-dependencies` — [SCHEMA.md](SCHEMA.md#auxiliary-dependency-folding) states the
contract and [auxiliary-folding.md](auxiliary-folding.md) what is and is not folded. Two limits
worth repeating: folding fixes edges, not `verification-status` soundness, and a zero in-degree
is still not a licence to delete a declaration.

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
Project constants: 119 in 8 module(s) | trusted: 9 | direct sorry carriers: 20 | tainted: 26
externally_verified tag set: 7 name(s) from externallyVerifiedAttr
26 constant(s) rest on an unexcused project sorry:
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
also announced on stderr by both commands, one `Note(axiom): <n> generated project axiom(s) trusted
by rule 1 (not source-visible declarations, e.g. from native_decide): a, b, …` line per run (names
capped at 10; the T listing names every one). Why they stay trusted, and the known gap, is in
[verification-status.md](verification-status.md#kernel-dependencies-not-executable-bodies). The
walk is memoized and stops at the project boundary and the trusted base, so it costs about a
second even on a 230-module Mathlib-backed project; `-m`/`-l` no longer narrow it.

### `viewify`

Filter an existing `extract` output into molecules for the web UI. No build or import runs.

```
probe-lean viewify <PROJECT_PATH> [OPTIONS]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--with-atoms <FILE>` | `-a` | Path to the `extract` output (default: auto-detected under `.verilib/probes/`) |
| `--output <PATH>` | `-o` | Output file path (default: `.verilib/views/molecules_all.json`) |

An atom becomes a molecule when it is not hidden, not lean- or aeneas-generated, relevant, and
its `code-path` ends with `Funs.lean`. The molecule fields are listed in
[SCHEMA.md](SCHEMA.md#molecules-probe-leanviewify).

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

If you've already built the project, probe-lean will detect that the build cache is up-to-date and skip the `lake build` step automatically (verification status comes from the kernel walk over the `.olean` files, so it does not need a fresh build log).

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

probe-lean automatically skips `lake build` when the build cache is up-to-date (no `.lean` file has been modified since the last build). Verification status comes from the kernel walk over the `.olean` files, so it does not need a fresh build log; only the build-log cross-check has nothing to compare against.

### Use `--skip-verify` to withhold statuses

`--skip-verify` leaves `verification-status` off every atom except trusted ones. The kernel walk
still runs (its summary line is still printed), so the flag saves only the build-log cross-check;
use it when a consumer must not see statuses rather than for speed:

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
      "is-in-package": true,
      "is-relevant": true,
      "is-hidden": false,
      "is-lean-generated": false,
      "is-aeneas-generated": false,
      "is-ignored": false,
      "is-primary-spec": false,
      "rust-source": null,
      "specs": ["probe:MyModule.helper_spec"],
      "primary-spec": "probe:MyModule.helper_spec",
      "verification-status": "transitively-verified",
      "codomain-head": "MyModule.MyType",
      "codomain-is-prop": false,
      "codomain-last-arg-is-bool": false
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
- If `relevant-crate` is not configured: `true` for every atom
- Otherwise, if `rust-source` exists: `true` if it contains the crate name AND doesn't start with `/` AND doesn't contain `/cargo/registry/`
- Otherwise (no `rust-source`): `false`

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
