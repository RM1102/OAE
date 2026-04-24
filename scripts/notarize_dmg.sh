#!/usr/bin/env bash
# Notarize and staple a DMG using App Store Connect API key (notarytool).
#
# Usage:
#   scripts/notarize_dmg.sh /path/to/OAE-v1.dmg
#
# When OAE_REQUIRE_NOTARIZE=1 (set by CI after importing a Developer ID certificate),
# missing credentials cause exit 1. Otherwise missing credentials skip (exit 0).
#
# Required env for notarization:
#   APP_STORE_CONNECT_API_KEY_P8   Contents of the .p8 private key (PEM), or base64 if APP_STORE_CONNECT_API_KEY_P8_IS_B64=1
#   APP_STORE_CONNECT_KEY_ID       Key ID
#   APP_STORE_CONNECT_ISSUER_ID    Issuer UUID (App Store Connect → Users and Access → Keys)
#
# Optional:
#   APP_STORE_CONNECT_TEAM_ID              Apple Team ID
#   APP_STORE_CONNECT_API_KEY_P8_IS_B64    Set to 1 if the secret stores base64-encoded .p8
set -euo pipefail

DMG="${1:?usage: $0 /path/to.dmg}"

have_creds() {
  [[ -n "${APP_STORE_CONNECT_API_KEY_P8:-}" && -n "${APP_STORE_CONNECT_KEY_ID:-}" && -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]
}

if [[ "${OAE_REQUIRE_NOTARIZE:-0}" == "1" ]]; then
  if ! have_creds; then
    echo "[notarize] OAE_REQUIRE_NOTARIZE=1 but App Store Connect API key env is incomplete." >&2
    echo "[notarize] Set APP_STORE_CONNECT_API_KEY_P8, APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID (see docs/RELEASING.md)." >&2
    exit 1
  fi
elif ! have_creds; then
  echo "[notarize] Skipping notarization (no API key configured and OAE_REQUIRE_NOTARIZE is not 1)."
  exit 0
fi

KEYFILE="$(mktemp -t oae-asc-key)"
trap 'rm -f "$KEYFILE"' EXIT
chmod 600 "$KEYFILE"

if [[ "${APP_STORE_CONNECT_API_KEY_P8_IS_B64:-0}" == "1" ]]; then
  echo "$APP_STORE_CONNECT_API_KEY_P8" | base64 --decode >"$KEYFILE"
else
  printf '%s\n' "$APP_STORE_CONNECT_API_KEY_P8" >"$KEYFILE"
fi

TEAM_ARGS=()
if [[ -n "${APP_STORE_CONNECT_TEAM_ID:-}" ]]; then
  TEAM_ARGS=(--team-id "$APP_STORE_CONNECT_TEAM_ID")
fi

echo "[notarize] Submitting $(basename "$DMG")…"
xcrun notarytool submit "$DMG" \
  --key "$KEYFILE" \
  --key-id "$APP_STORE_CONNECT_KEY_ID" \
  --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
  "${TEAM_ARGS[@]}" \
  --wait

echo "[notarize] Stapling ticket…"
xcrun stapler staple "$DMG"
echo "[notarize] Done."
