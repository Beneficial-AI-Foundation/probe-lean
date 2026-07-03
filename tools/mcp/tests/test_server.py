"""Tests for the MCP tool layer. Subprocess calls are mocked -- no build runs."""

import subprocess
import types

import pytest

from probe_lean_mcp import server


def fake_cp(returncode=0, stdout="", stderr=""):
    return types.SimpleNamespace(returncode=returncode, stdout=stdout, stderr=stderr)


# --------------------------------------------------------------------------- #
# Run tools: extract / viewify
# --------------------------------------------------------------------------- #

def test_extract_returns_summary_not_atoms(monkeypatch, fixture_path):
    monkeypatch.setattr(server, "_run", lambda argv, timeout: fake_cp(0))
    result = server.extract("proj", output=fixture_path)
    assert result["output_path"] == fixture_path
    assert result["atom_count"] == 7
    assert result["sorry_count"] == 2
    assert "duration_s" in result
    # A run tool must never return the atom map.
    assert "data" not in result and "atoms" not in result


def test_extract_build_failed(monkeypatch):
    monkeypatch.setattr(server, "_run", lambda argv, timeout: fake_cp(1, stderr="boom: sorry"))
    result = server.extract("proj")
    assert result["error"] == "build_failed"
    assert "boom" in result["hint"]


def test_extract_binary_not_found(monkeypatch):
    monkeypatch.delenv("PROBE_LEAN_BIN", raising=False)
    monkeypatch.setattr(server.shutil, "which", lambda _: None)
    result = server.extract("proj")
    assert result["error"] == "binary_not_found"


def test_extract_timeout(monkeypatch):
    monkeypatch.setattr(server, "_binary", lambda: "/bin/true")

    def boom(*a, **k):
        raise subprocess.TimeoutExpired(cmd="probe-lean", timeout=1)

    monkeypatch.setattr(server.subprocess, "run", boom)
    result = server.extract("proj")
    assert result["error"] == "timeout"


# --------------------------------------------------------------------------- #
# check_toolchain
# --------------------------------------------------------------------------- #

def test_check_toolchain_match(monkeypatch, tmp_path):
    (tmp_path / "lean-toolchain").write_text("leanprover/lean4:v4.30.0\n")
    monkeypatch.setenv("PROBE_LEAN_TOOLCHAIN", "leanprover/lean4:v4.30.0")
    result = server.check_toolchain(str(tmp_path))
    assert result["match"] is True
    assert result["project_toolchain"] == "leanprover/lean4:v4.30.0"


def test_check_toolchain_mismatch(monkeypatch, tmp_path):
    (tmp_path / "lean-toolchain").write_text("leanprover/lean4:v4.28.0-rc1\n")
    monkeypatch.setenv("PROBE_LEAN_TOOLCHAIN", "leanprover/lean4:v4.30.0")
    result = server.check_toolchain(str(tmp_path))
    assert result["match"] is False
    assert "mismatch" in result["note"].lower()


def test_check_toolchain_missing_project(monkeypatch, tmp_path):
    monkeypatch.setenv("PROBE_LEAN_TOOLCHAIN", "leanprover/lean4:v4.30.0")
    result = server.check_toolchain(str(tmp_path))
    assert result["match"] is False
    assert result["project_toolchain"] is None


# --------------------------------------------------------------------------- #
# Query tools
# --------------------------------------------------------------------------- #

def test_list_atoms(fixture_path):
    result = server.list_atoms(atoms_path=fixture_path)
    assert result["total"] == 7
    assert len(result["atoms"]) == 7
    assert all("dependencies" not in row for row in result["atoms"])


def test_list_atoms_filtered(fixture_path):
    result = server.list_atoms(atoms_path=fixture_path, status="unverified")
    assert result["total"] == 1
    assert result["atoms"][0]["name"] == "probe:Demo.Broken.bad"


def test_list_atoms_pagination(fixture_path):
    result = server.list_atoms(atoms_path=fixture_path, limit=2, offset=0)
    assert result["total"] == 7
    assert result["count"] == 2
    assert result["limit"] == 2


def test_get_atom_full(fixture_path):
    result = server.get_atom(name="Demo.Core.add", atoms_path=fixture_path)
    assert result["name"] == "probe:Demo.Core.add"
    assert result["atom"]["dependencies"] == ["probe:Demo.Core.helper"]


def test_get_atom_not_found(fixture_path):
    result = server.get_atom(name="Demo.Core.doesNotExist", atoms_path=fixture_path)
    assert result["error"] == "atom_not_found"


def test_find_unverified(fixture_path):
    result = server.find_unverified(atoms_path=fixture_path)
    names = {row["name"] for row in result["atoms"]}
    assert names == {"probe:Demo.Broken.bad", "probe:Demo.Broken.alsoBad"}


def test_find_sorries_matches_unverified(fixture_path):
    a = server.find_sorries(atoms_path=fixture_path)
    b = server.find_unverified(atoms_path=fixture_path)
    assert {r["name"] for r in a["atoms"]} == {r["name"] for r in b["atoms"]}


def test_get_dependencies_all(fixture_path):
    result = server.get_dependencies(name="Demo.Core.add", atoms_path=fixture_path)
    assert result["kind"] == "all"
    assert result["dependencies"] == ["probe:Demo.Core.helper"]


def test_get_dependencies_type_vs_term(fixture_path):
    t = server.get_dependencies(name="Demo.Core.add_spec", atoms_path=fixture_path, kind="type")
    m = server.get_dependencies(name="Demo.Core.add_spec", atoms_path=fixture_path, kind="term")
    assert t["dependencies"] == ["probe:Demo.Core.add"]
    assert m["dependencies"] == []


def test_get_dependencies_bad_kind(fixture_path):
    result = server.get_dependencies(name="Demo.Core.add", atoms_path=fixture_path, kind="bogus")
    assert result["error"] == "bad_args"


def test_get_specs(fixture_path):
    result = server.get_specs(name="Demo.Core.add", atoms_path=fixture_path)
    assert result["specs"] == ["probe:Demo.Core.add_spec"]
    assert result["primary_spec"] == "probe:Demo.Core.add_spec"


def test_query_no_output(tmp_path):
    result = server.list_atoms(project_path=str(tmp_path))
    assert result["error"] == "no_output"
    assert "extract" in result["hint"]
