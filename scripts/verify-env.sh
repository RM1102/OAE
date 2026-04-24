#!/usr/bin/env bash
set -euo pipefail

fail() { echo "ERROR: $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

require_cmd git
require_cmd cmake
require_cmd rustc
require_cmd cargo
if command -v bun >/dev/null 2>&1; then
  PKG_MGR="bun $(bun --version)"
elif command -v npm >/dev/null 2>&1; then
  PKG_MGR="npm $(npm --version) (bun recommended; install from https://bun.sh)"
else
  fail "missing bun or npm (install Bun: https://bun.sh)"
fi

echo "=== Environment ==="
echo "git:       $(git --version)"
echo "cmake:     $(cmake --version | head -1)"
echo "rustc:     $(rustc --version)"
echo "cargo:     $(cargo --version)"
echo "js pkg:    $PKG_MGR"
if xcode-select -p >/dev/null 2>&1; then
  echo "xcode CLT: $(xcode-select -p)"
else
  fail "Xcode Command Line Tools not installed (run: xcode-select --install)"
fi

# Rust >= 1.77
rust_ver=$(rustc --version | awk '{print $2}')
IFS='.' read -r major minor _ <<<"$rust_ver"
[[ "${major:-0}" -gt 1 || "${major:-0}" -eq 1 && "${minor:-0}" -ge 77 ]] || fail "Rust >= 1.77 required, got $rust_ver"

# cmake >= 3.24
cm=$(cmake --version | head -1 | awk '{print $3}')
IFS='.' read -r cmaj cmin _ <<<"$cm"
[[ "${cmaj:-0}" -gt 3 || "${cmaj:-0}" -eq 3 && "${cmin:-0}" -ge 24 ]] || fail "cmake >= 3.24 required, got $cm"

if command -v bun >/dev/null 2>&1; then
  bu=$(bun --version)
  IFS='.' read -r bmaj bmin _ <<<"$bu"
  [[ "${bmaj:-0}" -gt 1 || "${bmaj:-0}" -eq 1 && "${bmin:-0}" -ge 1 ]] || fail "bun >= 1.1 required, got $bu"
fi

echo "OK: all required tools present."
