#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
SOURCE="$ROOT/build/GestureControl.app"
TARGET="/Applications/GestureControl.app"

"$ROOT/scripts/build-app.sh" >/dev/null
pkill -f 'GestureControl.app/Contents/MacOS/GestureControl' 2>/dev/null || true
rm -rf "$TARGET"
ditto "$SOURCE" "$TARGET"
codesign --verify --deep --strict "$TARGET"
open "$TARGET"
echo "$TARGET"
