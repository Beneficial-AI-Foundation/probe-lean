#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

fetch_versions() {
    curl -s "https://api.github.com/repos/leanprover/lean4/releases?per_page=30" \
        | grep '"tag_name"' \
        | sed 's/.*"tag_name": "\(v4\.[^"]*\)".*/\1/' \
        | head -20
}

select_version() {
    local versions=("$@")
    echo "Available Lean versions:"
    local i=1
    for v in "${versions[@]}"; do
        echo "  $i. $v"
        ((i++))
    done
    echo
    while true; do
        read -p "Select version (number): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#versions[@]}" ]; then
            SELECTED_VERSION="${versions[$((choice-1))]}"
            return
        fi
        echo "Invalid choice, try again."
    done
}

install_binary() {
    local version=$1
    lake build

    mkdir -p ~/.local/bin ~/.local/lib/probe-lean
    rm -f ~/.local/bin/probe-lean ~/.local/bin/probe-lean-$version
    cp .lake/build/bin/probe-lean ~/.local/bin/probe-lean-$version
    ln -s probe-lean-$version ~/.local/bin/probe-lean

    # Copy interpreter .olean files (required by supportInterpreter)
    rm -rf ~/.local/lib/probe-lean/*
    cp -r .lake/build/lib/lean/ProbeLean* ~/.local/lib/probe-lean/

    echo "Installed probe-lean-$version to ~/.local/bin"

    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        echo "Warning: ~/.local/bin is not in your PATH"
        echo "Add it with: export PATH=\"\$PATH:\$HOME/.local/bin\""
    fi
}

# Get current version
CURRENT_VERSION=$(cat lean-toolchain | cut -d: -f2)

# Determine target version
if [ $# -ge 1 ]; then
    VERSION="$1"
else
    mapfile -t VERSIONS < <(fetch_versions)
    select_version "${VERSIONS[@]}"
    VERSION="$SELECTED_VERSION"
fi

# If version matches current, just build
if [ "$VERSION" = "$CURRENT_VERSION" ]; then
    echo "Version $VERSION matches current toolchain, building..."
    install_binary "$VERSION"
    exit 0
fi

echo "Switching from $CURRENT_VERSION to $VERSION..."

# Save originals
ORIGINAL_TOOLCHAIN=$(cat lean-toolchain)
ORIGINAL_LAKEFILE=$(cat lakefile.toml)

# Update files
echo "leanprover/lean4:$VERSION" > lean-toolchain
sed -i "s/rev = \"v[^\"]*\"/rev = \"$VERSION\"/" lakefile.toml

# Cleanup function to restore files
cleanup() {
    echo "$ORIGINAL_TOOLCHAIN" > lean-toolchain
    echo "$ORIGINAL_LAKEFILE" > lakefile.toml
    echo "Restored lean-toolchain and lakefile.toml"
}
trap cleanup EXIT

# Clean build artifacts
rm -rf .lake lake-manifest.json
echo "Removed .lake/ and lake-manifest.json"

# Build and install
install_binary "$VERSION"
