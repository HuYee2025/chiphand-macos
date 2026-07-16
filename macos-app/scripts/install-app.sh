#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
SOURCE="$ROOT/build/ChipHand.app"
TARGET="/Applications/薯片手.app"

"$ROOT/scripts/build-app.sh" >/dev/null
pkill -f 'ChipHand.app/Contents/MacOS/ChipHand' 2>/dev/null || true
pkill -f '薯片手.app/Contents/MacOS/ChipHand' 2>/dev/null || true
rm -rf "$TARGET"
ditto "$SOURCE" "$TARGET"
codesign --verify --deep --strict "$TARGET"
open "$TARGET"
echo "$TARGET"
