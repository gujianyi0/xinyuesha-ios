-- SPDX-License-Identifier: GPL-3.0-or-later

---@class SmartAI.Memory : { [string]: any }
---@field intentionScore table<SmartAI.Intention, number> 行动意向打分

---@class SmartAI: TrustAI, AIUtil
---@field public mem SmartAI.Memory @ 暂存某些值避免重复计算
local SmartAI = TrustAI:subclass("SmartAI")

local AIUtil = require 'ltk.server.ai.util'
SmartAI:include(AIUtil)

local AIGameLogic, AIGameEvent = require "ltk.server.ai.logic"
local AI = require "ltk.server.ai.strategies"

function SmartAI:initialize(player)
  TrustAI.initialize(self, player)
end

function SmartAI:makeReply()
  self.mem = setmetatable({}, { __mode = "k" })
  return TrustAI.makeReply(self)
end

--- 解析对整个策略的复用，技能和类型由spec指定
---@param spec AIReuseSpec
---@param stack any? 避免循环依赖
---@return AIStrategy?
local function resolveStrategyReuse(spec, stack)
  stack = stack or {}
  if stack[spec] then
    fk.qWarning("AI strategy reuse loop detected (=> %s)", spec._reuse_key)
    return nil
  end
  stack[spec] = true

  local skill = Fk.skills[spec._reuse_key]
  if not skill then return end
  local skel = skill:getSkeleton()
  if not skel then return end

  local resolved
  local reuse_tp = spec._reuse_type
  if not reuse_tp then
    fk.qWarning("reuse: no strategy type specified")
    stack[spec] = nil
    return nil
  end

  local list = skel.ai_strategies[reuse_tp] or Util.DummyTable
  resolved = list[1]
  if not resolved then
    fk.qWarning("reuse: failed to reuse %s (=>%s)", tostring(reuse_tp), spec._reuse_key)
    stack[spec] = nil
    return nil
  end

  local reuse = resolved --[[@as AIReuseSpec]]
  if reuse._reuse then
    resolved = resolveStrategyReuse(reuse, stack) --[[@as AIStrategy]]
    list[1] = resolved
  end

  stack[spec] = nil
  return resolved
end

--- 解析策略的某个字段的复用
---@param spec AIReuseSpec
---@param tp AIStrategy 类型
---@param key string 字段名
---@param stack any? 避免循环依赖
---@return any
local function resolveFieldReuseOfStrategy(spec, tp, key, stack)
  stack = stack or {}
  if stack[spec] then
    fk.qWarning("AI strategy reuse loop detected (=> %s)", spec._reuse_key)
    return nil
  end
  stack[spec] = true

  local skill = Fk.skills[spec._reuse_key]
  if not skill then return end
  local skel = skill:getSkeleton()
  if not skel then return end

  local resolved

  local list = skel.ai_strategies[tp] or Util.DummyTable
  if not list[1] then return end
  resolved = list[1][key]
  if not resolved then
    fk.qWarning("reuse: failed to reuse %s (=>%s)", tostring(tp), spec._reuse_key)
    stack[spec] = nil
    return nil
  end

  local reuse = resolved --[[@as AIReuseSpec]]
  if type(reuse) == "table" and reuse._reuse then
    resolved = resolveFieldReuseOfStrategy(reuse, tp, key, stack) --[[@as AIStrategy]]
    list[1][key] = resolved
  end

  stack[spec] = nil
  return resolved
end

--- 根据给定的类别、技能名，找到符合目前询问上下文的策略。
---
--- 如果有需要的话，会解析复用的策略/方法等。
---@generic T: AIStrategy
---@param tp T
---@param skill_name string
---@return T?
function SmartAI:findStrategyOfSkill(tp, skill_name)
  local skill = Fk.skills[skill_name]
  if not skill then return end
  local skel = skill:getSkeleton()
  if not skel then return end
  local list = skel.ai_strategies[tp] or Util.DummyTable

  local ret
  for i = #list, 1, -1 do
    local tmp = list[i] --[[@as AIReuseSpec]]
    local v
    if tmp._reuse then
      local t = resolveStrategyReuse(tmp)
      if t then
        v = t
        list[i] = t
      else
        table.remove(list, i)
      end
    else
      v = list[i]
    end

    if v and v:matchContext(self) then
      ret = v
      break
    end
  end
  if not ret then return nil end

  if ret._resolved then return ret end

  -- 确保找到的ret没有复用字段，可以直接拿来用了
  for k in pairs(ret) do
    local tmp = ret[k] --[[@as AIReuseSpec]]
    if type(tmp) == "table" and tmp._reuse then
      ret[k] = resolveFieldReuseOfStrategy(tmp, tp, k)
      -- 如果方法变成nil的话 会自动调这个class的默认方法的
    end
  end

  return ret
