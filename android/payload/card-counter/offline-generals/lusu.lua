-- SPDX-License-Identifier: GPL-3.0-or-later
local pack = Package:new("xinyuesha_offline_lusu")
pack.extensionName = "xinyuesha_offline_lusu"
local leitong = fk.CreateSkill { name = "xylusu__leitong", tags = { Skill.Compulsory } }
local zhenlei = fk.CreateSkill { name = "xylusu__zhenlei", tags = { Skill.Limited } }
local count = "xylusu_cards-round"
local currentDamage, previousDamage = "xylusu_thunder", "xylusu_previous_thunder"
local previousCard = "xylusu_previous_card"
local bonus = "xylusu_shield_bonus"
leitong:addLoseEffect(function(self, player) player[previousCard] = nil end)
local function releaseShieldBonus(player)
  local room, old = player.room, player:getMark(bonus)
  if old > 0 then
    room:removePlayerMark(player, MarkEnum.MaxShieldChanged, old)
    room:setPlayerMark(player, bonus, 0)
    if player.shield > player:getMaxShield() then room:changeShield(player, player:getMaxShield() - player.shield) end
  end
end
zhenlei:addLoseEffect(function(self, player) releaseShieldBonus(player) end)

-- Preserve the use event itself: a repeated physical/virtual card is a new use.
leitong:addEffect(fk.CardUsing, {
  anim_type = "offensive",
  can_refresh = function(self, event, target, player, data)
    return target == player and player:hasSkill(leitong.name)
  end,
  on_refresh = function(self, event, target, player, data)
    local last = player[previousCard]
    data.extra_data = data.extra_data or {}
    data.extra_data.xylusu_leitong = not last or not last.thunder
    player[previousCard] = { use = data, thunder = false }
  end,
  can_trigger = function(self, event, target, player, data)
    return target == player and player:hasSkill(leitong.name) and
      data.extra_data and data.extra_data.xylusu_leitong and #player.room.alive_players > 0
  end,
  on_cost = Util.TrueFunc,
  on_use = function(self, event, target, player, data)
    local room = player.room
    local targets = room:askToChoosePlayers(player, {
      targets = room.alive_players, min_num = 1, max_num = math.min(2, #room.alive_players),
      skill_name = leitong.name, prompt = "#xylusu-leitong", cancelable = false,
    })
    room:sortByAction(targets)
    for _, to in ipairs(targets) do
      if to:isAlive() then room:damage { from = player, to = to, damage = 1,
        damageType = fk.ThunderDamage, skillName = leitong.name } end
    end
  end,
})
leitong:addEffect(fk.PreDamage, {
  can_refresh = function(self, event, target, player, data)
    return target == player and player:hasSkill(leitong.name) and data.card and data.card.type == Card.TypeTrick
  end,
  on_refresh = function(self, event, target, player, data) data.damageType = fk.ThunderDamage end,
})
leitong:addEffect(fk.Damage, {
  can_refresh = function(self, event, target, player, data)
    local last = player[previousCard]
    return target == player and last and data.damageType == fk.ThunderDamage and data.damage > 0 and data.card and
      last.use.card == data.card and player.room.logic:getCurrentEvent():findParent(GameEvent.UseCard) and
      player.room.logic:getCurrentEvent():findParent(GameEvent.UseCard).data == last.use
  end,
  on_refresh = function(self, event, target, player, data) player[previousCard].thunder = true end,
})

local function activate(player)
  local room = player.room
  if player.hp < 1 then room:recover { who = player, num = 1 - player.hp, recoverBy = player, skillName = zhenlei.name } end
end
zhenlei:addEffect("active", {
  anim_type = "support", card_num = 0, target_num = 0,
  can_use = function(self, player) return player:usedSkillTimes(zhenlei.name, Player.HistoryGame) == 0 end,
  on_use = function(self, room, effect) activate(effect.from) end,
})
zhenlei:addEffect(fk.EnterDying, {
  anim_type = "support",
  can_trigger = function(self, event, target, player, data)
    return target == player and player:hasSkill(zhenlei.name) and player:usedSkillTimes(zhenlei.name, Player.HistoryGame) == 0
  end,
  on_use = function(self, event, target, player, data) activate(player) end,
})
zhenlei:addEffect(fk.CardUsing, {
  can_refresh = function(self, event, target, player, data)
    return target == player and player:hasSkill(zhenlei.name)
  end,
  on_refresh = function(self, event, target, player, data)
    local room = player.room
    if data.card.type ~= Card.TypeEquip then room:addPlayerMark(player, count, 1) end
    if player:usedSkillTimes(zhenlei.name, Player.HistoryGame) > 0 and data:isUsingHandcard(player) and player.shield < player:getMark(count) then
      local extra = math.max(0, player:getMark(count) - 5)
      local old = player:getMark(bonus)
      if extra > old then
        room:addPlayerMark(player, MarkEnum.MaxShieldChanged, extra - old)
        room:setPlayerMark(player, bonus, extra)
      end
      room:changeShield(player, 1)
    end
  end,
})
zhenlei:addEffect(fk.Damaged, {
  can_refresh = function(self, event, target, player, data)
    return target == player and player:hasSkill(zhenlei.name) and data.damageType == fk.ThunderDamage and data.damage > 0
  end,
  on_refresh = function(self, event, target, player, data) player.room:setPlayerMark(player, currentDamage, 1) end,
})
zhenlei:addEffect(fk.RoundStart, {
  can_refresh = function(self, event, target, player, data) return player:hasSkill(zhenlei.name) end,
  on_refresh = function(self, event, target, player, data)
    local room = player.room
    room:setPlayerMark(player, previousDamage, player:getMark(currentDamage))
    room:setPlayerMark(player, currentDamage, 0)
    releaseShieldBonus(player)
  end,
})
zhenlei:addEffect(fk.TurnStart, {
  can_refresh = function(self, event, target, player, data)
    return target == player and player:hasSkill(zhenlei.name) and player:getMark(previousDamage) == 0
  end,
  on_refresh = function(self, event, target, player, data) player:setSkillUseHistory(zhenlei.name, 0, Player.HistoryGame) end,
})
pack:loadSkillSkels { leitong, zhenlei }
local general = General:new(pack, "xinyuesha__lusu", "wu", 4)
general:addSkills { leitong.name, zhenlei.name }
Fk:loadTranslationTable {
  ["xinyuesha_offline_lusu"] = "单机 · 九雷震鼓", ["xinyuesha__lusu"] = "鲁肃", ["xinyuesha"] = "九雷",
  ["#xinyuesha__lusu"] = "九雷震鼓", [leitong.name] = "雷同", [zhenlei.name] = "震雷",
  [":" .. leitong.name] = "锁定技，你使用锦囊牌造成的伤害视为雷电伤害。你使用牌时，若你使用的上一张牌未造成雷电伤害（首张牌视为未造成），你选择一至两名角色，分别对其造成1点雷电伤害。",
  [":" .. zhenlei.name] = "限定技，出牌阶段或你进入濒死时，你可以将体力回复至1点。发动后，每次使用手牌获得1点护甲，此技能获得护甲的上限为本轮使用的非装备牌次数（含回合外）。你的回合开始时，若上一轮未受到雷电伤害，重置此技能。",
  ["#xylusu-leitong"] = "雷同：选择一至两名角色，各造成1点雷电伤害",
}
return pack
