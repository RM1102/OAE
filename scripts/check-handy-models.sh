#!/usr/bin/env bash
# Lists Whisper-related files in Handy's default macOS models directory.
set -euo pipefail
DIR="${HOME}/Library/Application Support/com.pais.handy/models"
if [[ ! -d "$DIR" ]]; then
  echo "Handy models directory not found: $DIR"
  exit 0
fi
echo "Handy models: $DIR"
ls -la "$DIR" 2>/dev/null | head -50 || true
find "$DIR" -maxdepth 1 -type f \( -name '*.bin' -o -name '*.onnx' \) -print 2>/dev/null | sort
