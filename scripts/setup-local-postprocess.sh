#!/usr/bin/env bash
# Sets up local Ollama + model for OAE Post Process.
set -euo pipefail

MODEL="${1:-gemma2:2b}"
OLLAMA_URL="http://127.0.0.1:11434"

echo "== OAE local post-process setup =="
echo "Model: ${MODEL}"

if ! command -v ollama >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "-> Installing Ollama via Homebrew..."
    brew install ollama
  else
    echo "❌ Ollama not installed and Homebrew is unavailable."
    echo "   Install Homebrew: https://brew.sh"
    echo "   Then run: brew install ollama"
    exit 1
  fi
fi

if ! curl -fsS "${OLLAMA_URL}/api/version" >/dev/null 2>&1; then
  echo "-> Starting Ollama daemon..."
  nohup ollama serve >/tmp/oae-ollama.log 2>&1 &
  for _ in $(seq 1 20); do
    if curl -fsS "${OLLAMA_URL}/api/version" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
fi

if ! curl -fsS "${OLLAMA_URL}/api/version" >/dev/null 2>&1; then
  echo "❌ Ollama daemon is not reachable."
  echo "   Start manually: ollama serve"
  exit 1
fi

TAGS_JSON="$(curl -fsS "${OLLAMA_URL}/api/tags" || true)"
if /usr/bin/python3 - "${MODEL}" "${TAGS_JSON}" <<'PY'
import json
import sys
model = sys.argv[1]
payload = sys.argv[2]
try:
    data = json.loads(payload) if payload else {}
except Exception:
    sys.exit(1)
models = [m.get("name", "") for m in data.get("models", []) if isinstance(m, dict)]
ok = any(name == model or name.endswith("/" + model) for name in models)
sys.exit(0 if ok else 1)
PY
then
  echo "✓ Model already available: ${MODEL}"
else
  echo "-> Pulling model: ${MODEL}"
  ollama pull "${MODEL}"
fi

echo "✓ Local setup complete."
echo "  In OAE Post Process:"
echo "  - Provider: Local Ollama (recommended)"
echo "  - Model: ${MODEL}"
echo "  - Prompt: Math Unicode + LaTeX"
