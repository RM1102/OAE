#!/usr/bin/env bash
# Builds a Release OAE.app and optionally installs / packages it.
# Usage:
#   scripts/build-mac.sh
#   scripts/build-mac.sh --install
#   scripts/build-mac.sh --dmg
#   OAE_SIGN_IDENTITY="OAE Dev" scripts/build-mac.sh --install
#   (ODI_SIGN_IDENTITY is still accepted as a fallback alias.)
set -euo pipefail

cd "$(dirname "$0")/.."

APP_DIR="apps/oae-mac"
BUILD_DIR="build/mac"
PRODUCT_NAME="OAE"
BUNDLE_ID="computer.oae.OAE"
SIGN_IDENTITY="${OAE_SIGN_IDENTITY:-${ODI_SIGN_IDENTITY:--}}"
APP_OUT="$BUILD_DIR/$PRODUCT_NAME.app"
INSTALL_DEST="/Applications/$PRODUCT_NAME.app"
ENTITLEMENTS_PATH="$APP_DIR/OAE/Resources/OAE.entitlements"

DO_INSTALL=0
DO_DMG=0
for arg in "$@"; do
    case "$arg" in
        --install) DO_INSTALL=1 ;;
        --dmg) DO_DMG=1 ;;
        *) echo "Unknown flag: $arg" >&2; exit 2 ;;
    esac
done

for cmd in xcodebuild codesign rsync defaults; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Required command not found: $cmd" >&2
        exit 1
    fi
done

mkdir -p "$BUILD_DIR"
if [ ! -d "$APP_DIR/OAE.xcodeproj" ]; then
    echo "-> No OAE.xcodeproj yet. Running bootstrap..."
    ./scripts/bootstrap.sh
fi

echo "-> Building ${PRODUCT_NAME} (Release, sign=${SIGN_IDENTITY})..."
xcodebuild \
    -project "$APP_DIR/OAE.xcodeproj" \
    -scheme "$PRODUCT_NAME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES \
    build

APP_SRC="$BUILD_DIR/DerivedData/Build/Products/Release/$PRODUCT_NAME.app"
if [ ! -d "$APP_SRC" ]; then
    echo "Could not locate built app at $APP_SRC" >&2
    exit 1
fi

rm -rf "$APP_OUT"
cp -R "$APP_SRC" "$APP_OUT"
echo "OK App at ${APP_OUT}"

if [ "$DO_INSTALL" -eq 1 ]; then
    if [ ! -f "$ENTITLEMENTS_PATH" ]; then
        echo "Entitlements file not found: $ENTITLEMENTS_PATH" >&2
        exit 1
    fi

    echo "-> Installing to ${INSTALL_DEST}..."
    if [ -d "${INSTALL_DEST}" ]; then
        EXISTING_BID="$(defaults read "${INSTALL_DEST}/Contents/Info" CFBundleIdentifier 2>/dev/null || true)"
        if [ -n "$EXISTING_BID" ] && [ "$EXISTING_BID" != "$BUNDLE_ID" ]; then
            echo "Refusing to overwrite unrelated /Applications/$PRODUCT_NAME.app (bundle id=$EXISTING_BID)" >&2
            exit 1
        fi
        rm -rf "${INSTALL_DEST}"
    fi

    rsync -a --delete "${APP_OUT}/" "${INSTALL_DEST}/"

    echo "-> Re-signing installed app with identity: ${SIGN_IDENTITY}"
    codesign --force --deep --options runtime \
        --entitlements "$ENTITLEMENTS_PATH" \
        --sign "$SIGN_IDENTITY" \
        "${INSTALL_DEST}"

    echo "-> Verifying installed signature..."
    codesign --verify --deep --strict --verbose=2 "${INSTALL_DEST}"

    if [ ! -d "${INSTALL_DEST}" ]; then
        echo "Install failed: ${INSTALL_DEST} does not exist after install." >&2
        exit 1
    fi
    echo "OK Installed at ${INSTALL_DEST}"
    echo "  Grant Microphone + Accessibility once in System Settings > Privacy & Security."
    echo "  Use OAE_SIGN_IDENTITY=\"OAE Dev\" (or legacy ODI_SIGN_IDENTITY) for persistent TCC grants across rebuilds."
    echo "  If prompts keep returning, run: scripts/reset-tcc.sh"
fi

if [ "$DO_DMG" -eq 1 ]; then
    if ! command -v create-dmg >/dev/null 2>&1; then
        if command -v brew >/dev/null 2>&1; then
            echo "-> Installing create-dmg..."
            brew install create-dmg
        else
            echo "create-dmg not installed. brew install create-dmg" >&2
            exit 1
        fi
    fi
    DMG_OUT="$BUILD_DIR/$PRODUCT_NAME.dmg"
    rm -f "$DMG_OUT"
    create-dmg \
        --volname "$PRODUCT_NAME" \
        --window-size 520 340 \
        --icon-size 96 \
        --icon "$PRODUCT_NAME.app" 140 160 \
        --app-drop-link 380 160 \
        "$DMG_OUT" \
        "$APP_OUT"
    echo "OK DMG at ${DMG_OUT}"
fi
