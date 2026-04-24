#!/usr/bin/env bash
# Import a Developer ID .p12 into a temporary keychain for GitHub Actions.
# When MACOS_CERTIFICATE_P12 is unset or empty, writes empty OAE_CODESIGN_IDENTITY to GITHUB_ENV and exits 0.
#
# Required env when using a certificate:
#   MACOS_CERTIFICATE_P12       Base64-encoded PKCS#12 (Developer ID Application)
#   MACOS_CERTIFICATE_PASSWORD  Password for the .p12
#
# Optional:
#   GITHUB_ENV                  If set, appends OAE_CODESIGN_IDENTITY=... for later steps
set -euo pipefail

append_env() {
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    printf '%s\n' "$1" >>"$GITHUB_ENV"
  fi
}

# GitHub Actions: multiline-safe value for identities with spaces/parentheses.
append_multiline_env() {
  local key="$1" val="$2"
  if [[ -z "${GITHUB_ENV:-}" ]]; then
    return
  fi
  {
    echo "${key}<<__OAE_GHENV__"
    printf '%s\n' "$val"
    echo "__OAE_GHENV__"
  } >>"$GITHUB_ENV"
}

if [[ -z "${MACOS_CERTIFICATE_P12:-}" ]]; then
  echo "[ci-sign] No MACOS_CERTIFICATE_P12 — DMG will be ad-hoc signed (Gatekeeper may block downloads)."
  append_env "OAE_CODESIGN_IDENTITY="
  append_env "OAE_REQUIRE_NOTARIZE=0"
  exit 0
fi

if [[ -z "${MACOS_CERTIFICATE_PASSWORD:-}" ]]; then
  echo "[ci-sign] MACOS_CERTIFICATE_P12 is set but MACOS_CERTIFICATE_PASSWORD is empty." >&2
  exit 1
fi

KEYCHAIN_PATH="${RUNNER_TEMP:-/tmp}/oae-build.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -base64 32)"

security delete-keychain "$KEYCHAIN_PATH" 2>/dev/null || true
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

CERT_PATH="${RUNNER_TEMP:-/tmp}/oae-cert.p12"
echo "$MACOS_CERTIFICATE_P12" | base64 --decode >"$CERT_PATH"

security import "$CERT_PATH" \
  -k "$KEYCHAIN_PATH" \
  -P "$MACOS_CERTIFICATE_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security \
  -T /usr/bin/productbuild

security list-keychains -d user -s "$KEYCHAIN_PATH"
security default-keychain -s "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

rm -f "$CERT_PATH"

IDENTITY="$(
  security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application/ { print $2; exit }'
)"
if [[ -z "$IDENTITY" ]]; then
  echo "[ci-sign] No 'Developer ID Application' identity found after import." >&2
  security find-identity -v -p codesigning >&2 || true
  exit 1
fi

echo "[ci-sign] Using identity: $IDENTITY"
append_multiline_env OAE_CODESIGN_IDENTITY "$IDENTITY"
append_env "OAE_REQUIRE_NOTARIZE=1"
