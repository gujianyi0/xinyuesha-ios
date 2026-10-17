"""Use the bundled Lua library to test the actual client bridge without FreeKill."""
from pathlib import Path
import argparse
import ctypes
import os

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument("--lua-dll", type=Path, default=ROOT.parents[1] / "lua54.dll")
args = parser.parse_args()
directory = os.add_dll_directory(str(args.lua_dll.resolve().parent)) if os.name == "nt" else None
lua = ctypes.CDLL(str(args.lua_dll.resolve()))
lua.luaL_newstate.restype = ctypes.c_void_p
lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
lua.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
lua.luaL_loadfilex.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
lua.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_ssize_t, ctypes.c_void_p]
lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
lua.lua_tolstring.restype = ctypes.c_char_p
lua.lua_close.argtypes = [ctypes.c_void_p]

for source in [ROOT / "lua/client/client.lua", ROOT / "lua/client/i18n/zh_CN.lua"]:
    state = lua.luaL_newstate()
    try:
        assert lua.luaL_loadfilex(state, os.fsencode(source), None) == 0, lua.lua_tolstring(state, -1, None)
    finally:
        lua.lua_close(state)

state = lua.luaL_newstate()
try:
    lua.luaL_openlibs(state)
    source = str(ROOT / "lua/client/client.lua").replace("\\", "/")
    assert lua.luaL_loadstring(state, f'CLIENT_SOURCE = "{source}"'.encode()) == 0
    assert lua.lua_pcallk(state, 0, 0, 0, 0, None) == 0
    test = Path(__file__).with_name("test_client_bridge.lua")
    assert lua.luaL_loadfilex(state, os.fsencode(test), None) == 0, lua.lua_tolstring(state, -1, None)
    assert lua.lua_pcallk(state, 0, 0, 0, 0, None) == 0, lua.lua_tolstring(state, -1, None)
finally:
    lua.lua_close(state)
    if directory:
        directory.close()
