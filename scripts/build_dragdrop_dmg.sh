#!/usr/bin/env bash
# Build OAE.app and a drag-and-drop DMG with Whisper CoreML embedded under
# OAE.app/Contents/Resources/BundledModels/
#
# Environment (optional):
#   OAE_BUILD_CONFIGURATION   Debug | Release (default: Debug)
#   OAE_DERIVED_DATA_PATH     If set, xcodebuild uses this path and the .app is read from there
#   OAE_MODEL_SOURCE_DIR      Search for MODEL_NAME here first (default: ~/Library/Application Support/OAE/Models)
#   OAE_DMG_OUT_DIR           Output directory for .dmg (default: repo root)
#   OAE_DMG_BASENAME          Filename without .dmg (default: OAE-Installer-Latest)
#   OAE_DMG_STAGE_DIR         Staging folder (default: Desktop or TMPDIR)
#
# Positional:
#   $1  MODEL_NAME variant id (default: openai_whisper-large-v3-v20240930_626MB)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="${OAE_PROJECT_DIR:-$ROOT/apps/oae-mac}"
SCHEME="OAE"
CONFIGURATION="${OAE_BUILD_CONFIGURATION:-Debug}"
MODEL_NAME="${1:-openai_whisper-large-v3-v20240930_626MB}"
SOURCE_MODELS_DIR="${OAE_MODEL_SOURCE_DIR:-$HOME/Library/Application Support/OAE/Models}"
OUT_NAME="${OAE_DMG_BASENAME:-OAE-Installer-Latest}"
OUT_DIR="${OAE_DMG_OUT_DIR:-$ROOT}"
STAGE_DIR="${OAE_DMG_STAGE_DIR:-$HOME/Desktop/${OUT_NAME}-staging}"
DMG_PATH="$OUT_DIR/${OUT_NAME}.dmg"
DERIVED_CUSTOM="${OAE_DERIVED_DATA_PATH:-}"

echo "[dmg] ROOT=$ROOT CONFIGURATION=$CONFIGURATION OUT_NAME=$OUT_NAME"

echo "[dmg] Resolving model source in: $SOURCE_MODELS_DIR"
if [[ -d "$SOURCE_MODELS_DIR/models" ]]; then
  SOURCE_MODELS_DIR="$SOURCE_MODELS_DIR/models"
fi

MODEL_SOURCE_PATH=""
if [[ -d "$SOURCE_MODELS_DIR/$MODEL_NAME" ]]; then
  MODEL_SOURCE_PATH="$SOURCE_MODELS_DIR/$MODEL_NAME"
elif compgen -G "$SOURCE_MODELS_DIR/*/$MODEL_NAME" >/dev/null; then
  MODEL_SOURCE_PATH="$(ls -1d "$SOURCE_MODELS_DIR"/*/"$MODEL_NAME" | head -n 1)"
else
  if compgen -G "$SOURCE_MODELS_DIR/*/*" >/dev/null; then
    MODEL_SOURCE_PATH="$(ls -1d "$SOURCE_MODELS_DIR"/*/* | head -n 1)"
  elif compgen -G "$SOURCE_MODELS_DIR/*" >/dev/null; then
    MODEL_SOURCE_PATH="$(ls -1d "$SOURCE_MODELS_DIR"/* | head -n 1)"
  fi
fi

if [[ -z "${MODEL_SOURCE_PATH:-}" ]]; then
  echo "[dmg] No local Whisper model found under $SOURCE_MODELS_DIR"
  echo "[dmg] Run: pip3 install -r scripts/requirements-dmg-ci.txt && python3 scripts/download_default_whisper_model.py /path/to/dir"
  echo "[dmg] Then: OAE_MODEL_SOURCE_DIR=/path/to/dir $0"
  exit 1
fi
echo "[dmg] Using bundled model payload: $MODEL_SOURCE_PATH"

