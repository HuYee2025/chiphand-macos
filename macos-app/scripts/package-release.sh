#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
PROJECT_ROOT="${ROOT:h}"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
RELEASES="$ROOT/releases"
STAGING="$ROOT/build/package-staging"
APP_SOURCE="$ROOT/build/ChipHand.app"
APP_NAME="薯片手.app"
BASE_NAME="ChipHand-macOS-${VERSION}-universal"

"$ROOT/scripts/build-app.sh" >/dev/null
rm -rf "$STAGING"
mkdir -p "$STAGING" "$RELEASES"

ditto "$APP_SOURCE" "$STAGING/$APP_NAME"
ln -s /Applications "$STAGING/Applications"
ditto "$PROJECT_ROOT/docs/user-guide" "$STAGING/使用说明"
ln -s "使用说明/index.html" "$STAGING/打开使用说明.html"
cp "$PROJECT_ROOT/LICENSE" "$STAGING/LICENSE.txt"
cp "$PROJECT_ROOT/THIRD_PARTY_NOTICES.md" "$STAGING/THIRD_PARTY_NOTICES.md"
cp -R "$PROJECT_ROOT/THIRD_PARTY_LICENSES" "$STAGING/THIRD_PARTY_LICENSES"

rm -f "$RELEASES/$BASE_NAME.dmg" "$RELEASES/$BASE_NAME.zip"
hdiutil create \
  -volname "薯片手 ChipHand" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$RELEASES/$BASE_NAME.dmg" >/dev/null

ditto -c -k --sequesterRsrc --keepParent \
  "$STAGING/$APP_NAME" \
  "$RELEASES/$BASE_NAME.zip"

(
  cd "$RELEASES"
  shasum -a 256 "$BASE_NAME.dmg" "$BASE_NAME.zip" > SHA256SUMS.txt
)

echo "$RELEASES/$BASE_NAME.dmg"
echo "$RELEASES/$BASE_NAME.zip"
echo "$RELEASES/SHA256SUMS.txt"
