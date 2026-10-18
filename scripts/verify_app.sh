#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Sanity-check the built .app before packaging it as an IPA.
set -euo pipefail

APP="${1:-}"
[[ -n "$APP" && -d "$APP" ]] || { echo "usage: verify_app.sh /path/to/FreeKill.app" >&2; exit 2; }

fail=0
check() {
  local label="$1" path="$2"
  if [[ -e "$path" ]]; then
    echo "  ok   $label"
  else
    echo "  FAIL $label ($path)"
    fail=1
  fi
}

echo "==> Verifying $APP"
check "executable" "$APP/FreeKill"
check "Info.plist" "$APP/Info.plist"
check "runtime Fk/main.qml" "$APP/res/Fk/main.qml"
check "runtime LunarLtk" "$APP/res/LunarLtk/qmldir"
check "card-counter SocialHost" "$APP/res/card-counter/SocialHost.qml"
check "card-counter bootstrap" "$APP/res/card-counter/bootstrap.lua"
check "freekill-core" "$APP/res/packages/freekill-core/Fk/main.qml"
check "freekill-core Git HEAD" "$APP/res/packages/freekill-core/.git/HEAD"
if ! git -C "$APP/res/packages/freekill-core" rev-parse --verify HEAD^{commit} >/dev/null 2>&1 \
    || ! git -C "$APP/res/packages/freekill-core" fsck --full --no-reflogs >/dev/null 2>&1; then
  echo "  FAIL freekill-core is not a complete Git repository"
  fail=1
fi
check "standard package" "$APP/res/packages/standard/init.lua"
check "Spine QML module" "$APP/res/Spine/qmldir"
check "CA certificates" "$APP/res/certs"
check "Chinese translation" "$APP/res/zh_CN.qm"
check "launch screen" "$APP/LaunchScreen.storyboardc"
check "FFmpeg avcodec" "$APP/Frameworks/libavcodec.framework"
check "FFmpeg avformat" "$APP/Frameworks/libavformat.framework"
check "FFmpeg avutil" "$APP/Frameworks/libavutil.framework"
check "iPhone icon" "$APP/Icon-60@3x.png"
check "iPad icon" "$APP/Icon-76@2x.png"

if [[ -f "$APP/Info.plist" ]]; then
  if ! /usr/bin/plutil -lint "$APP/Info.plist" >/dev/null; then
    echo "  FAIL Info.plist is not a valid property list"
    fail=1
  fi
  if ! /usr/bin/plutil -extract CFBundleIdentifier raw "$APP/Info.plist" >/dev/null 2>&1; then
    echo "  FAIL Info.plist has no CFBundleIdentifier"
    fail=1
  fi
fi

if [[ "$fail" != "0" ]]; then
  echo "ERROR: app bundle verification failed." >&2
  exit 1
fi
echo "==> App bundle looks complete."
