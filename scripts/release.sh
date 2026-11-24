#!/usr/bin/env bash
# End-to-end Apple Silicon (arm64) release pipeline for XYNTH-1:
#   1. Runs `swift test`
#   2. Builds arm64-only release bundle
#   3. Signs with Developer ID Application + Hardened Runtime, notarizes & staples (unless --unsigned)
#   4. Emits dist/XYNTH-1-v<version>-arm64.zip + .sha256
#   5. Optionally publishes to GitHub Releases via `gh` when passed `--publish`
#
# Usage:
#   ./scripts/release.sh                 # Full signed + notarized arm64 release build
#   ./scripts/release.sh --unsigned      # Ad-hoc signed arm64 release build (no Developer ID required)
#   ./scripts/release.sh --publish       # Build + sign + notarize + publish GitHub Release
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

UNSIGNED=false
PUBLISH=false

for arg in "$@"; do
  case "$arg" in
    --unsigned) UNSIGNED=true ;;
    --publish)  PUBLISH=true ;;
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

echo "Running unit tests..."
swift test

if [[ "$UNSIGNED" == true ]]; then
  echo "Building ad-hoc signed Apple Silicon release..."
  "$ROOT_DIR/scripts/build-app.sh" release --zip
else
  echo "Building Developer ID signed & Apple notarized Apple Silicon release..."
  "$ROOT_DIR/scripts/build-app.sh" release --sign --notarize --zip
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/build/XYNTH-1.app/Contents/Info.plist")"
ZIP_PATH="$ROOT_DIR/dist/XYNTH-1-v${VERSION}-arm64.zip"
SHA_PATH="${ZIP_PATH}.sha256"

if [[ "$PUBLISH" == true ]]; then
  command -v gh >/dev/null 2>&1 || { echo "gh CLI is required for --publish" >&2; exit 1; }
  TAG="v${VERSION}"
  SIGN_NOTE="Developer ID signed & Apple notarized (Gatekeeper-ready)."
  if [[ "$UNSIGNED" == true ]]; then
    SIGN_NOTE="Ad-hoc signed Apple Silicon build (right-click -> Open on first launch)."
  fi
  gh release create "$TAG" "$ZIP_PATH" "$SHA_PATH" \
    --title "XYNTH-1 ${TAG} (Apple Silicon)" \
    --notes "Apple Silicon (\`arm64\`) macOS 14+ release of **XYNTH-1**.

- ${SIGN_NOTE}
- SHA-256: \`$(cut -d' ' -f1 "$SHA_PATH")\`"
  echo "Published GitHub Release ${TAG}!"
fi
