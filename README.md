# OAE — Native macOS Dictation (WhisperKit)

Local, offline speech-to-text for macOS, built on [WhisperKit](https://github.com/argmaxinc/WhisperKit). Whisper's audio encoder and text decoder run on the **Apple Neural Engine**; the mel spectrogram runs on the **GPU**. The CPU only handles audio I/O and UI — never model math.

Four modes in one app:

1. **Dictate** — continuous live streaming transcription with LocalAgreement-2 confirmation.
2. **Capture** — push-to-talk. Right Option starts, left Option stops and copies.
3. **File** — drop any audio/video file, live partials while decoding, canonical text at the end.
4. **Post Process** — local-first equation/text cleanup. Default provider is **Local Ollama** (no API key). Groq and other OpenAI-compatible providers are available as fallback. API keys live in your macOS Keychain.

**Live subtitles** can show as a **floating island** (draggable) or a **top notch strip** pinned under the menu bar on the main display (Settings, menu bar extra, or the main window toolbar).

## Requirements

- macOS 14 Sonoma or later (macOS 15 Sequoia recommended).
- Apple Silicon (M1 or newer). Intel Macs will run on pure GPU with reduced throughput.
- Xcode 16 or later (`xcode-select --install` at minimum for command-line tools, the full Xcode is required for building).
- [Homebrew](https://brew.sh) — used only by the bootstrap script to install `xcodegen` and `create-dmg`.

## Download (prebuilt)

Published **Release** builds (DMG + SHA256) are attached on GitHub when you push a version tag such as `v1.0.0`:

**[https://github.com/RM_1102/OAE/releases/latest](https://github.com/RM_1102/OAE/releases/latest)**

1. Download `OAE-v*.dmg` from the latest release **Assets**.
2. Open the DMG and drag **OAE** into **Applications**.
3. First launch: macOS may show *“OAE can’t be opened because it is from an unidentified developer”* (or similar). **Right-click** OAE in Finder → **Open** → confirm **Open** once, or clear quarantine after copying to Applications:

   ```bash
   xattr -dr com.apple.quarantine /Applications/OAE.app
   ```

4. Open OAE from Applications. The in-app assistant installs bundled Whisper files when needed and sets up **Ollama** + the default local model on first run (internet required once). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for where models come from.

Maintainers: see [docs/RELEASING.md](docs/RELEASING.md) for tag-driven CI and local packaging.

## Quick start

```bash
# Generate the Xcode project, render the AppIcon PNGs, and resolve Swift packages.
./scripts/bootstrap.sh

# Either open the project in Xcode…
open apps/oae-mac/OAE.xcodeproj

# …or build a Release .app from the command line.
./scripts/build-mac.sh              # produces build/mac/OAE.app
./scripts/build-mac.sh --install    # also installs to /Applications/OAE.app
./scripts/build-mac.sh --dmg        # also produces build/mac/OAE.dmg
./scripts/setup-local-postprocess.sh gemma2:2b  # install/start/pull local model
./scripts/demo-smoke.sh             # campus-demo smoke checklist
```

### Release path for OAE demos (recommended)

Use one consistent flow before sharing with campus laptops:

```bash
# 1) Build + install locally
./scripts/build-mac.sh --install

# 2) Prepare local post-processing model
./scripts/setup-local-postprocess.sh gemma2:2b

# 3) Smoke test /Applications build (Dictate + Capture + Post Process)
open /Applications/OAE.app

# 4) Create distributable DMG
./scripts/build-mac.sh --dmg
```

Before demoing on someone else's machine:
- Install the DMG app into `/Applications`.
- Launch once and wait for model download/load completion.
- Grant Microphone and Accessibility when prompted.
- Run a short Dictate test sentence.
- Run `./scripts/demo-smoke.sh` and complete the manual checklist.

## First run (read this before filing bugs)

1. **Run from `/Applications`, not `DerivedData`.** macOS's privacy database (TCC) keys grants on the binary's code-signing hash **and** path. Running the app from Xcode's scratch directory effectively registers a new app every rebuild, which is why you'll see repeat Microphone and Accessibility prompts. Either open the generated `.xcodeproj` in Xcode and run it, or use `./scripts/build-mac.sh --install` to put a signed build at `/Applications/OAE.app` and launch from there.
2. **Wait for the model download.** The banner under the title bar shows "Downloading … XX%". Start buttons are disabled until it finishes. First download is ~626 MB; subsequent launches are instant.
3. **Allow Microphone** the first time, then **Accessibility** (only needed for push-to-talk). The Capture tab has a "Grant Accessibility" button if the pane doesn't open automatically.
4. If anything gets stuck, run `./scripts/reset-tcc.sh` — it wipes OAE's privacy grants so macOS will ask again cleanly.

### Making permission grants persist across rebuilds

If you're iterating on the code, the fastest way to stop the re-prompting noise is to sign with a stable identity:

```bash
# 1. Create a self-signed code-signing certificate once (GUI):
#    Keychain Access → Certificate Assistant → Create a Certificate…
#       Name: OAE Dev
#       Identity type: Self Signed Root
#       Certificate type: Code Signing
#    Accept the defaults. This adds "OAE Dev" to your login keychain.

# 2. Build + install with that identity.
OAE_SIGN_IDENTITY="OAE Dev" ./scripts/build-mac.sh --install

# 3. Launch /Applications/OAE.app, grant Microphone + Accessibility once.
#    Future `OAE_SIGN_IDENTITY="OAE Dev" ./scripts/build-mac.sh --install`
#    runs reuse those grants — TCC sees the same code requirement.
```

Without a stable identity the app still runs (ad-hoc signed), but macOS will re-prompt after every build.

## Permissions

macOS will prompt for these the first time each is needed:

| Permission | Where | Why |
|------------|-------|-----|
| **Microphone** | System Settings → Privacy → Microphone | Dictate & Capture modes |
| **Accessibility** | System Settings → Privacy → Accessibility | Distinguishing left vs right Option key for push-to-talk, and optional auto-paste (`Cmd+V`) via `CGEventTap` |

The app runs outside the App Sandbox (because `CGEventTap` is incompatible with sandboxing) but **with Hardened Runtime enabled**, so it can still be notarized for public distribution.

## Push-to-talk

- **Right Option** — start recording.
- **Left Option** — stop, transcribe the full buffer with WhisperKit, copy to clipboard, optionally auto-paste into the frontmost app.
- Modifier-side discrimination uses `kVK_Option` (`0x3A`) vs `kVK_RightOption` (`0x3D`), which macOS exposes only through a `CGEventTap`. That's why Accessibility permission is required.

## Post-processing (free LLMs)

### Local-first default (recommended)

OAE now defaults to a local model backend so demos work without internet/API keys.

```bash
# install Ollama
brew install ollama

# run server
ollama serve

# pull a small fast model (default in OAE)
ollama pull gemma2:2b

# optional better math quality if RAM allows
ollama pull gemma2:9b
```

Then in OAE Post Process:
- Provider: `Local Ollama (recommended)`
- Model: `gemma2:2b` (or `gemma2:9b`)
- Use the built-in prompt: `Math Unicode + LaTeX`

It returns Unicode math for display plus LaTeX copy (`Copy LaTeX` button).

### Groq fallback (when local model is unavailable)

1. Open [Groq API Keys](https://console.groq.com/keys) and create a key.
2. Copy the key immediately (Groq shows full secret once).
3. In OAE Post Process:
   - Provider: `Groq`
   - Paste key in `API Key`
   - Click `Save Key`
   - Click `Test Provider`
4. If test passes, run your prompt.

Built-in presets, all OpenAI Chat Completions compatible:

| Provider | Free tier | Privacy | Sign up |
|----------|-----------|---------|---------|
| Local Ollama | Local machine throughput | Local | [ollama.com](https://ollama.com) |
| Groq | 30 RPM / 30K TPM | No training | [console.groq.com](https://console.groq.com) |
| Cerebras | ~30 RPM | No training | [cloud.cerebras.ai](https://cloud.cerebras.ai) |
| GitHub Models | ~15 RPM | No training | [github.com/settings/tokens](https://github.com/settings/tokens) (PAT with `models:read`) |
| NVIDIA NIM | ~40 RPM | No training | [build.nvidia.com](https://build.nvidia.com) |
| OpenRouter | 20 RPM / 50 RPD on `:free` models | May train | [openrouter.ai](https://openrouter.ai) |
| Google Gemini | ~10 RPM / 250 RPD | May train | [aistudio.google.com](https://aistudio.google.com) |
| Mistral | ~1 B tokens/month | May train | [console.mistral.ai](https://console.mistral.ai) |
| Custom | Your call | Local | Any OpenAI-compatible base URL (Ollama, LM Studio, vLLM, FreeLLM/RelayFreeLLM gateways) |

Default `Option+Shift+Space` runs the selected prompt on the last finalized transcript.

## Project layout

```
apps/
  oae-mac/                 # This app (SwiftUI + WhisperKit)
    OAE/                   # Sources
    project.yml            # XcodeGen spec (source of truth)
  _legacy-tauri/           # Archived Tauri/Rust scaffold (not built)
    oae-stt/               # Legacy “OAE STT” Tauri prototype
scripts/
  bootstrap.sh             # xcodegen install + project generation
  build-mac.sh             # xcodebuild + optional create-dmg
vendor/
  whisperkit/              # reference: argmaxinc/WhisperKit
  handy/                   # reference: cjpais/handy
  metawhisp/               # reference: metawhisp (WhisperKit menu-bar app)
  whisper-stream-server/   # reference: streaming params
  whisper_streaming/       # reference: LocalAgreement-2 algorithm
  whisper.cpp/             # archived — not built
```

## Configuration

All user settings live in `UserDefaults` except API keys, which are stored in the macOS **Keychain** (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). You can change:

- Model (picker in **Settings → Models**)
- Language (`Auto` or any Whisper-supported locale)
- Auto-copy / auto-paste on Capture finalize
- LocalAgreement confirmation segments (default 2)
- Post-process provider, model, and prompt

## Verifying that inference is not on the CPU

1. Open Activity Monitor → **Energy** tab while using the app.
2. With transcription running you should see the app's **Neural Engine** column light up and GPU usage rise; **CPU** stays in low single digits.
3. The status pill in the app's toolbar reads `ANE+GPU` (green). On Intel Macs, or if the ANE is unavailable, it reads `GPU` (amber) and OAE runs on pure GPU. `CPU` (red) is refused: the app will not start in that state.

## Troubleshooting

- **Microphone prompt keeps returning every launch.** You're running from Xcode's `DerivedData` and/or with ad-hoc signing — each rebuild is a fresh app to TCC. Install to `/Applications` via `./scripts/build-mac.sh --install`, ideally with a stable `OAE_SIGN_IDENTITY` (see "First run" above).
- **"WhisperKit model did not load"** in the title-bar banner. Click **Retry**. If it fails again, delete `~/Library/Application Support/OAE/Models/` and relaunch — OAE will redownload cleanly. The engine now probes both the HuggingFace snapshot layout (`models/argmaxinc/whisperkit-coreml/<variant>/`) and the legacy flat path.
- **Accessibility prompt doesn't appear.** Open the **Capture** tab → click **Grant Accessibility**. macOS requires an explicit user action to surface the prompt when we have not prompted automatically (we don't — automatic prompts without a stable signature produce confusing re-prompts).
- **Privacy grants feel stuck.** Run `./scripts/reset-tcc.sh` to clear Microphone, Accessibility, and AppleEvents grants for `computer.oae.OAE`, then relaunch.
- **Model download stalls.** Delete `~/Library/Application Support/OAE/Models/` and try again. WhisperKit resumes from the latest complete snapshot on next run.
- **`xcodegen` not found.** `./scripts/bootstrap.sh` will install it via Homebrew. Or install manually: `brew install xcodegen`.
- **Build fails on `prefillCompute: .cpuOnly`.** This is correct — see [WhisperKit's Performance Optimization guide](https://mintlify.com/argmaxinc/WhisperKit/advanced/performance-optimization). Prefill is a one-shot KV-cache initialization that runs in microseconds per utterance; the expensive encoder and decoder remain on ANE.
- **Regenerate the app icon** after changing `scripts/generate-icon.swift`: `swift scripts/generate-icon.swift`.

## License

Source code in `apps/oae-mac/` is released under the MIT license. `vendor/*` entries retain their upstream licenses.
