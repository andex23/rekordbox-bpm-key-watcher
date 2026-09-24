#!/bin/zsh
set -euo pipefail

SOURCE_DIR="${0:A:h}"
APP_DIR="${1:-$SOURCE_DIR/dist/Rekordbox BPM Key Watcher.app}"
STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIR"' EXIT
STAGED_APP="$STAGING_DIR/Rekordbox BPM Key Watcher.app"
mkdir -p "$STAGED_APP/Contents/MacOS"
TARGET_ARCH="$(uname -m)"
swiftc -swift-version 5 -target "${TARGET_ARCH}-apple-macosx14.0" -framework AppKit -framework Vision -framework ScreenCaptureKit -framework ApplicationServices \
  "$SOURCE_DIR/Core.swift" "$SOURCE_DIR/RekordboxControl.swift" "$SOURCE_DIR/Watcher.swift" "$SOURCE_DIR/Main.swift" \
  -o "$STAGED_APP/Contents/MacOS/RekordboxBPMKeyWatcher"
cp "$SOURCE_DIR/Info.plist" "$STAGED_APP/Contents/Info.plist"
codesign --force --sign - "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"
mkdir -p "${APP_DIR:h}"
/usr/bin/ditto "$STAGED_APP" "$APP_DIR"
print "Built $APP_DIR"
