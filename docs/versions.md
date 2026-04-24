# Pinned versions

| Component | Version / ref |
|-----------|----------------|
| whisper.cpp (submodule) | tag `v1.8.4` — commit `fc674574ca27cac59a15e5b22a09b9d9ad62aafe` (see `vendor/whisper.cpp` after init) |
| transcribe-rs | `0.3.8` with `whisper-cpp` (CPU mode) |
| Tauri | `2.10.x` |
| Bun | ≥ 1.1 (or npm as fallback for `verify-env.sh` only) |

Refresh SHA after submodule update:

```bash
cd vendor/whisper.cpp && git rev-parse HEAD
```
