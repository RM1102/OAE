# OAE Shipping Validation Checklist

Run this checklist before handing OAE to professor.

## Clean-environment checks
- [ ] No pre-existing OAE models in `~/Library/Application Support/OAE/Models`
- [ ] Ollama not already running
- [ ] OAE not already installed

## Installer checks
- [ ] `install.command` copies app to `/Applications/OAE.app`
- [ ] `install.command` copies bundled model folder into app support models path
- [ ] OAE launches automatically after install

## First-run setup assistant checks
- [ ] Step 1 installs bundled Whisper model files successfully
- [ ] Step 2 detects/starts Ollama successfully
- [ ] Step 3 pulls required Ollama model successfully
- [ ] Setup status turns `done`

## Functional checks
- [ ] Dictate starts and transcribes speech
- [ ] Subtitle island opens and updates text
- [ ] Post Process run button becomes enabled after Ollama readiness
- [ ] Post Process completes output with local Ollama

## Permission checks
- [ ] Microphone prompt appears and can be granted
- [ ] Accessibility prompt path is visible from app

## Final handoff
- [ ] Zip package includes: `OAE.app`, `models/`, `install.command`, `README.md`
- [ ] Professor guide text is present and clear
