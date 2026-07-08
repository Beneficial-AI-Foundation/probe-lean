# Feature: MCP Server for probe-lean

## Summary

Ship a Model Context Protocol (MCP) server that lets coding agents (Claude Code,
Cursor, etc.) drive `probe-lean` and query its output without shelling out or
loading multi-megabyte JSON files into their context. The server is a thin
stdio process that (1) wraps the two CLI commands (`extract`, `viewify`) and
(2) adds read-only *query tools* over the produced extract JSON, so an agent can
ask targeted questions ("which atoms are unverified?", "what does `X` depend
on?") and get back small, structured answers. It lives in `tools/mcp/` and wraps
the `probe-lean` binary already on `PATH` — it does not reimplement any analysis.

## Requirements

- [ ] A stdio MCP server, in `tools/mcp/`, launchable as a single command and registrable via `claude mcp add`.
- [ ] Wrapper tools `extract` and `viewify` invoke the `probe-lean` binary and return a **summary + output path**, never the full JSON blob.
- [ ] Query tools read the extract JSON server-side and return small, filtered, paginated results: `list_atoms`, `get_atom`, `find_unverified`, `find_sorries`, `get_dependencies`, `get_specs`.
- [ ] A `check_toolchain` tool compares the target project's `lean-toolchain` against the installed `probe-lean` build and reports mismatch before any slow build is attempted. The probe-lean side is queried from the **binary itself** (`probe-lean --toolchain`), so it reflects the build extract would actually run, not the source tree the server ships in.
- [ ] Every tool returns a structured error (not a stack trace) when the binary is missing, the toolchain mismatches, the build fails, or no extract output exists yet.
- [ ] Query tools locate extract output the same way the CLI does (default `.verilib/probes/lean_<pkg>_<ver>.json`, or an explicit path), and fail cleanly if it is absent.
- [ ] No changes to the output schema, and only one CLI addition: a root-level `--toolchain` flag that prints the Lean toolchain probe-lean was built with, so `check_toolchain` can ask the binary instead of guessing from files. The server is otherwise additive and version-tracks the schema it reads.

## API / Interface Design

Transport: **stdio**. Language: **Python** (official `mcp` SDK). The server shells
out to `probe-lean` via `subprocess`; the binary must be on `PATH`.

Registration (documented in `tools/mcp/README.md`):

```bash
claude mcp add probe-lean -- python -m probe_lean_mcp
# or: claude mcp add probe-lean -- /path/to/tools/mcp/server.py
```

### Tool surface

All tools take an absolute or cwd-relative `project_path` (or, for query tools,
either `project_path` or an explicit `atoms_path`).

**Run tools** (side-effecting; wrap the CLI):

| Tool | Args | Returns |
|---|---|---|
| `extract` | `project_path`, optional `module`, `library`, `skip_verify`, `skip_enrich`, `class`, `output` | `{ output_path, atom_count, status_counts, sorry_count, duration_s }` — **not** the atom map |
| `viewify` | `project_path`, optional `with_atoms`, `output` | `{ output_path, molecule_count }` |
| `check_toolchain` | `project_path` | `{ project_toolchain, probe_lean_toolchain, probe_lean_toolchain_source, match: bool }` |

**Query tools** (read-only; parse existing extract JSON, no build):

| Tool | Args | Returns |
|---|---|---|
| `list_atoms` | `project_path`\|`atoms_path`, optional `module` prefix, `kind`, `status`, `limit` (default 50), `offset` | `{ total, offset, limit, atoms: [{name, kind, verification-status, code-path, lines}] }` (compact rows, no dep arrays) |
| `get_atom` | + `name` (bare name or `probe:` id) | the full atom object, or a not-found error |
| `find_unverified` | + optional `module`, `limit`, `offset` | atoms whose status ∈ {`unverified`, `failed`} (compact rows) |
| `find_sorries` | + optional `module`, `limit`, `offset` | atoms whose status is `unverified`/`failed` due to a detected sorry (compact rows) |
| `get_dependencies` | + `name`, optional `kind` = `all`\|`type`\|`term` (default `all`) | `{ name, dependencies: [...] }` from the requested edge set |
| `get_specs` | + `name` | `{ name, specs: [...], primary_spec }` |

`verification-status` values are exactly the schema enum: `verified`, `failed`,
`unverified`, `trusted`, `transitively-verified`.

### Output-size contract

- Run tools NEVER return the atom map — only counts + the path.
- Query tools default to `limit = 50` and always echo `total`/`offset`/`limit` so the agent can page.
- `list_atoms`/`find_*` return **compact rows** (name, kind, status, path, line span). Full atoms come only from `get_atom`.

## Behavior

**Normal operation.** An agent calls `check_toolchain` → `extract` (gets a path +
summary) → then `find_unverified` / `get_atom` / `get_dependencies` to navigate the
graph in small steps. `viewify` is available for the web-UI molecule view.

**Edge cases.**
- Extract output missing when a query tool is called → error instructing the agent to run `extract` first.
- Multiple candidate files under `.verilib/probes/` → pick the same one the CLI's auto-detect would; if ambiguous, error listing candidates and asking for explicit `atoms_path`.
- `get_atom`/`get_dependencies`/`get_specs` on an unknown name → not-found error naming the closest matches (by suffix).
- Large `limit` → clamp to a hard max (e.g. 500) and note the clamp in the response.
- Long builds (Mathlib) → run with a generous, configurable timeout; on timeout return a structured `timeout` error rather than hanging.

**Error handling.** Every failure path returns a structured object
`{ error: <machine-code>, message: <human text>, hint?: <next step> }` with codes:
`binary_not_found`, `toolchain_mismatch`, `build_failed`, `no_output`,
`atom_not_found`, `ambiguous_output`, `timeout`, `bad_args`. Build-failure messages
include the tail of `probe-lean`'s stderr so the agent can diagnose.

## Non-Goals

- Not writing the server in Lean, and not embedding an MCP server in the `probe-lean` binary.
- No mutation of extract output; query tools are strictly read-only.
- No HTTP/SSE transport in v1 (stdio only).
- No caching layer or incremental re-extract logic beyond what the CLI already does (the CLI already skips builds when the cache is current).
- No new atom fields or schema changes. The only CLI addition is the root-level `--toolchain` flag backing `check_toolchain`.
- No graph algorithms beyond direct edge lookup (no transitive closure tool in v1 — the extract already computes `transitively-verified`).

## Acceptance Criteria

- [ ] `claude mcp add` registers the server and `extract` runs against a sample project (e.g. `examples/`), returning a path + non-zero `atom_count`.
- [ ] After an extract, `find_unverified` returns only atoms with status `unverified`/`failed`, paginated, without dependency arrays.
- [ ] `get_atom` on a known name returns the full atom; on an unknown name returns `atom_not_found` with suggestions.
- [ ] `check_toolchain` correctly reports match vs mismatch against a project's `lean-toolchain`.
- [ ] Calling a query tool with no extract output present returns `no_output` with a hint to run `extract`, not a crash.
- [ ] A missing `probe-lean` binary returns `binary_not_found`, not a Python traceback.
- [ ] `tools/mcp/` has its own tests (pytest) covering: argument mapping to CLI flags, JSON parsing/filtering/pagination, and each error code. These run independently of `lake` (fixtures use a saved extract JSON).
- [ ] `tools/mcp/README.md` documents install, registration, every tool, and the error codes; root `README.md` and `docs/USAGE.md` gain an "MCP server" section.

## Open Questions (resolved at implementation)

1. **Distribution** → a `pip install`-able Python package under `tools/mcp/`
   (`probe_lean_mcp`), runnable as `probe-lean-mcp` (console entry) or
   `python -m probe_lean_mcp`. No TS package in v1.
2. **`find_sorries` vs `find_unverified`** → confirmed against the schema and a
   real extract: a declaration is `unverified`/`failed` *precisely because* sorry
   detection found a `sorry` in its body, so the two tools return the same set.
   `find_sorries` is kept as a distinct, documented alias for intent-clarity; it
   will diverge only if the schema later records a non-sorry unverified reason.
3. **Progress/streaming** → v1 blocks with a generous, configurable timeout
   (`PROBE_LEAN_TIMEOUT`, default 3600s) and returns a structured `timeout`
   error. No fire-and-poll.
4. **Auto-run `extract`** → no; query tools require the explicit two-step and
   return `no_output` with a hint when the extract JSON is absent.

Additional resolution: `check_toolchain` reports probe-lean's build toolchain
with this precedence, and echoes which source won in
`probe_lean_toolchain_source`:

1. `PROBE_LEAN_TOOLCHAIN` env var (`"env"`) — explicit override.
2. `probe-lean --toolchain` (`"binary"`) — the binary (resolved via
   `PROBE_LEAN_BIN`/`PATH`, same as `extract`) prints the toolchain it was
   built with. This is the normal path: it reflects the build that will run.

If neither source answers (binary missing or predating `--toolchain`
/ < 0.10.0), `probe_lean_toolchain` and its source are `null` and a `note`
suggests upgrading — the value is never guessed from the probe-lean repo's
`lean-toolchain` file, which may not match the installed binary.

`match` compares normalized version tags (`Lean.toolchain` omits the `v` that
the `lean-toolchain` file carries, e.g. `leanprover/lean4:4.28.0-rc1` vs
`leanprover/lean4:v4.28.0-rc1`).

---
Status: implemented (see `tools/mcp/`; 54 pytest tests passing)
