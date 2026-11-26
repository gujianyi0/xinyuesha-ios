-- SPDX-License-Identifier: GPL-3.0-or-later
-- Loaded at the end of lua/client/client.lua, before CreateLuaClient runs.
-- ltk/init.lua registers a cached class with the board game. client.lua then
-- loads ltk/client/client.lua again, creating a different global Client class.
-- enterRoom uses the registered class, so patch both identities.
FkCardCounterInstalled = FkCardCounterInstalled or setmetatable({}, {__mode="k"})
local function install(klass)
if not klass or FkCardCounterInstalled[klass] or type(klass.prepareDrawPile) ~= "function" then return end
FkCardCounterInstalled[klass] = true

-- Only committed public logs carry a player's turn/HP-loss identity. The
-- generic LoseHP sound event has no player id, so it must not drive haptics.
local originalFeedbackLog = klass.appendLog
if type(originalFeedbackLog) == "function" then
  klass.appendLog = function(self, message, ...)
    local result = originalFeedbackLog(self, message, ...)
    if type(message) == "table" and type(message.from) == "number" then
      local kind = message.type == "#LoseHP" and tonumber(message.arg) and tonumber(message.arg) > 0 and "lose-hp" or
        ((message.type == "$TurnStart" or message.type == "$ExtraTurnStart") and "turn" or nil)
      if kind then self:notifyUI("Fk.GameHaptic", {player=message.from, kind=kind}) end
    end
    return result
  end
end

local originalPrepare = klass.prepareDrawPile
klass.prepareDrawPile = function(self, ids)
  originalPrepare(self, ids)
  local pool = {}
  -- This runs before dealing: use membership, discard all ordering information.
  for _, id in ipairs(ids or self.draw_pile or {}) do pool[id] = true end
  self._counter_pool = pool
  if fk and fk.qInfo then
    local count = 0
    for _ in pairs(pool) do count = count + 1 end
    fk.qInfo("[CardCounter] selected pool captured: " .. count .. " physical cards")
  end
end

local originalMove = klass.moveCards
if type(originalMove) == "function" then
  klass.moveCards = function(self, data)
    FkCardCounterV2 = FkCardCounterV2 or dofile("card-counter/counter.lua")
    local moves = type(data) == "table" and data[1] or {}
    local ok, before = pcall(FkCardCounterV2.beforeMoves, self, moves)
    local result = originalMove(self, data)
    if ok then pcall(FkCardCounterV2.afterMoves, self, moves, before) end
    return result
  end
end


local originalUseActive = klass.askForUseActiveSkill
if type(originalUseActive) == "function" then
  klass.askForUseActiveSkill = function(self, data)
    local result = originalUseActive(self, data)
    FkCardCounterV2 = FkCardCounterV2 or dofile("card-counter/counter.lua")
    pcall(FkCardCounterV2.rememberRevealedRequest, self, data)
    return result
  end
end

local originalShuffle = klass.shuffleDrawPile
if type(originalShuffle) == "function" then
  klass.shuffleDrawPile = function(self, ...)
    local result = originalShuffle(self, ...)
    for _, player in ipairs(self.players or {}) do
      if player.card_tracker then
        player.card_tracker.draw_pile_order = {}
        player.card_tracker.draw_pile = {known_cards={}, uncertain_cards={}}
      end
    end
    return result
  end
end

local originalDeserialize = klass.deserialize
klass.deserialize = function(self, data)
  originalDeserialize(self, data)
  -- Reconnection supplies a complete current room snapshot. Unite all active
  -- zones into one pool, so no hidden hand/deck distribution is exposed.
  local pool = {}
  local function include(ids)
    for _, id in ipairs(ids or {}) do pool[id] = true end
  end
  local manager = data.card_manager or {}
  include(manager.draw_pile)
  include(manager.discard_pile)
  include(manager.processing_area)
  for _, p in ipairs(self.players or {}) do
    for _, ids in pairs(p.player_cards or {}) do include(ids) end
    for _, ids in pairs(p.special_cards or {}) do include(ids) end
  end
  self._counter_pool = pool
