#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/SpatialRelay.xcodeproj"
SCHEME="SpatialRelay"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT/build/DerivedData}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/build}"

PROJECT_VERSION="$(
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -showBuildSettings |
  awk -F ' = ' '/^[[:space:]]*MARKETING_VERSION = / && !found { print $2; found = 1 }'
)"
VERSION="${1:-$PROJECT_VERSION}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'Version must use MAJOR.MINOR.PATCH, received %s\n' "$VERSION" >&2
  exit 2
fi

if [[ "$VERSION" != "$PROJECT_VERSION" ]]; then
  printf 'Requested version %s does not match MARKETING_VERSION %s\n' \
    "$VERSION" "$PROJECT_VERSION" >&2
  exit 2
fi

mkdir -p "$OUTPUT_DIR"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/SpatialRelayRelease.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

xcodebuild -quiet \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  DEVELOPMENT_TEAM= \
  build

SOURCE_APP="$DERIVED_DATA_PATH/Build/Products/Release/SpatialRelay.app"
PACKAGED_APP="$STAGING_DIR/Spatial Audio Relay.app"
EXECUTABLE="$SOURCE_APP/Contents/MacOS/SpatialRelay"
ARCHIVE="$OUTPUT_DIR/QQMusicSpatialAudio-$VERSION-arm64.zip"
CHECKSUM="$ARCHIVE.sha256"

test -d "$SOURCE_APP"
lipo "$EXECUTABLE" -verify_arch arm64
codesign --verify --deep --strict --verbose=2 "$SOURCE_APP"

BUNDLE_VERSION="$(
  /usr/libexec/PlistBuddy \
    -c 'Print :CFBundleShortVersionString' \
    "$SOURCE_APP/Contents/Info.plist"
)"
test "$BUNDLE_VERSION" = "$VERSION"

ditto "$SOURCE_APP" "$PACKAGED_APP"
ditto "$ROOT/LICENSE" "$STAGING_DIR/LICENSE"
rm -f "$ARCHIVE" "$CHECKSUM"
(
  cd "$STAGING_DIR"
  COPYFILE_DISABLE=1 /usr/bin/zip -qry "$ARCHIVE" "Spatial Audio Relay.app" LICENSE
)

unzip -t "$ARCHIVE"
(
  cd "$OUTPUT_DIR"
  shasum -a 256 "$(basename "$ARCHIVE")" > "$(basename "$CHECKSUM")"
)

printf 'Created %s\n' "$ARCHIVE"
printf 'Created %s\n' "$CHECKSUM"
