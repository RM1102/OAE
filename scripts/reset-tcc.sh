#!/usr/bin/env bash
# Wipes OAE's cached TCC (privacy) grants so macOS re-prompts for Microphone /
# Accessibility / Automation after bundle-id or signing changes.

set -euo pipefail

BUNDLE_ID="computer.oae.OAE"

echo "Resetting TCC for $BUNDLE_ID …"
sudo tccutil reset Microphone "$BUNDLE_ID" 2>/dev/null || true
sudo tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
sudo tccutil reset AppleEvents "$BUNDLE_ID" 2>/dev/null || true

echo "✓ Done. Relaunch OAE to re-grant permissions."
