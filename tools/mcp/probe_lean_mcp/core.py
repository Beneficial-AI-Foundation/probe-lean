"""Pure logic for the probe-lean MCP server.

Everything here is free of the MCP SDK and of ``subprocess`` so it can be unit
tested against a saved extract JSON without ``lake`` or the ``probe-lean``
binary. The server module (:mod:`probe_lean_mcp.server`) is the only place that
shells out and talks to the SDK.
"""

from __future__ import annotations

import difflib
import json
import os
from collections import Counter
from pathlib import Path

from .errors import (
    AMBIGUOUS_OUTPUT,
    ATOM_NOT_FOUND,
    NO_OUTPUT,
    ProbeError,
)

# Pagination contract (see spec "Output-size contract").
DEFAULT_LIMIT = 50
HARD_MAX_LIMIT = 500

# Statuses that mean "locally unverified". In the current schema a declaration
# is only ``unverified``/``failed`` because sorry detection found a `sorry` in
# its body, so this set doubles as the "has a sorry" signal (Open Question #2).
UNVERIFIED_STATUSES = frozenset({"unverified", "failed"})

PROBE_PREFIX = "probe:"


# --------------------------------------------------------------------------- #
# Locating and loading extract output
# --------------------------------------------------------------------------- #

def probes_dir(project_path: str | os.PathLike) -> Path:
    return Path(project_path) / ".verilib" / "probes"


def find_atoms_path(
    project_path: str | os.PathLike | None = None,
    atoms_path: str | os.PathLike | None = None,
) -> Path:
    """Locate the extract JSON, mirroring the CLI's default output location.

    Precedence: an explicit ``atoms_path`` wins; otherwise auto-detect the sole
    ``lean_*.json`` under ``<project>/.verilib/probes/``.

    Raises ``no_output`` if nothing is found and ``ambiguous_output`` if several
    candidates exist.
    """
    if atoms_path is not None:
        p = Path(atoms_path)
        if not p.is_file():
            raise ProbeError(
                NO_OUTPUT,
                f"No extract output at {p}.",
                hint="Run `extract` first, or pass a correct `atoms_path`.",
            )
        return p

    if project_path is None:
        raise ProbeError(
            NO_OUTPUT,
            "Neither `project_path` nor `atoms_path` was provided.",
            hint="Pass `project_path` (to auto-detect) or an explicit `atoms_path`.",
        )

    d = probes_dir(project_path)
    candidates = sorted(d.glob("lean_*.json")) if d.is_dir() else []
    if not candidates:
        raise ProbeError(
            NO_OUTPUT,
            f"No extract output found under {d}.",
            hint="Run `extract` on this project first.",
        )
    if len(candidates) > 1:
        names = ", ".join(c.name for c in candidates)
        raise ProbeError(
            AMBIGUOUS_OUTPUT,
            f"Multiple extract files under {d}: {names}.",
            hint="Pass an explicit `atoms_path` to disambiguate.",
        )
    return candidates[0]


def load_envelope(path: str | os.PathLike) -> dict:
    """Read and parse an extract JSON envelope."""
    p = Path(path)
    try:
        with p.open(encoding="utf-8") as fh:
            return json.load(fh)
    except FileNotFoundError:
        raise ProbeError(
            NO_OUTPUT,
            f"No extract output at {p}.",
            hint="Run `extract` first.",
        )
    except json.JSONDecodeError as exc:
        raise ProbeError(
            NO_OUTPUT,
            f"Extract output at {p} is not valid JSON: {exc}.",
            hint="Re-run `extract` to regenerate it.",
        )


def atoms_of(envelope: dict) -> dict:
    """Return the atom map from an envelope (the ``data`` object)."""
    return envelope.get("data") or {}


# --------------------------------------------------------------------------- #
# Compact projections
# --------------------------------------------------------------------------- #

def _line_span(atom: dict) -> str | None:
    ct = atom.get("code-text")
    if not isinstance(ct, dict):
        return None
    start, end = ct.get("lines-start"), ct.get("lines-end")
    if start is None or end is None:
        return None
    return f"{start}-{end}"


