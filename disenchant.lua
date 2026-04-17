local SmartRez = _G.SmartRez
local DEBUG_DISENCHANT = false
local _C_GetBaseProfessionInfo = C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo
local _C_OpenTradeSkill = C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill
local button

local function debugPrint(...)
  if not DEBUG_DISENCHANT then
    return
  end

  print("Smart Rez DE:", ...)
end

local function findDisenchantTarget()
  local whitelist = SmartRez:GetDisenchantWhitelist()
  local target

  SmartRez:ForEachCraftingItemSourceSlot(function(bag, slot)
    local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
    if itemInfo and whitelist[itemInfo.itemID] then
      target = {
        itemID = itemInfo.itemID,
        bag = bag,
        slot = slot,
      }
      return true
    end
  end)

  return target
end

local function buildDisenchantMacroText(target)
  if not target or target.bag == nil or target.slot == nil then
    return nil
  end

  return string.format("/cast [nochanneling] Disenchant\n/use %d %d", target.bag, target.slot)
end

function SmartRez:HasDisenchantTarget()
  return findDisenchantTarget() ~= nil
end

function SmartRez:IsDisenchantLocked()
  return false
end

function SmartRez:PrepareDisenchantMacro()
  local enchantingProfessionID = SmartRez.Profession and SmartRez.Profession.Enchanting
  if enchantingProfessionID and _C_OpenTradeSkill then
    local professionInfo = _C_GetBaseProfessionInfo and _C_GetBaseProfessionInfo()
    if not professionInfo or professionInfo.professionID ~= enchantingProfessionID then
      _C_OpenTradeSkill(enchantingProfessionID)
      return nil
    end
  end

  local target = findDisenchantTarget()
  if not target then
    return nil
  end

  debugPrint("preclick item", target.itemID, "bag", target.bag, "slot", target.slot)
  return buildDisenchantMacroText(target)
end

button = CreateFrame("Button", "DisenchantBtn", nil, "SecureActionButtonTemplate")
button:RegisterForClicks("AnyDown")
button:SetAttribute("type", "macro")

button:SetScript("PreClick", function(self)
  if InCombatLockdown() then
    return
  end

  self:SetAttribute("macrotext", SmartRez:PrepareDisenchantMacro())
end)

button:SetScript("PostClick", function(self)
  self:SetAttribute("macrotext", nil)
end)

SmartRez:RegisterBindableAction({
  key = "disenchant",
  label = "Disenchant",
  buttonName = "DisenchantBtn",
  order = 10,
})
