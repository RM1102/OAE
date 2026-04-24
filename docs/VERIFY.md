# Verification checklist

- [x] `bash scripts/verify-env.sh` exits 0 (with npm fallback warning if Bun is missing).
- [x] `git submodule status` includes `vendor/whisper.cpp` pinned to `v1.8.4` commit (`fc674574...`).
- [x] Frontend build succeeds: `cd apps/_legacy-tauri/oae-stt && npm run build`.
- [x] Backend typecheck succeeds: `cd apps/_legacy-tauri/oae-stt/src-tauri && CMAKE_POLICY_VERSION_MINIMUM=3.5 cargo check`.
- [x] macOS bundle build succeeds (in this environment) with:
  ```bash
  cd apps/_legacy-tauri/oae-stt
  CXXFLAGS="-D_LIBCPP_DISABLE_AVAILABILITY" \
  CMAKE_CXX_FLAGS="-D_LIBCPP_DISABLE_AVAILABILITY" \
  CMAKE_POLICY_VERSION_MINIMUM=3.5 \
  npm run tauri build
  ```
  Output includes:
  - `apps/_legacy-tauri/oae-stt/src-tauri/target/release/bundle/macos/OAE STT.app`
  - `apps/_legacy-tauri/oae-stt/src-tauri/target/release/bundle/dmg/OAE STT_0.1.0_aarch64.dmg`

## Runtime smoke notes

- Model discovery scans Handy first (`~/Library/Application Support/com.pais.handy/models`) and falls back to OAE's own dir.
- File transcription path supports decode of common formats via Symphonia and streams segments/events.
- Global shortcut and tray wiring are present.
- Live mic command path is wired but intentionally conservative in this iteration to keep compilation stable across this toolchain.
