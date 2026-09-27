#!/bin/zsh
set -euo pipefail
SOURCE_DIR="${0:A:h}"
VERSION="v0.1.0-beta.5"
OUTPUT="$SOURCE_DIR/dist"
PACKAGE_NAME="Rekordbox-BPM-Key-Watcher-$VERSION-macOS-universal"
STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIR"' EXIT
PACKAGE_DIR="$STAGING_DIR/$PACKAGE_NAME"
mkdir -p "$PACKAGE_DIR" "$OUTPUT"
ARCHS="arm64 x86_64" "$SOURCE_DIR/build.sh" "$PACKAGE_DIR/Rekordbox BPM Key Watcher.app"
lipo "$PACKAGE_DIR/Rekordbox BPM Key Watcher.app/Contents/MacOS/RekordboxBPMKeyWatcher" -verify_arch arm64 x86_64
cp "$SOURCE_DIR/README.md" "$SOURCE_DIR/LICENSE" "$PACKAGE_DIR/"
ditto -c -k --sequesterRsrc --keepParent "$PACKAGE_DIR" "$OUTPUT/$PACKAGE_NAME.zip"
(cd "$OUTPUT" && shasum -a 256 "$PACKAGE_NAME.zip" > SHA256SUMS.txt)
print "Packaged $OUTPUT/$PACKAGE_NAME.zip"