end

---@type table<string, SkillAI>
fk.ai_skills = {}

---@param key string
---@param spec? SkillAISpec
---@param inherit? string
function SmartAI.static:setSkillAI(key, spec, inherit)
  do return end
end

SmartAI:setSkillAI("__card_skill", {
  choose_targets = function(self, ai)
    -- local targets = ai:getEnabledTargets()
    local logic = AIGameLogic:new(ai)
    local val_func = function(targets)
      logic.benefit = 0
      logic:useCard({
        from = ai.player,
        tos = targets,
        card = ai:getSelectedCard(),
      })
      if self._debug then
        verbose(1, "目前状况下，对[%s]的预测收益为%g", table.concat(table.map(targets, function(p)return tostring(p)end), "+"), logic.benefit)
      end
      return logic.benefit
    end
    local best_targets, best_val = nil, -100000
    for targets in self:searchTargetSelections(ai) do
      local val = val_func(targets)
      if (not best_targets) or (best_val < val) then
        best_targets, best_val = targets, val
      end
    end
    return best_targets or {}, best_val
  end,

  think = function(self, ai)
  end,
})

function SmartAI.static:setCardSkillAI(key, spec, key2)
  do return end
end

SmartAI:setCardSkillAI("default_card_skill", {
  on_use = function(self, logic, effect)
    self.skill:onUse(logic, effect)
  end,
  on_effect = function(self, logic, effect)
    self.skill:onEffect(logic, effect)
  end,
})

---@type table<string, TriggerSkillAI>
fk.ai_trigger_skills = {}

function SmartAI.static:setTriggerSkillAI(key, spec)
  do return end
end

function SmartAI:handleAskForUseActiveSkill()
  local name = self.handler.skill_name

  local ai
  if self:currentSkill() then
    ai = self:findStrategyOfSkill(AI.ActiveStrategy, self:currentSkill().name)
  end
  if not ai then
    ai = self:findStrategyOfSkill(AI.ActiveStrategy, name)
  end
  if not ai then return "" end
  local _dbg_skill = ai.skill and ai.skill.name or "unknown"
  if self._debug then
    verbose(1, "正在询问技能：%s", _dbg_skill)
  end
  local ret, real_val = ai:makeReply(self)
  if self._debug then
    verbose(1, "%s: 思考结果是%s, 收益是%s", _dbg_skill, json.encode(ret), json.encode(real_val))
  end
  return ret, real_val
end

-- 出牌阶段AI的步骤是：
-- 1. 分析手中的手牌、技能按钮以及局势，判断出本次行动意向：
-- 爆发（获得尽量多的牌）、控制（压制敌方状态）、增强（为友方加进攻buff）、进攻（削减敌人生命）、辅助（为友方加防御buff）
-- 2. 将可用方案按优先级排序，根据之前推测出的趋向，某些优先级会被修正
-- 4. 计算优先级最高的3个方案及其收益
--  * 收益值也会被意向值修正
--  * 如果都为负收益则顺延直到有3个正收益选项
--  * 如果依然全部为负收益则与直接点击取消键的收益进行权衡
-- 5. 返回收益最高者
--
-- 推算的相关中间变量都保存在self.mem中，方便各种和ai相关的函数读取。
-- self.mem在每次思考最开始时自动清空。单独开class方便编辑器补全
--====================

---@alias SmartAI.Intention "burst"|"control"|"strengthen"|"attack"|"support"

-- 行动意向评分表保存在mem中。意向评分受可用技能和局势影响，局势判断可以先写死，而技能需要提供自身的功能倾向
--  e.g.刘备有一张无中生有，队友黄月英，方案1开无中并仁德，方案2直接仁德。无中和集智是burst，仁德是support
-- 考虑最佳策略受到局势影响（刘备是否健康，黄月英能否存活到回合，甚至透视无中和集智摸的牌）。简单做法先burst后support，总是还不错的方案
-- 但也可以把仁德收益写得特别高，这样ai会先考虑给牌。取决于编写者的个人喜好

function SmartAI:initIntentionScore()
  if self.mem.intentionScore then return end
  self.mem.intentionScore = {}
end

