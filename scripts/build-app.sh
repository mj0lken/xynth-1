#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

CONFIG="${1:-release}"
APP_NAME="XYNTH-1"
VERSION="0.2.0"
APP_DIR="$ROOT_DIR/build/${APP_NAME}.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"

echo "Building ${APP_NAME} (${CONFIG})..."
swift build -c "$CONFIG"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN_PATH="$BIN_DIR/$APP_NAME"

if [[ ! -f "$BIN_PATH" ]]; then
  echo "Error: compiled binary not found at $BIN_PATH" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"
cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"

# Generate crisp macOS .icns icon
ICONSET_DIR="$ROOT_DIR/build/${APP_NAME}.iconset"
rm -rf "$ICONSET_DIR"
swift "$ROOT_DIR/scripts/make-icon.swift" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$RES_DIR/${APP_NAME}.icns"
rm -rf "$ICONSET_DIR"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>XYNTH-1</string>
    <key>CFBundleIconFile</key>
    <string>XYNTH-1</string>
    <key>CFBundleIdentifier</key>
    <string>com.xynth1.hapticsynth</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>XYNTH-1</string>
    <key>CFBundleDisplayName</key>
    <string>XYNTH-1</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "Built bundle: $APP_DIR"
if [[ "${2:-}" == "--zip" ]]; then
  mkdir -p "$ROOT_DIR/dist"
  ZIP_PATH="$ROOT_DIR/dist/${APP_NAME}-v${VERSION}-macos.zip"
  rm -f "$ZIP_PATH"
  ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
  echo "Packaged ZIP: $ZIP_PATH"
fi
echo "Launch with:  open \"$APP_DIR\""
