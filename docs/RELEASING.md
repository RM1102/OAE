# Releasing OAE (maintainers)

## GitHub Releases (automated)

1. Ensure `main` is green and the app version is bumped in Xcode (or in `Info.plist` / target settings) if you want the DMG to reflect a new marketing version.
2. Create and push an annotated tag:

   ```bash
   git tag -a v1.2.3 -m "v1.2.3"
   git push origin v1.2.3
   ```

3. The workflow `.github/workflows/release.yml` runs on `macos-14`, downloads the default Whisper CoreML bundle from Hugging Face (cached between runs), builds **Release**, runs `scripts/build_dragdrop_dmg.sh`, and creates a GitHub Release named after the tag.
4. Assets attached to the release:
   - `OAE-<tag>.dmg` — drag-and-drop installer (Whisper bundle embedded under `Contents/Resources/BundledModels`).
   - `OAE-<tag>.dmg.sha256` — checksum for verification.

If the workflow fails on the first download step, confirm outbound network access and that `huggingface_hub` can reach Hugging Face.

## Local DMG (same as CI)

From the repo root, after you have the default model locally (via OAE Settings → Models, or via download script):

```bash
pip3 install -r scripts/requirements-dmg-ci.txt
python3 scripts/download_default_whisper_model.py .ci-whisper-model

OAE_BUILD_CONFIGURATION=Release \
OAE_DERIVED_DATA_PATH="$PWD/.derivedData" \
OAE_MODEL_SOURCE_DIR="$PWD/.ci-whisper-model" \
OAE_DMG_OUT_DIR="$PWD/artifacts" \
OAE_DMG_BASENAME=OAE-local-test \
bash scripts/build_dragdrop_dmg.sh
```

## Public download URL

After the first successful release, share:

`https://github.com/RM1102/OAE/releases/latest`

(Replace `RM1102` or `OAE` if your GitHub user or repository name differs.)
