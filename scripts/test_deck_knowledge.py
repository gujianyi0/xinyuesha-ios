"""Reproduce stock simultaneous-exchange loss and check visibility-safe repairs."""
import argparse, ctypes, json, os
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--payload',type=Path,default=Path('runtime'));p.add_argument('--lua-library',required=True);a=p.parse_args()
directory=os.add_dll_directory(str(Path(a.lua_library).resolve().parent)) if os.name=='nt' else None
lib=ctypes.CDLL(a.lua_library);lib.luaL_newstate.restype=ctypes.c_void_p
lib.luaL_openlibs.argtypes=[ctypes.c_void_p];lib.luaL_loadstring.argtypes=[ctypes.c_void_p,ctypes.c_char_p]
lib.lua_pcallk.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_ssize_t,ctypes.c_void_p]
lib.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p];lib.lua_tolstring.restype=ctypes.c_char_p;lib.lua_close.argtypes=[ctypes.c_void_p]
def load(path):return 'assert(load('+json.dumps(path.read_text(encoding='utf8'),ensure_ascii=False)+'))()'
script=r'''
function class() local c={};c.__index=c;function c:new(...) local o=setmetatable({},self);o:initialize(...);return o end;return c end
function table.contains(t,v) for _,x in ipairs(t) do if x==v then return true end end;return false end
function table.indexOf(t,v) for i,x in ipairs(t) do if x==v then return i end end;return -1 end
function table.removeOne(t,v) local i=table.indexOf(t,v);if i>0 then table.remove(t,i) end end
function table.insertIfNeed(t,v) if not table.contains(t,v) then table.insert(t,v) end end
function table.insertTableIfNeed(t,other) for _,v in ipairs(other) do table.insertIfNeed(t,v) end end
function table.map(t,f) local out={};for i,v in ipairs(t) do out[i]=f(v) end;return out end
function table.filter(t,f) local out={};for _,v in ipairs(t) do if f(v) then out[#out+1]=v end end;return out end
Card={PlayerHand=1,PlayerEquip=2,PlayerJudge=3,PlayerSpecial=4,Processing=5,DrawPile=6,DiscardPile=7,Void=8}
Player={Hand=1,Equip=2,Judge=3,Special=4};fk={ReasonDraw=1}
local room={draw_pile={31,32,33,34,35,36,37,38},players={}}
Fk={currentRoom=function() return room end,boardgames={}}
local viewer={id=1};Self=viewer;ClientInstance=room
function viewer:cardVisible(id) return false end
local target={id=2,player_cards={[1]={27,28}}};room.players={viewer,target}
function room:getPlayerById(id) return id==1 and viewer or target end
function room:getCardsByArea(area,player) if area==6 then return self.draw_pile end;return self:getPlayerById(type(player)=='table' and player.id or player).player_cards[area] end
function room:getCardArea(id) return table.contains(self.draw_pile,id) and 6 or 1 end
function room:getCardOwner(id) return self:getCardArea(id)==1 and target or nil end
'''
script+='\nlocal Tracker='+load(Path(__file__).parent/'fixtures/known_card_tracker_0_5_25.lua')+'\nlocal M='+load(a.payload/'card-counter/counter.lua')+'\n'+r'''
viewer.card_tracker=Tracker:new(viewer)
local tracker=viewer.card_tracker
-- Actual Guanxu input: publicly shown top five plus the target's hand.
assert(M.remember({31,32,33,34,35},'top',8));M.remember({27,28})
assert(M.remember({38},'bottom',8))
local moves={
 {from=2,toArea=6,drawPilePosition=3,moveInfo={{cardId=27,fromArea=1}}},
 {to=2,toArea=1,moveInfo={{cardId=33,fromArea=6}}},
}
local before=M.beforeMoves(room,moves)
-- The client applies the entire batch before invoking the stock tracker.
room.draw_pile={31,32,27,34,35,36,37,38};target.player_cards[1]={28,33}
tracker:applyMoveDatas(moves)
assert(tracker.draw_pile_order[1]==-1 and tracker.draw_pile_order[8]==-1,'baseline must reproduce the report')
-- New logic can see the public length, but reading any hidden identity fails.
local actual=room.draw_pile
room.draw_pile=setmetatable({},{__len=function() return #actual end,__index=function() error('hidden identity read') end,__pairs=function() error('hidden enumeration') end})
M.afterMoves(room,moves,before)
assert(table.concat(tracker.draw_pile_order,',')=='31,32,27,34,35,-1,-1,38','same-size exchange preserves both ends')
-- Following draws shift the remaining known prefix and preserve the bottom.
local draw={{to=2,toArea=1,moveInfo={{cardId=31,fromArea=6}}}}
before=M.beforeMoves(room,draw);actual={32,27,34,35,36,37,38};M.afterMoves(room,draw,before)
assert(table.concat(tracker.draw_pile_order,',')=='32,27,34,35,-1,-1,38')
-- A normal unknown draw still certifies the top, preserving a known bottom.
tracker.draw_pile_order={-1,-1,-1,-1,-1,-1,38}
local unknownDraw={{to=2,toArea=1,moveReason=1,moveInfo={{cardId=32,fromArea=6}}}}
before=M.beforeMoves(room,unknownDraw);actual={27,34,35,36,37,38};M.afterMoves(room,unknownDraw,before)
assert(table.concat(tracker.draw_pile_order,',')=='-1,-1,-1,-1,-1,38')
-- Destination metadata or nil alone cannot certify an arbitrary hidden source.
local hiddenPick={{to=2,toArea=1,moveInfo={{cardId=36,fromArea=6}}}}
before=M.beforeMoves(room,hiddenPick);actual={27,34,35,37,38};M.afterMoves(room,hiddenPick,before)
assert(table.concat(tracker.draw_pile_order,',')=='-1,-1,-1,-1,-1')
actual={32,27,34,35,36,37,38};tracker.draw_pile_order={32,27,34,35,-1,-1,38}
-- Unknown interior removal cannot retain unsupported exact positions.
local random={{to=2,toArea=1,drawPilePosition=3,moveInfo={{cardId=36,fromArea=6}}}}
before=M.beforeMoves(room,random);actual={32,27,34,35,37,38};M.afterMoves(room,random,before)
assert(table.concat(tracker.draw_pile_order,',')=='-1,-1,-1,-1,-1,-1')
-- Quanbian's explicitly confirmed prefix followed by obtaining the chosen card.
actual={31,32,33,34,35,36,37,38};tracker.draw_pile_order={31,32,33,-1,-1,-1,-1,38}
room.draw_pile=actual;M.remember({33,31,32},'top',8)
local obtain={{to=1,toArea=1,moveInfo={{cardId=32,fromArea=6}}}}
before=M.beforeMoves(room,obtain);actual={33,31,34,35,36,37,38};room.draw_pile=setmetatable({},{__len=function()return #actual end,__index=function()error('hidden identity read')end})
M.afterMoves(room,obtain,before)
assert(table.concat(tracker.draw_pile_order,',')=='33,31,-1,-1,-1,-1,38')
return 'stock Guanxu loss reproduced; exchanged prefix/bottom, subsequent draw, unknown removal and Quanbian passed without hidden identity reads'
'''
vm=lib.luaL_newstate()
try:
 lib.luaL_openlibs(vm);assert lib.luaL_loadstring(vm,script.encode())==0,lib.lua_tolstring(vm,-1,None)
 assert lib.lua_pcallk(vm,0,1,0,0,None)==0,lib.lua_tolstring(vm,-1,None)
 print(lib.lua_tolstring(vm,-1,None).decode())
finally:
 lib.lua_close(vm)
 if directory:directory.close()