function SmartAI:handlePlayCard()
  local active_strategy_list = {} ---@type AI.ActiveStrategy[]
  do
    for _, sname in ipairs(self:getEnabledSkills()) do
      local ai = self:findStrategyOfSkill(AI.ActiveStrategy, sname)
      if ai then
        table.insert(active_strategy_list, ai)
      end
    end

    local tmp = {}
    for _, id in ipairs(self:getEnabledCards()) do
      local cd = Fk:getCardById(id)
      tmp[cd.skill.name] = true
    end

    for sname in pairs(tmp) do
      local ai = self:findStrategyOfSkill(AI.CardSkillStrategy, sname)
      if ai then
        table.insert(active_strategy_list, ai)
      end
    end
  end

  if self._debug then
    verbose(1, "======== %s: 开始计算出牌阶段 ========", tostring(self))
  end

  local best_ret, best_val, count = "", -1, 0
  if self._debug then
    verbose(1, "目前的决策：直接取消(收益%g)", best_val)
  end
  for _, ai in fk.sorted_pairs(active_strategy_list, function(a) return a.use_priority end) do
    self:selectSkill(ai.skill_name, true)

    local ret, real_val = ai:makeReply(self)
    if self._debug then
      verbose(1, "%s: 思考结果是%s, 收益是%s", ai.skill_name, json.encode(ret), json.encode(real_val))
    end
    real_val = real_val or -100000

    if best_val < real_val then
      if self._debug then
        verbose(1, "将决策%s换成更好的%s (收益%g => %g)", json.encode(best_ret), json.encode(ret), best_val, real_val)
      end
      best_ret, best_val = ret, real_val

      --只想20种比较好的决策
      count = count + 1
      if count > 20 then
        break
      end
    end
    self:unSelectAll()
  end

  if best_val >= 0 and best_ret ~= "" then
    if self._debug then
      verbose(1, "推测出最佳决策是%s", json.encode(best_ret))
    end
    return best_ret
  end

  return ""
end

---------------------------------------------------------------------

-- 其他交互：不涉及面板而是基于弹窗式的交互
-- SkillAI里面每个command给个方法
-- ========================================

function SmartAI:handleAskForCardChosen(data)
  local target, card_data, prompt = table.unpack(data)
  local reason = prompt:split(":")[4]
  local ai = self:findStrategyOfSkill(AI.CardChosenStrategy, reason)
  if ai then
    if self._debug then
      verbose(1, "正在询问技能：%s, %s", ai.skill_name, prompt)
    end
    local ret, real_val = ai:makeReply(self)
    if self._debug then
      verbose(1, "%s: 思考结果是%s, 收益是%s", ai.skill_name, json.encode(ret), real_val)
    end
    return ret
  end
end

function SmartAI:handleAskForSkillInvoke(data)
  local skillName, prompt = data[1], data[2]
  local ai = self:findStrategyOfSkill(AI.InvokeStrategy, skillName)
  if ai then
    if self._debug then
      verbose(1, "正在询问技能：%s, %s", skillName, prompt)
    end
    local ret = ai:makeReply(self)
    if self._debug then
      verbose(1, "%s: 思考结果是%s", skillName, json.encode(ret))
    end
    return ret and "1" or ""
  else
    return ""
  end
end

function SmartAI:handleAskForChoice(data)
  local choices, allChoices, skillName, prompt = table.unpack(data)
  local ai = self:findStrategyOfSkill(AI.ChoiceStrategy, skillName)
  if ai then
    if self._debug then
      verbose(1, "正在询问技能：%s, 可选选项列表：%s", ai.skill_name, table.concat(choices, "+"))
    end
    local ret, real_val = ai:makeReply(self)
    if self._debug then
      verbose(1, "%s: 思考结果是%s, 收益是%s", ai.skill_name, json.encode(ret), real_val)
    end
    return ret or choices[1]
  else
    return choices[1]
  end
end

