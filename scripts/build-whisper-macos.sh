#!/usr/bin/env bash
# Optional: build upstream whisper-cli from vendor/whisper.cpp (not used by OAE STT at runtime;
# transcribe-rs links whisper.cpp in-process). Useful for manual experiments / benchmarking.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WC="$ROOT/vendor/whisper.cpp"
[[ -d "$WC" ]] || { echo "Run: git submodule update --init"; exit 1; }
export CMAKE_POLICY_VERSION_MINIMUM="${CMAKE_POLICY_VERSION_MINIMUM:-3.5}"
cmake -S "$WC" -B "$WC/build" -DCMAKE_BUILD_TYPE=Release ${WHISPER_COREML:+ -DWHISPER_COREML=1}
cmake --build "$WC/build" -j --config Release
echo "Built: $WC/build/bin/whisper-cli"
