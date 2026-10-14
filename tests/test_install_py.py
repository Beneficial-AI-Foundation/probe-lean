#!/usr/bin/env python3
"""Tests for the helpers of tools/python/install.py. Run from the probe-lean root:
    python3 tests/test_install_py.py

Uses only the standard library. A stub replaces httpx, so the tests import the
real installer module and need no network.
"""
import contextlib
import importlib.util
import io
import sys
import types
from pathlib import Path

PASS = 0
FAIL = 0


def assert_eq(name, expected, actual):
    global PASS, FAIL
    if expected == actual:
        print(f"  PASS: {name}")
        PASS += 1
    else:
        print(f"  FAIL: {name} (expected {expected!r}, got {actual!r})")
        FAIL += 1


httpx_stub = types.ModuleType("httpx")
sys.modules["httpx"] = httpx_stub
spec = importlib.util.spec_from_file_location(
    "install", Path(__file__).resolve().parent.parent / "tools" / "python" / "install.py"
)
install = importlib.util.module_from_spec(spec)
spec.loader.exec_module(install)


def stderr_of(fn, *args):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        fn(*args)
    assert_eq(f"{fn.__name__}{args} prints nothing on stdout", "", out.getvalue())
    return err.getvalue()


print("=== Testing release_tag_from_url ===")
assert_eq(
    "tag from download URL",
    "v0.9.4",
    install.release_tag_from_url(
        "https://github.com/o/r/releases/download/v0.9.4/probe-lean-v4.28.0-rc1-linux-x86_64.tar.gz"
    ),
)
assert_eq("no tag in URL", None, install.release_tag_from_url("https://example.com/probe-lean.tar.gz"))
assert_eq("None URL", None, install.release_tag_from_url(None))

print("=== Testing version_older_than ===")
assert_eq("0.9.4 < v0.18.2", True, install.version_older_than("0.9.4", "v0.18.2"))
assert_eq("multi-digit: 0.9.6 < 0.18.2", True, install.version_older_than("0.9.6", "0.18.2"))
assert_eq("major wins", True, install.version_older_than("0.99.99", "1.0.0"))
assert_eq("equal", False, install.version_older_than("0.18.2", "v0.18.2"))
assert_eq("newer", False, install.version_older_than("0.19.0", "v0.18.2"))
assert_eq("empty first", False, install.version_older_than("", "v0.18.2"))
assert_eq("None second", False, install.version_older_than("0.9.4", None))
assert_eq("malformed", False, install.version_older_than("0.9", "v0.18.2"))

print("=== Testing stale_asset_warning ===")
err = stderr_of(install.stale_asset_warning, "v4.28.0-rc1", "v0.9.4", "v0.18.2")
assert_eq(
    "older asset warns",
    "Warning: the newest probe-lean release (v0.18.2) has no asset for Lean v4.28.0-rc1.",
    err.splitlines()[0] if err else "",
)
assert_eq("older asset warning has the build hint", True, "issues?q=label%3Alean-build-failure" in err)
assert_eq("same tag prints nothing", "", stderr_of(install.stale_asset_warning, "v4.28.0", "v0.18.2", "v0.18.2"))
assert_eq("None newest tag prints nothing", "", stderr_of(install.stale_asset_warning, "v4.28.0", "v0.9.4", None))

print("=== Testing installed_binary_warning ===")
err = stderr_of(install.installed_binary_warning, "v4.28.0", "0.9.6", "v0.18.2", True)
assert_eq(
    "older binary, newest has asset: first line",
    "Warning: the installed probe-lean-v4.28.0 is version 0.9.6. The newest release is v0.18.2.",
    err.splitlines()[0] if err else "",
)
assert_eq("older binary, newest has asset: --force hint", True, "--force" in err)
assert_eq("older binary, newest has asset: no build hint", False, "lean-build-failure" in err)
err = stderr_of(install.installed_binary_warning, "v4.28.0-rc1", "0.9.4", "v0.18.2", False)
assert_eq("older binary, no asset: build hint", True, "issues?q=label%3Alean-build-failure" in err)
assert_eq("older binary, no asset: no --force hint", False, "--force" in err)
assert_eq("equal version prints nothing", "", stderr_of(install.installed_binary_warning, "v4.28.0", "0.18.2", "v0.18.2", True))
assert_eq("newer version prints nothing", "", stderr_of(install.installed_binary_warning, "v4.28.0", "0.19.0", "v0.18.2", True))
assert_eq("None version prints nothing", "", stderr_of(install.installed_binary_warning, "v4.28.0", None, "v0.18.2", True))

print("=== Testing find_release_asset (fake httpx.get) ===")
PLAT = install.detect_platform()


def release(tag, *leans):
    return {
        "tag_name": tag,
        "assets": [
            {
                "name": f"probe-lean-{v}-{PLAT}.tar.gz",
                "browser_download_url": f"https://github.com/o/r/releases/download/{tag}/probe-lean-{v}-{PLAT}.tar.gz",
            }
            for v in leans
        ],
    }


class FakeResponse:
    def __init__(self, body):
        self.body = body

    def raise_for_status(self):
        pass

    def json(self):
        return self.body


PAGES = {}


def fake_get(url, params=None, headers=None):
    return FakeResponse(PAGES.get(params["page"], []))


httpx_stub.get = fake_get
# 100 releases on page 1, so the search goes on to page 2.
PAGES[1] = [release("v0.18.2", "v4.28.0"), release("v0.18.1", "v4.28.0")] + [release(f"v0.0.{i}") for i in range(98)]
PAGES[2] = [release("v0.9.4", "v4.28.0-rc1", "v4.28.0")]

url, newest = install.find_release_asset("v4.28.0")
assert_eq("asset on newest: tag", "v0.18.2", install.release_tag_from_url(url))
assert_eq("asset on newest: newest tag", "v0.18.2", newest)

url, newest = install.find_release_asset("v4.28.0-rc1")
assert_eq("asset only on page 2: tag", "v0.9.4", install.release_tag_from_url(url))
assert_eq("asset only on page 2: newest tag from page 1", "v0.18.2", newest)

url, newest = install.find_release_asset("v4.99.0")
assert_eq("no asset: URL is None", None, url)
assert_eq("no asset: newest tag still set", "v0.18.2", newest)

PAGES.clear()
PAGES[1] = {"message": "API rate limit exceeded"}
with contextlib.redirect_stdout(io.StringIO()):
    url, newest = install.find_release_asset("v4.28.0")
assert_eq("error body: URL is None", None, url)
assert_eq("error body: newest tag is None", None, newest)

print()
print(f"Results: {PASS} passed, {FAIL} failed")
sys.exit(1 if FAIL else 0)
