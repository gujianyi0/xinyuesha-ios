local jianxiong = fk.CreateSkill{
  name = "jianxiong",
}

jianxiong:addEffect(fk.Damaged, {
  anim_type = "masochism",
  can_trigger = function(self, event, target, player, data)
    return target == player and player:hasSkill(jianxiong.name) and
      data.card and player.room:getCardArea(data.card) == Card.Processing
  end,
  on_use = function(self, event, target, player, data)
    player.room:obtainCard(player, data.card, true, fk.ReasonJustMove, player, jianxiong.name)
  end,
})

jianxiong:addAI(Fk.Ltk.AI.newInvokeStrategy{
  think = function(self, ai)
    ---@type DamageData
    local data = ai.room.logic:getCurrentEvent().data
    return ai:getBenefitOfEvents(function(logic)
      logic:obtainCard(ai.player, data.card, true, fk.ReasonJustMove, ai.player, jianxiong.name)
    end) >= 0
  end,
})

return jianxiong
