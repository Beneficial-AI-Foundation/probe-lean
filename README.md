# probe-lean

Analyze Lean 4 projects: extract dependency graphs with verification status and spec relationships.

`probe-lean` walks the Lean environment of a built project. It writes JSON that lists every declaration with its type and term dependencies, source location, verification status and spec relationships. The output uses the Schema 3.0 envelope format, which [docs/schema.md](docs/schema.md) specifies.

## Prerequisites

- The Lean 4 toolchain (`elan`, `lake`). Install it with [elan](https://github.com/leanprover/elan#installation).
- A target project that builds with `lake build`.
- A probe-lean build for the same Lean version as the target project, because `.olean` files are version-specific. The target version is in `<target-project>/lean-toolchain`.

## Supported Projects

probe-lean can analyze a Lean 4 project that meets these conditions:

- The project uses Lean v4.28.0-rc1 or later.
- The Lean library targets build. probe-lean needs only the `.olean` files. If an executable fails to link, use `--library <lib>` to build only the library.
- All built modules load into one Lean environment. A preflight check stops extraction and lists the names that two modules declare. See [docs/usage.md](docs/usage.md), section "Troubleshooting".

If the target project ships a `flake.nix` or `shell.nix`, probe-lean runs `lake` inside that Nix shell. This requires `nix` or `nix-shell` on your system. Without Nix, you must install the system libraries of the project yourself.

### What will not work

- Projects on Lean versions below v4.28.0-rc1.
- Projects whose Lean libraries do not compile.
- A probe-lean build for a different Lean version than the target. A minor-level difference (v4.28.0-rc1 and v4.29.0) also needs a matching build. Use the installer flag `--from-project` to select the correct version.
- Projects in which two modules declare the same fully-qualified name. `--module <prefix>` can extract a subset with no conflict. See [docs/usage.md](docs/usage.md), section "Troubleshooting".

## Installation

Install for the Lean version of a target project:

```bash
curl -sSfL https://raw.githubusercontent.com/Beneficial-AI-Foundation/probe-lean/main/tools/bash/install.sh \
  | bash -s -- --from-project ./my-lean-project
```

Install for a specified Lean version:

```bash
curl -sSfL https://raw.githubusercontent.com/Beneficial-AI-Foundation/probe-lean/main/tools/bash/install.sh \
  | bash -s -- --lean-version v4.29.0
```

The installer puts the binary in `~/.local/bin`. Add that directory to your `PATH`.

The installer searches the GitHub releases from newest to oldest. It downloads the first release that has a binary for your Lean version and platform (`linux-x86_64` or `darwin-arm64`). For a Lean version that the current release does not cover, such as a superseded release candidate, this is an old probe-lean release. For example, `--lean-version v4.28.0-rc1` installs probe-lean 0.9.4. If no release has a matching binary or the download fails, the installer builds from source. For the installer flags and the list of built Lean versions, see [docs/usage.md](docs/usage.md), sections "Installer flags" and "Pre-built binary availability".

### GitHub Actions

```yaml
- uses: Beneficial-AI-Foundation/probe-lean/action@main
  with:
    project-path: .
```

The action reads the Lean version from the project, installs probe-lean with the installer and runs `extract`. For all inputs, see [action/action.yml](action/action.yml).

## Quick start

```bash
# Build, extract atoms and decide verification status
probe-lean extract ./my-lean-project

# Build and analyze only some libraries
probe-lean extract ./my-lean-project --library "Extraction,Spqr"
```

The default output file is `<target-project>/.verilib/probes/lean_<pkg>_<ver>.json`. For a sample, see [examples/lean_ExampleProject_0.1.0.json](examples/lean_ExampleProject_0.1.0.json). For the field definitions, see [docs/schema.md](docs/schema.md).

## Commands

| Command | Description |
|---------|-------------|
| `extract` | Build a project, extract atoms with dependencies, specs and `verification-status`. |
| `viewify` | Filter `extract` output into molecules for the web UI (`.verilib/views/molecules_all.json`). |
| `check-axioms` | List every project constant that rests on an unexcused project `sorry`, with the same kernel walk as `extract`. |

For all flags and examples, see [docs/usage.md](docs/usage.md), section "Commands".

## How extract works

1. Build: run `lake build` on `--library`, else `defaultTargets`, else all `[[lean_lib]]` entries. If the build cache is up to date, `extract` skips this step. If the project uses Mathlib and has no Mathlib `.olean` files, `extract` first runs `lake exe cache get`.
2. Select modules: keep every built module that has a `.lean` source, then apply `--library` and `--module`. See [docs/usage.md](docs/usage.md), section "Commands".
3. Atomize: import the modules into one environment and convert each declaration to an atom with type and term dependencies. Edges through auxiliary constants such as `X._proof_N` are folded into the caller. See [docs/schema.md](docs/schema.md), section "Auxiliary-dependency folding".
4. Filter: apply the flags from `.verilib/probes/config.json` and mark generated code as hidden. See [docs/schema.md](docs/schema.md).
5. Specs: compute `specs` and `primary-spec` from the `type-dependencies` of theorems. Only data `def`, `abbrev`, `instance`, `opaque` and `axiom` atoms receive them. Types, projections, proofs and predicates do not. See [docs/schema.md](docs/schema.md), section "Specs and primary-spec".
6. Status: a kernel walk decides `verification-status`. Direct `sorry` carriers read `"unverified"`. An atom that rests on an unexcused `sorry` below it reads `"verified"` with `"status-origin": "kernel-taint"`. Clean atoms read `"transitively-verified"`, or `"verified"` with no marker under `--skip-enrich`. Axioms and externally verified declarations read `"trusted"`, unless their statement rests on a project `sorry`. See [docs/verification-status.md](docs/verification-status.md).
7. Write: wrap the atoms in the Schema 3.0 envelope with the git commit, package information and a timestamp.

## Documentation

- [docs/usage.md](docs/usage.md): command reference, installation, Mathlib cache, configuration and troubleshooting.
- [docs/schema.md](docs/schema.md): output format and field rules.
- [docs/verification-status.md](docs/verification-status.md): how the kernel walk decides `verification-status`, and the stderr lines it prints.
- [tools/audit/README.md](tools/audit/README.md): audit scripts.
- [CHANGELOG.md](CHANGELOG.md): release history.
- [CLAUDE.md](CLAUDE.md): contributor guide, with testing and versioning.
- [specs/template.md](specs/template.md): template for feature specs.

## License

Apache-2.0
