-- SPDX-License-Identifier: GPL-3.0-or-later
-- FreeKill 0.5.22: aggregate card knowledge, never the hidden deck/hand order.
local M = {}
local catalogs = setmetatable({}, { __mode = "k" })

local function playerLabel(player)
  -- ClientPlayer stores the account nickname on its native player object,
  -- not on the Lua wrapper (which only has the numeric id in stock clients).
  local ok, name = pcall(function() return player.player:getScreenName() end)
  if ok and type(name) == "string" and name ~= "" then return name end
  for _, field in ipairs({"screenName", "screen_name"}) do
    name = player[field]
    if type(name) == "string" and name ~= "" then return name end
  end
  local seat = tonumber(player.seat)
  return seat and seat > 0 and ("第 " .. tostring(seat) .. " 位玩家") or "玩家"
end

function M.snapshot(room, engine, viewer, detailKey)
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
    if not d then return end
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
  -- Detail records come exclusively from this viewer's visibility/tracker.
  -- Never recover identities/order by inspecting the actual hidden draw pile.
  local knowledge = {hands = {}, top = {}, bottom = {}}
  local function record(id, owner, position, uncertain)
    if type(id) ~= "number" or id < 1 then return nil end
    local c = card(id)
    if not c then return nil end
    return {id = id, key = c.name, name = engine:translate(c.name),
      suit = c.suit or 5, number = c.number or 0,
      owner = owner or "", position = position or 0, uncertain = uncertain == true}
  end
  for _, player in ipairs(room.players or {}) do
    if player ~= viewer then
      local seen = {}
      local label = playerLabel(player)
      local zones = tracker and tracker.player_cards and tracker.player_cards[player.id]
      local knownHand = zones and zones[1] or {}
      local function append(id, uncertain)
        if seen[id] then return end
        local row = record(id, label, 0, uncertain)
        if row then row.token = tostring(player.id) .. ":" .. tostring(id); knowledge.hands[#knowledge.hands+1] = row; seen[id] = true end
      end
      for _, id in ipairs(knownHand.known_cards or {}) do append(id, false) end
      for _, id in ipairs((player.player_cards or {})[1] or {}) do
        if viewer:cardVisible(id) then append(id, false) end
      end
      for _, id in ipairs(knownHand.uncertain_cards or {}) do append(id, true) end
    end
  end
  local order = tracker and tracker.draw_pile_order or {}
  for i = 1, #order do
    local row = record(order[i], nil, i)
    if not row then break end
    row.token = tostring(row.id); knowledge.top[#knowledge.top+1] = row
  end
  for i = #order, 1, -1 do
    local row = record(order[i], nil, #order-i+1)
    if not row then break end
    row.token = tostring(row.id); knowledge.bottom[#knowledge.bottom+1] = row
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
          details = (not detailKey or detailKey == key) and
            {unseen=distribution(), discard=distribution(), hand=distribution(), total=distribution()} or {} }
        row.suits = row.details.unseen and row.details.unseen.suits or nil
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
    known = known, discard = discarded, hand = inHand, viewer = viewer.id, knowledge = knowledge,
    message = "未见含牌堆及未知手牌；数字按实体原始牌面统计" }
end

-- Called only with face-up CardItem IDs from an actually visible skill popup.
-- Updating the existing viewer tracker lets its move rules handle uncertainty.
function M.remember(ids, edge, deckCount)
  local room, viewer = ClientInstance, Self
  if not room or not viewer or not viewer.card_tracker then return false end
  local ordered, seen, validEdge = {}, {}, (edge == "top" or edge == "bottom")
  for _, id in ipairs(ids or {}) do
    if type(id) == "number" and id > 0 then
      local area = room:getCardArea(id)
      if area ~= Card.DrawPile or seen[id] then validEdge = false end
      seen[id] = true
      ordered[#ordered+1] = id
      local owner = room:getCardOwner(id)
      if area == Card.PlayerHand and owner then
        viewer.card_tracker:setCardKnown(id, owner, Card.PlayerHand)
      elseif area == Card.Processing or area == Card.DrawPile then
        viewer.card_tracker:setCardKnown(id, nil, area)
      end
    else validEdge = false end
  end
  -- A read-only view does not move cards, so the stock move tracker never
  -- creates order entries. Seed only the explicitly shown edge and public
  -- deck length; never inspect the actual hidden deck IDs/order.
  if validEdge and type(deckCount) == "number" and deckCount % 1 == 0 and
      deckCount >= #ordered and deckCount <= 10000 and #ordered > 0 then
    local old = viewer.card_tracker.draw_pile_order or {}
    local order = {}
    for i = 1, deckCount do order[i] = #old == deckCount and old[i] or -1 end
    -- A newly observed position supersedes an older position for the same card.
    for i, id in ipairs(order) do if seen[id] then order[i] = -1 end end
    for i, id in ipairs(ordered) do
      local index = edge == "top" and i or deckCount - #ordered + i
      order[index] = id
    end
    viewer.card_tracker.draw_pile_order = order
  end
  return true
end

-- Preserve only viewer-known positions across a whole simultaneous move batch.
-- The stock tracker processes losses/additions against the final deck size and
-- clears both ends for a same-size exchange. Never consult hidden deck IDs.
function M.beforeMoves(room, moves)
  local viewer = Self
  if not viewer or not viewer.card_tracker then return nil end
  local touchesDeck = false
  for _, move in ipairs(moves or {}) do
    for _, info in ipairs(move.moveInfo or {}) do
      if info.fromArea == Card.DrawPile or move.toArea == Card.DrawPile then touchesDeck = true; break end
    end
    if touchesDeck then break end
  end
  if not touchesDeck then return nil end
  local old = viewer.card_tracker.draw_pile_order or {}
  local order, visible = {}, {}
  for i, id in ipairs(old) do order[i] = id end
  for _, move in ipairs(moves or {}) do
    for _, info in ipairs(move.moveInfo or {}) do
      local id = info.cardId
      local known = false
      local tracker = viewer.card_tracker
      if tracker.getKnownCardsByArea then
        local zone = tracker:getKnownCardsByArea(info.fromArea, move.from, info.fromSpecialName)
        for _, seen in ipairs(zone and zone.known_cards or {}) do if seen == id then known = true; break end end
      end
      visible[id] = known or viewer:cardVisible(id, move)
    end
  end
  return {order = order, visible = visible, viewer = viewer}
end

function M.afterMoves(room, moves, before)
  if not before or Self ~= before.viewer then return end
  local order, visible = before.order, before.visible
  local finalCount = #room.draw_pile -- public length only, never its identities
  local removed, added = 0, 0
  for _, move in ipairs(moves or {}) do
    for _, info in ipairs(move.moveInfo or {}) do
      if info.fromArea == Card.DrawPile then removed = removed + 1 end
      if move.toArea == Card.DrawPile then added = added + 1 end
    end
  end
  if removed + added == 0 then return end
  local initialCount = finalCount + removed - added
  if #order ~= initialCount then
    order = {}; for i = 1, initialCount do order[i] = -1 end
  end
  -- All removals precede insertions. A known card's index is legitimate prior
  -- knowledge; an unknown removal is positional only for explicit edge draws.
  for _, move in ipairs(moves or {}) do
    for _, info in ipairs(move.moveInfo or {}) do
      if info.fromArea == Card.DrawPile then
        local index
        for i, id in ipairs(order) do if id > 0 and id == info.cardId then index = i; break end end
        if not index and move.drawPilePosition == nil then index = 1 end
        if not index and move.drawPilePosition == -1 then index = #order end
        if index and index > 0 then table.remove(order, index)
        else
          local count = math.max(0, #order - 1)
          order = {}; for i = 1, count do order[i] = -1 end
        end
      end
    end
  end
  for _, move in ipairs(moves or {}) do
    for _, info in ipairs(move.moveInfo or {}) do
      if move.toArea == Card.DrawPile then
        local pos = move.drawPilePosition
        local index = pos == -1 and #order + 1 or (pos or 1)
        if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > #order + 1 then
          local count = #order + 1; order = {}; for i = 1, count do order[i] = -1 end
        else
          table.insert(order, index, visible[info.cardId] and info.cardId or -1)
        end
      end
    end
  end
  if #order ~= finalCount then order = {}; for i = 1, finalCount do order[i] = -1 end end
  before.viewer.card_tracker.draw_pile_order = order
end

function M.current(detailKey)
  local ok, result = pcall(M.snapshot, ClientInstance, Fk, Self, detailKey)
  if ok then return result end
  return { ready = false, rows = {}, message = "记牌数据暂不可用", error = tostring(result) }
end

return M
