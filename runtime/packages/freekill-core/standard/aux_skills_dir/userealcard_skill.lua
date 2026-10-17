local useRealCardSkill = fk.CreateSkill{
  name = "userealcard_skill",
}

useRealCardSkill:addEffect("viewas", {
  card_filter = function (self, player, to_select, selected)
    return #selected == 0 and table.contains(self.cardIds or {}, to_select)
  end,
  view_as = function(self, player, cards)
    if #cards == 1 then
      return Fk:getCardById(cards[1])
    end
    return nil
  end,
})

useRealCardSkill:addAI(Fk.Ltk.AI.newActiveStrategy {
  think = function(self, ai)
    local ret, benefit = nil, 0
    for _, id in ipairs(ai:getEnabledCards()) do
      local card = Fk:getCardById(id)
      if card then
        ai:selectSkill(self.skill_name, true)
        ai:selectCard(id, true)
        for targets in self:searchTargetSelections(ai) do
          local tmp = ai:getBenefitOfEvents(function (logic)
            logic:useCard{
              from = ai.player,
              tos = targets or card:getDefaultTarget(ai.player),
              card = card,
            }
          end)
          if tmp > benefit then
            ret, benefit = { { id }, targets or {} }, tmp
          end
        end
        ai:unSelectAll()
      end
    end
    if ret then
      return ret, benefit
    end
  end,
})

return useRealCardSkill
