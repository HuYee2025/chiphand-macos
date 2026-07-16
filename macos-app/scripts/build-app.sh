#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
PROJECT_ROOT="${ROOT:h}"
cd "$ROOT"

# A freshly installed Xcode blocks xcrun until its License is accepted. Keep
# local prototype builds usable through the already-installed Command Line Tools.
if ! xcrun --find swift >/dev/null 2>&1; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi

npm --prefix "$PROJECT_ROOT" run build:native-recognizer
swift build -c release --arch arm64 --arch x86_64 --product ChipHand

APP="$ROOT/build/ChipHand.app"
CONTENTS="$APP/Contents"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$ROOT/.build/apple/Products/Release/ChipHand" "$CONTENTS/MacOS/ChipHand"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp -R "$ROOT/Resources/MediaPipeRecognizer" "$CONTENTS/Resources/MediaPipeRecognizer"
cp "$ROOT/Resources/ChipHand.icns" "$CONTENTS/Resources/ChipHand.icns"
cp "$ROOT/Resources/ChipHandIcon.png" "$CONTENTS/Resources/ChipHandIcon.png"
cp -R "$PROJECT_ROOT/docs/user-guide" "$CONTENTS/Resources/UserGuide"
cp "$PROJECT_ROOT/LICENSE" "$CONTENTS/Resources/LICENSE.txt"
cp "$PROJECT_ROOT/THIRD_PARTY_NOTICES.md" "$CONTENTS/Resources/THIRD_PARTY_NOTICES.md"
cp -R "$PROJECT_ROOT/THIRD_PARTY_LICENSES" "$CONTENTS/Resources/THIRD_PARTY_LICENSES"

BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$ROOT/Resources/Info.plist")"
DESIGNATED_REQUIREMENT="=designated => identifier \"$BUNDLE_IDENTIFIER\""
codesign --force --deep --sign - \
  --identifier "$BUNDLE_IDENTIFIER" \
  --requirements "$DESIGNATED_REQUIREMENT" \
  --entitlements "$ROOT/Resources/GestureControl.entitlements" \
  "$APP"

codesign --verify --deep --strict "$APP"
file "$CONTENTS/MacOS/ChipHand" | grep -q "universal binary"
echo "$APP"
