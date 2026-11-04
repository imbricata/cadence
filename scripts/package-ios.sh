#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/build"
OUTPUT_IPA="$OUTPUT_DIR/Cadence.ipa"
DERIVED_DATA="$OUTPUT_DIR/CadenceDerivedData"

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Required tool not found: %s\n' "$1" >&2
    exit 1
  fi
}

for tool in xcodegen xcodebuild ditto zip unzip mktemp plutil; do
  require_tool "$tool"
done

mkdir -p "$OUTPUT_DIR"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cadence-package.XXXXXX")"
cleanup() {
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

STAGING_DIR="$TEMP_ROOT/Staging"

cd "$ROOT_DIR"
xcodegen generate

xcodebuild \
  -quiet \
  -project "$ROOT_DIR/Cadence.xcodeproj" \
  -scheme CadenceiOS \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

APP_PATH="$DERIVED_DATA/Build/Products/Release-iphoneos/Cadence.app"
if [[ ! -d "$APP_PATH" ]]; then
  printf 'Built app not found at expected path: %s\n' "$APP_PATH" >&2
  exit 1
fi

BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw -o - "$APP_PATH/Info.plist")"
if [[ "$BUNDLE_ID" != 'com.theocoronges.cadence' ]]; then
  printf 'Unexpected iOS bundle identifier: %s\n' "$BUNDLE_ID" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR" "$STAGING_DIR/Payload"
ditto "$APP_PATH" "$STAGING_DIR/Payload/Cadence.app"
(
  cd "$STAGING_DIR"
  zip -qry "$TEMP_ROOT/Cadence.ipa" Payload
)

# Start from a fresh archive so removed resources cannot linger from a previous build.
ditto "$TEMP_ROOT/Cadence.ipa" "$OUTPUT_IPA"

ARCHIVE_CONTENTS="$(unzip -Z1 "$OUTPUT_IPA")"
if [[ "$ARCHIVE_CONTENTS" != *'Payload/Cadence.app/Info.plist'* ]]; then
  printf 'IPA does not contain Payload/Cadence.app/Info.plist\n' >&2
  exit 1
fi

ARCHIVE_BUNDLE_ID="$(unzip -p "$OUTPUT_IPA" 'Payload/Cadence.app/Info.plist' | plutil -extract CFBundleIdentifier raw -o - -)"
if [[ "$ARCHIVE_BUNDLE_ID" != 'com.theocoronges.cadence' ]]; then
  printf 'Unexpected IPA bundle identifier: %s\n' "$ARCHIVE_BUNDLE_ID" >&2
  exit 1
fi

printf 'Created unsigned IPA: %s\n' "$OUTPUT_IPA"
printf 'Bundle identifier: %s\n' "$ARCHIVE_BUNDLE_ID"
printf '%s\n' 'Use AltStore Classic or SideStore to sign and install it; this IPA is not directly installable.'