def compact_row(name: str, atom: dict) -> dict:
    """A small row for list/find results -- never includes dependency arrays."""
    return {
        "name": name,
        "kind": atom.get("kind"),
        "verification-status": atom.get("verification-status"),
        "code-path": atom.get("code-path"),
        "lines": _line_span(atom),
    }


# --------------------------------------------------------------------------- #
# Name resolution
# --------------------------------------------------------------------------- #

def _fqn(key: str) -> str:
    """Strip the ``probe:`` prefix from a code-name key."""
    return key[len(PROBE_PREFIX):] if key.startswith(PROBE_PREFIX) else key


def _suggestions(atoms: dict, name: str, n: int = 5) -> list[str]:
    """Closest existing code-names to a miss, by fuzzy match on the FQN."""
    target = _fqn(name.strip())
    fqns = {_fqn(k): k for k in atoms}
    close = difflib.get_close_matches(target, list(fqns), n=n, cutoff=0.5)
    return [fqns[c] for c in close]


def resolve_atom(atoms: dict, name: str) -> tuple[str, dict]:
    """Resolve a user-supplied name to a ``(key, atom)`` pair.

    Accepts the full key (``probe:Foo.Bar``), the bare FQN (``Foo.Bar``), or a
    trailing suffix / display-name (``Bar``). Raises ``atom_not_found`` with
    suggestions when there is no match, or when a suffix is ambiguous.
    """
    if not name or not name.strip():
        raise ProbeError(ATOM_NOT_FOUND, "Empty atom name.", hint="Pass a name like `Foo.Bar`.")
    q = name.strip()

    # 1. Exact key, or with the prefix added.
    if q in atoms:
        return q, atoms[q]
    prefixed = q if q.startswith(PROBE_PREFIX) else PROBE_PREFIX + q
    if prefixed in atoms:
        return prefixed, atoms[prefixed]

    # 2. Suffix / display-name match on the FQN.
    bare = _fqn(q)
    matches = [
        k for k in atoms
        if _fqn(k) == bare or _fqn(k).endswith("." + bare)
    ]
    if len(matches) == 1:
        return matches[0], atoms[matches[0]]
    if len(matches) > 1:
        raise ProbeError(
            ATOM_NOT_FOUND,
            f"Ambiguous name '{name}' matches {len(matches)} atoms.",
            hint="Use a fully qualified name. Candidates: " + ", ".join(sorted(matches)[:5]),
        )

    # 3. No match -> fuzzy suggestions.
    sug = _suggestions(atoms, q)
    hint = ("Closest: " + ", ".join(sug)) if sug else "Run `list_atoms` to browse available names."
    raise ProbeError(ATOM_NOT_FOUND, f"No atom named '{name}'.", hint=hint)


# --------------------------------------------------------------------------- #
# Filtering and pagination
# --------------------------------------------------------------------------- #

def filter_atoms(
    atoms: dict,
    module: str | None = None,
    kind: str | None = None,
    status: str | None = None,
    statuses: frozenset[str] | None = None,
) -> list[tuple[str, dict]]:
    """Return ``(key, atom)`` pairs matching the filters, sorted by key.

    ``module`` matches as a prefix of the atom's ``code-module``. ``status``
    matches one exact value; ``statuses`` matches any of a set.
    """
    out = []
    for key, atom in atoms.items():
        if module is not None:
            cm = atom.get("code-module") or ""
            if not (cm == module or cm.startswith(module + ".") or cm.startswith(module)):
                continue
        if kind is not None and atom.get("kind") != kind:
            continue
        st = atom.get("verification-status")
        if status is not None and st != status:
            continue
        if statuses is not None and st not in statuses:
            continue
        out.append((key, atom))
    out.sort(key=lambda kv: kv[0])
    return out


