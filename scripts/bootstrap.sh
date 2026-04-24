#!/usr/bin/env bash
# Installs XcodeGen (via Homebrew) and generates the OAE Xcode project.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required to install xcodegen." >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "→ Installing xcodegen…"
  brew install xcodegen
fi

ICONSET="apps/oae-mac/OAE/Resources/Assets.xcassets/AppIcon.appiconset"
if [[ ! -f "$ICONSET/AppIcon-1024.png" ]]; then
  echo "→ Generating default app icon (1024)…"
  swift "$ROOT/scripts/generate-icon.swift" || true
fi

cd apps/oae-mac
echo "→ Generating OAE.xcodeproj from project.yml…"
xcodegen generate

echo "→ Resolving Swift packages…"
xcodebuild -resolvePackageDependencies -project OAE.xcodeproj -scheme OAE >/dev/null

echo "✓ Done. Open apps/oae-mac/OAE.xcodeproj in Xcode."
