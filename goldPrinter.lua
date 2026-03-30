local SmartRez = _G.SmartRez

local SHARD_CRAFT_KEY = "shardcraft"
local SHATTERING_KEY = "shattering"

local PHASE_CRAFT = "craft"
local PHASE_DISENCHANT = "disenchant"
local PHASE_SHATTER = "shatter"
local PHASE_ORDER = {
  PHASE_CRAFT,
  PHASE_DISENCHANT,
  PHASE_SHATTER,
}

local dispatcher = CreateFrame("Button", "GoldPrinterBtn", nil, "SecureActionButtonTemplate")
local stateFrame = CreateFrame("Frame")

dispatcher:RegisterForClicks("AnyDown")
dispatcher:SetAttribute("type", "click")

SmartRez.goldPrinterPhase = SmartRez.goldPrinterPhase or PHASE_CRAFT

local function refreshViews()
  if SmartRez.RefreshViews then
    SmartRez:RefreshViews()
  end
end

local function resetPhase()
  if SmartRez.goldPrinterPhase ~= PHASE_CRAFT then
    SmartRez.goldPrinterPhase = PHASE_CRAFT
    refreshViews()
  end
end

local function advancePhase()
  if SmartRez.goldPrinterPhase == PHASE_CRAFT then
    SmartRez.goldPrinterPhase = PHASE_DISENCHANT
  elseif SmartRez.goldPrinterPhase == PHASE_DISENCHANT then
    SmartRez.goldPrinterPhase = PHASE_SHATTER
  else
    SmartRez.goldPrinterPhase = PHASE_CRAFT
  end

  refreshViews()
end

local function getPhaseLabel(phase)
  if phase == PHASE_CRAFT then
    return "Crafting"
  end

  if phase == PHASE_DISENCHANT then
    return "Disenchanting"
  end

  if phase == PHASE_SHATTER then
    return "Shattering"
  end

  return "Idle"
end

local function hasCraftWork()
  return SmartRez:GetFreeBagSlots() > SmartRez:GetGoldPrinterMinFreeSlots()
    and SmartRez:GetCraftRecipeTarget(SHARD_CRAFT_KEY) ~= nil
end

local function hasDisenchantWork()
  return SmartRez:HasDisenchantTarget()
end

local function hasShatterWork()
  return SmartRez:GetCraftSalvageTarget(SHATTERING_KEY) ~= nil
end

local function getPhaseAction(phase)
  if phase == PHASE_CRAFT then
    if hasCraftWork() then
      return {
        actionType = "click",
        target = _G["ShardCraftBtn"],
      }
    end
    return nil, true
  end

  if phase == PHASE_DISENCHANT then
    if SmartRez:IsDisenchantLocked() then
      return nil, false
    end

    if hasDisenchantWork() then
      local macroText = SmartRez:PrepareDisenchantMacro()
      if macroText then
        return {
          actionType = "macro",
          macroText = macroText,
        }
      end
      return nil, false
    end
    return nil, true
  end

  if phase == PHASE_SHATTER then
    if hasShatterWork() then
      return {
        actionType = "click",
        target = _G["ShatterBtn"],
      }
    end
    return nil, true
  end
end

local function chooseAction()
  for _ = 1, #PHASE_ORDER do
    local action, phaseComplete = getPhaseAction(SmartRez.goldPrinterPhase)
    if action then
      return action
    end

    if not phaseComplete then
      return nil
    end

    advancePhase()
  end

  resetPhase()
  return nil
end

dispatcher:SetScript("PreClick", function(self)
  if InCombatLockdown() then
    return
  end

  local action = chooseAction()
  if not action then
    self:SetAttribute("type", "click")
    self:SetAttribute("clickbutton", nil)
    self:SetAttribute("macrotext", nil)
    return
  end

  if action.actionType == "macro" then
    self:SetAttribute("type", "macro")
    self:SetAttribute("clickbutton", nil)
    self:SetAttribute("macrotext", action.macroText)
    return
  end

  self:SetAttribute("type", "click")
  self:SetAttribute("clickbutton", action.target)
  self:SetAttribute("macrotext", nil)
end)

dispatcher:SetScript("PostClick", function(self)
  if InCombatLockdown() then
    return
  end

  self:SetAttribute("type", "click")
  self:SetAttribute("clickbutton", nil)
  self:SetAttribute("macrotext", nil)
end)

stateFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
stateFrame:SetScript("OnEvent", function(_, eventName)
  if eventName == "PLAYER_ENTERING_WORLD" then
    resetPhase()
  end
end)

SmartRez:RegisterBindableAction({
  key = "goldprinter",
  label = "Gold Printer",
  buttonName = "GoldPrinterBtn",
  order = 5,
})

function SmartRez:GetGoldPrinterPhase()
  return SmartRez.goldPrinterPhase or PHASE_CRAFT
end

function SmartRez:GetGoldPrinterPhaseLabel()
  return getPhaseLabel(self:GetGoldPrinterPhase())
end
