#!/usr/bin/env bash
set -euo pipefail

GITHUB_REPO="Beneficial-AI-Foundation/probe-lean"

usage() {
    cat <<EOF
Usage: install.sh [OPTIONS] [VERSION]

Install probe-lean for a specific Lean version.

Options:
  --from-project <path>    Auto-detect Lean version from target project's lean-toolchain
  --lean-version <ver>     Explicit Lean version (e.g., v4.28.0-rc1)
  --force                  Rebuild/reinstall even if already installed
  -h, --help               Show this help message

Arguments:
  VERSION                  Lean version (positional, same as --lean-version)

If no version is specified, an interactive menu is shown.

Examples:
  install.sh --from-project ../my-lean-project
  install.sh --lean-version v4.28.0-rc1
  install.sh v4.28.0-rc1
  install.sh
EOF
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

detect_version_from_project() {
    local project_path=$1
    if [ ! -e "$project_path" ]; then
        echo "Error: --from-project path does not exist: $project_path" >&2
        echo "       Point it at a Lean project directory (the one containing lakefile.toml/lakefile.lean and lean-toolchain)." >&2
        exit 1
    fi
    if [ ! -d "$project_path" ]; then
        echo "Error: --from-project path is not a directory: $project_path" >&2
        echo "       Point it at a Lean project directory (the one containing lakefile.toml/lakefile.lean and lean-toolchain)." >&2
        exit 1
    fi
    local contents
    if [ -f "$project_path/lean-toolchain" ]; then
        contents=$(cat "$project_path/lean-toolchain")
    else
        # No toolchain at the top level. The installer is run automatically on a
        # project path with no chance for the user to retry, so search recursively
        # (the Lean package often lives in a subdirectory, e.g. cedar-spec/cedar-lean).
        # Exclude .lake so dependencies' toolchains don't pollute the search.
        local found
        found=$(find -L "$project_path" -name lean-toolchain -not -path '*/.lake/*' 2>/dev/null | sort)
        if [ -z "$found" ]; then
            echo "Error: no lean-toolchain found anywhere under $project_path" >&2
            echo "       Pass an explicit version with --lean-version <ver>." >&2
            exit 1
        fi
        # Collect the distinct versions across all toolchain files found.
        local versions
        versions=$(while IFS= read -r f; do
            local c
            c=$(cat "$f" | tr -d '[:space:]')
            echo "${c##*:}"
        done <<< "$found" | sort -u)
        if [ "$(echo "$versions" | wc -l)" -gt 1 ]; then
            echo "Error: lean-toolchain files with differing versions under $project_path:" >&2
            while IFS= read -r f; do
                echo "         $f -> $(cat "$f" | tr -d '[:space:]')" >&2
            done <<< "$found"
            echo "       Point --from-project at the specific Lean package, or use --lean-version <ver>." >&2
            exit 1
        fi
        local chosen
        chosen=$(echo "$found" | head -1)
        echo "Note: no lean-toolchain at $project_path; detected from $chosen" >&2
        contents=$(cat "$chosen")
    fi
    contents=$(echo "$contents" | tr -d '[:space:]')
    # Extract version after ":" (e.g., leanprover/lean4:v4.28.0-rc1 -> v4.28.0-rc1)
    if [[ "$contents" == *":"* ]]; then
        echo "${contents##*:}"
    else
        echo "$contents"
    fi
}

detect_platform() {
    local os arch
    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    arch=$(uname -m)
    case "$os" in
        linux)  os="linux" ;;
        darwin) os="darwin" ;;
        *)      echo "unknown-$os-$arch"; return ;;
    esac
    case "$arch" in
        x86_64)  arch="x86_64" ;;
        aarch64|arm64) arch="arm64" ;;
        *)       echo "$os-$arch"; return ;;
    esac
    echo "$os-$arch"
}

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

