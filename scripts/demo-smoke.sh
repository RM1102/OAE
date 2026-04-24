#!/usr/bin/env bash
# Campus-demo smoke checklist for OAE installs.
set -euo pipefail

APP_PATH="/Applications/OAE.app"
BIN_PATH="${APP_PATH}/Contents/MacOS/OAE"

echo "== OAE demo smoke =="

if [[ ! -x "$BIN_PATH" ]]; then
  echo "error: missing $BIN_PATH (run scripts/install-oae-macos.sh first)" >&2
  exit 1
fi

echo "Opening OAE…"
open -a OAE
