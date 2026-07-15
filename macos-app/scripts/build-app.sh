#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

swift build -c release

APP="$ROOT/build/GestureControl.app"
CONTENTS="$APP/Contents"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$ROOT/.build/release/GestureControl" "$CONTENTS/MacOS/GestureControl"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

codesign --force --deep --sign - \
  --entitlements "$ROOT/Resources/GestureControl.entitlements" \
  "$APP"

codesign --verify --deep --strict "$APP"
echo "$APP"