try_prebuilt_download() {
    local version=$1
    local platform
    platform=$(detect_platform)
    local artifact="probe-lean-${version}-${platform}.tar.gz"

    echo "Checking for pre-built binary: probe-lean-${version}-${platform}..."

    # Search the releases for an artifact matching this Lean version + platform.
    # Releases are paginated newest-first; the watcher appends artifacts to the
    # latest release over time and superseded RCs live only on older releases, so
    # walk the pages until found or exhausted. An optional token avoids the low
    # unauthenticated rate limit.
    local releases_url="https://api.github.com/repos/${GITHUB_REPO}/releases"
    local auth_header=""
    if [ -n "${GH_TOKEN:-}" ]; then
        auth_header="Authorization: Bearer ${GH_TOKEN}"
    elif [ -n "${GITHUB_TOKEN:-}" ]; then
        auth_header="Authorization: Bearer ${GITHUB_TOKEN}"
    fi
    # Escape dots so the version matches literally. The trailing quote anchors to
    # the end of the asset name, so the .sha256 sidecar is never matched.
    local artifact_re
    artifact_re=$(printf '%s' "$artifact" | sed 's/\./\\./g')
    local download_url="" per_page=100 page=1 body trimmed
    while [ "$page" -le 50 ]; do  # cap pages so we never loop unbounded
        body=$(curl -sL ${auth_header:+-H "$auth_header"} \
            "${releases_url}?per_page=${per_page}&page=${page}" 2>/dev/null) || break
        download_url=$(printf '%s' "$body" \
            | grep -o "\"browser_download_url\": \"[^\"]*${artifact_re}\"" \
            | head -1 \
            | sed 's/"browser_download_url": "//;s/"//') || true
        [ -n "$download_url" ] && break
        # Page on while the body is a non-empty JSON array; stop on the empty last
        # page or on an error body (rate limit / auth) — falling back to source.
        trimmed=$(printf '%s' "$body" | tr -d '[:space:]')
        case "$trimmed" in
            '[]')    break ;;
            '['*']') page=$((page + 1)) ;;
            *)
                if printf '%s' "$body" | grep -q '"message"'; then
                    echo "Note: GitHub API did not return releases (rate limit or auth?); set GH_TOKEN to raise the limit." >&2
                fi
                break ;;
        esac
    done

    if [ -z "$download_url" ]; then
        echo "No pre-built binary available, falling back to source build..."
        return 1
    fi

    echo "Downloading pre-built binary from $download_url..."
    local tmpdir
    tmpdir=$(mktemp -d)
    trap "rm -rf $tmpdir" RETURN

    if ! curl -sL "$download_url" | tar -xz -C "$tmpdir"; then
        echo "Download failed, falling back to source build..."
        return 1
    fi

    local versioned_lib=~/.local/lib/probe-lean-$version
    mkdir -p ~/.local/bin "$versioned_lib"
    rm -f ~/.local/bin/probe-lean-$version
    cp "$tmpdir/bin/probe-lean" ~/.local/bin/probe-lean-$version
    chmod +x ~/.local/bin/probe-lean-$version

    if [ -d "$tmpdir/lib" ]; then
        rm -rf "$versioned_lib"/*
        cp -r "$tmpdir"/lib/ProbeLean* "$versioned_lib"/
    fi

    return 0
}

find_probe_lean_source() {
    # If we're inside the repo already, use it
    local script_dir
    script_dir="$(cd "$(dirname "$0")" && pwd)"
    local repo_root="$script_dir/../.."
    if [ -f "$repo_root/lakefile.toml" ] && [ -d "$repo_root/.git" ]; then
        echo "$repo_root"
        return 0
    fi

    # Otherwise use a cached clone
    local src_dir=~/.local/src/probe-lean
    if [ -d "$src_dir/.git" ]; then
        echo "Updating probe-lean source..." >&2
        git -C "$src_dir" fetch origin main --quiet 2>/dev/null || true
        git -C "$src_dir" checkout origin/main --quiet 2>/dev/null || true
    else
        echo "Cloning probe-lean source..." >&2
        mkdir -p ~/.local/src
        git clone --quiet "https://github.com/${GITHUB_REPO}.git" "$src_dir"
    fi
    echo "$src_dir"
}

build_from_source() {
    local version=$1
    local source_dir
    source_dir=$(find_probe_lean_source)

    cd "$source_dir"

    local current_version
    current_version=$(cat lean-toolchain | cut -d: -f2 | tr -d '[:space:]')

    if [ "$version" = "$current_version" ]; then
        echo "Version $version matches source toolchain, building..."
        lake build
    else
        echo "Switching from $current_version to $version..."

        local original_toolchain original_lakefile original_manifest
        original_toolchain=$(cat lean-toolchain)
        original_lakefile=$(cat lakefile.toml)
        original_manifest=$(cat lake-manifest.json 2>/dev/null || true)

        echo "leanprover/lean4:$version" > lean-toolchain
        # Rewrite the rev of ONLY the lean4-cli dependency (portable awk; no sed -i).
        awk -v ver="$version" '
          /^[[:space:]]*\[\[/ { incli = 0 }
          /git = ".*lean4-cli"/ { incli = 1 }
          incli && /^[[:space:]]*rev[[:space:]]*=/ { sub(/"v[^"]*"/, "\"" ver "\"") }
          { print }
        ' lakefile.toml > lakefile.toml.tmp && mv lakefile.toml.tmp lakefile.toml

        rm -rf .lake
        echo "Cleared .lake/"

        # Re-resolve Cli for the rewritten rev — the committed manifest pins an
        # unrelated rev, so `lake build` alone would build the wrong lean4-cli.
        # --keep-toolchain leaves the toolchain lean/elan selected untouched.
        local build_ok=true
        lake --keep-toolchain update Cli && lake build || build_ok=false

        echo "$original_toolchain" > lean-toolchain
        echo "$original_lakefile" > lakefile.toml
        # Restore the manifest too, so an in-repo install leaves the tree clean.
        if [ -n "$original_manifest" ]; then
            printf '%s\n' "$original_manifest" > lake-manifest.json
        fi
        echo "Restored lean-toolchain, lakefile.toml, and lake-manifest.json"

        if [ "$build_ok" = false ]; then
            echo "Build failed" >&2
            exit 1
        fi
    fi

    local versioned_lib=~/.local/lib/probe-lean-$version
    mkdir -p ~/.local/bin "$versioned_lib"
    rm -f ~/.local/bin/probe-lean-$version
    cp .lake/build/bin/probe-lean ~/.local/bin/probe-lean-$version

    rm -rf "$versioned_lib"/*
    cp -r .lake/build/lib/lean/ProbeLean* "$versioned_lib"/
}

update_symlinks() {
    local version=$1
    rm -f ~/.local/bin/probe-lean
    ln -s "probe-lean-$version" ~/.local/bin/probe-lean
    # May be an old directory or a symlink from a previous install
    rm -rf ~/.local/lib/probe-lean
    ln -sfn "probe-lean-$version" ~/.local/lib/probe-lean
}

check_elan() {
    if ! command -v elan &>/dev/null && ! command -v lake &>/dev/null; then
        echo "Warning: elan/lake not found. Source builds require elan." >&2
        echo "Install elan: curl -sSf https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh | bash" >&2
    fi
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

VERSION=""
FROM_PROJECT=""
FORCE=false

while [ $# -gt 0 ]; do
    case "$1" in
        --from-project)
            FROM_PROJECT="$2"
            shift 2
            ;;
        --lean-version)
            VERSION="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
        *)
            VERSION="$1"
            shift
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Determine version
# ---------------------------------------------------------------------------

if [ -n "$FROM_PROJECT" ]; then
    VERSION=$(detect_version_from_project "$FROM_PROJECT")
    echo "Detected Lean version: $VERSION"
fi

if [ -z "$VERSION" ]; then
    mapfile -t VERSIONS < <(fetch_versions)
    select_version "${VERSIONS[@]}"
    VERSION="$SELECTED_VERSION"
fi

echo "Installing probe-lean for Lean $VERSION..."

# ---------------------------------------------------------------------------
# Check if already installed
# ---------------------------------------------------------------------------

if [ "$FORCE" = false ] && [ -f ~/.local/bin/probe-lean-$VERSION ]; then
    echo "probe-lean-$VERSION is already installed."
    update_symlinks "$VERSION"
    echo "Symlinks updated."

    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        echo "Warning: ~/.local/bin is not in your PATH"
        echo "Add it with: export PATH=\"\$PATH:\$HOME/.local/bin\""
    fi
    exit 0
fi

# ---------------------------------------------------------------------------
# Try pre-built download, fall back to source build
# ---------------------------------------------------------------------------

if try_prebuilt_download "$VERSION"; then
    echo "Installed pre-built probe-lean-$VERSION"
else
    check_elan
    build_from_source "$VERSION"
    echo "Built and installed probe-lean-$VERSION from source"
fi

update_symlinks "$VERSION"

if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    echo "Warning: ~/.local/bin is not in your PATH"
    echo "Add it with: export PATH=\"\$PATH:\$HOME/.local/bin\""
fi

echo "Done. Run 'probe-lean --version' to verify."
