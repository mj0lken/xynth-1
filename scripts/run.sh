#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT_DIR/scripts/build-app.sh" release
open "$ROOT_DIR/build/XYNTH-1.app"
