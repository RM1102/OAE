#!/usr/bin/env python3
"""Download the default WhisperKit CoreML variant for DMG packaging (CI or local).

Requires: pip install huggingface_hub
Usage: python3 scripts/download_default_whisper_model.py /path/to/output_dir

The output directory will contain a single folder named like
`openai_whisper-large-v3-v20240930_626MB`, suitable as OAE_MODEL_SOURCE_DIR.
"""
from __future__ import annotations

import os
import sys


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: download_default_whisper_model.py OUTPUT_DIR", file=sys.stderr)
        return 2
    dest = sys.argv[1]
    variant = os.environ.get(
        "OAE_WHISPER_VARIANT", "openai_whisper-large-v3-v20240930_626MB"
    )
    os.makedirs(dest, exist_ok=True)
    try:
        from huggingface_hub import snapshot_download
    except ImportError:
        print("Install huggingface_hub: pip3 install huggingface_hub", file=sys.stderr)
        return 1

    patterns = [f"{variant}/**", f"*/{variant}/**"]
    print(f"[download] argmaxinc/whisperkit-coreml → {dest} (patterns={patterns})")
    snapshot_download(
        repo_id="argmaxinc/whisperkit-coreml",
        local_dir=dest,
        allow_patterns=patterns,
    )
    marker = os.path.join(dest, variant)
    if not os.path.isdir(marker):
        print(f"[download] expected folder missing: {marker}", file=sys.stderr)
        return 1
    print(f"[download] OK: {marker}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
