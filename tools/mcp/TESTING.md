# Testing the probe-lean MCP server

There are four layers of testing, fastest to most realistic. Start with layer 1
for regression safety, use layer 3 to explore interactively, and finish with
layer 4 for the real agent experience.

All commands assume you are in `tools/mcp/`:

```bash
cd tools/mcp
```

---

## Layer 1 — Unit tests (fastest; no build, no binary)

The 54 pytest tests run against a saved extract fixture
(`tests/fixtures/sample_extract.json`), so they are fast and never touch
`lake` or the `probe-lean` binary. They cover CLI argument mapping, JSON
parsing/filtering/pagination, name resolution, every error code, and a
stdio protocol round-trip (layer 2).

```bash
pip install -e '.[dev]'      # once: installs pytest + the mcp SDK
python -m pytest -q
```

Expected: `54 passed`.

The tests are split so the pure logic (`probe_lean_mcp/core.py`) and the tool
layer (`probe_lean_mcp/server.py`, with `subprocess` mocked) are exercised
independently:

- `tests/test_core.py` — argv building, output-file location, compact rows, name
  resolution, filtering, pagination clamping, summary, toolchain reading and
  version-tag normalization.
- `tests/test_server.py` — each tool's happy path and error path, with the
  build subprocess mocked (no real `lake` run), including `check_toolchain`'s
  env → binary (`--toolchain`) resolution order and the unknown-toolchain
  path for binaries predating the flag.
- `tests/test_protocol.py` — launches the server as a real stdio subprocess
  and drives it over MCP JSON-RPC (layer 2, automated).

---

## Layer 2 — Protocol test (proves the stdio JSON-RPC layer)

The unit tests call the tool functions directly; this layer launches the server
as a subprocess and drives it through the real MCP stdio protocol with an
in-process client — the same handshake `claude mcp add` uses.

This layer is automated in `tests/test_protocol.py` and runs as part of the
pytest suite above (against the saved fixture). To explore the same flow by
hand against a **real** extract file, use the standalone snippet:

```bash
python3 - <<'PY'
import asyncio, json
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

async def main():
    params = StdioServerParameters(command="python3", args=["-m", "probe_lean_mcp"])
    async with stdio_client(params) as (r, w):
        async with ClientSession(r, w) as s:
            await s.initialize()
            tools = await s.list_tools()
            print("TOOLS:", sorted(t.name for t in tools.tools))

            # Query a real extract file (adjust the path as needed):
            res = await s.call_tool("find_unverified", {
                "atoms_path": "../../lean_lean4lean_97addd5.json", "limit": 2})
            print("find_unverified:", json.loads(res.content[0].text))

            # Error path: unknown atom -> structured error, not a crash.
            err = await s.call_tool("get_atom", {
                "atoms_path": "../../lean_lean4lean_97addd5.json", "name": "Nope.Missing"})
            print("error path:", json.loads(err.content[0].text)["error"])

asyncio.run(main())
PY
```

Expected: the 9 tool names, a `find_unverified` result with `total`/`count`, and
`error path: atom_not_found`.

---

## Layer 3 — MCP Inspector (interactive GUI)

The [MCP Inspector](https://github.com/modelcontextprotocol/inspector) gives a
browser UI to see each tool's schema and call it with a form. Best for poking at
behavior by hand.

```bash
npx @modelcontextprotocol/inspector python3 -m probe_lean_mcp
```

In the UI:

- Open the **Tools** tab to see all 9 tools and their input schemas.
- Call a **query tool** without a build by pointing it at an existing extract
  file, e.g. `list_atoms` with
  `atoms_path = /home/zhang-liao/probe-lean/lean_lean4lean_97addd5.json`.
- Call `check_toolchain` with `project_path = /home/zhang-liao/probe-lean` to see
  the match report.

---

## Layer 4 — Live in Claude Code (the real thing)

Register the server and use it from an agent session.

```bash
pip install -e .
claude mcp add probe-lean -- probe-lean-mcp
claude mcp list            # confirm it is registered and reachable
```

Then, in a Claude Code session:

- Ask: *"use probe-lean to list the unverified atoms in this project"* — the
  agent will call `find_unverified` / `list_atoms`.
- Use `/mcp` to inspect the connection and available tools.

To remove it again:

```bash
claude mcp remove probe-lean
```

---

## Live `extract` (closing the build gap)

Layers 1–2 mock the build subprocess. To exercise the real
build → summary → output-path flow, call the `extract` tool against a built Lean
project (via the Inspector, layer 3, or Claude Code, layer 4):

```
extract  project_path = /home/zhang-liao/probe-lean
```

This runs `lake build`, then returns `{ output_path, atom_count, status_counts,
sorry_count, duration_s }`. For projects that depend on Mathlib, warm the cache
first (`lake exe cache get` in the target project) and expect a long first run —
raise `PROBE_LEAN_TIMEOUT` if needed.

---

## Configuration used by tests

| Variable | Purpose in testing |
|---|---|
| `PROBE_LEAN_BIN` | Point at a specific `probe-lean` binary if it is not on `PATH`. |
| `PROBE_LEAN_TIMEOUT` | Lower it to test the `timeout` error path quickly; raise it for real Mathlib builds. |
| `PROBE_LEAN_TOOLCHAIN` | Set an explicit toolchain string to test `check_toolchain` match/mismatch. |
