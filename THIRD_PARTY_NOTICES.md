# Third-party components

OAE links to or redistributes material from these projects (see each package for its license):

| Component | Use in OAE | Upstream |
|-------------|------------|----------|
| **WhisperKit** | On-device speech recognition (CoreML) | [argmaxinc/WhisperKit](https://github.com/argmaxinc/WhisperKit) |
| **whisperkit-coreml** (Hugging Face) | Default transcription model weights | [argmaxinc/whisperkit-coreml](https://huggingface.co/argmaxinc/whisperkit-coreml) |
| **KeyboardShortcuts** | Global shortcuts UI | [sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) |
| **Ollama** (optional, not bundled) | Local LLM for post-process; user installs via OAE setup or [ollama.com](https://ollama.com) | [ollama/ollama](https://github.com/ollama/ollama) |

The default post-process model name (e.g. `gemma2:2b`) is pulled by the user’s Ollama installation; OAE does not ship Gemma weights inside the app.
