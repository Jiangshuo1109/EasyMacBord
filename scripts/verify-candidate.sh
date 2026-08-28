#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INPUT="${1:-}"
MOUNT_DIR=""
ATTACHED=false

usage() {
  cat <<'USAGE'
Usage:
  scripts/verify-candidate.sh <manifest path | DMG path | candidate basename>

Examples:
  scripts/verify-candidate.sh dist/EasyMacBord-0.1.0-beta.2-arm64.dmg.manifest.json
  scripts/verify-candidate.sh dist/EasyMacBord-0.1.0-beta.2-arm64.dmg
  scripts/verify-candidate.sh EasyMacBord-0.1.0-beta.2-arm64
USAGE
}

fail() {
  print -u2 -r -- "Verification failed: $1"
  exit 1
}

cleanup() {
  if [[ "$ATTACHED" == true ]]; then
    hdiutil detach "$MOUNT_DIR" -quiet || print -u2 -r -- "Warning: could not detach $MOUNT_DIR"
  fi
  if [[ -n "$MOUNT_DIR" && -d "$MOUNT_DIR" ]]; then
    rmdir "$MOUNT_DIR" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if [[ -z "$INPUT" || "$INPUT" == "--help" || "$INPUT" == "-h" ]]; then
  usage
  [[ -n "$INPUT" ]] && exit 0
  exit 2
fi

if [[ "$INPUT" == *.manifest.json ]]; then
  MANIFEST_INPUT="$INPUT"
elif [[ "$INPUT" == *.dmg ]]; then
  MANIFEST_INPUT="${INPUT}.manifest.json"
else
  if [[ "$INPUT" == */* ]]; then
    DMG_INPUT="${INPUT}.dmg"
  else
    DMG_INPUT="$ROOT_DIR/dist/${INPUT}.dmg"
  fi
  MANIFEST_INPUT="${DMG_INPUT}.manifest.json"
fi

[[ -f "$MANIFEST_INPUT" ]] || fail "manifest not found: $MANIFEST_INPUT"
MANIFEST_DIR="$(cd "$(dirname "$MANIFEST_INPUT")" && pwd)"
MANIFEST_FILE="$MANIFEST_DIR/$(basename "$MANIFEST_INPUT")"

MANIFEST_VALUES="$(swift - "$MANIFEST_FILE" <<'SWIFT'
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Verification failed: \(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count == 2 else {
    fail("manifest path is required")
}

let manifestURL = URL(fileURLWithPath: CommandLine.arguments[1])
guard let data = try? Data(contentsOf: manifestURL),
      let object = try? JSONSerialization.jsonObject(with: data),
      let manifest = object as? [String: Any] else {
    fail("manifest is not a JSON object")
}

guard manifest["schema_version"] as? Int == 1 else {
    fail("unsupported manifest schema_version")
}
guard let version = manifest["version"] as? String,
      version.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*$", options: .regularExpression) != nil else {
    fail("invalid manifest version")
}
guard manifest["source_tree_state"] as? String == "clean" else {
    fail("source_tree_state must be clean")
}
guard manifest["architecture"] as? String == "arm64" else {
    fail("manifest architecture must be arm64")
}
guard let tests = manifest["tests"] as? [String: Any],
      tests["status"] as? String == "passed",
      let testCount = tests["count"] as? Int,
      testCount > 0 else {
    fail("manifest must record a passing, nonzero test count")
}
guard let dmg = manifest["dmg"] as? [String: Any],
      let filename = dmg["filename"] as? String,
      filename == "EasyMacBord-\(version)-arm64.dmg",
      let checksum = dmg["sha256"] as? String,
      checksum.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil else {
    fail("manifest DMG filename or SHA-256 is invalid")
}
guard let codesign = manifest["codesign"] as? [String: Any],
      codesign["identifier"] as? String == "com.easymacbord.app",
      let signature = codesign["signature"] as? String,
      !signature.isEmpty,
      let teamIdentifier = codesign["team_identifier"] as? String,
      !teamIdentifier.isEmpty,
      let format = codesign["format"] as? String,
      !format.isEmpty else {
    fail("manifest codesign summary is incomplete")
}

print("\(version)\t\(filename)\t\(checksum.lowercased())")
SWIFT
)" || exit 1

IFS=$'\t' read -r VERSION DMG_FILENAME MANIFEST_SHA256 <<< "$MANIFEST_VALUES"
[[ -n "$VERSION" && -n "$DMG_FILENAME" && -n "$MANIFEST_SHA256" ]] || fail "could not read manifest values"

[[ "$(basename "$MANIFEST_FILE")" == "${DMG_FILENAME}.manifest.json" ]] || fail "manifest filename does not match its DMG"
DMG_FILE="$MANIFEST_DIR/$DMG_FILENAME"
CHECKSUM_FILE="$DMG_FILE.sha256"
[[ -f "$DMG_FILE" ]] || fail "DMG not found: $DMG_FILE"
[[ -f "$CHECKSUM_FILE" ]] || fail "checksum file not found: $CHECKSUM_FILE"

ACTUAL_SHA256="$(shasum -a 256 "$DMG_FILE" | awk '{print $1}')"
[[ "$ACTUAL_SHA256" == "$MANIFEST_SHA256" ]] || fail "DMG SHA-256 does not match manifest"

EXPECTED_CHECKSUM_LINE="$MANIFEST_SHA256  $DMG_FILENAME"
CHECKSUM_LINE="$(<"$CHECKSUM_FILE")"
[[ "$CHECKSUM_LINE" == "$EXPECTED_CHECKSUM_LINE" ]] || fail "checksum file does not match manifest"
(
  cd "$MANIFEST_DIR"
  shasum -a 256 -c "$(basename "$CHECKSUM_FILE")"
)

MOUNT_DIR="$(mktemp -d)"
diskutil image attach --readOnly --nobrowse --mountPoint "$MOUNT_DIR" "$DMG_FILE" >/dev/null
ATTACHED=true

APP_DIR="$MOUNT_DIR/EasyMacBord.app"
[[ -d "$APP_DIR" ]] || fail "EasyMacBord.app is missing from the DMG"
BIN_FILE="$APP_DIR/Contents/MacOS/EasyMacBord"
[[ -f "$BIN_FILE" ]] || fail "main executable is missing from the application bundle"

codesign --verify --strict "$APP_DIR"
ARCHITECTURES="$(lipo -archs "$BIN_FILE")"
[[ "$ARCHITECTURES" == "arm64" ]] || fail "expected arm64 main executable, found: $ARCHITECTURES"

print -r -- "Candidate verified: version=$VERSION sha256=$ACTUAL_SHA256 architecture=$ARCHITECTURES"
