local SmartRez = _G.SmartRez

-- Item IDs that should be disenchanted, regardless of quality.
-- Add your exact itemIDs here.
local DISENCHANT_WHITELIST = {
  -- [12345] = true, -- Example item
  [244770] = true, -- Plate Stompers
  [245344] = true,
}

local function findDisenchantTarget()
  for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
      if itemInfo and DISENCHANT_WHITELIST[itemInfo.itemID] then
        return itemInfo.itemID
      end
    end
  end
end

local button = CreateFrame("Button", "DisenchantBtn", nil, "SecureActionButtonTemplate")
button:RegisterForClicks("AnyUp", "AnyDown")
button:SetAttribute("type", "macro")
button:SetScript("PreClick", function(self)
  if InCombatLockdown() then
    return
  end

  local itemID = findDisenchantTarget()
  if itemID then
    self:SetAttribute("macrotext", "/cast Disenchant\n/use item:" .. itemID)
  else
    self:SetAttribute("macrotext", nil)
  end
end)

SmartRez:RegisterBindableAction({
  key = "disenchant",
  label = "Disenchant",
  buttonName = "DisenchantBtn",
  order = 10,
})