echo "[dmg] Building $SCHEME ($CONFIGURATION)..."
BUILD_LOG="${TMPDIR:-/tmp}/oae-dmg-build.log"
XB=(
  xcodebuild
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -project "$PROJECT_DIR/OAE.xcodeproj"
)
if [[ -n "$DERIVED_CUSTOM" ]]; then
  mkdir -p "$DERIVED_CUSTOM"
  XB+=(-derivedDataPath "$DERIVED_CUSTOM")
fi
XB+=(build)
# GitHub-hosted runners have no Apple Development cert for our team; use ad-hoc sign.
if [[ "${GITHUB_ACTIONS:-false}" == "true" ]]; then
  echo "[dmg] GITHUB_ACTIONS=true: ad-hoc code signing (CODE_SIGN_IDENTITY=-, CODE_SIGNING_REQUIRED=NO)"
  XB+=(
    CODE_SIGN_IDENTITY="-"
    CODE_SIGN_STYLE=Manual
    DEVELOPMENT_TEAM=""
    CODE_SIGNING_REQUIRED=NO
  )
fi

set +e
"${XB[@]}" 2>&1 | tee "$BUILD_LOG"
xc=${PIPESTATUS[0]}
set -e
if [[ "$xc" -ne 0 ]]; then
  echo "[dmg] xcodebuild failed (exit $xc). Last 80 lines of $BUILD_LOG:" >&2
  tail -n 80 "$BUILD_LOG" >&2 || true
  exit "$xc"
fi

if [[ -n "$DERIVED_CUSTOM" ]]; then
  LATEST_APP="$DERIVED_CUSTOM/Build/Products/$CONFIGURATION/OAE.app"
else
  DERIVED_BASE="${HOME}/Library/Developer/Xcode/DerivedData"
  LATEST_APP="$(ls -td "$DERIVED_BASE"/OAE-*/Build/Products/"$CONFIGURATION"/OAE.app 2>/dev/null | head -n 1)"
fi

if [[ ! -d "${LATEST_APP:-}" ]]; then
  echo "[dmg] Could not locate built OAE.app at $LATEST_APP (see $BUILD_LOG)" >&2
  tail -n 40 "$BUILD_LOG" >&2 || true
  exit 1
fi

VERSION="$(defaults read "$LATEST_APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo 0.0.0)"
echo "[dmg] Built app: $LATEST_APP (CFBundleShortVersionString=$VERSION)"

echo "[dmg] Preparing drag-drop staging folder..."
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$LATEST_APP" "$STAGE_DIR/OAE.app"
ln -s /Applications "$STAGE_DIR/Applications"
cat >"$STAGE_DIR/README.txt" <<'EOF'
1) Drag OAE.app onto Applications.
2) Open OAE from Applications. That's it.
   - OAE sets itself up automatically the first time you open it
     (installs the transcription model and the local AI model).
3) If macOS asks, click "Open" for an unidentified developer, and
   grant Microphone and Accessibility permissions when prompted.

No commands, no Terminal. Just drag and open.
EOF

echo "[dmg] Embedding bundled models inside app resources..."
APP_BUNDLED_MODELS="$STAGE_DIR/OAE.app/Contents/Resources/BundledModels"
mkdir -p "$APP_BUNDLED_MODELS"
cp -R "$MODEL_SOURCE_PATH" "$APP_BUNDLED_MODELS/"

echo "[dmg] Creating DMG..."
mkdir -p "$OUT_DIR"
rm -f "$DMG_PATH"
hdiutil create -volname "OAE Installer" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_PATH" >"${TMPDIR:-/tmp}/oae-dmg-create.log" 2>&1

SUM_FILE="$DMG_PATH.sha256"
(
  cd "$OUT_DIR"
  shasum -a 256 "$(basename "$DMG_PATH")" >"$(basename "$SUM_FILE")"
)
echo "[dmg] SHA256 written to $SUM_FILE"

echo "[dmg] Ready: $DMG_PATH"
echo "[dmg] Open it and drag OAE.app to Applications."
