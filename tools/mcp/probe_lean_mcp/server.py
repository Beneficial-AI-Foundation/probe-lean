"""MCP server exposing probe-lean's CLI and query tools over stdio.

This is the only module that shells out to ``probe-lean`` and imports the MCP
SDK. All parsing/filtering lives in :mod:`probe_lean_mcp.core`.
"""

from __future__ import annotations

import functools
import os
import shutil
import subprocess
import time
from pathlib import Path
from typing import Optional

from mcp.server.fastmcp import FastMCP

from . import core
from .errors import (
    BINARY_NOT_FOUND,
    BUILD_FAILED,
    NO_OUTPUT,
    TIMEOUT,
    ProbeError,
)

mcp = FastMCP("probe-lean")

# Generous default so a cold Mathlib build does not spuriously time out.
DEFAULT_TIMEOUT_S = int(os.environ.get("PROBE_LEAN_TIMEOUT", "3600"))

# How many characters of stderr to echo back on a build failure.
STDERR_TAIL = 2000


def _guard(fn):
    """Convert any raised :class:`ProbeError` into its structured dict."""

    @functools.wraps(fn)
    def wrapper(*args, **kwargs):
        try:
            return fn(*args, **kwargs)
        except ProbeError as exc:
            return exc.to_dict()

    return wrapper


def _binary() -> str:
    """Locate the ``probe-lean`` binary (``PROBE_LEAN_BIN`` overrides PATH)."""
    override = os.environ.get("PROBE_LEAN_BIN")
    if override:
        if Path(override).is_file():
            return override
        raise ProbeError(
            BINARY_NOT_FOUND,
            f"PROBE_LEAN_BIN points at {override}, which is not a file.",
            hint="Fix PROBE_LEAN_BIN or unset it to use PATH.",
        )
    found = shutil.which("probe-lean")
    if not found:
        raise ProbeError(
            BINARY_NOT_FOUND,
            "The `probe-lean` binary was not found on PATH.",
            hint="Install probe-lean and ensure it is on PATH, or set PROBE_LEAN_BIN.",
        )
    return found


