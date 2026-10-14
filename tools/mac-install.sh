#!/bin/sh
# Build (if needed) and install the macOS input method for the current user.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/Mac/build/Build/Products/Release/Scriptorium.app"
DEST="$HOME/Library/Input Methods/Scriptorium.app"
if [ "$1" != "--no-build" ]; then
  (cd "$ROOT/Mac" && xcodegen generate -q && xcodebuild -project ScriptoriumIME.xcodeproj -scheme ScriptoriumIME \
     -configuration Release -derivedDataPath build build -quiet)
fi
pkill -x Scriptorium 2>/dev/null || true         # running copy keeps the old binary
mkdir -p "$HOME/Library/Input Methods"
rm -rf "$DEST" && cp -R "$APP" "$DEST"
swift "$ROOT/tools/tis.swift" register "$DEST"
swift "$ROOT/tools/tis.swift" enable
swift "$ROOT/tools/tis.swift" list
echo "Installed. Pick Latin / Greek (Scriptorium) from the input menu in the menu bar."
