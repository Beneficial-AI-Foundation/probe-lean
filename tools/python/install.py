#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = ["httpx"]
# ///
import argparse
import os
import re
import shutil
import subprocess
from pathlib import Path

import httpx


def fetch_lean_versions() -> list[str]:
    """Fetch available Lean 4 versions from GitHub releases."""
    url = "https://api.github.com/repos/leanprover/lean4/releases"
    response = httpx.get(url, params={"per_page": 30})
    response.raise_for_status()
    releases = response.json()
    versions = [r["tag_name"] for r in releases if r["tag_name"].startswith("v4.")]
    return versions


def select_version(versions: list[str]) -> str:
    """Present a menu to select a version."""
    print("Available Lean versions:")
    for i, v in enumerate(versions, 1):
        print(f"  {i}. {v}")
    print()
    while True:
        choice = input("Select version (number): ").strip()
        if choice.isdigit() and 1 <= int(choice) <= len(versions):
            return versions[int(choice) - 1]
        print("Invalid choice, try again.")


def update_toolchain(project_root: Path, version: str) -> str:
    """Update lean-toolchain and return original content."""
    toolchain_path = project_root / "lean-toolchain"
    original = toolchain_path.read_text()
    toolchain_path.write_text(f"leanprover/lean4:{version}\n")
    return original


def update_lakefile(project_root: Path, version: str) -> str:
    """Update lakefile.toml Cli rev and return original content."""
    lakefile_path = project_root / "lakefile.toml"
    original = lakefile_path.read_text()
    # Replace rev = "vX.Y.Z..." with new version
    updated = re.sub(r'rev = "v[^"]+"', f'rev = "{version}"', original)
    lakefile_path.write_text(updated)
    return original


def clean_build(project_root: Path):
    """Remove .lake and lake-manifest.json."""
    lake_dir = project_root / ".lake"
    manifest = project_root / "lake-manifest.json"
    if lake_dir.exists():
        shutil.rmtree(lake_dir)
        print("Removed .lake/")
    if manifest.exists():
        manifest.unlink()
        print("Removed lake-manifest.json")


def install_binary(project_root: Path, version: str):
    """Build and install the binary."""
    subprocess.run(["lake", "build"], check=True)

    local_bin = Path.home() / ".local" / "bin"
    local_lib = Path.home() / ".local" / "lib" / "probe-lean"
    local_bin.mkdir(parents=True, exist_ok=True)
    local_lib.mkdir(parents=True, exist_ok=True)

    symlink_path = local_bin / "probe-lean"
    versioned_path = local_bin / f"probe-lean-{version}"
    binary_path = project_root / ".lake" / "build" / "bin" / "probe-lean"
    olean_src = project_root / ".lake" / "build" / "lib" / "lean"

    symlink_path.unlink(missing_ok=True)
    versioned_path.unlink(missing_ok=True)

    shutil.copy2(binary_path, versioned_path)
    symlink_path.symlink_to(f"probe-lean-{version}")

    # Copy interpreter .olean files (required by supportInterpreter)
    for item in local_lib.iterdir():
        if item.name.startswith("ProbeLean"):
            if item.is_dir():
                shutil.rmtree(item)
            else:
                item.unlink()
    for item in olean_src.iterdir():
        if item.name.startswith("ProbeLean"):
            dest = local_lib / item.name
            if item.is_dir():
                shutil.copytree(item, dest)
            else:
                shutil.copy2(item, dest)

    print(f"Installed probe-lean-{version} to {local_bin}")

    path_dirs = os.environ.get("PATH", "").split(os.pathsep)
    if str(local_bin) not in path_dirs:
        print(f"Warning: {local_bin} is not in your PATH")
        print('Add it with: export PATH="$PATH:$HOME/.local/bin"')


def main():
    parser = argparse.ArgumentParser(description="Install probe-lean")
    parser.add_argument("version", nargs="?", help="Lean version (e.g., v4.28.0-rc1)")
    args = parser.parse_args()

    project_root = Path(__file__).resolve().parent.parent.parent
    os.chdir(project_root)

    # Get current version from toolchain
    current_toolchain = (project_root / "lean-toolchain").read_text().strip()
    current_version = current_toolchain.split(":")[1]

    # Determine target version
    if args.version:
        version = args.version
    else:
        versions = fetch_lean_versions()
        version = select_version(versions)

    # If version matches current, just build
    if version == current_version:
        print(f"Version {version} matches current toolchain, building...")
        install_binary(project_root, version)
        return

    print(f"Switching from {current_version} to {version}...")

    # Save originals and update files
    original_toolchain = update_toolchain(project_root, version)
    original_lakefile = update_lakefile(project_root, version)

    try:
        clean_build(project_root)
        install_binary(project_root, version)
    finally:
        # Restore original files
        (project_root / "lean-toolchain").write_text(original_toolchain)
        (project_root / "lakefile.toml").write_text(original_lakefile)
        print("Restored lean-toolchain and lakefile.toml")


if __name__ == "__main__":
    main()
