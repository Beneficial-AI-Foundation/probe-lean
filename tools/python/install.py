#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = ["httpx"]
# ///
"""Install probe-lean for a specific Lean version.

Supports auto-detection from a target project, pre-built binary download
with source-build fallback, and per-version installation.
"""
import argparse
import os
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

import httpx

GITHUB_REPO = "Beneficial-AI-Foundation/probe-lean"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def detect_version_from_project(project_path: Path) -> str:
    """Read lean-toolchain from a target project and extract the version."""
    toolchain_file = project_path / "lean-toolchain"
    if not toolchain_file.exists():
        print(f"Error: lean-toolchain not found at {toolchain_file}", file=sys.stderr)
        sys.exit(1)
    contents = toolchain_file.read_text().strip()
    if ":" in contents:
        return contents.split(":")[-1]
    return contents


def detect_platform() -> str:
    """Return a platform string like linux-x86_64 or darwin-arm64."""
    system = platform.system().lower()
    machine = platform.machine().lower()
    os_name = {"linux": "linux", "darwin": "darwin"}.get(system, system)
    arch = {
        "x86_64": "x86_64",
        "amd64": "x86_64",
        "aarch64": "arm64",
        "arm64": "arm64",
    }.get(machine, machine)
    return f"{os_name}-{arch}"


def fetch_lean_versions() -> list[str]:
    """Fetch available Lean 4 versions from GitHub releases."""
    url = "https://api.github.com/repos/leanprover/lean4/releases"
    response = httpx.get(url, params={"per_page": 30})
    response.raise_for_status()
    releases = response.json()
    return [r["tag_name"] for r in releases if r["tag_name"].startswith("v4.")]


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


def try_prebuilt_download(version: str) -> bool:
    """Attempt to download a pre-built binary. Returns True on success."""
    plat = detect_platform()
    artifact_name = f"probe-lean-{version}-{plat}.tar.gz"

    print(f"Checking for pre-built binary: probe-lean-{version}-{plat}...")

    # Search across all releases for an artifact matching this Lean version + platform
    try:
        releases_url = f"https://api.github.com/repos/{GITHUB_REPO}/releases"
        releases = httpx.get(releases_url).json()
        download_url = None
        for release in releases:
            for asset in release.get("assets", []):
                if asset["name"] == artifact_name:
                    download_url = asset["browser_download_url"]
                    break
            if download_url:
                break

        if not download_url:
            print("No pre-built binary available, falling back to source build...")
            return False

        print(f"Downloading pre-built binary...")
        with tempfile.TemporaryDirectory() as tmpdir:
            tarball = Path(tmpdir) / "probe-lean.tar.gz"
            with httpx.stream("GET", download_url, follow_redirects=True) as response:
                response.raise_for_status()
                with open(tarball, "wb") as f:
                    for chunk in response.iter_bytes():
                        f.write(chunk)

            with tarfile.open(tarball, "r:gz") as tar:
                tar.extractall(path=tmpdir, filter="data")

            local_bin = Path.home() / ".local" / "bin"
            versioned_lib = Path.home() / ".local" / "lib" / f"probe-lean-{version}"
            local_bin.mkdir(parents=True, exist_ok=True)
            versioned_lib.mkdir(parents=True, exist_ok=True)

            versioned_path = local_bin / f"probe-lean-{version}"
            versioned_path.unlink(missing_ok=True)
            shutil.copy2(Path(tmpdir) / "bin" / "probe-lean", versioned_path)
            versioned_path.chmod(0o755)

            lib_src = Path(tmpdir) / "lib"
            if lib_src.exists():
                for item in versioned_lib.iterdir():
                    if item.name.startswith("ProbeLean"):
                        if item.is_dir():
                            shutil.rmtree(item)
                        else:
                            item.unlink()
                for item in lib_src.iterdir():
                    if item.name.startswith("ProbeLean"):
                        dest = versioned_lib / item.name
                        if item.is_dir():
                            shutil.copytree(item, dest)
                        else:
                            shutil.copy2(item, dest)
            return True
    except Exception:
        print("No pre-built binary available, falling back to source build...")
        return False


def find_probe_lean_source() -> Path:
    """Locate the probe-lean source tree (in-repo or cached clone)."""
    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent.parent
    if (repo_root / "lakefile.toml").exists() and (repo_root / ".git").exists():
        return repo_root

    src_dir = Path.home() / ".local" / "src" / "probe-lean"
    if (src_dir / ".git").exists():
        print("Updating probe-lean source...")
        subprocess.run(
            ["git", "-C", str(src_dir), "fetch", "origin", "main", "--quiet"],
            check=False,
        )
        subprocess.run(
            ["git", "-C", str(src_dir), "checkout", "origin/main", "--quiet"],
            check=False,
        )
    else:
        print("Cloning probe-lean source...")
        src_dir.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            [
                "git",
                "clone",
                "--quiet",
                f"https://github.com/{GITHUB_REPO}.git",
                str(src_dir),
            ],
            check=True,
        )
    return src_dir


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