def paginate(rows: list, limit: int | None, offset: int | None) -> dict:
    """Slice ``rows`` and return the pagination envelope.

    Clamps ``limit`` to ``HARD_MAX_LIMIT`` (noting the clamp) and normalizes a
    missing/invalid ``limit``/``offset``.
    """
    total = len(rows)
    off = offset if isinstance(offset, int) and offset > 0 else 0
    lim = limit if isinstance(limit, int) and limit > 0 else DEFAULT_LIMIT
    clamped = False
    if lim > HARD_MAX_LIMIT:
        lim = HARD_MAX_LIMIT
        clamped = True
    page = rows[off:off + lim]
    result: dict = {"total": total, "offset": off, "limit": lim, "count": len(page)}
    if clamped:
        result["clamped"] = True
        result["note"] = f"limit clamped to hard max {HARD_MAX_LIMIT}"
    return {**result, "_page": page}


# --------------------------------------------------------------------------- #
# Summaries
# --------------------------------------------------------------------------- #

def summarize_extract(envelope: dict) -> dict:
    """Counts-only summary of an extract envelope (never the atom map)."""
    atoms = atoms_of(envelope)
    status_counts: Counter[str] = Counter()
    sorry_count = 0
    for atom in atoms.values():
        st = atom.get("verification-status")
        if st is not None:
            status_counts[st] += 1
        if st in UNVERIFIED_STATUSES:
            sorry_count += 1
    return {
        "atom_count": len(atoms),
        "status_counts": dict(sorted(status_counts.items())),
        "sorry_count": sorry_count,
    }


# --------------------------------------------------------------------------- #
# CLI argument construction
# --------------------------------------------------------------------------- #

def build_extract_argv(
    project_path: str,
    module: str | None = None,
    library: str | None = None,
    skip_verify: bool = False,
    skip_enrich: bool = False,
    cls: str | None = None,
    output: str | None = None,
) -> list[str]:
    """Map the ``extract`` tool arguments to a ``probe-lean`` CLI argv."""
    argv = ["extract"]
    if module:
        argv += ["--module", module]
    if library:
        argv += ["--library", library]
    if skip_verify:
        argv.append("--skip-verify")
    if skip_enrich:
        argv.append("--skip-enrich")
    if cls:
        argv += ["--class", cls]
    if output:
        argv += ["--output", output]
    argv.append(project_path)
    return argv


def build_viewify_argv(
    project_path: str,
    with_atoms: str | None = None,
    output: str | None = None,
) -> list[str]:
    """Map the ``viewify`` tool arguments to a ``probe-lean`` CLI argv."""
    argv = ["viewify"]
    if with_atoms:
        argv += ["--with-atoms", with_atoms]
    if output:
        argv += ["--output", output]
    argv.append(project_path)
    return argv


# --------------------------------------------------------------------------- #
# Toolchain
# --------------------------------------------------------------------------- #

def read_toolchain(project_path: str | os.PathLike) -> str | None:
    """Read a project's ``lean-toolchain`` (trimmed), or ``None`` if absent."""
    p = Path(project_path) / "lean-toolchain"
    try:
        return p.read_text(encoding="utf-8").strip()
    except (FileNotFoundError, NotADirectoryError):
        return None


def toolchain_tag(s: str | None) -> str | None:
    """Normalize a toolchain string to its bare version tag.

    ``leanprover/lean4:v4.28.0-rc1`` and ``leanprover/lean4:4.28.0-rc1`` (the
    ``Lean.toolchain`` constant omits the ``v``) both normalize to
    ``4.28.0-rc1`` so they compare equal.
    """
    if s is None:
        return None
    tag = s.rsplit(":", 1)[-1].strip()
    if tag.startswith("v"):
        tag = tag[1:]
    return tag or None


def toolchain_from_env() -> str | None:
    """The ``PROBE_LEAN_TOOLCHAIN`` override, or ``None`` if unset/blank."""
    env = os.environ.get("PROBE_LEAN_TOOLCHAIN")
    return env.strip() if env and env.strip() else None


def toolchain_from_repo() -> str | None:
    """Fallback: the probe-lean repo root's ``lean-toolchain``.

    This describes the source tree the server ships inside, NOT necessarily the
    installed binary — only used when the binary is too old to report its own
    toolchain via ``probe-lean --toolchain``.
    """
    # tools/mcp/probe_lean_mcp/core.py -> repo root is three levels up.
    repo_root = Path(__file__).resolve().parents[3]
    return read_toolchain(repo_root)
