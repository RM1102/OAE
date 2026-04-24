#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="/Users/rahulmasand/Documents/Ideas/For IITD/OAE/apps/oae-mac"
SCHEME="OAE"
CONFIGURATION="Debug"
DERIVED_BASE="$HOME/Library/Developer/Xcode/DerivedData"
MODEL_NAME="${1:-openai_whisper-large-v3-v20240930_626MB}"
SOURCE_MODELS_DIR="$HOME/Library/Application Support/OAE/Models"
OUT_BASE="$HOME/Desktop/OAE-Professor-Kit"

echo "[ship] Verifying model source..."
# Handle nested layout (Models/models/<variant>) if present.
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
  if [[ -n "${MODEL_SOURCE_PATH:-}" ]]; then
    MODEL_NAME="$(basename "$MODEL_SOURCE_PATH")"
    echo "[ship] Default model missing; using installed model: $MODEL_NAME"
  else
    echo "[ship] Missing bundled model: $SOURCE_MODELS_DIR/$MODEL_NAME"
    echo "[ship] First download a model in OAE Settings -> Models, then rerun."
    exit 1
  fi
fi

echo "[ship] Building latest app..."
xcodebuild -scheme "$SCHEME" -configuration "$CONFIGURATION" build -project "$PROJECT_DIR/OAE.xcodeproj" >/tmp/oae-ship-build.log

LATEST_APP="$(ls -td "$DERIVED_BASE"/OAE-*/Build/Products/"$CONFIGURATION"/OAE.app 2>/dev/null | head -n 1)"
if [[ -z "${LATEST_APP:-}" ]]; then
  echo "[ship] Could not locate built OAE.app in DerivedData"
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$OUT_BASE-$STAMP"
mkdir -p "$OUT_DIR"

echo "[ship] Staging app and models..."
cp -R "$LATEST_APP" "$OUT_DIR/OAE.app"
mkdir -p "$OUT_DIR/models"
cp -R "$MODEL_SOURCE_PATH" "$OUT_DIR/models/"

cat >"$OUT_DIR/install.command" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_SRC="$SRC_DIR/OAE.app"
MODELS_SRC="$SRC_DIR/models"
DEST_APP="/Applications/OAE.app"
DEST_BUNDLED="$HOME/Library/Application Support/OAE/BundledModels"

if [[ ! -d "$APP_SRC" ]]; then
  echo "[install] OAE.app not found beside install.command"
  exit 1
fi
if [[ ! -d "$MODELS_SRC" ]]; then
  echo "[install] models/ not found beside install.command"
  exit 1
fi

echo "[install] Installing app to /Applications..."
rm -rf "$DEST_APP"
cp -R "$APP_SRC" "$DEST_APP"

echo "[install] Installing bundled models..."
rm -rf "$DEST_BUNDLED"
mkdir -p "$DEST_BUNDLED"
cp -R "$MODELS_SRC"/. "$DEST_BUNDLED"/

defaults write computer.oae.OAE oae.shipping.requireSetup -bool true
defaults write computer.oae.OAE oae.shipping.setupCompleted -bool false
defaults write computer.oae.OAE oae.shipping.modelsReady -bool false
defaults write computer.oae.OAE oae.shipping.ollamaReady -bool false

echo "[install] Launching OAE..."
open "$DEST_APP"
echo "[install] Done. Complete the in-app setup assistant."
EOF

chmod +x "$OUT_DIR/install.command"

cp "/Users/rahulmasand/Documents/Ideas/For IITD/OAE/docs/professor/README.md" "$OUT_DIR/README.md" 2>/dev/null || true
cp "/Users/rahulmasand/Documents/Ideas/For IITD/OAE/docs/professor/VALIDATION_CHECKLIST.md" "$OUT_DIR/VALIDATION_CHECKLIST.md" 2>/dev/null || true

ZIP_PATH="$OUT_DIR.zip"
echo "[ship] Creating zip package..."
ditto -c -k --sequesterRsrc --keepParent "$OUT_DIR" "$ZIP_PATH"

echo "[ship] Ready:"
echo "       Folder: $OUT_DIR"
echo "       Zip:    $ZIP_PATH"
