#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
XCODEPROJ="$ROOT/apps/oae-mac/OAE.xcodeproj"

echo "[install-oae-macos] Building Debug…"
xcodebuild -scheme OAE -configuration Debug -project "$XCODEPROJ" -destination "platform=macOS" build

DERIVED="$(ls -dt "$HOME/Library/Developer/Xcode/DerivedData"/OAE-* 2>/dev/null | head -1 || true)"
if [[ -z "$DERIVED" ]]; then
  echo "[install-oae-macos] error: no OAE-* DerivedData folder found" >&2
  exit 1
fi
BUILT="$DERIVED/Build/Products/Debug/OAE.app"
if [[ ! -d "$BUILT" ]]; then
  echo "[install-oae-macos] error: missing $BUILT" >&2
  exit 1
fi

echo "[install-oae-macos] Installing → /Applications/OAE.app"
ditto "$BUILT" "/Applications/OAE.app"

# Legacy Tauri bundles (old product names)
if ls /Applications/*STT*.app &>/dev/null; then
  echo "[install-oae-macos] Removing legacy *STT*.app bundles in /Applications…"
  rm -rf /Applications/*STT*.app || true
fi
if [[ -d "/Applications/ODI.app" ]]; then
  echo "[install-oae-macos] Removing previous /Applications/ODI.app"
  rm -rf "/Applications/ODI.app"
fi
if [[ -d "/Applications/OAE STT.app" ]]; then
  echo "[install-oae-macos] Removing /Applications/OAE STT.app"
  rm -rf "/Applications/OAE STT.app"
fi

echo "[install-oae-macos] Done. New build: $BUILT"
echo "[install-oae-macos] Open: open -a OAE"
