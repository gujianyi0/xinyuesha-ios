// SPDX-License-Identifier: MIT
// C++ wrapper header for Lua 5.4 (the upstream GitHub source archive does not
// ship lua.hpp; the release tarball does). Kept byte-for-byte compatible with
// the upstream lua.hpp.
extern "C" {
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
}
