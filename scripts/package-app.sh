#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION=""
ALLOW_DIRTY=false
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/EasyMacBord.app"
DMG_FILE=""
CHECKSUM_FILE=""
MANIFEST_FILE=""
ICON_FILE="$ROOT_DIR/Packaging/Assets/EasyMacBord.icns"
DMG_STAGING_DIR="$(mktemp -d)"
TEST_OUTPUT_FILE="$(mktemp)"

json_string() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  print -nr -- "\"$value\""
}

codesign_field() {
  local field="$1"
  print -r -- "$CODESIGN_DETAILS" | sed -n "s/^${field}=//p" | head -n 1
}

cleanup() {
  rm -rf "$DMG_STAGING_DIR" "$TEST_OUTPUT_FILE"
}
trap cleanup EXIT

usage() {
  cat <<'USAGE'
Usage: scripts/package-app.sh <version> [--allow-dirty]

Internal Beta candidates require a clean source tree. Use --allow-dirty only
for a local diagnostic package; its manifest cannot be used as a candidate.
USAGE
}

for argument in "$@"; do
  case "$argument" in
    --allow-dirty)
      ALLOW_DIRTY=true
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    -*)
      usage >&2
      exit 2
      ;;
    *)
      if [[ -n "$VERSION" ]]; then
        usage >&2
        exit 2
      fi
      VERSION="$argument"
      ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  usage >&2
  exit 2
fi

