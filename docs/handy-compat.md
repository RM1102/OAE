# Handy compatibility

Patterns mirrored from [Handy](https://github.com/cjpais/handy):

- **Inference:** `transcribe-rs` with `whisper-cpp` + `whisper-metal` on macOS (same as Handy’s `Cargo.toml` target deps).
- **Managers:** `model_registry`, `audio`, `transcription` — Tauri state + command/event flow.
- **Models:** Read-only scan of `~/Library/Application Support/com.pais.handy/models/`; prefer Handy paths when the same logical model exists in both Handy and OAE dirs.
- **VAD:** Silero `silero_vad_v4.onnx` — reuse file from Handy’s models dir if present; else bundle under `src-tauri/resources/models/`.
- **Not adopted:** Handy’s `[patch.crates-io]` Tauri fork (panel overlay).
