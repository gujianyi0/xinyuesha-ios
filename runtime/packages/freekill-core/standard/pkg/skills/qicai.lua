local qicai = fk.CreateSkill{
  name = "qicai",
  tags = { Skill.Compulsory },
}

qicai:addEffect("targetmod", {
  bypass_distances = function(self, player, skill, card)
    return player:hasSkill(qicai.name) and card and card.type == Card.TypeTrick
  end,
})

return qicai
