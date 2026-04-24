#!/usr/bin/env bash
# Fail the Release workflow unless every secret needed for a DMG that passes
# Gatekeeper on a normal double-click (no Terminal, no xattr) is configured.
#
# Invoked from .github/workflows/release.yml with secrets passed as env vars.
set -euo pipefail

missing=()
[[ -z "${MACOS_CERTIFICATE_P12:-}" ]] && missing+=(MACOS_CERTIFICATE_P12)
[[ -z "${MACOS_CERTIFICATE_PASSWORD:-}" ]] && missing+=(MACOS_CERTIFICATE_PASSWORD)
[[ -z "${APP_STORE_CONNECT_API_KEY_P8:-}" ]] && missing+=(APP_STORE_CONNECT_API_KEY_P8)
[[ -z "${APP_STORE_CONNECT_KEY_ID:-}" ]] && missing+=(APP_STORE_CONNECT_KEY_ID)
[[ -z "${APP_STORE_CONNECT_ISSUER_ID:-}" ]] && missing+=(APP_STORE_CONNECT_ISSUER_ID)

if ((${#missing[@]} > 0)); then
  echo "::error::OAE GitHub Release is configured to only publish DMGs that open like any normal Mac app (double-click → drag to Applications → launch). That requires Apple Developer ID signing plus notarization. Add the missing Actions secrets, then push a new version tag."
  echo ""
  echo "Missing secrets: ${missing[*]}"
  echo ""
  echo "See docs/RELEASING.md in this repository for exact steps (export Developer ID .p12, App Store Connect API key, paste into GitHub → Settings → Secrets and variables → Actions)."
  exit 1
fi

echo "[ci] All required distribution secrets are set."