def _run(argv: list[str], timeout: int) -> subprocess.CompletedProcess:
    """Run ``probe-lean`` with the given argv, mapping failures to ProbeError."""
    binary = _binary()
    try:
        return subprocess.run(
            [binary, *argv],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        raise ProbeError(
            TIMEOUT,
            f"`probe-lean {argv[0]}` did not finish within {timeout}s.",
            hint="Increase PROBE_LEAN_TIMEOUT, or pre-warm the build "
            "(e.g. `lake exe cache get` for Mathlib) before extracting.",
        )


def _check_build(cp: subprocess.CompletedProcess, argv: list[str]) -> None:
    if cp.returncode != 0:
        tail = (cp.stderr or cp.stdout or "").strip()[-STDERR_TAIL:]
        raise ProbeError(
            BUILD_FAILED,
            f"`probe-lean {argv[0]}` exited with code {cp.returncode}.",
            hint="stderr tail:\n" + tail if tail else "No output captured.",
        )


# --------------------------------------------------------------------------- #
# Run tools (side-effecting; wrap the CLI)
# --------------------------------------------------------------------------- #

@mcp.tool()
@_guard
def extract(
    project_path: str,
    module: Optional[str] = None,
    library: Optional[str] = None,
    skip_verify: bool = False,
    skip_enrich: bool = False,
    cls: Optional[str] = None,
    output: Optional[str] = None,
) -> dict:
    """Run `probe-lean extract` on a Lean project.

    Builds the project, extracts atoms, computes specs, and detects sorries.
    Returns a summary and the output path -- never the full atom map. Use the
    query tools (list_atoms, find_unverified, get_atom, ...) to inspect results.

    Args:
        project_path: Path to the Lean 4 project.
        module: Restrict analysis to this module-name prefix.
        library: Comma-separated library names to build and analyze.
        skip_verify: Skip sorry detection.
        skip_enrich: Skip transitive-verification enrichment.
        cls: Override the detected project class (e.g. "security-protocol").
        output: Explicit output path (default .verilib/probes/lean_<pkg>_<ver>.json).
    """
    argv = core.build_extract_argv(
        project_path, module=module, library=library,
        skip_verify=skip_verify, skip_enrich=skip_enrich, cls=cls, output=output,
    )
    start = time.monotonic()
    cp = _run(argv, DEFAULT_TIMEOUT_S)
    duration = round(time.monotonic() - start, 1)
    _check_build(cp, argv)

    out_path = core.find_atoms_path(
        project_path=project_path, atoms_path=output,
    )
    envelope = core.load_envelope(out_path)
    summary = core.summarize_extract(envelope)
    return {"output_path": str(out_path), "duration_s": duration, **summary}


@mcp.tool()
@_guard
def viewify(
    project_path: str,
    with_atoms: Optional[str] = None,
    output: Optional[str] = None,
) -> dict:
    """Run `probe-lean viewify` to produce web-UI molecules from extract output.

    Returns the molecules output path and a count -- never the molecule map.

    Args:
        project_path: Path to the Lean 4 project.
        with_atoms: Path to extract output (default: auto-detect from .verilib/probes/).
        output: Explicit output path (default .verilib/views/molecules_all.json).
    """
    argv = core.build_viewify_argv(project_path, with_atoms=with_atoms, output=output)
    cp = _run(argv, DEFAULT_TIMEOUT_S)
    _check_build(cp, argv)

    out_path = Path(output) if output else (
        Path(project_path) / ".verilib" / "views" / "molecules_all.json"
    )
    envelope = core.load_envelope(out_path)
    molecules = envelope.get("data") or {}
    return {"output_path": str(out_path), "molecule_count": len(molecules)}


@mcp.tool()
@_guard
def check_toolchain(project_path: str) -> dict:
    """Compare a project's lean-toolchain against probe-lean's build toolchain.

    Call this before a slow extract: a mismatch means the .olean files would be
    incompatible and the build would fail or be rejected.

    Args:
        project_path: Path to the Lean 4 project.
    """
    project_tc = core.read_toolchain(project_path)
    probe_tc = core.probe_lean_toolchain()
    match = bool(project_tc and probe_tc and project_tc == probe_tc)
    result = {
        "project_toolchain": project_tc,
        "probe_lean_toolchain": probe_tc,
        "match": match,
    }
    if project_tc is None:
        result["note"] = "No lean-toolchain file found in the project."
    elif probe_tc is None:
        result["note"] = (
            "Could not determine probe-lean's toolchain; "
            "set PROBE_LEAN_TOOLCHAIN to compare."
        )
    elif not match:
        result["note"] = (
            "Toolchain mismatch: extract will likely fail. "
            "Rebuild probe-lean against the project's toolchain, or vice versa."
        )
    return result


# --------------------------------------------------------------------------- #
# Query tools (read-only; parse existing extract JSON)
# --------------------------------------------------------------------------- #

def _load(project_path: Optional[str], atoms_path: Optional[str]) -> dict:
    path = core.find_atoms_path(project_path=project_path, atoms_path=atoms_path)
    return core.atoms_of(core.load_envelope(path))


def _rows_result(pairs, limit, offset) -> dict:
    page = core.paginate([core.compact_row(k, a) for k, a in pairs], limit, offset)
    rows = page.pop("_page")
    return {**page, "atoms": rows}


@mcp.tool()
@_guard
def list_atoms(
    project_path: Optional[str] = None,
    atoms_path: Optional[str] = None,
    module: Optional[str] = None,
    kind: Optional[str] = None,
    status: Optional[str] = None,
    limit: int = core.DEFAULT_LIMIT,
    offset: int = 0,
) -> dict:
    """List atoms as compact rows (name, kind, status, path, lines), paginated.

    Dependency arrays are omitted -- use get_atom for the full object.

    Args:
        project_path: Project whose extract output to read (auto-detects the file).
        atoms_path: Explicit path to an extract JSON (alternative to project_path).
        module: Filter to a code-module prefix.
        kind: Filter to a declaration kind (def, theorem, structure, ...).
        status: Filter to one verification-status value.
        limit: Max rows (default 50, hard max 500).
        offset: Rows to skip for pagination.
    """
    atoms = _load(project_path, atoms_path)
    pairs = core.filter_atoms(atoms, module=module, kind=kind, status=status)
    return _rows_result(pairs, limit, offset)


@mcp.tool()
@_guard
def get_atom(
    name: str,
    project_path: Optional[str] = None,
    atoms_path: Optional[str] = None,
) -> dict:
    """Return the full atom object for one declaration.

    Args:
        name: Code-name -- full (`probe:Foo.Bar`), bare FQN (`Foo.Bar`), or suffix (`Bar`).
        project_path: Project whose extract output to read.
        atoms_path: Explicit path to an extract JSON.
    """
    atoms = _load(project_path, atoms_path)
    key, atom = core.resolve_atom(atoms, name)
    return {"name": key, "atom": atom}


@mcp.tool()
@_guard
def find_unverified(
    project_path: Optional[str] = None,
    atoms_path: Optional[str] = None,
    module: Optional[str] = None,
    limit: int = core.DEFAULT_LIMIT,
    offset: int = 0,
) -> dict:
    """List atoms whose verification-status is `unverified` or `failed`.

    Note: `transitively-verified` atoms are locally sorry-free (a dependency is
    unverified); they are NOT returned here.

    Args:
        project_path: Project whose extract output to read.
        atoms_path: Explicit path to an extract JSON.
        module: Filter to a code-module prefix.
        limit: Max rows (default 50, hard max 500).
        offset: Rows to skip for pagination.
    """
    atoms = _load(project_path, atoms_path)
    pairs = core.filter_atoms(atoms, module=module, statuses=core.UNVERIFIED_STATUSES)
    return _rows_result(pairs, limit, offset)


@mcp.tool()
@_guard
def find_sorries(
    project_path: Optional[str] = None,
    atoms_path: Optional[str] = None,
    module: Optional[str] = None,
    limit: int = core.DEFAULT_LIMIT,
    offset: int = 0,
) -> dict:
    """List atoms that contain a `sorry`.

    In the current schema a declaration is `unverified`/`failed` precisely when
    sorry detection found a `sorry` in its body, so this returns the same set as
    find_unverified. It is exposed separately for intent-clarity.

    Args:
        project_path: Project whose extract output to read.
        atoms_path: Explicit path to an extract JSON.
        module: Filter to a code-module prefix.
        limit: Max rows (default 50, hard max 500).
        offset: Rows to skip for pagination.
    """
    atoms = _load(project_path, atoms_path)
    pairs = core.filter_atoms(atoms, module=module, statuses=core.UNVERIFIED_STATUSES)
    return _rows_result(pairs, limit, offset)


@mcp.tool()
@_guard
def get_dependencies(
    name: str,
    project_path: Optional[str] = None,
    atoms_path: Optional[str] = None,
    kind: str = "all",
) -> dict:
    """Return one atom's dependency edges.

    Args:
        name: Code-name -- full, bare FQN, or suffix.
        project_path: Project whose extract output to read.
        atoms_path: Explicit path to an extract JSON.
        kind: Which edge set -- "all" (default), "type", or "term".
    """
    if kind not in ("all", "type", "term"):
        from .errors import BAD_ARGS
        raise ProbeError(BAD_ARGS, f"kind must be all|type|term, got '{kind}'.")
    atoms = _load(project_path, atoms_path)
    key, atom = core.resolve_atom(atoms, name)
    field = {
        "all": "dependencies",
        "type": "type-dependencies",
        "term": "term-dependencies",
    }[kind]
    return {"name": key, "kind": kind, "dependencies": atom.get(field, [])}


@mcp.tool()
@_guard
def get_specs(
    name: str,
    project_path: Optional[str] = None,
    atoms_path: Optional[str] = None,
) -> dict:
    """Return the specification theorems associated with an atom.

    Args:
        name: Code-name -- full, bare FQN, or suffix.
        project_path: Project whose extract output to read.
        atoms_path: Explicit path to an extract JSON.
    """
    atoms = _load(project_path, atoms_path)
    key, atom = core.resolve_atom(atoms, name)
    return {
        "name": key,
        "specs": atom.get("specs", []),
        "primary_spec": atom.get("primary-spec"),
    }


def main() -> None:
    """Entry point: run the MCP server over stdio."""
    mcp.run()


# Silence unused-import lint for re-exported error codes documented in README.
_ = (NO_OUTPUT,)
