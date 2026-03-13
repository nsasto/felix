#!/usr/bin/env bash
# Felix CLI - macOS .dmg packager
#
# Creates a drag-to-install disk image for macOS.
# Must be run on macOS (requires hdiutil, built-in).
#
# Usage:
#   ./scripts/package-dmg.sh [--version 0.9.0] [--rid osx-arm64|osx-x64]
#
# Output:
#   .release/felix-{version}-{rid}.dmg
#
# Run package-release.ps1 (or dotnet publish) first so the binary exists at
#   .release/{rid}/felix

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
RELEASE_DIR="$REPO_ROOT/.release"

VERSION=""
RID=""

# ── Parse args ────────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --version)  VERSION="$2"; shift 2 ;;
        --rid)      RID="$2";     shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--version X.Y.Z] [--rid osx-arm64|osx-x64]"
            exit 0 ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1 ;;
    esac
done

# ── Defaults ──────────────────────────────────────────────────────────────────
if [ -z "$VERSION" ]; then
    VERSION_FILE="$REPO_ROOT/.felix/version.txt"
    if [ -f "$VERSION_FILE" ]; then
        VERSION="$(cat "$VERSION_FILE" | tr -d '[:space:]')"
    else
        echo "Error: could not find .felix/version.txt. Pass --version explicitly." >&2
        exit 1
    fi
fi

if [ -z "$RID" ]; then
    ARCH="$(uname -m)"
    if [ "$ARCH" = "arm64" ]; then
        RID="osx-arm64"
    else
        RID="osx-x64"
    fi
fi

BINARY="$RELEASE_DIR/$RID/felix"

if [ ! -f "$BINARY" ]; then
    echo "Error: binary not found at $BINARY" >&2
    echo "Run 'dotnet publish' or 'scripts/package-release.ps1' for $RID first." >&2
    exit 1
fi

DMG_NAME="felix-$VERSION-$RID.dmg"
DMG_PATH="$RELEASE_DIR/$DMG_NAME"
TMP="$(mktemp -d)"

echo ""
echo "Felix DMG Packager  v$VERSION"
echo "=============================="
echo "  RID    : $RID"
echo "  Output : $DMG_PATH"
echo ""

# ── Stage files ───────────────────────────────────────────────────────────────
STAGE="$TMP/stage"
mkdir -p "$STAGE"
cp "$BINARY" "$STAGE/felix"
chmod +x "$STAGE/felix"

# Create an "Install Felix.command" double-click helper
cat > "$STAGE/Install Felix.command" << 'INSTALLER'
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.local/bin"
mkdir -p "$INSTALL_DIR"

cp "$SCRIPT_DIR/felix" "$INSTALL_DIR/felix"
chmod +x "$INSTALL_DIR/felix"

"$INSTALL_DIR/felix" install

echo ""
echo "Felix installed to $INSTALL_DIR/felix"
echo ""
echo "Make sure $INSTALL_DIR is in your PATH."
echo "Add this line to ~/.zshrc (or ~/.bash_profile):"
echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
echo ""
read -p "Press Enter to close..."
INSTALLER

chmod +x "$STAGE/Install Felix.command"

# Create a README
cat > "$STAGE/README.txt" << README
Felix CLI v$VERSION
===================

To install:
  1. Double-click "Install Felix.command" — it copies felix to ~/.local/bin
     and runs the initial setup.

  OR manually:
  2. Copy the "felix" binary to any directory in your PATH, then run:
       felix install

Documentation: https://www.felix.ai
README

# ── Build writable .dmg, populate, convert to compressed read-only ─────────────
TMP_DMG="$TMP/tmp.dmg"
hdiutil create -size 30m -fs HFS+ -volname "Felix CLI $VERSION" "$TMP_DMG" -quiet

# Mount and capture the mount point
MOUNT_OUTPUT="$(hdiutil attach "$TMP_DMG" -noautoopen -quiet)"
TMP_MOUNT="$(echo "$MOUNT_OUTPUT" | awk '/Volumes/{for(i=3;i<=NF;i++) printf "%s%s",(i==3?"":OFS),$i; print ""}')"

if [ -z "$TMP_MOUNT" ]; then
    echo "Error: failed to determine DMG mount point." >&2
    rm -rf "$TMP"
    exit 1
fi

# Copy staged files
cp "$STAGE/felix"              "$TMP_MOUNT/felix"
cp "$STAGE/Install Felix.command" "$TMP_MOUNT/Install Felix.command"
cp "$STAGE/README.txt"         "$TMP_MOUNT/README.txt"

# Detach
hdiutil detach "$TMP_MOUNT" -quiet

# Convert to compressed read-only
if [ -f "$DMG_PATH" ]; then
    rm -f "$DMG_PATH"
fi
hdiutil convert "$TMP_DMG" -format UDZO -o "$DMG_PATH" -quiet

rm -rf "$TMP"

# ── Checksums ─────────────────────────────────────────────────────────────────
if command -v shasum >/dev/null 2>&1; then
    HASH="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
elif command -v sha256sum >/dev/null 2>&1; then
    HASH="$(sha256sum "$DMG_PATH" | awk '{print $1}')"
else
    HASH="(sha256sum not available)"
fi

SIZE_MB="$(du -m "$DMG_PATH" | awk '{print $1}')"

# Append to checksums file if it exists
CHECKSUM_FILE="$RELEASE_DIR/checksums-$VERSION.txt"
if [ -f "$CHECKSUM_FILE" ]; then
    # Remove existing entry for this dmg if re-running
    grep -v "$DMG_NAME" "$CHECKSUM_FILE" > "$CHECKSUM_FILE.tmp" || true
    echo "$HASH  $DMG_NAME" >> "$CHECKSUM_FILE.tmp"
    mv "$CHECKSUM_FILE.tmp" "$CHECKSUM_FILE"
fi

echo "  [OK]  $DMG_NAME  (~${SIZE_MB}MB)"
echo "        SHA256: $HASH"
echo ""
echo "Upload to:  https://www.felix.ai/releases/$DMG_NAME"
echo ""
