-- Only transport, UI registration and native player handles are stubbed.
-- Negotiation, request cleanup, eligibility and victory rules are loaded above
-- from the production Lua files, including the complete standard package.
function class() local c = {}; c.__index = c; return c end
function table.filter(t, f) local r = {}; for _, v in ipairs(t) do if f(v) then r[#r+1] = v end end; return r end
function table.find(t, f) for _, v in ipairs(t) do if f(v) then return v end end end
function table.every(t, f) for _, v in ipairs(t) do if not f(v) then return false end end; return true end
function table.contains(t, value) return table.find(t, function(v) return v == value end) ~= nil end
function table.simpleClone(t) local r = {}; for k,v in pairs(t) do r[k] = v end; return r end
function table.connect(...) local r = {}; for _,t in ipairs({...}) do for _,v in ipairs(t) do r[#r+1] = v end end; return r end
function string:split(sep) local r = {}; for s in self:gmatch('[^' .. sep .. ']+') do r[#r+1] = s end; return r end
local swallowedErrors = 0
function Pcall(f, ...) local ok, result = pcall(f, ...); if ok then return result end; swallowedErrors = swallowedErrors + 1 end
Util = { TrueFunc = function() return true end }
fk = { Player_Online = 1, Player_Run = 2, Player_Robot = 3 }
local currentRoom
Fk = { game_modes = {}, currentRoom = function() return currentRoom end,
  translate = function(_, s) return s end, loadTranslationTable = function() end }
GameMode = assert(load(sources.mode, '@game_mode.lua'))()
fk.CreateGameMode = function(spec)
  spec.getWinner = spec.winner_getter
  spec.surrenderFunc = spec.surrender_func
  spec.friendEnemyJudge = spec.friend_enemy_judge
  return setmetatable(spec, { __index = GameMode })
end
Package = { new = function() return {
  loadSkillSkelsByPath = function() end,
  addGameMode = function(_, mode) Fk.game_modes[mode.name] = mode end,
} end }
General = setmetatable({ new = function() return { addSkills = function() end } end }, { __call = function() return {} end })
package.preload['ui_emu.preferences'] = function() return setmetatable({}, { __index = function() return function(spec) return spec end end }) end
assert(load(sources.role, '@standard/pkg/init.lua'))()
local roleMode = Fk.game_modes.aaa_role_mode
local RoomBase = assert(load(sources.room, '@server/roombase.lua'))()
local Request = assert(load(sources.request, '@server/request.lua'))()
local serial, checks = 0, 0
os.getms = function() serial = serial + 1; return serial end
local function check(value, label)
  assert(value, label); checks = checks + 1
end

local function fixture(options)
  options = options or {}
  -- Eight-seat identity game, both generals populated on every seat.
  -- The old lord and renegade are dead; a loyalist has inherited the throne.
  local roles = { 'lord', 'loyalist', 'lord', 'rebel', 'rebel', 'rebel', 'rebel', 'renegade' }
  local room = setmetatable({ id=1, tag={}, players={}, alive_players={}, game_started=true,
    game_finished=false, start_time=os.time()-600, broadcasts={}, closed={}, asked={},
    gameOvers=0, resumes=0, getWinnerCalls=0 }, { __index = RoomBase })
  function room:getSettings(key) if key == 'gameMode' then return 'test-mode' end; return false end
  function room:getPlayerById(id) return table.find(self.players, function(p) return p.id == id end) end
  function room:setPlayerMark(p,k,v) p.marks[k] = v end
  function room:broadcastProperty(p,k) self.broadcasts[#self.broadcasts+1] = { id=p.id, key=k, value=p[k] } end
  function room:doBroadcastNotify(command, data) self.broadcasts[#self.broadcasts+1] = { command=command, data=data } end
  function room:gameOver(winner) self.gameOvers=self.gameOvers+1; self.winner=winner; self.game_finished=true; self.game_started=false end
  function room:finishRequest()
    if not self.current_request then return end
    self.current_request:_finish()
  end
  ResumeRoom = function(id) check(id == room.id, 'only the intended room is resumed'); room.resumes=room.resumes+1 end
  for id, role in ipairs(roles) do
    local p = { id=id, role=role, rest=0, dead=(id==1 or id==8), surrendered=false,
      room=room, marks={}, state=fk.Player_Online, general='general-'..id, deputyGeneral='deputy-'..id }
    function p:getMark(k) return self.marks[k] or 0 end
    function p:isFriend(other) return roleMode:friendEnemyJudge(self, other) end
    function p:getFriends(includeSelf, includeDead)
      return table.filter(room.players, function(other)
        return (includeSelf ~= false or self ~= other) and (includeDead or not other.dead or other.rest > 0) and self:isFriend(other)
      end)
    end
    function p:doNotify(command, data)
      if command == 'CloseSurrenderNegotiation' then room.closed[#room.closed+1] = self.id end
      if command == 'AskForSurrenderNegotiation' then room.asked[#room.asked+1] = self.id end
    end
    p.serverplayer = { getState=function() return p.state end, setThinking=function() end }
    p._splayer = { getScreenName=function() return 'fixture-'..id end }
    room.players[#room.players+1] = p
    if not p.dead then room.alive_players[#room.alive_players+1] = p end
  end
  -- Exercise the opposite seat order as well, without changing player identity.
  if options.lordFirst then room.players[2],room.players[3] = room.players[3],room.players[2] end
  if options.noHeir then room:getPlayerById(1).role='loyalist' end
  local mode = setmetatable({}, { __index = roleMode })
  function mode:getWinner(victim)
    room.getWinnerCalls=room.getWinnerCalls+1
    if options.errorWinner then error('fixture winner error') end
    if options.noWinner then return '' end
    return roleMode:getWinner(victim)
  end
  Fk.game_modes['test-mode'] = mode
  currentRoom = room
  if options.active ~= false then
    room.current_request = setmetatable({ room=room, players={}, result={}, default_reply={}, send_success={} }, { __index=Request })
  end
  return room
end

local function accept(room, initiator)
  room:handleSurrenderNegotiation(initiator, {})
  local negotiation = room:getTag('surrenderNegotiationing')
  if negotiation then
    local voters = table.simpleClone(negotiation.voters)
    for _,p in ipairs(voters) do room:handleSurrenderNegotiationReply(p.id, { nil,nil,negotiation.id,'true' }) end
  end
end

if expectBug then
  local room = fixture()
  accept(room, 3)
  check(room.hasSurrendered == true, 'baseline accepts the new lord negotiation')
  room:finishRequest()
  check(room.gameOvers == 0, 'baseline reproduces accepted negotiation without game over')
  check(not room:getPlayerById(2).surrendered and room:getPlayerById(3).surrendered,
    'baseline reproduces one gray portrait left behind while the game continues')
  local loyalistRoom = fixture()
  accept(loyalistRoom, 2)
  loyalistRoom:finishRequest()
  check(loyalistRoom.gameOvers == 0, 'baseline also fails for a loyalist initiator')
  return tostring(checks)
end

for _,active in ipairs({true,false}) do
  for _,lordFirst in ipairs({true,false}) do
    for _,initiator in ipairs({2,3}) do
      for _,noHeir in ipairs({true,false}) do
        local room = fixture{ active=active, lordFirst=lordFirst, noHeir=noHeir }
        accept(room, initiator)
        if active then
          check(room.gameOvers == 0 and room.hasSurrendered, 'active request defers game over to request cleanup')
          local calls=room.getWinnerCalls
          room:finishRequest()
          check(room.getWinnerCalls == calls, 'request cleanup consumes the confirmed result without seat-order recomputation')
        end
        check(room.gameOvers == 1 and room.game_finished, 'agreed identity-team surrender ends exactly once')
        check(type(room.winner)=='table' and #room.winner==4 and table.every(room.winner,function(p) return p.role=='rebel' end), 'four rebels are the correct winners')
        check(room:getPlayerById(2).surrendered and room:getPlayerById(3).surrendered, 'all surrendering teammates share the final state')
        check(not room:getPlayerById(1).surrendered and not room:getPlayerById(8).surrendered, 'dead former lord and renegade are excluded')
        check(room.surrenderResult == nil, 'pending result is consumed')
        check(table.every(room.players,function(p) return p.general=='general-'..p.id and p.deputyGeneral=='deputy-'..p.id end), 'both generals remain unchanged')
        local requests=room.resumes
        room:handleSurrenderNegotiation(initiator,{})
        check(room.gameOvers==1 and room.resumes==requests, 'late duplicate requests cannot settle or resume twice')
      end
    end
  end
end

for _,options in ipairs({ {noWinner=true}, {errorWinner=true} }) do
  local room=fixture(options)
  accept(room,3)
  check(room.gameOvers==0 and room.resumes==0 and not room.hasSurrendered, 'failed or exceptional victory calculation never cancels the ongoing request')
  check(table.every(room.players,function(p) return not p.surrendered end), 'failed settlement restores every portrait')
  check(room:getTag('surrenderNegotiationing')==nil and #room.closed==1, 'failed settlement closes the complete vote')
  check(room.surrenderResult==nil, 'failed settlement leaves no pending result')
end
check(swallowedErrors > 0, 'winner errors were exercised through Pcall')

do
  local room=fixture()
  room:handleSurrenderNegotiation(3,{})
  local vote=room:getTag('surrenderNegotiationing')
  room:handleSurrenderNegotiationReply(4,{nil,nil,vote.id,'true'})
  room:handleSurrenderNegotiationReply(2,{nil,nil,'stale-id','true'})
  check(not room.hasSurrendered and room.gameOvers==0, 'opponents and stale vote replies are ignored')
  room:handleSurrenderNegotiationReply(2,{nil,nil,vote.id,'false'})
  check(table.every(room.players,function(p) return not p.surrendered end) and room:getTag('surrenderNegotiationing')==nil, 'a rejection cancels the vote without surrender flags')
end
for _,state in ipairs({fk.Player_Run,fk.Player_Robot}) do
  local room=fixture()
  room:getPlayerById(2).state=state
  accept(room,3)
  room:finishRequest()
  check(room.gameOvers==1 and #room.asked==0, 'existing offline/bot auto-agreement still settles')
end
do
  local room=fixture()
  room:getPlayerById(8).dead=false
  room.alive_players[#room.alive_players+1]=room:getPlayerById(8)
  room:handleSurrenderNegotiation(3,{})
  check(room:getTag('surrenderNegotiationing')==nil and not room.hasSurrendered, 'three living factions still fail negotiation eligibility')
end
do
  local room=fixture()
  room:getPlayerById(2).surrendered=true
  room:getPlayerById(3).surrendered=true
  room.hasSurrendered=true
  room:finishRequest()
  check(room.gameOvers==1, 'legacy accepted flags do not depend on the first seat being the lord')
end
do
  local room=fixture{noWinner=true}
  room:getPlayerById(2).surrendered=true
  room:getPlayerById(3).surrendered=true
  room.hasSurrendered=true
  room:finishRequest()
  check(room.gameOvers==0 and not room.hasSurrendered and table.every(room.players,function(p)return not p.surrendered end), 'legacy failed settlement restores every surrendered player')
end
do
  local room=fixture()
  for _,p in ipairs(room.players) do if p.id~=3 and p.id~=4 then p.dead=true end end
  room.alive_players={room:getPlayerById(3),room:getPlayerById(4)}
  room:handleSurrender(3,{})
  room:finishRequest()
  check(room.gameOvers==1 and type(room.winner)=='table' and #room.winner==4, 'ordinary single-player surrender still settles using identity rules')
end
-- Run the entire production ask/yield/ResumeRoom/_finish chain, rather than
-- only invoking its cleanup. Native packet polling remains pending until the
-- real negotiation handler wakes the request's coroutine.
for _,initiator in ipairs({2,3}) do
  for _,lordFirst in ipairs({true,false}) do
    local room=fixture{active=false,lordFirst=lordFirst}
    local waiting=room:getPlayerById(4)
    waiting._timewaste_count=0
    room.room={setRequestTimer=function()end,destroyRequestTimer=function()end}
    room.logic={trigger=function()end}
    function room:notifyMoveFocus()end
    function room:yield()return coroutine.yield('waiting-for-player')end
    local request=setmetatable({room=room,players={waiting},command='PlayCard',timeout=30,n=1,
      winners={},overtimes={},send_success={},result={},default_reply={}}, {__index=Request})
    function request:_sendPacket(p)self.send_success[p.serverplayer]=true end
    function request:_checkReply()return '__notready'end
    local co=coroutine.create(function()request:ask()end)
    local ok,reason=coroutine.resume(co)
    check(ok and reason=='waiting-for-player' and room.current_request==request, 'production request is suspended awaiting a card play')
    ResumeRoom=function(id)
      check(id==room.id,'negotiation resumes the correct suspended room')
      room.resumes=room.resumes+1
      local resumed,error=coroutine.resume(co,'surrender')
      assert(resumed,error)
    end
    accept(room,initiator)
    check(coroutine.status(co)=='dead' and request._asked and room.current_request==nil, 'accepted negotiation unwinds the real request coroutine')
    check(room.gameOvers==1 and #room.winner==4,'suspended card-play request ends the game once with the correct team')
  end
end
return tostring(checks)