cd "$ROOT_DIR"
if [[ ! "$VERSION" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  echo "Version must contain only letters, numbers, dots, underscores, or hyphens." >&2
  exit 1
fi

DMG_FILE="$DIST_DIR/EasyMacBord-${VERSION}-arm64.dmg"
CHECKSUM_FILE="$DMG_FILE.sha256"
MANIFEST_FILE="$DMG_FILE.manifest.json"

GIT_COMMIT="$(git rev-parse --verify HEAD)"
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  SOURCE_TREE_STATE="dirty"
  if [[ "$ALLOW_DIRTY" != true ]]; then
    echo "Refusing to create a candidate from a dirty source tree. Use --allow-dirty only for local diagnostics." >&2
    exit 1
  fi
else
  SOURCE_TREE_STATE="clean"
fi
XCODE_VERSION="$(xcodebuild -version | sed -n 's/^Xcode //p' | head -n 1)"
XCODE_BUILD="$(xcodebuild -version | sed -n 's/^Build version //p' | head -n 1)"
SWIFT_VERSION="$(swift --version | sed -n '1p')"

if [[ -z "$XCODE_VERSION" || -z "$SWIFT_VERSION" ]]; then
  echo "Unable to determine the Xcode or Swift version." >&2
  exit 1
fi

if [[ ! -f "$ICON_FILE" ]]; then
  echo "Missing application icon: $ICON_FILE" >&2
  exit 1
fi
swift test 2>&1 | tee "$TEST_OUTPUT_FILE"
TEST_COUNT="$(sed -nE 's/.*Executed ([0-9]+) tests, with 0 failures.*/\1/p' "$TEST_OUTPUT_FILE" | tail -n 1)"
if [[ -z "$TEST_COUNT" ]]; then
  echo "Unable to determine the passing test count from swift test output." >&2
  exit 1
fi
rm -rf "$APP_DIR" "$DMG_FILE" "$CHECKSUM_FILE" "$MANIFEST_FILE"
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
/usr/libexec/PlistBuddy -c "Add :EasyMacBordBuildArchitecture string arm64" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :EasyMacBordSigningSummary string 内部 ad-hoc 签名（未公证，无开发团队标识）" "$APP_DIR/Contents/Info.plist"

# Preserve one local designated requirement across ad-hoc rebuilds so macOS
# can retain the user's Input Monitoring approval for this development app.
codesign --force --sign - -r='designated => identifier "com.easymacbord.app"' "$APP_DIR"
codesign --verify --strict "$APP_DIR"
CODESIGN_DETAILS="$(codesign --display --verbose=4 "$APP_DIR" 2>&1)"
CODESIGN_IDENTIFIER="$(codesign_field "Identifier")"
CODESIGN_SIGNATURE="$(codesign_field "Signature")"
CODESIGN_TEAM_IDENTIFIER="$(codesign_field "TeamIdentifier")"
CODESIGN_FORMAT="$(codesign_field "Format")"
if [[ -z "$CODESIGN_IDENTIFIER" || -z "$CODESIGN_SIGNATURE" || -z "$CODESIGN_TEAM_IDENTIFIER" || -z "$CODESIGN_FORMAT" ]]; then
  echo "Unable to determine the codesign summary." >&2
  exit 1
fi
ARCHITECTURES="$(lipo -archs "$APP_DIR/Contents/MacOS/EasyMacBord")"
if [[ "$ARCHITECTURES" != "arm64" ]]; then
  echo "Expected arm64 only, found: $ARCHITECTURES" >&2
  exit 1
fi
cp -R "$APP_DIR" "$DMG_STAGING_DIR/EasyMacBord.app"
diskutil image create from --format UDZO --volumeName "EasyMacBord" "$DMG_STAGING_DIR" "$DMG_FILE"
DMG_SHA256="$(shasum -a 256 "$DMG_FILE" | awk '{print $1}')"
print -r -- "$DMG_SHA256  ${DMG_FILE:t}" > "$CHECKSUM_FILE"

{
  print -r -- "{"
  print -r -- "  \"schema_version\": 1,"
  print -n -- "  \"version\": "
  json_string "$VERSION"
  print -r -- ","
  print -n -- "  \"git_commit\": "
  json_string "$GIT_COMMIT"
  print -r -- ","
  print -n -- "  \"source_tree_state\": "
  json_string "$SOURCE_TREE_STATE"
  print -r -- ","
  print -r -- "  \"toolchain\": {"
  print -n -- "    \"xcode_version\": "
  json_string "$XCODE_VERSION"
  print -r -- ","
  print -n -- "    \"xcode_build\": "
  json_string "$XCODE_BUILD"
  print -r -- ","
  print -n -- "    \"swift_version\": "
  json_string "$SWIFT_VERSION"
  print -r -- ""
  print -r -- "  },"
  print -r -- "  \"tests\": {"
  print -r -- "    \"status\": \"passed\","
  print -r -- "    \"count\": $TEST_COUNT"
  print -r -- "  },"
  print -n -- "  \"architecture\": "
  json_string "$ARCHITECTURES"
  print -r -- ","
  print -r -- "  \"dmg\": {"
  print -n -- "    \"filename\": "
  json_string "${DMG_FILE:t}"
  print -r -- ","
  print -n -- "    \"sha256\": "
  json_string "$DMG_SHA256"
  print -r -- ""
  print -r -- "  },"
  print -r -- "  \"codesign\": {"
  print -n -- "    \"identifier\": "
  json_string "$CODESIGN_IDENTIFIER"
  print -r -- ","
  print -n -- "    \"signature\": "
  json_string "$CODESIGN_SIGNATURE"
  print -r -- ","
  print -n -- "    \"team_identifier\": "
  json_string "$CODESIGN_TEAM_IDENTIFIER"
  print -r -- ","
  print -n -- "    \"format\": "
  json_string "$CODESIGN_FORMAT"
  print -r -- ""
  print -r -- "  }"
  print -r -- "}"
} > "$MANIFEST_FILE"

echo "Created: $DMG_FILE"
echo "Checksum: $CHECKSUM_FILE"
echo "Manifest: $MANIFEST_FILE"
echo "Signing: identifier=$CODESIGN_IDENTIFIER signature=$CODESIGN_SIGNATURE team_identifier=$CODESIGN_TEAM_IDENTIFIER"
