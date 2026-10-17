#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# One-command macOS build: installs Qt for iOS + the matching desktop Qt
# (cross-compile host tools) if needed, builds Lua/OpenSSL/libgit2, compiles
# the app, and writes build-ios/ipa/*.ipa.
#
#   bash scripts/build_all_mac.sh
#
# Requires: macOS + Xcode (including command line tools), Homebrew, Python 3.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QT_VERSION="${QT_VERSION:-6.8.3}"
QT_ROOT="${QT_ROOT:-$HOME/Qt/$QT_VERSION/ios}"
QT_HOST_PATH="${QT_HOST_PATH:-$HOME/Qt/$QT_VERSION/macos}"
AQT_VENV="$ROOT/.venv-aqt"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: this script must run on macOS." >&2
  exit 1
fi
xcode-select -p >/dev/null 2>&1 || {
  echo "ERROR: Xcode command line tools not configured. Run: xcode-select --install" >&2
  exit 1
}

if ! command -v brew >/dev/null; then
  echo "ERROR: Homebrew not found (https://brew.sh)." >&2
  exit 1
fi
command -v cmake >/dev/null || brew install cmake
command -v swig >/dev/null || brew install swig

ensure_aqt() {
  if [[ ! -x "$AQT_VENV/bin/aqt" ]]; then
    python3 -m venv "$AQT_VENV"
    "$AQT_VENV/bin/pip" install --upgrade pip aqtinstall
  fi
}

if [[ ! -x "$QT_ROOT/bin/qt-cmake" ]]; then
  echo "==> Installing Qt $QT_VERSION for iOS via aqtinstall"
  ensure_aqt
  "$AQT_VENV/bin/aqt" install-qt mac ios "$QT_VERSION" ios \
    -m qtmultimedia qt5compat qtshadertools -O "$HOME/Qt"
fi

if [[ ! -x "$QT_HOST_PATH/bin/qmake" ]]; then
  echo "==> Installing host Qt $QT_VERSION (moc/rcc/qsb)"
  ensure_aqt
  "$AQT_VENV/bin/aqt" install-qt mac desktop "$QT_VERSION" clang_64 \
    -m qtshadertools -O "$HOME/Qt"
fi

bash "$ROOT/scripts/build_deps.sh" --prefix "$ROOT/ios-deps"
bash "$ROOT/scripts/build_ios.sh" \
  --qt "$QT_ROOT" --host-qt "$QT_HOST_PATH" --deps "$ROOT/ios-deps"
