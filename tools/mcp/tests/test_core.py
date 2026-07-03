"""Unit tests for the pure core logic -- no lake, binary, or MCP SDK needed."""

import pytest

from probe_lean_mcp import core
from probe_lean_mcp.errors import (
    AMBIGUOUS_OUTPUT,
    ATOM_NOT_FOUND,
    NO_OUTPUT,
    ProbeError,
)


# --------------------------------------------------------------------------- #
# CLI argument mapping
# --------------------------------------------------------------------------- #

def test_extract_argv_minimal():
    assert core.build_extract_argv("proj") == ["extract", "proj"]


def test_extract_argv_all_flags():
    argv = core.build_extract_argv(
        "proj", module="Demo", library="a,b", skip_verify=True,
        skip_enrich=True, cls="security-protocol", output="out.json",
    )
    assert argv == [
        "extract", "--module", "Demo", "--library", "a,b",
        "--skip-verify", "--skip-enrich", "--class", "security-protocol",
        "--output", "out.json", "proj",
    ]
    # Positional project path is always last.
    assert argv[-1] == "proj"


def test_viewify_argv():
    assert core.build_viewify_argv("proj") == ["viewify", "proj"]
    assert core.build_viewify_argv("proj", with_atoms="a.json", output="o.json") == [
        "viewify", "--with-atoms", "a.json", "--output", "o.json", "proj",
    ]


# --------------------------------------------------------------------------- #
# Locating extract output
# --------------------------------------------------------------------------- #

def test_find_atoms_explicit_path(fixture_path):
    assert core.find_atoms_path(atoms_path=fixture_path).name == "sample_extract.json"


def test_find_atoms_explicit_missing(tmp_path):
    with pytest.raises(ProbeError) as ei:
        core.find_atoms_path(atoms_path=str(tmp_path / "nope.json"))
    assert ei.value.code == NO_OUTPUT


def test_find_atoms_autodetect(tmp_path):
    probes = tmp_path / ".verilib" / "probes"
    probes.mkdir(parents=True)
    (probes / "lean_demo_abc.json").write_text("{}")
    assert core.find_atoms_path(project_path=str(tmp_path)).name == "lean_demo_abc.json"


def test_find_atoms_none(tmp_path):
    with pytest.raises(ProbeError) as ei:
        core.find_atoms_path(project_path=str(tmp_path))
    assert ei.value.code == NO_OUTPUT
    assert "extract" in (ei.value.hint or "")


def test_find_atoms_ambiguous(tmp_path):
    probes = tmp_path / ".verilib" / "probes"
    probes.mkdir(parents=True)
    (probes / "lean_a_1.json").write_text("{}")
    (probes / "lean_b_2.json").write_text("{}")
    with pytest.raises(ProbeError) as ei:
        core.find_atoms_path(project_path=str(tmp_path))
    assert ei.value.code == AMBIGUOUS_OUTPUT


# --------------------------------------------------------------------------- #
# Compact rows & loading
# --------------------------------------------------------------------------- #

def test_compact_row_shape(atoms):
    row = core.compact_row("probe:Demo.Core.add", atoms["probe:Demo.Core.add"])
    assert row == {
        "name": "probe:Demo.Core.add",
        "kind": "def",
        "verification-status": "verified",
        "code-path": "Demo/Core.lean",
        "lines": "1-5",
    }
    # Compact rows never leak dependency arrays.
    assert "dependencies" not in row


def test_load_bad_json(tmp_path):
    bad = tmp_path / "bad.json"
    bad.write_text("{not json")
    with pytest.raises(ProbeError) as ei:
        core.load_envelope(bad)
    assert ei.value.code == NO_OUTPUT


# --------------------------------------------------------------------------- #
# Name resolution
# --------------------------------------------------------------------------- #

def test_resolve_exact_key(atoms):
    key, _ = core.resolve_atom(atoms, "probe:Demo.Core.helper")
    assert key == "probe:Demo.Core.helper"


def test_resolve_bare_fqn(atoms):
    key, _ = core.resolve_atom(atoms, "Demo.Core.helper")
    assert key == "probe:Demo.Core.helper"


