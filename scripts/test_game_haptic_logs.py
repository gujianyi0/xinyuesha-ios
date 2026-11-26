"""Run actual bootstrap: only structured public HP-loss/turn logs emit haptics."""
import argparse,ctypes,json,os
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--payload',type=Path,required=True);p.add_argument('--lua-library',required=True);a=p.parse_args()
directory=os.add_dll_directory(str(Path(a.lua_library).resolve().parent)) if os.name=='nt' else None
lib=ctypes.CDLL(a.lua_library);lib.luaL_newstate.restype=ctypes.c_void_p
lib.luaL_openlibs.argtypes=[ctypes.c_void_p];lib.luaL_loadstring.argtypes=[ctypes.c_void_p,ctypes.c_char_p]
lib.lua_pcallk.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_ssize_t,ctypes.c_void_p]
lib.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p];lib.lua_tolstring.restype=ctypes.c_char_p;lib.lua_close.argtypes=[ctypes.c_void_p]
source=json.dumps((a.payload/'card-counter/bootstrap.lua').read_text(encoding='utf8'),ensure_ascii=False)
script=r'''
local events,oldCalls={},0
local function klass()
 return {prepareDrawPile=function()end,deserialize=function()end,
 appendLog=function(self,message,visible)oldCalls=oldCalls+1;assert(visible=='public');return 'kept'end}
end
Client=klass();local registered=klass();Fk={boardgames={{client_klass=registered}},packages={}}
ClientInstance={class=registered,callbacks={},notifyUI=function(self,command,data)events[#events+1]={command,data}end}
local boot=assert(load(SOURCE));boot();local first=ClientInstance.callbacks.GameLog;boot();assert(first==ClientInstance.callbacks.GameLog)
for _,row in ipairs({{type='#LoseHP',from=2,arg=1},{type='$TurnStart',from=2},{type='$ExtraTurnStart',from=3}})do
 assert(first(ClientInstance,row,'public')=='kept')
end
assert(#events==3 and oldCalls==3)
assert(events[1][1]=='Fk.GameHaptic' and events[1][2].kind=='lose-hp' and events[1][2].player==2)
assert(events[2][2].kind=='turn' and events[3][2].player==3)
for _,row in ipairs({{type='#LoseHP',from=2,arg=0},{type='#LoseHP',from=2,arg=-1},
 {type='#LoseHP',arg=1},{type='#LoseHP',from='2',arg=1},{type='LoseHP',from=2,arg=1},
 {type='#HealHP',from=2,arg=1},{type='#Damage',from=2,arg=1},{type='AskForUseCard',from=2}})do
 first(ClientInstance,row,'public')
end
assert(#events==3 and oldCalls==11,'Unknown sound owner, healing and prompts must not trigger')
Client.appendLog(ClientInstance,{type='$TurnStart',from=2},'public');assert(#events==4,'Both cached classes are hooked')
'''.replace('SOURCE',source)
state=lib.luaL_newstate();lib.luaL_openlibs(state)
try:
 status=lib.luaL_loadstring(state,script.encode('utf8')) or lib.lua_pcallk(state,0,0,0,0,None)
 if status:raise AssertionError(lib.lua_tolstring(state,-1,None).decode('utf8'))
 print(json.dumps({'passed':True,'payload':str(a.payload),'publicTurnAndExtraTurnAndHpLoss':True,'noGuessedOwnerForSound':True,'originalHandlerAndBothClassesPreserved':True,'idempotent':True,'serverPacketsSent':0}))
finally:lib.lua_close(state)
