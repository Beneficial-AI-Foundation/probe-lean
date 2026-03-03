#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

lake build

mkdir -p ~/.local/bin
VERSION=$(cat lean-toolchain | cut -d: -f2)
rm -f ~/.local/bin/probe-lean ~/.local/bin/probe-lean-$VERSION
cp .lake/build/bin/probe-lean ~/.local/bin/probe-lean-$VERSION
ln -s probe-lean-$VERSION ~/.local/bin/probe-lean

echo "Installed probe-lean-$VERSION to ~/.local/bin"

if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    echo "Warning: ~/.local/bin is not in your PATH"
    echo "Add it with: export PATH=\"\$PATH:\$HOME/.local/bin\""
fi