def build_from_source(version: str):
    """Build probe-lean from source for the given version."""
    source_dir = find_probe_lean_source()
    os.chdir(source_dir)

    current_toolchain = (source_dir / "lean-toolchain").read_text().strip()
    current_version = current_toolchain.split(":")[-1] if ":" in current_toolchain else current_toolchain

    if version == current_version:
        print(f"Version {version} matches source toolchain, building...")
        subprocess.run(["lake", "build"], check=True)
    else:
        print(f"Switching from {current_version} to {version}...")
        original_toolchain = update_toolchain(source_dir, version)
        original_lakefile = update_lakefile(source_dir, version)
        try:
            clean_build(source_dir)
            subprocess.run(["lake", "build"], check=True)
        finally:
            (source_dir / "lean-toolchain").write_text(original_toolchain)
            (source_dir / "lakefile.toml").write_text(original_lakefile)
            print("Restored lean-toolchain and lakefile.toml")

    local_bin = Path.home() / ".local" / "bin"
    versioned_lib = Path.home() / ".local" / "lib" / f"probe-lean-{version}"
    local_bin.mkdir(parents=True, exist_ok=True)
    versioned_lib.mkdir(parents=True, exist_ok=True)

    versioned_path = local_bin / f"probe-lean-{version}"
    binary_path = source_dir / ".lake" / "build" / "bin" / "probe-lean"
    olean_src = source_dir / ".lake" / "build" / "lib" / "lean"

    versioned_path.unlink(missing_ok=True)
    shutil.copy2(binary_path, versioned_path)

    for item in versioned_lib.iterdir():
        if item.name.startswith("ProbeLean"):
            if item.is_dir():
                shutil.rmtree(item)
            else:
                item.unlink()
    for item in olean_src.iterdir():
        if item.name.startswith("ProbeLean"):
            dest = versioned_lib / item.name
            if item.is_dir():
                shutil.copytree(item, dest)
            else:
                shutil.copy2(item, dest)


def update_symlinks(version: str):
    """Update the probe-lean symlinks to point to the given version."""
    local_bin = Path.home() / ".local" / "bin"
    lib_symlink = Path.home() / ".local" / "lib" / "probe-lean"

    bin_symlink = local_bin / "probe-lean"
    bin_symlink.unlink(missing_ok=True)
    bin_symlink.symlink_to(f"probe-lean-{version}")

    if lib_symlink.is_dir() and not lib_symlink.is_symlink():
        shutil.rmtree(lib_symlink)
    elif lib_symlink.is_symlink() or lib_symlink.exists():
        lib_symlink.unlink()
    lib_symlink.symlink_to(f"probe-lean-{version}")


def check_elan():
    """Warn if elan/lake are not available."""
    if shutil.which("elan") is None and shutil.which("lake") is None:
        print(
            "Warning: elan/lake not found. Source builds require elan.",
            file=sys.stderr,
        )
        print(
            "Install elan: curl -sSf https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh | bash",
            file=sys.stderr,
        )


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(description="Install probe-lean for a specific Lean version")
    parser.add_argument("version", nargs="?", help="Lean version (e.g., v4.28.0-rc1)")
    parser.add_argument("--from-project", metavar="PATH", help="Auto-detect version from target project's lean-toolchain")
    parser.add_argument("--lean-version", metavar="VER", help="Explicit Lean version")
    parser.add_argument("--force", action="store_true", help="Rebuild/reinstall even if already installed")
    args = parser.parse_args()

    # Determine version
    version = None
    if args.from_project:
        version = detect_version_from_project(Path(args.from_project))
        print(f"Detected Lean version: {version}")
    elif args.lean_version:
        version = args.lean_version
    elif args.version:
        version = args.version
    else:
        versions = fetch_lean_versions()
        version = select_version(versions)

    print(f"Installing probe-lean for Lean {version}...")

    # Check if already installed
    local_bin = Path.home() / ".local" / "bin"
    versioned_path = local_bin / f"probe-lean-{version}"
    if not args.force and versioned_path.exists():
        print(f"probe-lean-{version} is already installed.")
        update_symlinks(version)
        print("Symlinks updated.")
        path_dirs = os.environ.get("PATH", "").split(os.pathsep)
        if str(local_bin) not in path_dirs:
            print(f"Warning: {local_bin} is not in your PATH")
            print('Add it with: export PATH="$PATH:$HOME/.local/bin"')
        return

    # Try pre-built download, fall back to source build
    if try_prebuilt_download(version):
        print(f"Installed pre-built probe-lean-{version}")
    else:
        check_elan()
        build_from_source(version)
        print(f"Built and installed probe-lean-{version} from source")

    update_symlinks(version)

    path_dirs = os.environ.get("PATH", "").split(os.pathsep)
    if str(local_bin) not in path_dirs:
        print(f"Warning: {local_bin} is not in your PATH")
        print('Add it with: export PATH="$PATH:$HOME/.local/bin"')

    print("Done. Run 'probe-lean --version' to verify.")


if __name__ == "__main__":
    main()
