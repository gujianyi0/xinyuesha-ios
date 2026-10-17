local skill = fk.CreateSkill {
  name = "slash_skill",
}

skill:addEffect("cardskill", {
  prompt = function(self, player, selected_cards)
    local slash = Fk:cloneCard("slash")
    slash:addSubcards(selected_cards)
    local max_num = self:getMaxTargetNum(player, slash) -- halberd
    if max_num > 1 then
      local num = #table.filter(Fk:currentRoom().alive_players, function (p)
        return p ~= player and not player:isProhibited(p, slash)
      end)
      max_num = math.min(num, max_num)
    end
    return max_num > 1 and "#slash_skill_multi:::" .. max_num or "#slash_skill"
  end,
  max_phase_use_time = 1,
  target_num = 1,
  can_use = function(self, player, card, extra_data)
    if player:prohibitUse(card) then return end
    return (extra_data and extra_data.bypass_times) or player.phase ~= Player.Play or
      self:withinTimesLimit(player, Player.HistoryPhase, card, "slash") or
      table.find(Fk:currentRoom().alive_players, function(p)
        return p ~= player and self:withinTimesLimit(player, Player.HistoryPhase, card, "slash", p)
      end) ~= nil
  end,
  mod_target_filter = function(self, player, to_select, selected, card, extra_data)
    return to_select ~= player and
      not (not (extra_data and extra_data.bypass_distances) and not self:withinDistanceLimit(player, true, card, to_select))
  end,
  target_filter = function(self, player, to_select, selected, _, card, extra_data)
    if not Util.CardTargetFilter(self, player, to_select, selected, _, card, extra_data) then return end
    return self:modTargetFilter(player, to_select, selected, card, extra_data) and
      (
        #selected > 0 or
        player.phase ~= Player.Play or
        (extra_data and extra_data.bypass_times) or
        self:withinTimesLimit(player, Player.HistoryPhase, card, "slash", to_select)
      )
  end,
  on_effect = function(self, room, effect)
    if not effect.to.dead then
      room:damage({
        from = effect.from,
        to = effect.to,
        card = effect.card,
        damage = 1,
        damageType = fk.NormalDamage,
        skillName = skill.name,
      })
    end
  end,
})

skill:addAI(Fk.Ltk.AI.newCardSkillStrategy {
  keep_value = 3.6,
  use_value = 4.5,
  use_priority = 2.6,

  on_effect = function(self, logic, effect)
    logic:damage({
      from = effect.from,
      to = effect.to,
      card = effect.card,
      damage = 1,
      damageType = fk.NormalDamage,
      skillName = skill.name,
    })
  end,
})

return skill
