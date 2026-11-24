#!/usr/bin/env bash
# Builds XYNTH-1.app for Apple Silicon (arm64) only.
#
# Usage:
#   ./scripts/build-app.sh [debug|release] [--zip] [--sign] [--notarize] [--install]
#
# Environment variables:
#   VERSION           Bundle version (defaults to latest v* git tag, fallback 0.2.1).
#   BUILD_NUMBER      Bundle build number (defaults to git rev-list --count HEAD).
#   SIGNING_IDENTITY  Signing identity ("-" for ad-hoc, or "Developer ID Application: ...").
#   NOTARY_PROFILE    Keychain profile created with `xcrun notarytool store-credentials` (default: xynth-1).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

CONFIG="release"
DO_ZIP=false
DO_SIGN=false
DO_NOTARIZE=false
DO_INSTALL=false

for arg in "$@"; do
  case "$arg" in
    debug|release) CONFIG="$arg" ;;
    --zip)         DO_ZIP=true ;;
    --sign)        DO_SIGN=true ;;
    --notarize)    DO_NOTARIZE=true; DO_SIGN=true; DO_ZIP=true ;;
    --install)     DO_INSTALL=true ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

APP_NAME="XYNTH-1"
VERSION="${VERSION:-$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null | sed 's/^v//' || echo 0.2.1)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
ARCH="arm64"
APP_DIR="$ROOT_DIR/build/${APP_NAME}.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"
ZIP_PATH="$ROOT_DIR/dist/${APP_NAME}-v${VERSION}-${ARCH}.zip"

fail() {
  printf '\n  XYNTH-1 build error: %s\n\n' "$1" >&2
  exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || fail "XYNTH-1 builds on macOS only."

echo "Building ${APP_NAME} v${VERSION} (${BUILD_NUMBER}, ${CONFIG}, Apple Silicon ${ARCH} only)..."
swift build -c "$CONFIG" --arch "$ARCH"

BIN_DIR="$(swift build -c "$CONFIG" --arch "$ARCH" --show-bin-path)"
BIN_PATH="$BIN_DIR/$APP_NAME"
[[ -f "$BIN_PATH" ]] || fail "Compiled binary not found at $BIN_PATH"

BUILT_ARCHS="$(lipo -archs "$BIN_PATH" 2>/dev/null || true)"
[[ "$BUILT_ARCHS" == "$ARCH" ]] || fail "Expected ${ARCH}-only binary, got: ${BUILT_ARCHS}"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"
cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"

# Generate crisp macOS .icns icon
ICONSET_DIR="$ROOT_DIR/build/${APP_NAME}.iconset"
rm -rf "$ICONSET_DIR"
swift "$ROOT_DIR/scripts/make-icon.swift" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$RES_DIR/${APP_NAME}.icns"
rm -rf "$ICONSET_DIR"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.xynth1.hapticsynth</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSArchitecturePriority</key>
    <array>
        <string>arm64</string>
    </array>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

IDENTITY="${SIGNING_IDENTITY:-${SIGN_IDENTITY:-}}"
if [[ -z "$IDENTITY" && "$DO_SIGN" == true ]]; then
  IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -n 1)"
  if [[ -z "$IDENTITY" ]]; then
    fail "No 'Developer ID Application' certificate found in Keychain."
  fi
fi

if [[ -n "$IDENTITY" && "$IDENTITY" != "-" ]]; then
  echo "Signing ${APP_NAME}.app with Hardened Runtime (${IDENTITY})..."
  codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP_DIR"
else
  echo "Ad-hoc signing ${APP_NAME}.app for local Apple Silicon execution..."
  codesign --force --deep --sign - "$APP_DIR"
fi
codesign --verify --deep --strict "$APP_DIR"

echo "Built bundle: $APP_DIR (arch: ${BUILT_ARCHS})"

if [[ "$DO_ZIP" == true ]]; then
  mkdir -p "$ROOT_DIR/dist"
  rm -f "$ZIP_PATH" "${ZIP_PATH}.sha256"
  ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
fi

if [[ "$DO_NOTARIZE" == true ]]; then
  PROFILE="${NOTARY_PROFILE:-xynth-1}"
  NOTARY_ARGS=(--keychain-profile "$PROFILE")
  if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then
    NOTARY_ARGS+=(--keychain "$NOTARY_KEYCHAIN")
  fi
  if ! xcrun notarytool history "${NOTARY_ARGS[@]}" >/dev/null 2>&1; then
    fail "No saved notarytool keychain profile named \"${PROFILE}\"."
  fi

  echo "Submitting ${ZIP_PATH} to Apple Notary Service (profile: ${PROFILE})..."
  xcrun notarytool submit "$ZIP_PATH" "${NOTARY_ARGS[@]}" --wait \
    || fail "Notarization failed. Inspect logs with: xcrun notarytool log <submission-id> --keychain-profile ${PROFILE}"

  echo "Stapling notarization ticket to ${APP_NAME}.app..."
  xcrun stapler staple "$APP_DIR"
  xcrun stapler validate "$APP_DIR"
  spctl --assess --type execute -vv "$APP_DIR"

  rm -f "$ZIP_PATH"
  ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
fi

if [[ "$DO_ZIP" == true ]]; then
  SHA="$(shasum -a 256 "$ZIP_PATH" | cut -d' ' -f1)"
  echo "${SHA}  $(basename "$ZIP_PATH")" | tee "${ZIP_PATH}.sha256"
  echo "Packaged Apple Silicon ZIP: $ZIP_PATH"
fi

if [[ "$DO_INSTALL" == true ]]; then
  if pgrep -x "$APP_NAME" >/dev/null; then
    osascript -e 'quit app id "com.xynth1.hapticsynth"' 2>/dev/null || true
    for _ in 1 2 3 4 5; do pgrep -x "$APP_NAME" >/dev/null || break; sleep 1; done
    pkill -x "$APP_NAME" 2>/dev/null || true
  fi
  rm -rf "/Applications/${APP_NAME}.app"
  cp -R "$APP_DIR" /Applications/
  echo "Installed to /Applications/${APP_NAME}.app"
  open "/Applications/${APP_NAME}.app"
else
  echo "Launch with:  open \"$APP_DIR\""
fi
