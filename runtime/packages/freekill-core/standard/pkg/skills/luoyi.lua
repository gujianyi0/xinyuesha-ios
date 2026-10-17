local luoyi = fk.CreateSkill {
  name = "luoyi",
}

luoyi:addEffect(fk.DrawNCards, {
  anim_type = "offensive",
  can_trigger = function(self, event, target, player, data)
    return target == player and player:hasSkill(luoyi.name) and data.n > 0
  end,
  on_use = function(self, event, target, player, data)
    data.n = data.n - 1
  end,
})

luoyi:addEffect(fk.DamageCaused, {
  anim_type = "offensive",
  is_delay_effect = true,
  can_trigger = function(self, event, target, player, data)
    return player:usedSkillTimes(luoyi.name, Player.HistoryTurn) > 0 and target == player and
      data.card and (data.card.trueName == "slash" or data.card.name == "duel") and data.by_user
  end,
  on_cost = Util.TrueFunc,
  on_use = function(self, event, target, player, data)
    data:changeDamage(1)
  end,
})

luoyi:addAI(Fk.Ltk.AI.newInvokeStrategy{
  think = function(self, ai)
    return #table.filter(ai.player:getHandlyIds(), function (id)
      return Fk:getCardById(id).trueName == "slash" or Fk:getCardById(id).name == "duel"
    end) > 0
  end,
})

return luoyi
