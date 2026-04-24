# Releasing OAE (maintainers)

## What “it just works” means

Anyone should be able to: **download the DMG from GitHub → open it → drag OAE to Applications → double-click OAE** with **no Terminal commands** and **no clearing quarantine**.

Apple only allows that for apps that are **Developer ID signed** and **notarized**. Those credentials **cannot** live inside the DMG; they must be available on the machine that builds the app. For GitHub Actions, that means **one-time** setup: add the secrets below to this repository. The workflow `scripts/ci_require_github_release_secrets.sh` **refuses to run a release** until every required secret is set, so you never publish a DMG that fails Gatekeeper for normal users.

## One-time: GitHub Actions secrets

Create these in **GitHub → Settings → Secrets and variables → Actions**:

| Secret | Purpose |
|--------|---------|
| `MACOS_CERTIFICATE_P12` | Base64-encoded `.p12` exported from Keychain (**Developer ID Application** certificate + private key). |
| `MACOS_CERTIFICATE_PASSWORD` | Password you set when exporting the `.p12`. |
| `APP_STORE_CONNECT_API_KEY_P8` | Contents of the App Store Connect API **private key** (`.p8` file), or base64 of that file (see variable below). |
| `APP_STORE_CONNECT_KEY_ID` | Key ID next to the key in [App Store Connect](https://appstoreconnect.apple.com/) → Users and Access → Keys. |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID on the same Keys page. |

Optional repository **Variables** (Settings → Secrets and variables → Actions → Variables):

| Variable | Purpose |
|----------|---------|
| `APP_STORE_CONNECT_API_KEY_P8_IS_B64` | Set to `1` if the `APP_STORE_CONNECT_API_KEY_P8` secret stores base64-encoded `.p8` content instead of raw PEM. |
| `APP_STORE_CONNECT_TEAM_ID` | Also available as a **secret** with the same name in the workflow; use if `notarytool` reports a team mismatch. |

**Exporting the Developer ID .p12**

1. On a Mac that has the **Developer ID Application** cert in Keychain Access, export **both** the certificate and private key as `.p12`.
2. `base64 -i Certificate.p12 | pbcopy` and paste into the `MACOS_CERTIFICATE_P12` secret.

**App Store Connect API key**

1. Users and Access → Keys → generate a key with **Developer** access (enough for notarization).
2. Download the `.p8` once; paste its full PEM text into `APP_STORE_CONNECT_API_KEY_P8`, or base64 the file and set `APP_STORE_CONNECT_API_KEY_P8_IS_B64=1`.

## GitHub Releases (automated)

1. Ensure `main` is green and bump the app marketing version in Xcode if needed.
2. Add all required secrets (above). Until you do, pushing a tag will **fail** on the “Require distribution secrets” step with a clear error.
3. Create and push an annotated tag:

   ```bash
   git tag -a v1.2.3 -m "v1.2.3"
   git push origin v1.2.3
   ```

4. The workflow `.github/workflows/release.yml` runs on **`macos-15`** (Xcode 16+), downloads the default Whisper CoreML bundle (cached), builds **Release**, **signs** with your Developer ID, **notarizes and staples** the DMG, then creates the GitHub Release.
5. Assets:
   - `OAE-<tag>.dmg` — drag-and-drop installer (Whisper under `Contents/Resources/BundledModels`).
   - `OAE-<tag>.dmg.sha256` — checksum.

If the workflow fails on the Hugging Face download step, confirm outbound network access.

## Troubleshooting

If a user still sees **“damaged”** on an **old** release created before secrets existed, they must use a **new** tag built after secrets were configured, or (only for those legacy builds) remove quarantine after install: `xattr -dr com.apple.quarantine /Applications/OAE.app`.

## Local DMG (same as CI)

From the repo root, after you have the default model locally:

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

For a distribution build from your machine, set `OAE_CODESIGN_IDENTITY` to your Developer ID string, then run `scripts/notarize_dmg.sh` on the DMG (see script header for env vars).

## Public download URL

`https://github.com/RM1102/OAE/releases/latest`

(Adjust org/repo if yours differs.)