function SmartAI:handleAskForUseCard(data)
  local card_ids = self:getEnabledCards()
  local skill_name, pattern, prompt = data[1], data[2], data[3]
  if pattern == "jink" then
    for _, id in ipairs(card_ids) do
      self:selectCard(id, true) -- 默认按下卡牌后直接可确定 懒得管了
      return self:doOKButton()
    end
  elseif pattern == "nullification" then
    local from, to, card
    if data[5] and data[5].effectFrom then
      if data[5].effectFrom then
        from = self.room:getPlayerById(data[5].effectFrom)
      end
      if data[5].effectCardId then
        card = Fk:getCardById(data[5].effectCardId)
      end
    end
    to = prompt:startsWith("#AskForNullificationWithoutTo") and prompt:split(":")[2] or prompt:split(":")[3]
    if to then
      to = self.room:getPlayerById(tonumber(to))
    end
    if from and to and card then
      local benefit = self:getBenefitOfEvents(function(logic)
        logic:useCard{
          from = from,
          tos = { to },
          card = card,
        }
      end)
      if benefit < 0 then
        for _, id in ipairs(card_ids) do
          self:selectCard(id, true)
          return self:doOKButton()
        end
      end
    else
      if to and self:isFriend(to) then
        for _, id in ipairs(card_ids) do
          self:selectCard(id, true)
          return self:doOKButton()
        end
      end
    end
    return ""
  elseif pattern:startsWith("peach") then
    local to = prompt:startsWith("#AskForPeachesSelf") and self.player.id or prompt:split(":")[2]
    if to then
      to = self.room:getPlayerById(tonumber(to))
      if self:isFriend(to) then
        for _, cd in ipairs(card_ids) do
          self:selectCard(cd, true)
          return self:doOKButton()
        end
      end
    end
    return ""
  end

  local skill_ai_list = {}
  for _, id in ipairs(card_ids) do
    local cd = Fk:getCardById(id)
    local ai = fk.ai_skills[cd.skill.name]
    if ai then
      table.insertIfNeed(skill_ai_list, ai)
    end
  end
  for _, sname in ipairs(self:getEnabledSkills()) do
    local ai = fk.ai_skills[sname]
    if ai then
      table.insertIfNeed(skill_ai_list, ai)
    end
  end
  if self._debug then
    verbose(1, "======== %s: 开始计算出牌阶段 ========", tostring(self))
    verbose(1, "待选技能：[%s]", table.concat(table.map(skill_ai_list, function(ai) return ai.skill.name end), ", "))
  end

  local value_func = function(ai)
    if not ai then return -500 end
    local val = ai:getEstimatedBenefit(self)
    return val or 0
  end

  local best_ret, best_val = "", -100000
  for _, ai, val in fk.sorted_pairs(skill_ai_list, value_func) do
    if self._debug then
      verbose(1, "[*] 考虑 %s (预估收益%g)", ai.skill.name, val)
    end
    self:selectSkill(ai.skill.name, true)
    local ret, real_val = ai:think(self)
    if self._debug then
      verbose(1, "%s: 思考结果是%s, 收益是%s", ai.skill.name, json.encode(ret), json.encode(real_val))
    end
    real_val = real_val or -100000
    -- if ret and ret ~= "" then return ret end
    if best_val < real_val then
      if self._debug then
        verbose(1, "将决策%s换成更好的%s (收益%g => %g)", json.encode(best_ret), json.encode(ret), best_val, real_val)
      end
      best_ret, best_val = ret, real_val
    end
    self:unSelectAll()
  end
  if self._debug then
    verbose(1, "推测出最佳决策是%s", json.encode(best_ret))
  end
  if best_ret and best_ret ~= "" then return best_ret end
  return ""
end

-- 敌友判断相关。
-- 目前才开始，做个明身份打牌的就行了。
--========================================

---@param target ServerPlayer
function SmartAI:isFriend(target)
  return self.player:isFriend(target)
end

---@param target ServerPlayer
function SmartAI:isEnemy(target)
  return not self.player:isFriend(target)
end

-- 排序相关函数。
-- 众所周知AI要排序，再选出尽可能最佳的选项。
-- 这里提供了常见的完整排序和效率更高的不完整排序。
--=================================================

-- sorted_pairs 见 core/util.lua

---@param tab ServerPlayer[]
---@param key "hp"|"handcard"|"handcard_defense"|"value"|"taunt"|"defense"|"threat"
---@param reverse boolean?
function SmartAI:sortPlayers(tab, key, reverse)
end

---@param card integer|Card
---@param key "keep_value"|"use_value"|nil
---@return number
function SmartAI:getCardValue(card, key)
  if type(card) == "number" then
    card = Fk:getCardById(card)
  end
  ---@cast card -integer

  local strategy = self:findStrategyOfSkill(AI.CardSkillStrategy, card.skill.name)
  local ret = 0
  if strategy then
    -- TODO: 可能可以是function
    ret = strategy.keep_value
  end

  -- TODO: 可能可以类似状态技一样给Room挂点状态技性质策略
  -- TODO: 这样那些策略会影响某些卡的keep value

  return ret
end

