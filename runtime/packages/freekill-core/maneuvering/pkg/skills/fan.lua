local fanSkill = fk.CreateSkill {
  name = "#fan_skill",
  attached_equip = "fan",
}

fanSkill:addEffect(fk.AfterCardUseDeclared, {
  can_trigger = function(self, event, target, player, data)
    return target == player and player:hasSkill(fanSkill.name) and data.card.name == "slash"
  end,
  on_use = function(self, event, target, player, data)
    data:changeCard("fire__slash", data.card.suit, data.card.number, fanSkill.name)
  end,
})

fanSkill:addAI(Fk.Ltk.AI.newInvokeStrategy{
  think = function(self, ai)
    ---@type UseCardData
    local data = ai.room.logic:getCurrentEvent().data
    local new_data = table.simpleClone(data)
    local card = Fk:cloneCard("fire__slash", data.card.suit, data.card.number)
    if data.card:isVirtual() then
      card.subcards = data.card.subcards
    else
      card.id = data.card.id
    end
    card.virt_id = data.card.virt_id
    card.skillNames = data.card.skillNames
    new_data.card = card
    new_data.from = data.from
    new_data.tos = data.tos
    return ai:getBenefitOfEvents(function(logic)
      logic:useCard(new_data)
    end) >= ai:getBenefitOfEvents(function(logic)
      logic:useCard(data)
    end)
  end,
})

return fanSkill
