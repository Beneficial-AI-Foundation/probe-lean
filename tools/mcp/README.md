# probe-lean MCP server

A [Model Context Protocol](https://modelcontextprotocol.io) server that lets
coding agents (Claude Code, Cursor, …) drive `probe-lean` and query its output
**without shelling out or loading multi-megabyte JSON into their context**.

It is a thin stdio process that:

1. **wraps** the two CLI commands (`extract`, `viewify`), returning a summary +
   output path rather than the atom map, and
2. adds read-only **query tools** over the produced extract JSON, so an agent
   can ask targeted questions ("which atoms are unverified?", "what does `X`
   depend on?") and get back small, structured answers.

It wraps the `probe-lean` binary already on your `PATH` — it does not
reimplement any analysis, and makes no changes to the output schema. The only
CLI surface it uses beyond `extract`/`viewify` is `probe-lean --toolchain`
(added in 0.10.0), which lets `check_toolchain` report the toolchain of the
binary that will actually run.

## Requirements

- Python ≥ 3.10
- The `probe-lean` binary on `PATH` (or set `PROBE_LEAN_BIN`). See the repo
  [README](../../README.md#installation) for install instructions.

## Install

```bash
cd tools/mcp
pip install -e .            # installs the `mcp` SDK and a `probe-lean-mcp` entry point
```

Or run it without installing (from `tools/mcp/`):

```bash
python -m probe_lean_mcp
```

## Register with Claude Code

```bash
# If installed with pip (entry point on PATH):
claude mcp add probe-lean -- probe-lean-mcp

# Or run the module directly (no install needed), from tools/mcp/:
claude mcp add probe-lean -- python -m probe_lean_mcp
```

Then, in a session, the agent can call `check_toolchain` → `extract` →
`find_unverified` / `get_atom` / `get_dependencies` to navigate a project.

## Configuration (environment variables)

| Variable | Default | Purpose |
|---|---|---|
| `PROBE_LEAN_BIN` | (search `PATH`) | Explicit path to the `probe-lean` binary. |
| `PROBE_LEAN_TIMEOUT` | `3600` | Seconds before a build (`extract`/`viewify`) returns a `timeout` error. |
| `PROBE_LEAN_TOOLCHAIN` | (ask the binary via `--toolchain`) | Override the toolchain `check_toolchain` reports as probe-lean's build toolchain. |

## Tools

### Run tools (side-effecting; wrap the CLI)

| Tool | Key args | Returns |
|---|---|---|
| `extract` | `project_path`, optional `module`, `library`, `skip_verify`, `skip_enrich`, `cls`, `output` | `{ output_path, atom_count, status_counts, sorry_count, duration_s }` — **not** the atom map |
| `viewify` | `project_path`, optional `with_atoms`, `output` | `{ output_path, molecule_count }` |
| `check_toolchain` | `project_path` | `{ project_toolchain, probe_lean_toolchain, probe_lean_toolchain_source, match }` |

Call `check_toolchain` **before** a slow `extract`: a mismatch means the
project's `.olean` files are incompatible with probe-lean's build and the
extract will fail.

`check_toolchain` resolves probe-lean's toolchain with this precedence, echoed
in `probe_lean_toolchain_source`:

1. `"env"` — the `PROBE_LEAN_TOOLCHAIN` override.
2. `"binary"` — `probe-lean --toolchain`, run through the same
   `PROBE_LEAN_BIN`/`PATH` resolution as `extract`, so the answer describes the
   binary that will actually run. This is the normal path.

If neither answers (binary missing, or predates `--toolchain` / < 0.10.0), the
toolchain is reported as `null` with a `note` suggesting an upgrade — it is
never guessed from the probe-lean source tree, which may not match the
installed binary.

`match` compares normalized version tags: the binary reports
`leanprover/lean4:4.28.0-rc1` (no `v`) while the `lean-toolchain` file says
`leanprover/lean4:v4.28.0-rc1` — these count as matching.

### Query tools (read-only; parse existing extract JSON, no build)

All query tools take either `project_path` (auto-detects the sole
`.verilib/probes/lean_*.json`) **or** an explicit `atoms_path`.

| Tool | Extra args | Returns |
|---|---|---|
| `list_atoms` | `module`, `kind`, `status`, `limit` (default 50), `offset` | `{ total, offset, limit, count, atoms: [compact rows] }` |
| `get_atom` | `name` | `{ name, atom }` — the full atom object |
| `find_unverified` | `module`, `limit`, `offset` | compact rows with status `unverified`/`failed` |
| `find_sorries` | `module`, `limit`, `offset` | same set as `find_unverified` (see note) |
| `get_dependencies` | `name`, `kind` = `all`\|`type`\|`term` | `{ name, kind, dependencies }` |
| `get_specs` | `name` | `{ name, specs, primary_spec }` |

**Compact rows** are `{ name, kind, verification-status, code-path, lines }` —
never dependency arrays. Full atoms come only from `get_atom`.

**`name`** accepts the full code-name (`probe:Foo.Bar`), the bare fully-qualified
name (`Foo.Bar`), or a trailing suffix / display-name (`Bar`). An ambiguous
suffix or a miss returns `atom_not_found` with suggestions.

**`verification-status`** values are exactly the schema enum: `verified`,
`failed`, `unverified`, `trusted`, `transitively-verified`.

> **Note on `find_sorries` vs `find_unverified`.** In the current schema a
> declaration is `unverified`/`failed` *precisely because* sorry detection found
> a `sorry` in its body, so both tools return the same set. `find_sorries` is
> exposed separately for intent-clarity; if the schema later distinguishes
> "unverified for another reason", the two will diverge.

## Output-size contract

- Run tools **never** return the atom map — only counts + the output path.
- Query tools default to `limit = 50`, clamp to a hard max of `500` (noting the
  clamp), and always echo `total`/`offset`/`limit`/`count` so an agent can page.

## Errors

Every failure returns a structured object instead of a stack trace:

```json
{ "error": "<code>", "message": "<human text>", "hint": "<next step>" }
```

| Code | Meaning |
|---|---|
| `binary_not_found` | `probe-lean` is not on `PATH` (and `PROBE_LEAN_BIN` is unset/invalid). |
| `toolchain_mismatch` | Reserved for toolchain conflicts (`check_toolchain` reports mismatch in its `match`/`note` fields). |
| `build_failed` | `probe-lean` exited non-zero; the hint carries the tail of its stderr. |
| `no_output` | A query tool found no extract JSON — run `extract` first. |
| `atom_not_found` | Unknown `name`; the hint lists the closest matches. |
| `ambiguous_output` | Multiple `.verilib/probes/lean_*.json` files — pass an explicit `atoms_path`. |
| `timeout` | A build exceeded `PROBE_LEAN_TIMEOUT`. |
| `bad_args` | An argument was out of range (e.g. `kind` not in `all`/`type`/`term`). |

## Development

```bash
cd tools/mcp
pip install -e '.[dev]'
python -m pytest           # 54 tests; run against a saved extract fixture, no lake/binary needed
```

For the full testing approach — unit tests, a protocol-level stdio test, the MCP
Inspector, and live use in Claude Code — see **[TESTING.md](TESTING.md)**.

Tests are split so they exercise the pure logic (`probe_lean_mcp/core.py`) and
the tool layer (`probe_lean_mcp/server.py`, with subprocess mocked)
independently of `lake` and the binary. The design keeps all parsing/filtering
in `core.py`; `server.py` is the only module that shells out and imports the MCP
SDK.
```
tools/mcp/
├── probe_lean_mcp/
│   ├── errors.py     # ProbeError + the closed set of error codes
│   ├── core.py       # pure logic: locate/parse/filter/paginate, argv building, toolchain
│   ├── server.py     # FastMCP tools + subprocess runner
│   └── __main__.py   # `python -m probe_lean_mcp`
├── tests/            # pytest (fixtures + core + server)
└── pyproject.toml
```
