#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.0}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/EasyMacBord.app"

cd "$ROOT_DIR"
rm -rf "$APP_DIR" "$DIST_DIR/EasyMacBord-${VERSION}-arm64.dmg"
swift build --configuration release --arch arm64

BIN_DIR="$(swift build --show-bin-path --configuration release --arch arm64)"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/EasyMacBord" "$APP_DIR/Contents/MacOS/EasyMacBord"
cp "$ROOT_DIR/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP_DIR/Contents/Info.plist"

codesign --force --sign - "$APP_DIR"
codesign --verify --strict --verbose=2 "$APP_DIR"
codesign --display --verbose=4 "$APP_DIR"
ARCHITECTURES="$(lipo -archs "$APP_DIR/Contents/MacOS/EasyMacBord")"
if [[ "$ARCHITECTURES" != "arm64" ]]; then
  echo "Expected arm64 only, found: $ARCHITECTURES" >&2
  exit 1
fi
hdiutil create -volname "EasyMacBord" -srcfolder "$APP_DIR" -ov -format UDZO "$DIST_DIR/EasyMacBord-${VERSION}-arm64.dmg"

echo "Created: $DIST_DIR/EasyMacBord-${VERSION}-arm64.dmg"
