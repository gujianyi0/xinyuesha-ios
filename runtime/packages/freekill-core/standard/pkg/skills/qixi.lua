local qixi = fk.CreateSkill {
  name = "qixi",
}

qixi:addEffect("viewas", {
  anim_type = "control",
  pattern = "dismantlement",
  prompt = "#qixi",
  -- mute_card = true,
  handly_pile = true,
  filter_pattern = {
    min_num = 1,
    max_num = 1,
    pattern = ".|.|black",
  },
  view_as = function(self, player, cards)
    if #cards ~= 1 then return end
    local c = Fk:cloneCard("dismantlement")
    c.skillName = qixi.name
    c:addSubcard(cards[1])
    return c
  end,
  enabled_at_response = function (self, player, response)
    return not response
  end
})

qixi:addAI(Fk.Ltk.AI.newActiveStrategy {
  think = function(self, ai)
    local ret, benefit = nil, -100000
    for _, id in ipairs(ai:getEnabledCards()) do
      local card = Fk.skills[self.skill_name]:viewAs(ai.player, { id })
      if card and ai:getCardValue(id) <= ai:getCardValue(card) then
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

return qixi
