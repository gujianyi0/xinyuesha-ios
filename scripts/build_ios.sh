#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Configure and build the iOS app, then package an UNSIGNED .ipa.
#
# Usage (on macOS):
#   bash scripts/build_ios.sh \
#     --qt "$HOME/Qt/6.8.3/ios" \
#     --deps "$PWD/ios-deps"
#
# The .ipa can be signed and installed with Sideloadly/AltStore using a normal
# Apple ID, or opened in Xcode with a development team.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QT_ROOT="${QT_ROOT:-$HOME/Qt/6.8.3/ios}"
QT_HOST_PATH="${QT_HOST_PATH:-$(dirname "$QT_ROOT")/macos}"
DEPS="$ROOT/ios-deps"
BUILD="$ROOT/build-ios"
MIN_IOS="16.0"
BUNDLE_ID="com.cui.freekill.ios"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
PACKAGE=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --qt) QT_ROOT="$2"; shift 2 ;;
    --host-qt) QT_HOST_PATH="$2"; shift 2 ;;
    --deps) DEPS="$2"; shift 2 ;;
    --build) BUILD="$2"; shift 2 ;;
    --min-ios) MIN_IOS="$2"; shift 2 ;;
    --bundle-id) BUNDLE_ID="$2"; shift 2 ;;
    --jobs) JOBS="$2"; shift 2 ;;
    --no-package) PACKAGE=0; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: iOS apps must be built on macOS with Xcode." >&2
  exit 1
fi
[[ -x "$QT_ROOT/bin/qt-cmake" ]] || {
  echo "ERROR: Qt for iOS not found at $QT_ROOT/bin/qt-cmake" >&2
  echo "Install it with: python3 -m aqt install-qt mac ios 6.8.3 ios -m qtmultimedia qt5compat qtshadertools -O \"\$HOME/Qt\"" >&2
  exit 1
}
[[ -f "$DEPS/lib/liblua54.a" && -f "$DEPS/lib/libgit2.a" ]] || {
  echo "ERROR: iOS dependencies missing under $DEPS (run scripts/build_deps.sh)." >&2
  exit 1
}
# A cross-compiled Qt needs the matching desktop Qt for moc/rcc/qsb/qmlcachegen.
if [[ ! -f "$QT_HOST_PATH/lib/cmake/Qt6/Qt6Config.cmake" ]]; then
  for candidate in "$(dirname "$QT_ROOT")/macos" "$(dirname "$QT_ROOT")/clang_64"; do
    if [[ -f "$candidate/lib/cmake/Qt6/Qt6Config.cmake" ]]; then QT_HOST_PATH="$candidate"; break; fi
  done
fi
[[ -f "$QT_HOST_PATH/lib/cmake/Qt6/Qt6Config.cmake" ]] || {
  echo "ERROR: host Qt not found. Install it with:" >&2
  echo "  aqt install-qt mac desktop 6.8.3 clang_64 -m qtshadertools -O \$HOME/Qt" >&2
  echo "then pass --host-qt <prefix> (default: $(dirname "$QT_ROOT")/macos)." >&2
  exit 1
}

echo "==> Configuring (Qt: $QT_ROOT)"
rm -rf "$BUILD"
"$QT_ROOT/bin/qt-cmake" -S "$ROOT" -B "$BUILD" -G Xcode \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_IOS" \
  -DQT_HOST_PATH="$QT_HOST_PATH" \
  -DQT_NO_FFMPEG_XCODE_EMBED_FRAMEWORKS_CODE_SIGN_ON_COPY=ON \
  -DFK_IOS_DEPS="$DEPS" \
  -DFK_IOS_DEPLOYMENT_TARGET="$MIN_IOS" \
  -DFK_IOS_BUNDLE_ID="$BUNDLE_ID"

echo "==> Building (this may take a while)"
if ! cmake --build "$BUILD" --config Release --target FreeKill --parallel "$JOBS" -- \
  -sdk iphoneos \
  -destination "generic/platform=iOS" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM=""; then
  echo "==> cmake --build failed; retrying with xcodebuild -target"
  xcodebuild -project "$BUILD/FreeKill.xcodeproj" -target FreeKill \
    -configuration Release -sdk iphoneos \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    DEVELOPMENT_TEAM="" build
fi

APP="$(find "$BUILD" -type d -name 'FreeKill.app' -prune -print | head -n 1)"
[[ -n "$APP" ]] || { echo "ERROR: FreeKill.app not found under $BUILD" >&2; exit 1; }
echo "==> App bundle: $APP"

# The Qt FFmpeg xcframeworks are dynamic; Xcode embeds them but code signing
# is disabled for this unsigned build. Ad-hoc sign them so the bundle is
# internally consistent; Sideloadly replaces the signature with the Apple ID
# certificate when installing.
if [[ -d "$APP/Frameworks" ]]; then
  while IFS= read -r -d '' fw; do
    /usr/bin/codesign --force --sign - "$fw" >/dev/null 2>&1 || echo "warning: ad-hoc codesign failed for $fw" >&2
  done < <(find "$APP/Frameworks" -maxdepth 1 -name '*.framework' -print0)
fi

python3 "$ROOT/scripts/prepare_core_repository.py" "$APP/res"
bash "$ROOT/scripts/verify_app.sh" "$APP"

if [[ "$PACKAGE" == "1" ]]; then
  echo "==> Packaging unsigned IPA"
  IPA_DIR="$BUILD/ipa"
  rm -rf "$IPA_DIR"
  mkdir -p "$IPA_DIR/Payload"
  cp -R "$APP" "$IPA_DIR/Payload/"
  IPA="$IPA_DIR/新月杀测试版-0.5.25-ios-unsigned.ipa"
  rm -f "$IPA"
  (cd "$IPA_DIR" && /usr/bin/zip -qry "$(basename "$IPA")" Payload)
  echo
  echo "IPA: $IPA"
  echo "SHA-256: $(shasum -a 256 "$IPA" | awk '{print $1}')"
  echo "Size: $(du -h "$IPA" | awk '{print $1}')"
else
  echo "App only: $APP"
fi