def test_resolve_suffix(atoms):
    key, _ = core.resolve_atom(atoms, "helper")
    assert key == "probe:Demo.Core.helper"


def test_resolve_ambiguous_suffix(atoms):
    # "add" is a display-name of both Demo.Core.add and Demo.Other.add.
    with pytest.raises(ProbeError) as ei:
        core.resolve_atom(atoms, "add")
    assert ei.value.code == ATOM_NOT_FOUND
    assert "Ambiguous" in ei.value.message


def test_resolve_not_found_suggests(atoms):
    with pytest.raises(ProbeError) as ei:
        core.resolve_atom(atoms, "Demo.Core.helpr")
    assert ei.value.code == ATOM_NOT_FOUND
    assert "helper" in (ei.value.hint or "")


# --------------------------------------------------------------------------- #
# Filtering
# --------------------------------------------------------------------------- #

def test_filter_by_module(atoms):
    pairs = core.filter_atoms(atoms, module="Demo.Broken")
    assert {k for k, _ in pairs} == {
        "probe:Demo.Broken.bad", "probe:Demo.Broken.alsoBad",
    }


def test_filter_by_kind(atoms):
    pairs = core.filter_atoms(atoms, kind="axiom")
    assert [k for k, _ in pairs] == ["probe:Demo.Trust.ax"]


def test_filter_by_status(atoms):
    pairs = core.filter_atoms(atoms, status="unverified")
    assert [k for k, _ in pairs] == ["probe:Demo.Broken.bad"]


def test_filter_unverified_set(atoms):
    pairs = core.filter_atoms(atoms, statuses=core.UNVERIFIED_STATUSES)
    assert {k for k, _ in pairs} == {
        "probe:Demo.Broken.bad", "probe:Demo.Broken.alsoBad",
    }


def test_filter_is_sorted(atoms):
    pairs = core.filter_atoms(atoms)
    keys = [k for k, _ in pairs]
    assert keys == sorted(keys)


# --------------------------------------------------------------------------- #
# Pagination
# --------------------------------------------------------------------------- #

def test_paginate_defaults():
    page = core.paginate(list(range(10)), None, None)
    assert page["total"] == 10
    assert page["offset"] == 0
    assert page["limit"] == core.DEFAULT_LIMIT
    assert page["_page"] == list(range(10))


def test_paginate_offset_and_limit():
    page = core.paginate(list(range(10)), 3, 2)
    assert page["_page"] == [2, 3, 4]
    assert page["count"] == 3


def test_paginate_clamps_hard_max():
    page = core.paginate(list(range(1000)), 10_000, 0)
    assert page["limit"] == core.HARD_MAX_LIMIT
    assert page.get("clamped") is True
    assert len(page["_page"]) == core.HARD_MAX_LIMIT


# --------------------------------------------------------------------------- #
# Summary
# --------------------------------------------------------------------------- #

def test_summarize_extract(envelope):
    summary = core.summarize_extract(envelope)
    assert summary["atom_count"] == 7
    assert summary["status_counts"] == {
        "failed": 1, "trusted": 1, "transitively-verified": 1,
        "unverified": 1, "verified": 3,
    }
    # Both locally-unverified statuses count as sorries.
    assert summary["sorry_count"] == 2


# --------------------------------------------------------------------------- #
# Toolchain
# --------------------------------------------------------------------------- #

def test_read_toolchain(tmp_path):
    (tmp_path / "lean-toolchain").write_text("leanprover/lean4:v4.30.0\n")
    assert core.read_toolchain(tmp_path) == "leanprover/lean4:v4.30.0"


def test_read_toolchain_missing(tmp_path):
    assert core.read_toolchain(tmp_path) is None


def test_probe_toolchain_env_override(monkeypatch):
    monkeypatch.setenv("PROBE_LEAN_TOOLCHAIN", "leanprover/lean4:v9.9.9")
    assert core.probe_lean_toolchain() == "leanprover/lean4:v9.9.9"
