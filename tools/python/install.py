#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = []
# ///
import os
import shutil
import subprocess
from pathlib import Path

def main():
    project_root = Path(__file__).resolve().parent.parent.parent
    os.chdir(project_root)

    # Build the project
    subprocess.run(["lake", "build"], check=True)

    # Get version from lean-toolchain
    toolchain = (project_root / "lean-toolchain").read_text().strip()
    version = toolchain.split(":")[1]

    # Install to ~/.local/bin
    local_bin = Path.home() / ".local" / "bin"
    local_bin.mkdir(parents=True, exist_ok=True)

    symlink_path = local_bin / "probe-lean"
    versioned_path = local_bin / f"probe-lean-{version}"
    binary_path = project_root / ".lake" / "build" / "bin" / "probe-lean"

    # Remove existing files
    symlink_path.unlink(missing_ok=True)
    versioned_path.unlink(missing_ok=True)

    # Copy binary and create symlink
    shutil.copy2(binary_path, versioned_path)
    symlink_path.symlink_to(f"probe-lean-{version}")

    print(f"Installed probe-lean-{version} to {local_bin}")

    # Check if ~/.local/bin is in PATH
    path_dirs = os.environ.get("PATH", "").split(os.pathsep)
    if str(local_bin) not in path_dirs:
        print(f"Warning: {local_bin} is not in your PATH")
        print('Add it with: export PATH="$PATH:$HOME/.local/bin"')

if __name__ == "__main__":
    main()
