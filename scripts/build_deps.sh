#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Build the three native dependencies FreeKill needs on iOS as static arm64
# libraries: Lua 5.4.8 (vendored), OpenSSL 3.5.x and libgit2 1.9.x.
#
# Run on macOS with Xcode command line tools installed:
#   bash scripts/build_deps.sh --prefix "$PWD/ios-deps"
#
# The resulting prefix contains:
#   include/lua/lua.h ...
#   include/openssl/...
#   include/git2.h ...
#   lib/liblua54.a libcrypto.a libssl.a libgit2.a
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="$ROOT/ios-deps"
BUILD="$ROOT/build-deps"
MIN_IOS="16.0"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
OPENSSL_VERSION="3.5.1"
LIBGIT2_VERSION="1.9.7"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    --build) BUILD="$2"; shift 2 ;;
    --min-ios) MIN_IOS="$2"; shift 2 ;;
    --jobs) JOBS="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: iOS dependencies can only be built on macOS (Xcode required)." >&2
  exit 1
fi
command -v xcrun >/dev/null || { echo "ERROR: xcrun not found; install Xcode." >&2; exit 1; }
command -v cmake >/dev/null || { echo "ERROR: cmake not found; brew install cmake." >&2; exit 1; }
command -v curl >/dev/null || { echo "ERROR: curl not found." >&2; exit 1; }

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANG="$(xcrun --sdk iphoneos -f clang)"
AR="$(xcrun --sdk iphoneos -f ar 2>/dev/null || command -v ar)"
export SDK

mkdir -p "$PREFIX/lib" "$PREFIX/include" "$BUILD"

fetch() {
  local url="$1" out="$2"
  if [[ -s "$out" ]]; then return; fi
  echo "==> downloading $url"
  # Download to a .part file so an interrupted transfer is not mistaken for a
  # complete archive on the next run.
  curl --fail --location --retry 3 --retry-delay 2 --output "$out.part" "$url"
  mv "$out.part" "$out"
}

echo "==> 1/3 Lua 5.4.8 (static, arm64)"
LUA_SRC="$ROOT/thirdparty/lua"
LUA_OBJ="$BUILD/lua"
rm -rf "$LUA_OBJ" "$PREFIX/include/lua"
mkdir -p "$LUA_OBJ" "$PREFIX/include/lua"
for f in "$LUA_SRC"/*.c; do
  case "$(basename "$f")" in
    lua.c|luac.c|onelua.c|ltests.c) continue ;;
  esac
  "$CLANG" -arch arm64 -isysroot "$SDK" -mios-version-min="$MIN_IOS" \
    -O2 -fPIC -fno-common -DLUA_USE_IOS -I"$LUA_SRC" \
    -c "$f" -o "$LUA_OBJ/$(basename "${f%.c}").o"
done
"$AR" rcs "$PREFIX/lib/liblua54.a" "$LUA_OBJ"/*.o
cp "$LUA_SRC"/lua.h "$LUA_SRC"/luaconf.h "$LUA_SRC"/lauxlib.h \
   "$LUA_SRC"/lualib.h "$LUA_SRC"/lua.hpp "$PREFIX/include/lua/"

echo "==> 2/3 OpenSSL $OPENSSL_VERSION (static, arm64)"
OPENSSL_TGZ="$BUILD/openssl-$OPENSSL_VERSION.tar.gz"
OPENSSL_DIR="$BUILD/openssl-$OPENSSL_VERSION"
fetch "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz" "$OPENSSL_TGZ"
rm -rf "$OPENSSL_DIR"
tar -xzf "$OPENSSL_TGZ" -C "$BUILD"
pushd "$OPENSSL_DIR" >/dev/null
if grep -q 'ios64-xcrun' Configurations/10-main.conf; then
  ./Configure ios64-xcrun no-shared no-tests no-docs no-asm \
    --prefix="$PREFIX" --openssldir="$PREFIX/ssl"
else
  export CROSS_TOP="$(xcrun --sdk iphoneos --show-sdk-platform-path)/Developer"
  export CROSS_SDK="iPhoneOS.sdk"
  ./Configure ios64-cross no-shared no-tests no-docs no-asm \
    --prefix="$PREFIX" --openssldir="$PREFIX/ssl"
fi
make -j"$JOBS"
make install_sw
popd >/dev/null

echo "==> 3/3 libgit2 $LIBGIT2_VERSION (static, arm64)"
LIBGIT2_TGZ="$BUILD/libgit2-$LIBGIT2_VERSION.tar.gz"
LIBGIT2_SRC="$BUILD/libgit2-$LIBGIT2_VERSION"
fetch "https://github.com/libgit2/libgit2/archive/refs/tags/v$LIBGIT2_VERSION.tar.gz" "$LIBGIT2_TGZ"
rm -rf "$LIBGIT2_SRC" "$BUILD/libgit2-build"
tar -xzf "$LIBGIT2_TGZ" -C "$BUILD"
cmake -S "$LIBGIT2_SRC" -B "$BUILD/libgit2-build" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_IOS" \
  -DCMAKE_OSX_SYSROOT="$SDK" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_TESTS=OFF \
  -DBUILD_CLI=OFF \
  -DBUILD_EXAMPLES=OFF \
  -DUSE_SSH=OFF \
  -DUSE_HTTPS=OpenSSL \
  -DUSE_SHA1=OpenSSL \
  -DUSE_SHA256=OpenSSL \
  -DOPENSSL_ROOT_DIR="$PREFIX" \
  -DOPENSSL_INCLUDE_DIR="$PREFIX/include" \
  -DOPENSSL_CRYPTO_LIBRARY="$PREFIX/lib/libcrypto.a" \
  -DOPENSSL_SSL_LIBRARY="$PREFIX/lib/libssl.a" \
  -DREGEX_BACKEND=builtin \
  -DUSE_BUNDLED_ZLIB=ON \
  -DUSE_HTTP_PARSER=builtin
cmake --build "$BUILD/libgit2-build" --parallel "$JOBS"
cmake --install "$BUILD/libgit2-build"

for f in lib/liblua54.a lib/libcrypto.a lib/libssl.a lib/libgit2.a include/lua/lua.h include/git2.h; do
  [[ -e "$PREFIX/$f" ]] || { echo "ERROR: missing $PREFIX/$f" >&2; exit 1; }
done

echo
echo "Dependencies installed in: $PREFIX"
du -sh "$PREFIX"
