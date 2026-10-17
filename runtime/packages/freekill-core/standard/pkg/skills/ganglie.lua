local ganglie = fk.CreateSkill({
  name = "ganglie",
})

ganglie:addEffect(fk.Damaged, {
  anim_type = "masochism",
  on_use = function(self, event, target, player, data)
    local room = player.room
    local from = data.from
    if from and not from.dead then room:doIndicate(player.id, {from.id}) end
    local judge = {
      who = player,
      reason = ganglie.name,
      pattern = ".|.|^heart",
    }
    room:judge(judge)
    if judge:matchPattern() and from and not from.dead then
      local discards = room:askToDiscard(from, {
        min_num = 2,
        max_num = 2,
        include_equip = false,
        skill_name = ganglie.name,
        cancelable = true,
      })
      if #discards == 0 then
        room:damage{
          from = player,
          to = from,
          damage = 1,
          skillName = ganglie.name,
        }
      end
    end
  end,
})

ganglie:addAI({
  think = function(self, ai)
    local cards = ai:getEnabledCards()
    if #cards < 2 then return "" end

    local cancel_val = ai:getBenefitOfEvents(function(logic)
      logic:damage{
        from = ai.room.logic:getCurrentEvent().data[2],
        to = ai.player,
        damage = 1,
        skillName = self.skill.name,
      }
    end)
    local to_discard, discard_val = ai:askToDiscard({
      min_num = 2,
      max_num = 2,
      skill_name = self.skill.name,
      cancelable = false,
    })

    if discard_val > cancel_val then
      return { cards = to_discard }
    else
      return ""
    end
  end,

  think_skill_invoke = function(self, ai, skill_name, prompt)
    ---@type DamageData
    local dmg = ai.room.logic:getCurrentEvent().data
    local from = dmg.from
    if not from or ai:isFriend(dmg.from) then return false end
    local dmg_val = ai:getBenefitOfEvents(function(logic)
      logic:damage{
        from = ai.player,
        to = from,
        damage = 1,
        skillName = self.skill.name,
      }
    end)
    local discard_val = ai:getBenefitOfEvents(function(logic)
      local cards = from:getCardIds("h")
      if #cards < 2 then
        logic.benefit = -1
        return
      end
      logic:throwCard(table.random(cards, 2), self.skill.name, from, from)
    end)
    if dmg_val > 0 or discard_val > 0 then
      return true
    end
    return false
  end,
})

return ganglie
