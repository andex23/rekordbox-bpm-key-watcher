#!/bin/zsh
set -euo pipefail

SOURCE_DIR="${0:A:h}"
APP_DIR="${1:-$SOURCE_DIR/dist/Rekordbox BPM Key Watcher.app}"
mkdir -p "$APP_DIR/Contents/MacOS"
TARGET_ARCH="$(uname -m)"
swiftc -swift-version 5 -target "${TARGET_ARCH}-apple-macosx14.0" -framework AppKit -framework Vision -framework ScreenCaptureKit -framework ApplicationServices \
  "$SOURCE_DIR/Core.swift" "$SOURCE_DIR/RekordboxControl.swift" "$SOURCE_DIR/Watcher.swift" "$SOURCE_DIR/Main.swift" \
  -o "$APP_DIR/Contents/MacOS/RekordboxBPMKeyWatcher"
cp "$SOURCE_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
xattr -cr "$APP_DIR"
codesign --force --sign - "$APP_DIR"
codesign --verify "$APP_DIR"
print "Built $APP_DIR"
