local lijian = fk.CreateSkill {
  name = "lijian",
}

lijian:addEffect("active", {
  anim_type = "offensive",
  prompt = "#lijian-active",
  max_phase_use_time = 1,
  card_num = 1,
  target_num = 2,
  card_filter = function(self, player, to_select, selected)
    return #selected == 0 and not player:prohibitDiscard(to_select)
  end,
  target_filter = function(self, player, to_select, selected)
    if #selected < 2 and to_select ~= player and to_select:isMale() then
      if #selected == 0 then
        return true
      else
        return to_select:canUseTo(Fk:cloneCard("duel"), selected[1])
      end
    end
  end,
  on_use = function(self, room, effect)
    local player = effect.from
    room:throwCard(effect.cards, lijian.name, player, player)
    local new_use = { ---@type UseCardDataSpec
      from = effect.tos[2],
      tos = { effect.tos[1] },
      card = Fk:cloneCard("duel", nil, nil, lijian.name),
      prohibitedCardNames = { "nullification" },
    }
    room:useCard(new_use)
  end,
  target_tip = function(self, _, to_select, selected, _, _, selectable, _)
    if not selectable then return end
    if #selected == 0 or (#selected > 0 and selected[1] == to_select) then
      return "use_to"
    else
      return "use_from"
    end
  end,
})

return lijian
