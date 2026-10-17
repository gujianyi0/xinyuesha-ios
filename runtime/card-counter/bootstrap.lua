-- SPDX-License-Identifier: GPL-3.0-or-later
-- Loaded at the end of lua/client/client.lua, before CreateLuaClient runs.
-- ltk/init.lua registers a cached class with the board game. client.lua then
-- loads ltk/client/client.lua again, creating a different global Client class.
-- enterRoom uses the registered class, so patch both identities.
FkCardCounterInstalled = FkCardCounterInstalled or setmetatable({}, {__mode="k"})
local function install(klass)
if not klass or FkCardCounterInstalled[klass] or type(klass.prepareDrawPile) ~= "function" then return end
FkCardCounterInstalled[klass] = true
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
end
install(Client)
for _, boardgame in pairs((Fk and Fk.boardgames) or {}) do
  install(boardgame.client_klass)
end
if ClientInstance and ClientInstance.callbacks then
  install(ClientInstance.class)
  ClientInstance.callbacks.PrepareDrawPile = ClientInstance.class.prepareDrawPile
end
