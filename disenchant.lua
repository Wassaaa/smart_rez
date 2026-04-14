local SmartRez = _G.SmartRez
local DEBUG_DISENCHANT = false
local button

local function debugPrint(...)
  if not DEBUG_DISENCHANT then
    return
  end

  print("Smart Rez DE:", ...)
end

local function findDisenchantTarget()
  local whitelist = SmartRez:GetDisenchantWhitelist()
  for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
      if itemInfo and whitelist[itemInfo.itemID] then
        return {
          itemID = itemInfo.itemID,
          bag = bag,
          slot = slot,
        }
      end
    end
  end
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
