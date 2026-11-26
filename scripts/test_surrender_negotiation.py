"""Exercise the real server request, negotiation and identity-mode Lua code."""
import argparse
import ctypes
import json
import os
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--lua-library', required=True)
parser.add_argument('--core', type=Path, default=Path('runtime/packages/freekill-core'))
parser.add_argument('--expect-bug', action='store_true')
parser.add_argument('--result', type=Path)
args = parser.parse_args()

directory = os.add_dll_directory(str(Path(args.lua_library).resolve().parent)) if os.name == 'nt' else None
lib = ctypes.CDLL(args.lua_library)
lib.luaL_newstate.restype = ctypes.c_void_p
lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
lib.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
lib.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_ssize_t, ctypes.c_void_p]
lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
lib.lua_tolstring.restype = ctypes.c_char_p
lib.lua_close.argtypes = [ctypes.c_void_p]

sources = {}
for name, relative in {
    'room': 'lua/server/roombase.lua',
    'request': 'lua/server/request.lua',
    'mode': 'lua/core/game_mode.lua',
    'role': 'standard/pkg/init.lua',
}.items():
    sources[name] = (args.core / relative).read_text(encoding='utf-8')
script = 'local sources = {\n' + ''.join(f'[{json.dumps(k)}]={json.dumps(v, ensure_ascii=False)},\n' for k, v in sources.items()) + '}\n'
script += f'local expectBug = {str(args.expect_bug).lower()}\n'
script += Path(__file__).with_suffix('.lua').read_text(encoding='utf-8')
vm = lib.luaL_newstate()
try:
    lib.luaL_openlibs(vm)
    for status in [lib.luaL_loadstring(vm, script.encode('utf-8'))]:
        if status:
            raise RuntimeError(lib.lua_tolstring(vm, -1, None).decode('utf-8'))
    if lib.lua_pcallk(vm, 0, 1, 0, 0, None):
        raise RuntimeError(lib.lua_tolstring(vm, -1, None).decode('utf-8'))
    count = int(lib.lua_tolstring(vm, -1, None))
    report = {'passed': True, 'baselineBugReproduced': args.expect_bug, 'checks': count,
              'method': 'Lua 5.4, actual server modules and standard identity winner/eligibility functions',
              'realDeviceRetest': 'pending', 'primaryServerDeployment': 'not_performed'}
    if args.result:
        args.result.parent.mkdir(parents=True, exist_ok=True)
        args.result.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False))
finally:
    lib.lua_close(vm)
    if directory:
        directory.close()
