#!/usr/bin/env sh
# Felix CLI - macOS / Linux Bootstrapper
#
# One-liner install:
#   curl -sSL https://YOUR-SERVER/install.sh | sh
#
# With options:
#   curl -sSL https://YOUR-SERVER/install.sh | sh -s -- --version 0.9.0
#   curl -sSL https://YOUR-SERVER/install.sh | sh -s -- --force
#
# Or download and run locally:
#   chmod +x scripts/install.sh && ./scripts/install.sh [--version 0.9.0] [--force]

set -e

BASE_URL="https://YOUR-SERVER/releases"   # <-- fill in your server URL
VERSION=""
FORCE=0

# ── Parse args ───────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --version)  VERSION="$2";  shift 2 ;;
        --base-url) BASE_URL="$2"; shift 2 ;;
        --force)    FORCE=1;       shift   ;;
        *)          echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# ── Detect platform RID ───────────────────────────────────────────────────────
OS="$(uname -s)"
ARCH="$(uname -m)"
case "${OS}-${ARCH}" in
    Linux-x86_64)   RID="linux-x64"  ;;
    Darwin-arm64)   RID="osx-arm64"  ;;
    Darwin-x86_64)  RID="osx-x64"    ;;
    *)
        echo "Unsupported platform: $OS / $ARCH" >&2
        echo "Supported: Linux x86_64, macOS arm64, macOS x86_64" >&2
        exit 1
        ;;
esac

# ── Resolve version ───────────────────────────────────────────────────────────
if [ -z "$VERSION" ]; then
    printf "Checking latest version ... "
    VERSION="$(curl -sSL "$BASE_URL/latest.txt" 2>/dev/null | tr -d '[:space:]' || true)"
    if [ -z "$VERSION" ]; then
        echo "" >&2
        echo "Could not determine latest version from $BASE_URL/latest.txt" >&2
        echo "Specify one with: curl -sSL ... | sh -s -- --version 0.9.0" >&2
        exit 1
    fi
    echo "$VERSION"
fi

ZIP_NAME="felix-${VERSION}-${RID}.zip"
ZIP_URL="${BASE_URL}/${ZIP_NAME}"
CSU_URL="${BASE_URL}/checksums-${VERSION}.txt"

# ── Download ──────────────────────────────────────────────────────────────────
echo ""
echo "Felix CLI Installer"
echo "==================="
echo "  Version : $VERSION"
echo "  Platform: $RID"
echo ""

TMP="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf '$TMP'" EXIT

ZIP_PATH="${TMP}/${ZIP_NAME}"

printf "Downloading %s ...\n" "$ZIP_URL"
if command -v curl >/dev/null 2>&1; then
    curl -sSL -o "$ZIP_PATH" "$ZIP_URL"
elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$ZIP_PATH" "$ZIP_URL"
else
    echo "Error: curl or wget is required." >&2
    exit 1
fi

# ── Checksum verification (best-effort) ──────────────────────────────────────
sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

EXPECTED="$(curl -sSL "$CSU_URL" 2>/dev/null | grep "$ZIP_NAME" | awk '{print $1}' || true)"
if [ -n "$EXPECTED" ]; then
    ACTUAL="$(sha256_of "$ZIP_PATH")"
    if [ -n "$ACTUAL" ]; then
        if [ "$ACTUAL" != "$EXPECTED" ]; then
            echo "SHA256 mismatch!" >&2
            echo "  Expected : $EXPECTED" >&2
            echo "  Got      : $ACTUAL"  >&2
            exit 1
        fi
        echo "  [OK] Checksum verified"
    fi
fi

# ── Extract ───────────────────────────────────────────────────────────────────
EXTRACT_DIR="${TMP}/x"
mkdir -p "$EXTRACT_DIR"

if command -v unzip >/dev/null 2>&1; then
    unzip -q "$ZIP_PATH" -d "$EXTRACT_DIR"
else
    echo "Error: unzip is required." >&2
    exit 1
fi

FELIX_BIN="${EXTRACT_DIR}/felix"
if [ ! -f "$FELIX_BIN" ]; then
    echo "Error: 'felix' binary not found in downloaded archive." >&2
    exit 1
fi
chmod +x "$FELIX_BIN"

# ── Copy to install dir and set PATH ─────────────────────────────────────────
INSTALL_DIR="$HOME/.local/share/felix"
mkdir -p "$INSTALL_DIR"

cp "$FELIX_BIN" "$INSTALL_DIR/felix"
chmod +x "$INSTALL_DIR/felix"
echo "  [OK] felix installed to $INSTALL_DIR"

# Add to PATH in shell profiles (idempotent)
EXPORT_LINE="export PATH=\"\$PATH:$INSTALL_DIR\""
UPDATED=""
for PROFILE in ".bashrc" ".zshrc" ".profile"; do
    PROFILE_PATH="$HOME/$PROFILE"
    if [ -f "$PROFILE_PATH" ] && ! grep -q "$INSTALL_DIR" "$PROFILE_PATH" 2>/dev/null; then
        printf "\n# Felix CLI\n%s\n" "$EXPORT_LINE" >> "$PROFILE_PATH"
        UPDATED="$UPDATED ~/$PROFILE"
    fi
done

if [ -n "$UPDATED" ]; then
    echo "  [OK] PATH added to:$UPDATED"
else
    echo "  [OK] Already in PATH"
fi

echo ""
echo "Done! To start using felix:"
echo "  Reload your shell : source ~/.zshrc   (or open a new terminal)"
echo "  Then run          : felix setup"
echo "  in your project directory to initialise Felix."
echo ""
