local fanjian = fk.CreateSkill {
  name = "fanjian",
}

fanjian:addEffect("active", {
  anim_type = "offensive",
  prompt = "#fanjian-active",
  max_phase_use_time = 1,
  card_filter = Util.FalseFunc,
  target_filter = function(self, player, to_select, selected)
    return #selected == 0 and to_select ~= player
  end,
  target_num = 1,
  on_use = function(self, room, effect)
    local player = effect.from
    local target = effect.tos[1]
    local choice = room:askToChoice(target, {
      choices = { "log_spade", "log_heart", "log_club", "log_diamond" },
      skill_name = fanjian.name,
    })
    local card = room:askToChooseCard(target, {
      target = player,
      flag = "h",
      skill_name = fanjian.name,
    })
    local yes = Fk:getCardById(card):getSuitString(true) ~= choice
    room:obtainCard(target, card, true, fk.ReasonPrey, target, fanjian.name)
    if yes and not target.dead then
      room:damage {
        from = player,
        to = target,
        damage = 1,
        skillName = fanjian.name,
      }
    end
  end,
})

fanjian:addAI(Fk.Ltk.AI.newActiveStrategy {
  think = function(self, ai)
    local player = ai.player
    if ai.player:isKongcheng() or #ai:getEnabledTargets() == 0 then return {}, 0 end

    local ret, benefit = nil, 0
    for _, p in ipairs(ai:getEnabledTargets()) do
      local tmp = 0
      for _, id in ipairs(ai.player:getCardIds("h")) do
        tmp = tmp + ai:getBenefitOfEvents(function(logic)
          logic:moveCardTo(id, Card.PlayerHand, p, fk.ReasonGive)
          logic:damage {
            from = ai.player,
            to = p,
            damage = 1,
          }
        end)
      end
      tmp = tmp / player:getHandcardNum()
      if tmp > benefit then
        ret, benefit = p, tmp
      end
    end
    if ret then
      return { {}, { ret } }, benefit
    end
  end,
})

return fanjian
