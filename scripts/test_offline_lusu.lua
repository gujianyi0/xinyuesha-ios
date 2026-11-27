-- Runs inside the actual game's Lua VM through its --testskills entry point.
-- Events/skills are production engine classes; room I/O is a deterministic fixture.
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
check(Fk.generals.xinyuesha__lusu == nil, "Offline general leaked into normal engine startup")
dofile("card-counter/offline-generals/load.lua")
check(Fk.generals.xinyuesha__lusu == nil, "Unprivileged load must not register offline rules")
__XinyueshaOfflineLusu = "true"
dofile("card-counter/offline-generals/load.lua")
local g = Fk.generals.xinyuesha__lusu
check(g and g.hp == 4 and g.kingdom == "wu", "Offline pack failed to register")
dofile("card-counter/offline-generals/load.lua")
check(Fk.generals.xinyuesha__lusu == g, "Loader must be idempotent")
local l, z = Fk.skill_skels.xylusu__leitong, Fk.skill_skels.xylusu__zhenlei
check(l and z and Fk.skills[l.name] and Fk.skills[z.name], "Actual skill compilation/registration failed")
local function spec(skel, event)
  for _, row in ipairs(skel.effect_spec_list) do if row[1] == event then return row[3] end end
  error("Missing production effect " .. tostring(event))
end
local marks, history, damages = {}, {}, {}
local room = { alive_players = {}, logic = {} }
local player = { room=room, hp=4, shield=0 }
function player:hasSkill(name) return name==l.name or name==z.name end
function player:getMark(name) return marks[name] or 0 end
function player:usedSkillTimes(name, scope) return history[name] or 0 end
function player:setSkillUseHistory(name,n,scope) history[name]=n end
function player:getMaxShield() return 5+self:getMark(MarkEnum.MaxShieldChanged) end
function player:isAlive() return true end
function room:setPlayerMark(p,n,v) marks[n]=v end
function room:addPlayerMark(p,n,v) marks[n]=(marks[n] or 0)+v end
function room:removePlayerMark(p,n,v) marks[n]=math.max(0,(marks[n] or 0)-v) end
function room:changeShield(p,n) p.shield=math.max(0, math.min(p:getMaxShield(),p.shield+n)) end
function room:recover(data) data.who.hp=data.who.hp+data.num end
function room:askToChoosePlayers(p,params) check(params.min_num==1 and params.max_num<=2,"Invalid target bound");return {self.alive_players[1]} end
function room:sortByAction(targets) end
function room:damage(data) damages[#damages+1]=data end
room.alive_players={player}
local use = { from=player, card={type=Card.TypeTrick} }
function use:isUsingHandcard() return true end
local s=spec(l,fk.CardUsing)
check(s.can_refresh(nil,nil,player,player,use),"Own card missing")
s.on_refresh(nil,nil,player,player,use)
check(s.can_trigger(nil,nil,player,player,use),"First card must follow documented no-prior-thunder convention")
s.on_use(nil,nil,player,player,use)
check(#damages==1 and damages[1].damageType==fk.ThunderDamage,"One alive target must work")
local d={card=use.card,damageType=fk.NormalDamage,damage=1}
s=spec(l,fk.PreDamage);check(s.can_refresh(nil,nil,player,player,d),"Trick conversion missing");s.on_refresh(nil,nil,player,player,d)
check(d.damageType==fk.ThunderDamage,"Trick damage not converted")
function room.logic:getCurrentEvent() return {findParent=function()return {data=use}end} end
s=spec(l,fk.Damage);check(s.can_refresh(nil,nil,player,player,d),"Resolved thunder card must be tracked");s.on_refresh(nil,nil,player,player,d)
local nextUse={from=player,card={type=Card.TypeBasic}};function nextUse:isUsingHandcard()return true end
s=spec(l,fk.CardUsing);s.on_refresh(nil,nil,player,player,nextUse)
check(not s.can_trigger(nil,nil,player,player,nextUse),"Previous thunder card must suppress bonus damage")
local third={from=player,card={type=Card.TypeBasic}};s.on_refresh(nil,nil,player,player,third)
check(s.can_trigger(nil,nil,player,player,third),"Non-damaging previous card must enable bonus")
s=spec(z,"active");check(s.can_use(nil,player),"Unused limited skill unavailable");s.on_use(nil,room,{from=player})
check(player.hp==4,"Healing must never reduce healthy HP")
player.hp=-2;s.on_use(nil,room,{from=player});check(player.hp==1,"Dying recovery must reach exactly 1")
history[z.name]=1;check(not s.can_use(nil,player),"Limited use missing")
s=spec(z,fk.CardUsing);s.on_refresh(nil,nil,player,player,use)
check(player:getMark("xylusu_cards-round")==1 and player.shield==1,"Handcard must grant armor after activation")
local equipment={card={type=Card.TypeEquip},isUsingHandcard=function()return true end}
s.on_refresh(nil,nil,player,player,equipment);check(player:getMark("xylusu_cards-round")==1 and player.shield==1,"Equipment must not increase X/cross cap")
local outside={card={type=Card.TypeBasic},isUsingHandcard=function()return true end}
for _=1,6 do s.on_refresh(nil,nil,player,player,outside) end
check(player:getMark("xylusu_cards-round")==7 and player.shield==7,"Round-wide outside-turn count/armor above base 5 broken")
s=spec(z,fk.Damaged);s.on_refresh(nil,nil,player,player,{damageType=fk.ThunderDamage,damage=1})
s=spec(z,fk.RoundStart);s.on_refresh(nil,nil,nil,player,{})
s=spec(z,fk.TurnStart);check(not s.can_refresh(nil,nil,player,player,{}),"Previous round thunder must block reset")
spec(z,fk.RoundStart).on_refresh(nil,nil,nil,player,{})
check(s.can_refresh(nil,nil,player,player,{}),"Thunder-free previous round must permit reset");s.on_refresh(nil,nil,player,player,{})
check(history[z.name]==0,"Limited history did not reset")
history[z.name]=1;spec(z,fk.CardUsing).on_refresh(nil,nil,player,player,outside)
z.on_lose(player,false)
check(player:getMark("xylusu_shield_bonus")==0 and player:getMark(MarkEnum.MaxShieldChanged)==0 and player.shield<=5,"Losing the skill must restore its armor-limit contribution")
print("OFFLINE_LUSU_TEST_CHECKS="..checks)
