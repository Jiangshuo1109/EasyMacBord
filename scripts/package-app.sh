#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.0}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/EasyMacBord.app"
DMG_FILE="$DIST_DIR/EasyMacBord-${VERSION}-arm64.dmg"
CHECKSUM_FILE="$DMG_FILE.sha256"
ICON_FILE="$ROOT_DIR/Packaging/Assets/EasyMacBord.icns"

cd "$ROOT_DIR"
rm -rf "$APP_DIR" "$DMG_FILE" "$CHECKSUM_FILE"
if [[ ! -f "$ICON_FILE" ]]; then
  echo "Missing application icon: $ICON_FILE" >&2
  exit 1
fi
swift build --configuration release --arch arm64

BIN_DIR="$(swift build --show-bin-path --configuration release --arch arm64)"
RESOURCE_BUNDLE="$BIN_DIR/EasyMacBord_EasyMacBord.bundle"
if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
  echo "Missing SwiftPM resource bundle: $RESOURCE_BUNDLE" >&2
  exit 1
fi
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/EasyMacBord" "$APP_DIR/Contents/MacOS/EasyMacBord"
cp "$ROOT_DIR/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ICON_FILE" "$APP_DIR/Contents/Resources/EasyMacBord.icns"
cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/"
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
diskutil image create from --format UDZO --volumeName "EasyMacBord" "$APP_DIR" "$DMG_FILE"
shasum -a 256 "$DMG_FILE" > "$CHECKSUM_FILE"

echo "Created: $DMG_FILE"
echo "Checksum: $CHECKSUM_FILE"