end

-- Use the public, structured card-use log, not the translated UI text or a
-- request prompt (which can be cancelled). Only this client's frontend hears
-- the action; no packet, game state or card identity is changed.
local originalAppendLog = klass.appendLog
if type(originalAppendLog) == "function" then
  klass.appendLog = function(self, message, ...)
    local result = originalAppendLog(self, message, ...)
    if type(message) == "table" and message.type == "$GameStart" then
      self:notifyUI("Fk.HandkillGameStart", {})
    end
    if type(message) == "table" and message.type == "#TiansuanResult" and message.from and
       type(message.arg) == "string" then
      self:notifyUI("Fk.HandkillPublicLog", {type=message.type, player=message.from, result=message.arg})
    end
    if type(message) == "table" and message.from and
       (message.type == "#UseCard" or message.type == "#UseCardToTargets" or message.type == "#UseCardToCard") then
      local targets = {}
      for _, id in ipairs(type(message.to) == "table" and message.to or {}) do
        if type(id) == "number" then targets[#targets+1] = id end
      end
      self:notifyUI("Fk.GuanNingSkinAction", {player=message.from, action="attack", targets=targets})
    end
    if type(message) == "table" and message.from and
       (message.type == "#UseCard" or message.type == "#UseCardToTargets" or
        message.type == "#UseCardToCard" or message.type == "#ResponsePlayCard") then
      -- Only identities already present in this public committed log are used.
      local card = type(message.card) == "table" and message.card[1] or nil
      if type(card) == "number" then
        local ok, real = pcall(function() return card > 0 and Fk:getCardById(card, true) or nil end)
        card = ok and real or nil
      end
      if type(card) == "table" and type(card.name) == "string" then
        self:notifyUI("Fk.HandkillCard", {player=message.from, cardName=card.name})
      end
    end
    return result
  end
end
-- updateQuestSkillUI consumes a public server event but normally emits only
-- the generic skill-icon refresh. Preserve it and forward its exact identity.
local originalQuest = klass.updateQuestSkillUI
if type(originalQuest) == "function" then
  klass.updateQuestSkillUI = function(self, data, ...)
    local result = originalQuest(self, data, ...)
    if type(data) == "table" and data[1] and data[2] == "zhongao" then
      self:notifyUI("Fk.HandkillQuest", { data[1], data[2] })
    end
    return result
  end
end
end
install(Client)
for _, boardgame in pairs((Fk and Fk.boardgames) or {}) do
  install(boardgame.client_klass)
end
if ClientInstance and ClientInstance.callbacks then
  install(ClientInstance.class)
  if ClientInstance.class.appendLog then ClientInstance.callbacks.GameLog = ClientInstance.class.appendLog end
  ClientInstance.callbacks.PrepareDrawPile = ClientInstance.class.prepareDrawPile
  if ClientInstance.class.askForUseActiveSkill then ClientInstance.callbacks.AskForUseActiveSkill = ClientInstance.class.askForUseActiveSkill end
  if ClientInstance.class.moveCards then ClientInstance.callbacks.MoveCards = ClientInstance.class.moveCards end
  if ClientInstance.class.appendLog then ClientInstance.callbacks.GameLog = ClientInstance.class.appendLog end
  if ClientInstance.class.updateQuestSkillUI then ClientInstance.callbacks.UpdateQuestSkillUI = ClientInstance.class.updateQuestSkillUI end
end

-- Route the named built-in skin downloader to the local responsive frontend.
-- Only runtime menu metadata changes; packages and their checksums stay intact.
for _, package in pairs((Fk and Fk.packages) or {}) do
  for _, page in ipairs(package.customPages or {}) do
    local qml = page.qml
    if qml and qml.uri == "LunarLtk.Pages" and qml.name == "SkinSetting" then
      page.qml = {url = "card-counter/SkinSetting.qml"}
    end
  end
end
