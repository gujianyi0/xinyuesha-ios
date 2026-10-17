-- SPDX-License-Identifier: GPL-3.0-or-later
-- FreeKill 0.5.22: aggregate card knowledge, never the hidden deck/hand order.
local M = {}
local catalogs = setmetatable({}, { __mode = "k" })

function M.snapshot(room, engine, viewer)
  if not room or not viewer or not viewer.player_cards then
    return { ready = false, rows = {}, message = "等待牌局数据" }
  end
  local rows, byName, pool, outside, hand, discard = {}, {}, {}, {}, {}, {}
  local catalog = catalogs[room]
  if not catalog or catalog.locations ~= room.card_place or catalog.viewer ~= viewer or catalog.pool ~= room._counter_pool then
    catalog = {locations = room.card_place, viewer = viewer, pool = room._counter_pool, extra = {}}
    catalogs[room] = catalog
  end
  for id in pairs(catalog.extra) do pool[id] = true end
  local function card(id) return engine:getCardById(id, true) end
  -- Exact initial membership is captured from PrepareDrawPile, after the server
  -- has applied this room's chosen packs / custom game mode. No deck order kept.
  if room._counter_pool then
    for id in pairs(room._counter_pool) do pool[id] = true end
  else
    return {ready=false, rows={}, message="等待本局牌堆同步"}
  end
  local function distribution()
    local points = {}
    for i = 1, 70 do points[i] = 0 end
    return {suits = {0, 0, 0, 0, 0}, points = points}
  end
  local function increment(row, field, c)
    local suit, number = c.suit or 5, c.number or 0
    if suit < 1 or suit > 5 then suit = 5 end
    if number < 0 or number > 13 then number = 0 end
    local d = row.details[field]
    d.suits[suit] = d.suits[suit] + 1
    local index = (suit - 1) * 14 + number + 1
    d.points[index] = d.points[index] + 1
  end
  local function addVisible(ids, category)
    for _, id in ipairs(ids or {}) do
      if viewer:cardVisible(id) then
        outside[id] = true
        if category then category[id] = true end
        pool[id] = true -- visible printed / derived physical cards
        catalog.extra[id] = true
      end
    end
  end
  -- Enumerate only public zones and player zones gated by cardVisible.
  addVisible(room.discard_pile, discard)
  addVisible(room.processing_area)
  for _, p in ipairs(room.players or {}) do
    for area, ids in pairs(p.player_cards or {}) do
      addVisible(ids, p == viewer and area == 1 and hand or nil)
    end
    for _, ids in pairs(p.special_cards or {}) do addVisible(ids) end
  end
  -- The engine's viewer-specific tracker knows cards even after they turn over.
  -- Uncertain memories deliberately remain in the unseen count.
  local tracker = viewer.card_tracker
  local function addKnown(known)
    for _, id in ipairs((known or {}).known_cards or {}) do
      outside[id] = true
      pool[id] = true
      catalog.extra[id] = true
    end
  end
  if tracker then
    -- These zones are read from their current public state above. The upstream
    -- tracker can retain old discard IDs after ShuffleDrawPile; do not use them.
    addKnown(tracker.void)
    for _, zones in pairs(tracker.player_cards or {}) do
      for _, known in pairs(zones) do addKnown(known) end
    end
  end
  -- No access to room.draw_pile IDs, hidden card locations, or other trackers.
  for id in pairs(pool) do
    local c = card(id)
    if c then
      local key = c.name
      local row = byName[key]
      if not row then
        row = { key = key, name = engine:translate(key), kind = c.type or 0,
          total = 0, unseen = 0, known = 0, hand = 0, discard = 0,
          details = {unseen=distribution(), discard=distribution(), hand=distribution(), total=distribution()} }
        row.suits = row.details.unseen.suits
        byName[key] = row
        rows[#rows + 1] = row
      end
      row.total = row.total + 1
      increment(row, "total", c)
      if outside[id] then row.known = row.known + 1
      else
        row.unseen = row.unseen + 1
        increment(row, "unseen", c)
      end
      if hand[id] then row.hand = row.hand + 1; increment(row, "hand", c) end
      if discard[id] then row.discard = row.discard + 1; increment(row, "discard", c) end
    end
  end
  local priority = {slash=1, fire__slash=2, thunder__slash=3, jink=4, peach=5,
    analeptic=6, nullification=7}
  table.sort(rows, function(a,b)
    local ap, bp = priority[a.key] or 100, priority[b.key] or 100
    if ap ~= bp then return ap < bp end
    if a.kind ~= b.kind then return a.kind < b.kind end
    return a.key < b.key
  end)
  local total, unseen, known, discarded, inHand = 0, 0, 0, 0, 0
  for _, row in ipairs(rows) do
    total = total + row.total; unseen = unseen + row.unseen; known = known + row.known
    discarded = discarded + row.discard; inHand = inHand + row.hand
  end
  return { ready = total > 0, rows = rows, total = total, unseen = unseen,
    known = known, discard = discarded, hand = inHand, viewer = viewer.id,
    message = "未见含牌堆及未知手牌；数字按实体原始牌面统计" }
end

function M.current()
  local ok, result = pcall(M.snapshot, ClientInstance, Fk, Self)
  if ok then return result end
  return { ready = false, rows = {}, message = "记牌数据暂不可用", error = tostring(result) }
end

return M
