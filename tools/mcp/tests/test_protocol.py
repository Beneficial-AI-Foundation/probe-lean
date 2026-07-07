"""Protocol-level tests: launch the server as a real stdio subprocess and
drive it over MCP JSON-RPC — the same handshake ``claude mcp add`` performs.

Unlike test_server.py (which calls the tool functions directly with
``subprocess`` mocked), these prove the wire layer: process startup, tool
discovery with input schemas, and request/response framing. Only build-free
query tools are exercised, against the saved fixture, so no lake or
probe-lean binary is needed.
"""

import asyncio
import json
import sys
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

PKG_ROOT = Path(__file__).resolve().parents[1]
FIXTURE = Path(__file__).parent / "fixtures" / "sample_extract.json"

EXPECTED_TOOLS = {
    "extract",
    "viewify",
    "check_toolchain",
    "list_atoms",
    "get_atom",
    "find_unverified",
    "find_sorries",
    "get_dependencies",
    "get_specs",
}


def run_session(scenario):
    """Spawn the server over stdio, initialize, and run ``scenario(session)``."""

    async def runner():
        params = StdioServerParameters(
            command=sys.executable,
            args=["-m", "probe_lean_mcp"],
            # ``python -m`` puts cwd on sys.path, so the package is importable
            # without an install — same trick as conftest.py.
            cwd=str(PKG_ROOT),
        )
        async with stdio_client(params) as (read, write):
            async with ClientSession(read, write) as session:
                await session.initialize()
                return await scenario(session)

    return asyncio.run(asyncio.wait_for(runner(), timeout=60))


def payload(result) -> dict:
    """Decode a tool result's JSON text content."""
    return json.loads(result.content[0].text)


def test_handshake_lists_all_tools_with_schemas():
    async def scenario(session):
        return await session.list_tools()

    tools = run_session(scenario).tools
    assert {t.name for t in tools} == EXPECTED_TOOLS
    for tool in tools:
        assert tool.inputSchema.get("type") == "object", tool.name


def test_query_tool_over_the_wire():
    async def scenario(session):
        return await session.call_tool(
            "find_unverified", {"atoms_path": str(FIXTURE), "limit": 10}
        )

    out = payload(run_session(scenario))
    assert out["total"] == 2
    assert {a["name"] for a in out["atoms"]} == {
        "probe:Demo.Broken.bad",
        "probe:Demo.Broken.alsoBad",
    }
    for row in out["atoms"]:
        assert {"name", "kind", "verification-status"} <= row.keys()
        assert "dependencies" not in row  # compact rows only


def test_error_is_structured_not_a_crash():
    async def scenario(session):
        return await session.call_tool(
            "get_atom", {"atoms_path": str(FIXTURE), "name": "Nope.Missing"}
        )

    out = payload(run_session(scenario))
    assert out["error"] == "atom_not_found"
    assert out["hint"]
