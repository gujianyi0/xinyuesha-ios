"""Actual bootstrap Lua: public committed card uses emit once, cancelled requests do not."""
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
local oldCalls,events,questCalls=0,{},0
local function klass()
 return {prepareDrawPile=function()end,deserialize=function()end,updateQuestSkillUI=function(self,data)questCalls=questCalls+1;return 'questkept'end,
  appendLog=function(self,message,visible)oldCalls=oldCalls+1;assert(visible=='public');return 'kept'end}
end
Client=klass();local registered=klass()
Fk={boardgames={{client_klass=registered}},packages={},getCardById=function(self,id,public)assert(public and id==10);return {name='jink'}end}
ClientInstance={class=registered,callbacks={},notifyUI=function(self,cmd,data)events[#events+1]={cmd,data}end}
local boot=assert(load(SOURCE))
boot();local first=ClientInstance.callbacks.GameLog;boot();assert(ClientInstance.callbacks.GameLog==first,'idempotent install')
for _,kind in ipairs({'#UseCard','#UseCardToTargets','#UseCardToCard'})do
 assert(ClientInstance.callbacks.GameLog(ClientInstance,{type=kind,from=2},'public')=='kept')
end
assert(#events==3 and oldCalls==3)
for _,event in ipairs(events)do assert(event[1]=='Fk.GuanNingSkinAction' and event[2].player==2 and event[2].action=='attack')end
for _,kind in ipairs({'#DrawCards','#InvokeSkill','AskForUseCard','CancelRequest','#ResponsePlayCard'})do
 ClientInstance.callbacks.GameLog(ClientInstance,{type=kind,from=2},'public')
end
ClientInstance.callbacks.GameLog(ClientInstance,{type='#UseCard'},'public')
assert(#events==3 and oldCalls==9,'no guessed action from non-use events or missing actor')
local other={notifyUI=ClientInstance.notifyUI}
Client.appendLog(other,{type='#UseCard',from=3},'public')
assert(#events==4 and events[4][2].player==3,'both cached client class identities are adapted')
ClientInstance.callbacks.GameLog(ClientInstance,{type='#UseCard',from=2,card={{name='slash'}}},'public')
assert(#events==6 and events[5][1]=='Fk.GuanNingSkinAction' and events[6][1]=='Fk.HandkillCard' and events[6][2].cardName=='slash')
ClientInstance.callbacks.GameLog(ClientInstance,{type='#ResponsePlayCard',from=2,card={10}},'public')
assert(#events==7 and events[7][1]=='Fk.HandkillCard' and events[7][2].cardName=='jink','public response, no Guanning attack')
for _,kind in ipairs({'##ResponsePlayCard','#DrawCards','AskForUseCard','CancelRequest'})do
 ClientInstance.callbacks.GameLog(ClientInstance,{type=kind,from=2,card={{name='slash'}}},'public')
end
assert(#events==7,'hidden or footnote events never emit card actions')
ClientInstance.callbacks.GameLog(ClientInstance,{type='$GameStart'},'public')
assert(#events==8 and events[8][1]=='Fk.HandkillGameStart')
ClientInstance.callbacks.GameLog(ClientInstance,{type='#TiansuanResult',from=2,arg='tiansuanSSR'},'public')
assert(#events==9 and events[9][1]=='Fk.HandkillPublicLog' and events[9][2].result=='tiansuanSSR')
assert(ClientInstance.callbacks.UpdateQuestSkillUI(ClientInstance,{2,'zhongao'})=='questkept')
assert(#events==10 and events[10][1]=='Fk.HandkillQuest' and events[10][2][1]==2 and questCalls==1)
ClientInstance.callbacks.UpdateQuestSkillUI(ClientInstance,{2,'foreign_skill'})
assert(#events==10 and questCalls==2,'unrelated quest callback preserved without cosmetic event')
'''.replace('SOURCE',source)
state=lib.luaL_newstate();lib.luaL_openlibs(state)
try:
 status=lib.luaL_loadstring(state,script.encode('utf8')) or lib.lua_pcallk(state,0,0,0,0,None)
 if status:raise AssertionError(lib.lua_tolstring(state,-1,None).decode('utf8'))
 print(json.dumps({'passed':True,'publicCardUses':3,'excludedNonUseCases':6,'idempotent':True,'bothClientClasses':True,'serverPacketsSent':0,'publicHandkillCardAndResponse':True,'noPrivateOrFootnoteCardEvents':True,'gameStartNotification':True,'publicQuestCallbackForwardedExactlyOnce':True,'publicTiansuanResultOnly':True}))
finally:lib.lua_close(state)
