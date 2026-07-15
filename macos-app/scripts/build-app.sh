#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

# A freshly installed Xcode blocks xcrun until its License is accepted. Keep
# local prototype builds usable through the already-installed Command Line Tools.
if ! xcrun --find swift >/dev/null 2>&1; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi

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
