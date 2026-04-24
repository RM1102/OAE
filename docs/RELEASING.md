# Releasing OAE (maintainers)

## GitHub Releases (automated)

1. Ensure `main` is green and the app version is bumped in Xcode (or in `Info.plist` / target settings) if you want the DMG to reflect a new marketing version.
2. Create and push an annotated tag:

   ```bash
   git tag -a v1.2.3 -m "v1.2.3"
   git push origin v1.2.3
   ```

3. The workflow `.github/workflows/release.yml` runs on **`macos-15`** (Xcode 16+ for `objectVersion` 77), downloads the default Whisper CoreML bundle from Hugging Face (cached between runs), builds **Release**, runs `scripts/build_dragdrop_dmg.sh`, optionally **notarizes** the DMG, and creates a GitHub Release named after the tag.
4. Assets attached to the release:
   - `OAE-<tag>.dmg` — drag-and-drop installer (Whisper bundle embedded under `Contents/Resources/BundledModels`).
   - `OAE-<tag>.dmg.sha256` — checksum for verification.

If the workflow fails on the first download step, confirm outbound network access and that `huggingface_hub` can reach Hugging Face.

## Gatekeeper: “damaged” or blocked downloads

Browsers tag downloads with **quarantine**. An ad-hoc–signed app (the default when no Apple certificate is configured in CI) **fails Gatekeeper** and macOS often says the app is **“damaged and can’t be opened”** — that usually means **signature / notarization failed**, not a corrupt file.

**For public releases**, configure repository **Secrets** (below) so CI uses **Developer ID Application** signing and **Apple notarization**. Then the DMG opens normally after download.

**Without those secrets**, tell testers to remove quarantine after copying to `/Applications`:

```bash
xattr -dr com.apple.quarantine /Applications/OAE.app
```

Or **Finder → right-click OAE → Open** once.

## CI secrets (Developer ID + notarization)

Create these in **GitHub → Settings → Secrets and variables → Actions** for the repository:

| Secret | Purpose |
|--------|---------|
| `MACOS_CERTIFICATE_P12` | Base64-encoded `.p12` exported from Keychain (**Developer ID Application** certificate + private key). |
| `MACOS_CERTIFICATE_PASSWORD` | Password you set when exporting the `.p12`. |
| `APP_STORE_CONNECT_API_KEY_P8` | Contents of the App Store Connect API **private key** (`.p8` file), or base64 of that file (see below). |
| `APP_STORE_CONNECT_KEY_ID` | Key ID shown next to the key in [App Store Connect](https://appstoreconnect.apple.com/) → Users and Access → Keys. |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID on the same Keys page. |
| `APP_STORE_CONNECT_TEAM_ID` | (Optional) Your 10-character Apple Team ID; include if `notarytool` reports a team mismatch. |

**Exporting the Developer ID .p12**

1. On a Mac that has the **Developer ID Application** cert in Keychain Access, export **both** the certificate and private key as `.p12`.
2. `base64 -i Certificate.p12 | pbcopy` and paste into the `MACOS_CERTIFICATE_P12` secret.

**App Store Connect API key**

1. Users and Access → Keys → generate a key with **Developer** access (enough for notarization).
2. Download the `.p8` once; paste its full PEM text into `APP_STORE_CONNECT_API_KEY_P8`, **or** base64-encode the file and set repository variable `APP_STORE_CONNECT_API_KEY_P8_IS_B64` to `1` (some teams prefer a single-line secret).

If `MACOS_CERTIFICATE_P12` is set, **notarization becomes mandatory** for the workflow: you must also set the three `APP_STORE_CONNECT_*` secrets, or the **Notarize DMG** step fails on purpose so you do not ship a signed-but-unnotarized DMG by mistake.

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

For a **distribution** build from your machine, set `OAE_CODESIGN_IDENTITY` to your Developer ID string, then notarize:

```bash
export OAE_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
# … same env as above …
bash scripts/build_dragdrop_dmg.sh
export APP_STORE_CONNECT_API_KEY_P8="$(cat AuthKey_XXX.p8)"
export APP_STORE_CONNECT_KEY_ID="…"
export APP_STORE_CONNECT_ISSUER_ID="…"
bash scripts/notarize_dmg.sh artifacts/OAE-local-test.dmg
```

## Public download URL

After the first successful release, share:

`https://github.com/RM1102/OAE/releases/latest`

(Replace `RM1102` or `OAE` if your GitHub user or repository name differs.)