-- 将卡牌id数组按照某种估值从小到大原地排序
---@param ids integer[]
---@param key "keep_value"|"use_value"|"use_priority"
---@param reverse boolean? 是否反过来（从大到小）排序
function SmartAI:sortCards(ids, key, reverse)
  -- value_tab是必须的，因为table.sort每轮比较时都会调用一次fun(a,b)
  -- 太阳神卡慢的点之一就是没有提前计算出结果
  local value_tab = {}
  for _, id in ipairs(ids) do
    value_tab[id] = self:getCardValue(id)
  end

  table.sort(ids, function(a, b)
    local va, vb = value_tab[a], value_tab[b]
    if reverse then
      return va > vb
    else
      return va < vb
    end
  end)
end

-- 基于事件的收益推理；内置事件
--=================================================

--- 传一个函数，函数里面模拟操作，返回一系列模拟操作后的收益
---@param fn fun(logic: AIGameLogic) 此函数放置想要的事件
function SmartAI:getBenefitOfEvents(fn)
  local logic = AIGameLogic:new(self)
  fn(logic)
  return logic.benefit
end

---------------------------------------------------------------------

-- 封装一些简单策略
-- ========================================

---@class AIAskToChooseCardsParams
---@field cards integer[] @ 被选择的牌
---@field skill_name string @ 请求发动的技能名
---@field data table @ 用moveCardTo的参数表示这些牌即将被用来做什么操作

--- 选牌
---@param params AIAskToChooseCardsParams @ 各种变量
---@return integer[], integer @ 返回本次选牌收益最大的一种情况，选择的卡牌和收益
function SmartAI:askToChooseCards(params)
  local skill_name, data = params.skill_name, params.data
  data.min = data.min or 1
  data.max = data.max or data.min
  local cards = table.simpleClone(params.cards)
  local ret, benefit = { }, -100000
  for _ = data.max, 1, -1 do
    local tmp_id, tmp_benefit = -1, -100000
    for _, id in ipairs(cards) do
      local v = self:getBenefitOfEvents(function(logic)
        logic:moveCardTo(id, data.toArea, data.target, data.reason, skill_name, nil, false, data.proposer)
      end)
      if v > tmp_benefit then
        tmp_id, tmp_benefit = id, v
      end
    end
    table.insertIfNeed(ret, tmp_id)
    benefit = benefit + tmp_benefit
    table.removeOne(cards, tmp_id)
  end
  return ret, benefit
end

---@class AIAskToChoosePlayersParams
---@field benefit_func function @ 计算选这些角色收益的函数
---@field basic_benefit integer? @ 基础收益，默认为0（如“突袭”的基础收益是放弃摸牌）

--- 选角色
---@param params AIAskToChoosePlayersParams @ 各种变量
---@return ServerPlayer[], integer @ 返回本次选角色收益最大的一种情况，选择的角色和收益
function SmartAI:askToChoosePlayers(params)
  params.skill_name = params.skill_name or ""
  if params.cancelable then
    params.min_num = 0
  else
    params.min_num = params.min_num or 1
  end
  params.max_num = params.max_num or params.min_num
  local players = table.simpleClone(params.targets or self:getEnabledTargets())
  local benefits = table.map(players, function(p)
    return { p, self:getBenefitOfEvents(function(logic)
      params.benefit_func(logic, p)
    end) }
  end)
  local total_benefit = params.basic_benefit or 0
  local targets = {}
  table.sort(benefits, function(a, b) return a[2] > b[2] end)
  for i, benefit in ipairs(benefits) do
    local p, val = table.unpack(benefit)
    if val < 0 and i > params.min_num then break end
    table.insert(targets, p)
    total_benefit = total_benefit + val
    if i == params.max_num then break end
  end
  if #targets == 0 then return {}, 0 end
  return targets, total_benefit
end

-- 局势分析
--========================================

-- AI需要“帮助”某玩家的程度
---@param target ServerPlayer
---@param key string?
---@return number
function SmartAI:needHelp(target, key)
  local keys = { "hp", "h", "e" }
  if key then
    keys = string.split(key, "|")
  end
  local n = 0
  if table.contains(keys, "hp") then
    n = n + 200 * (target.maxHp - target.hp - target.shield)
  end
  if table.contains(keys, "h") then
    for _, id in ipairs(target:getCardIds("h")) do
      n = n + target.ai:getCardValue(id)
    end
  end
  if table.contains(keys, "e") then
    for _, id in ipairs(target:getCardIds("e")) do
      n = n + target.ai:getCardValue(id)
    end
  end
  if self.player:isEnemy(target) then
    n = -n
  end
  return n
end

return SmartAI
