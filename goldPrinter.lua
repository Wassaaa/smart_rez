local SmartRez = _G.SmartRez

local SHARD_CRAFT_KEY = "shardcraft"
local SHATTERING_KEY = "enchanting"

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

dispatcher:RegisterForClicks("AnyUp", "AnyDown")
dispatcher:SetAttribute("type", "click")

SmartRez.goldPrinterPhase = SmartRez.goldPrinterPhase or PHASE_CRAFT
SmartRez.goldPrinterDebugState = SmartRez.goldPrinterDebugState or {}

local function debugPrint(...)
  if not (SmartRez.GetDebugEnabled and SmartRez:GetDebugEnabled()) then
    return
  end

  print("SmartRez GP:", ...)
end

local function debugStateChanged(key, ...)
  if not (SmartRez.GetDebugEnabled and SmartRez:GetDebugEnabled()) then
    return
  end

  local parts = { ... }
  local state = table.concat(parts, "|")
  if SmartRez.goldPrinterDebugState[key] == state then
    return
  end

  SmartRez.goldPrinterDebugState[key] = state
  print("SmartRez GP:", ...)
end

local function buildClickMacro(buttonName, down)
  if not buttonName or buttonName == "" then
    return nil
  end

  return "/click " .. buttonName .. " LeftButton " .. (down and "1" or "0")
end

local function refreshViews()
  if SmartRez.RefreshViews then
    SmartRez:RefreshViews()
  end
end

local function resetPhase()
  if SmartRez.goldPrinterPhase ~= PHASE_CRAFT then
    debugPrint("reset phase", SmartRez.goldPrinterPhase, "->", PHASE_CRAFT)
    SmartRez.goldPrinterPhase = PHASE_CRAFT
    refreshViews()
  end
end

local function advancePhase()
  local previousPhase = SmartRez.goldPrinterPhase
  if SmartRez.goldPrinterPhase == PHASE_CRAFT then
    SmartRez.goldPrinterPhase = PHASE_DISENCHANT
  elseif SmartRez.goldPrinterPhase == PHASE_DISENCHANT then
    SmartRez.goldPrinterPhase = PHASE_SHATTER
  else
    SmartRez.goldPrinterPhase = PHASE_CRAFT
  end

  debugPrint("advance phase", previousPhase, "->", SmartRez.goldPrinterPhase)
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
  if SmartRez.IsCraftRecipeActionBlocked and SmartRez:IsCraftRecipeActionBlocked(SHARD_CRAFT_KEY) then
    debugStateChanged("craftPhase", "craft phase blocked")
    return false, false
  end

  local hasFreeSlots = SmartRez:GetFreeBagSlots() > SmartRez:GetGoldPrinterMinFreeSlots()
  local hasTarget = SmartRez:GetCraftRecipeTarget(SHARD_CRAFT_KEY) ~= nil
  debugStateChanged("craftPhase", "craft phase", "freeSlotsOk", tostring(hasFreeSlots), "hasTarget", tostring(hasTarget))
  return hasFreeSlots and hasTarget, true
end

local function hasDisenchantWork()
  local hasTarget = SmartRez:HasDisenchantTarget()
  debugStateChanged("disenchantPhase", "disenchant phase", "locked", tostring(SmartRez:IsDisenchantLocked()), "hasTarget", tostring(hasTarget))
  return hasTarget
end

local function hasShatterWork()
  if SmartRez.IsCraftSalvageActionBlocked and SmartRez:IsCraftSalvageActionBlocked(SHATTERING_KEY) then
    debugStateChanged("shatterPhase", "shatter phase blocked")
    return false, false
  end

  local hasTarget = SmartRez:GetCraftSalvageTarget(SHATTERING_KEY) ~= nil
  debugStateChanged("shatterPhase", "shatter phase", "hasTarget", tostring(hasTarget))
  return hasTarget, true
end

local function getPhaseAction(phase)
  if phase == PHASE_CRAFT then
    local canCraft, phaseComplete = hasCraftWork()
    if canCraft then
      return {
        actionType = "macro",
        macroText = buildClickMacro("ShardCraftBtn", SmartRez:IsActiveCraftClickPhase(true)),
        targetName = "ShardCraftBtn",
      }
    end
    return nil, phaseComplete
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
    local canShatter, phaseComplete = hasShatterWork()
    if canShatter then
      return {
        actionType = "macro",
        macroText = buildClickMacro("ShatterBtn", SmartRez:IsActiveCraftClickPhase(true)),
        targetName = "ShatterBtn",
      }
    end
    return nil, phaseComplete
  end
end

local function chooseAction()
  for _ = 1, #PHASE_ORDER do
    local action, phaseComplete = getPhaseAction(SmartRez.goldPrinterPhase)
    if action then
      debugStateChanged("chooseAction", "choose action", SmartRez.goldPrinterPhase, action.actionType, action.targetName or "macro")
      return action
    end

    if not phaseComplete then
      debugStateChanged("chooseAction", "phase incomplete", SmartRez.goldPrinterPhase)
      return nil
    end

    advancePhase()
  end

  resetPhase()
  return nil
end

dispatcher:SetScript("PreClick", function(self, _, down)
  if not SmartRez:IsActiveCraftClickPhase(down) then
    return
  end

  if InCombatLockdown() then
    debugStateChanged("dispatch", "blocked in combat")
    return
  end

  local action = chooseAction()
  if not action then
    debugStateChanged("dispatch", "no action")
    self:SetAttribute("type", "macro")
    self:SetAttribute("macrotext", nil)
    return
  end

  if action.targetName then
    action.macroText = buildClickMacro(action.targetName, down)
  end

  debugStateChanged("dispatch", "dispatch macro", action.targetName or "custom")
  self:SetAttribute("type", "macro")
  self:SetAttribute("macrotext", action.macroText)
end)

dispatcher:SetScript("PostClick", function(self)
  if InCombatLockdown() then
    return
  end

  self:SetAttribute("type", "macro")
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
