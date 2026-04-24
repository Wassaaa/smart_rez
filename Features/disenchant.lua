local SmartRez = _G.SmartRez

local C_Container = C_Container
local C_CVar = C_CVar
local C_TradeSkillUI = C_TradeSkillUI
local C_Item = C_Item
local CreateFrame = CreateFrame
local GetCVar = GetCVar
local GetLootSlotInfo = GetLootSlotInfo
local GetNumLootItems = GetNumLootItems
local InCombatLockdown = InCombatLockdown
local LootSlot = LootSlot
local CloseLoot = CloseLoot
local UIErrorsFrame = UIErrorsFrame

local DISENCHANT_SPELL_ID = 13262
---@class SmartRezDisenchantSlotState
---@field bag integer
---@field slot integer
---@field itemID integer
---@field isLocked boolean
---@field isBeingDisenchanted boolean

local DE = {
  trackedSlots = {},
  buttonClicked = false,
  clickedBagSlot = nil,
  disenchantCasting = false,
  disenchantCastSuccess = false,
  lootingInProgress = false,
  materialsWaiting = false,
  defaultAutoLootDisabled = false,
  verifiedItemID = nil,
  itemVerified = false,
  verificationError = nil,
  itemDisenchantability = {},
}

DE.HiddenTooltip = CreateFrame("GameTooltip", "SmartRezDisenchantHiddenTooltip", UIParent, "GameTooltipTemplate")
DE.HiddenTooltip:SetOwner(UIParent, "ANCHOR_NONE")

DE.HotkeyButton = CreateFrame("Button", "DisenchantBtn", UIParent, "SecureActionButtonTemplate")
DE.HotkeyButton:RegisterForClicks("AnyUp", "AnyDown")
DE.HotkeyButton:SetAttribute("type1", "macro")

DE.MainButton = CreateFrame("Button", "SmartRezDisenchantMainButton", UIParent, "SecureActionButtonTemplate")
DE.MainButton:RegisterForClicks("AnyUp", "AnyDown")
DE.MainButton:SetAttribute("type1", "macro")

DE.VerifyButton = CreateFrame("Button", "SmartRezDisenchantVerifyButton", UIParent, "SecureActionButtonTemplate")
DE.VerifyButton:RegisterForClicks("AnyUp", "AnyDown")
DE.VerifyButton:SetAttribute("type", "spell")
DE.VerifyButton:SetAttribute("spell", tostring(DISENCHANT_SPELL_ID))

DE.SpellButton = CreateFrame("Button", "SmartRezDisenchantSpellButton", UIParent, "SecureActionButtonTemplate")
DE.SpellButton:RegisterForClicks("AnyUp", "AnyDown")
DE.SpellButton:SetAttribute("type", "spell")

DE.Events = CreateFrame("Frame", "SmartRezDisenchantEvents", UIParent)

local function getBagSlotKey(bag, slot)
  return string.format("%d %d", bag, slot)
end

local function setAutoLootDefault(value)
  if C_CVar and C_CVar.SetCVar then
    C_CVar.SetCVar("autoLootDefault", tostring(value))
    return
  end

  SetCVar("autoLootDefault", tostring(value))
end

local function getClickSuffix()
  if GetCVar("ActionButtonUseKeyDown") == "1" then
    return " LeftButton 1"
  end

  return ""
end

local function debugDisenchant(message, ...)
  if not SmartRez.GetDebugEnabled or not SmartRez:GetDebugEnabled() then
    return
  end

  if select("#", ...) > 0 then
    print(string.format("SmartRez DE: " .. message, ...))
    return
  end

  print("SmartRez DE: " .. message)
end

local function scanTooltipForDisenchantability(itemID)
  if not itemID then
    return false
  end

  DE.HiddenTooltip:SetItemByID(itemID)

  for lineIndex = 1, DE.HiddenTooltip:NumLines() do
    local textRegion = _G[DE.HiddenTooltip:GetName() .. "TextLeft" .. lineIndex]
    local line = textRegion and textRegion:GetText()
    if line and string.find(line, ITEM_DISENCHANT_NOT_DISENCHANTABLE, 1, true) then
      return false
    end
  end

  return true
end

local function isConfiguredKeyDown()
  return GetCVar("ActionButtonUseKeyDown") == "1"
end

local function isActiveClickPhase(down)
  return (down == true) == isConfiguredKeyDown()
end

function DE:ResetVerification(itemID)
  if self.verifiedItemID ~= itemID then
    self.verifiedItemID = itemID
    self.itemVerified = false
    self.verificationError = nil
  end
end

function DE:ResetTrackedSlots()
  for _, slotState in pairs(self.trackedSlots) do
    slotState.isLocked = false
    slotState.isBeingDisenchanted = false
  end
end

function DE:ResetSession()
  self.buttonClicked = false
  self.clickedBagSlot = nil
  self.disenchantCasting = false
  self.disenchantCastSuccess = false
  self.lootingInProgress = false
  self.materialsWaiting = false
  self.defaultAutoLootDisabled = false
  self:ResetTrackedSlots()
end

function DE:RegisterDisenchantingEvents()
  self.Events:RegisterEvent("ITEM_LOCKED")
  self.Events:RegisterEvent("ITEM_UNLOCKED")
  self.Events:RegisterEvent("ITEM_PUSH")
  self.Events:RegisterEvent("LOOT_READY")
  self.Events:RegisterEvent("LOOT_OPENED")
  self.Events:RegisterEvent("LOOT_CLOSED")
end

function DE:UnregisterDisenchantingEvents()
  self.Events:UnregisterEvent("ITEM_LOCKED")
  self.Events:UnregisterEvent("ITEM_UNLOCKED")
  self.Events:UnregisterEvent("ITEM_PUSH")
  self.Events:UnregisterEvent("LOOT_READY")
  self.Events:UnregisterEvent("LOOT_OPENED")
  self.Events:UnregisterEvent("LOOT_CLOSED")
end

function DE:IsTrackedSlotBlocked(bag, slot, itemInfo)
  local slotKey = getBagSlotKey(bag, slot)
  local slotState = self.trackedSlots[slotKey]

  if not slotState then
    return itemInfo.isLocked
  end

  if slotState.itemID ~= itemInfo.itemID then
    self.trackedSlots[slotKey] = nil
    return itemInfo.isLocked
  end

  return slotState.isLocked or slotState.isBeingDisenchanted or itemInfo.isLocked
end

function DE:PruneTrackedSlots()
  for slotKey, slotState in pairs(self.trackedSlots) do
    local itemInfo = C_Container.GetContainerItemInfo(slotState.bag, slotState.slot)
    if not itemInfo or itemInfo.itemID ~= slotState.itemID then
      self.trackedSlots[slotKey] = nil
    end
  end
end

function DE:GetFirstTarget()
  local whitelist = SmartRez:GetDisenchantWhitelist()
  local target

  self:PruneTrackedSlots()

  SmartRez:ForEachCraftingItemSourceSlot(function(bag, slot)
    local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
    if itemInfo and whitelist[itemInfo.itemID] and not self:IsTrackedSlotBlocked(bag, slot, itemInfo) then
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

function DE:IsRemoteTarget(target)
  if not target then
    return false
  end

  for _, bag in ipairs(SmartRez:GetPlayerBagContainerIDs()) do
    if bag == target.bag then
      return false
    end
  end

  return true
end

function DE:HasRemoteInventorySourcesEnabled()
  local inventorySources = SmartRez:GetInventorySources()
  return inventorySources.warbank == true
end

function DE:ShouldPrimeRemoteAccess()
  if not self:HasRemoteInventorySourcesEnabled() then
    return false
  end

  local enchantingProfessionID = SmartRez.Profession and SmartRez.Profession.Enchanting
  if not enchantingProfessionID then
    return false
  end

  if SmartRez.IsProfessionProxyReady and SmartRez:IsProfessionProxyReady(enchantingProfessionID) then
    return false
  end

  return true
end

function DE:IsRemoteTargetReady(target)
  if not self:IsRemoteTarget(target) then
    return true
  end

  local enchantingProfessionID = SmartRez.Profession and SmartRez.Profession.Enchanting
  if not enchantingProfessionID then
    return false
  end

  if SmartRez.IsProfessionProxyReady and SmartRez:IsProfessionProxyReady(enchantingProfessionID) then
    return true
  end

  local professionInfo = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
  return professionInfo and professionInfo.professionID == enchantingProfessionID or false
end

function DE:OpenRemoteTargetAccess(target)
  if not self:IsRemoteTarget(target) then
    return true
  end

  local enchantingProfessionID = SmartRez.Profession and SmartRez.Profession.Enchanting
  if not enchantingProfessionID then
    return false
  end

  if SmartRez.IsProfessionProxyReady and SmartRez:IsProfessionProxyReady(enchantingProfessionID) then
    return true
  end

  if SmartRez.OpenProfessionProxy then
    debugDisenchant("opening enchanting proxy")
    SmartRez:OpenProfessionProxy(enchantingProfessionID)
    return false
  end

  if C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill then
    debugDisenchant("opening enchanting window")
    C_TradeSkillUI.OpenTradeSkill(enchantingProfessionID)
    return false
  end

  return true
end

function DE:ClearSpellButton()
  self.SpellButton:SetAttribute("spell", "")
  self.SpellButton:SetAttribute("target-bag", "")
  self.SpellButton:SetAttribute("target-slot", "")
end

function DE:BuildMacroText(target)
  if not target then
    return ""
  end

  self:ResetVerification(target.itemID)
  self.SpellButton:SetAttribute("spell", tostring(DISENCHANT_SPELL_ID))
  self.SpellButton:SetAttribute("target-bag", target.bag)
  self.SpellButton:SetAttribute("target-slot", target.slot)

  local clickSuffix = getClickSuffix()
  if not self.itemVerified then
    return string.format(
      "/click %s%s;\n/run SmartRez_VerifyDisenchantItem(%d)\n/stopspelltarget\n/click %s%s;",
      self.VerifyButton:GetName(),
      clickSuffix,
      target.itemID,
      self.SpellButton:GetName(),
      clickSuffix
    )
  end

  if self.verificationError then
    return ""
  end

  return string.format("/click %s%s;", self.SpellButton:GetName(), clickSuffix)
end

function DE:UpdateButtons(disableButton, macroText)
  if InCombatLockdown() then
    return
  end

  macroText = macroText or ""
  self.MainButton:SetAttribute("macrotext1", macroText)
  self.HotkeyButton:SetAttribute("macrotext1", macroText)

  if disableButton then
    self.MainButton:Disable()
    self.HotkeyButton:Disable()
  else
    self.MainButton:Enable()
    self.HotkeyButton:Enable()
  end
end

function DE:RefreshButtons()
  if InCombatLockdown() then
    return
  end

  local disableButton = self.disenchantCasting or self.disenchantCastSuccess or self.lootingInProgress

  if not disableButton then
    local target = self:GetFirstTarget()
    if target then
      self:ResetVerification(target.itemID)
      disableButton = self.verificationError ~= nil
    elseif self:ShouldPrimeRemoteAccess() then
      disableButton = false
    else
      disableButton = true
      self:ClearSpellButton()
    end
  end

  self:UpdateButtons(disableButton, "")
end

function DE:FinishSuccessfulDisenchant()
  self.lootingInProgress = false
  self.buttonClicked = false
  self.clickedBagSlot = nil
  self.disenchantCastSuccess = false
  self:RefreshButtons()
  self:UnregisterDisenchantingEvents()
end

function DE:HandleFailedDisenchant()
  self:UnregisterDisenchantingEvents()
  self:ResetSession()
  self:RefreshButtons()
end

function DE:QuickAutoLoot()
  if self.lootingInProgress then
    return
  end

  self.lootingInProgress = true
  self.materialsWaiting = true
  self:UpdateButtons(true, self.HotkeyButton:GetAttribute("macrotext1"))

  local lootItems = GetNumLootItems()
  if self.buttonClicked and lootItems and lootItems > 0 then
    for lootSlot = lootItems, 1, -1 do
      local _, lootName, _, _, _, locked = GetLootSlotInfo(lootSlot)
      if lootName and not locked then
        LootSlot(lootSlot)
      end
    end
    CloseLoot()
  end
end

function DE.Events:OnEvent(eventName, ...)
  if self[eventName] then
    self[eventName](self, eventName, ...)
  end
end

DE.Events:SetScript("OnEvent", DE.Events.OnEvent)

function DE.Events:PLAYER_ENTERING_WORLD()
  DE:RefreshButtons()
end

function DE.Events:PLAYER_REGEN_DISABLED()
  DE.MainButton:Disable()
  DE.HotkeyButton:Disable()
end

function DE.Events:PLAYER_REGEN_ENABLED()
  DE:RefreshButtons()
end

function DE.Events:UNIT_SPELLCAST_START(_, _, _, spellID)
  if spellID ~= DISENCHANT_SPELL_ID then
    return
  end

  DE.MainButton:Disable()
  DE.HotkeyButton:Disable()
  DE.disenchantCasting = true
  DE.disenchantCastSuccess = false

  if DE.buttonClicked and DE.clickedBagSlot and DE.trackedSlots[DE.clickedBagSlot] then
    DE.trackedSlots[DE.clickedBagSlot].isBeingDisenchanted = true
  end

  DE:RegisterDisenchantingEvents()
end

function DE.Events:UNIT_SPELLCAST_SUCCEEDED(_, _, _, spellID)
  if spellID ~= DISENCHANT_SPELL_ID then
    return
  end

  DE.disenchantCastSuccess = true
  DE.disenchantCasting = false

  if DE.buttonClicked and GetCVar("autoLootDefault") == "1" then
    setAutoLootDefault(0)
    DE.defaultAutoLootDisabled = true
  end
end

function DE.Events:UNIT_SPELLCAST_STOP(_, _, _, spellID)
  if spellID ~= DISENCHANT_SPELL_ID or DE.disenchantCastSuccess then
    return
  end

  DE:HandleFailedDisenchant()
end

function DE.Events:ITEM_LOCKED(_, bag, slot)
  local slotState = DE.trackedSlots[getBagSlotKey(bag, slot)]
  if slotState then
    slotState.isLocked = true
  end
end

function DE.Events:ITEM_UNLOCKED(_, bag, slot)
  local slotState = DE.trackedSlots[getBagSlotKey(bag, slot)]
  if slotState then
    slotState.isLocked = false
  end
end

function DE.Events:ITEM_PUSH()
  if DE.lootingInProgress and not DE.materialsWaiting then
    DE:FinishSuccessfulDisenchant()
  end
end

function DE.Events:LOOT_READY()
  DE:QuickAutoLoot()
end

function DE.Events:LOOT_OPENED()
  DE:QuickAutoLoot()
end

function DE.Events:LOOT_CLOSED()
  if DE.lootingInProgress and DE.materialsWaiting then
    DE.materialsWaiting = false

    if DE.buttonClicked and DE.defaultAutoLootDisabled then
      setAutoLootDefault(1)
      DE.defaultAutoLootDisabled = false
    end
  end
end

function _G.SmartRez_VerifyDisenchantItem(itemID)
  DE.verificationError = nil

  if itemID and SpellIsTargeting() then
    DE.HiddenTooltip:SetItemByID(itemID)

    for lineIndex = 1, DE.HiddenTooltip:NumLines() do
      local textRegion = _G[DE.HiddenTooltip:GetName() .. "TextLeft" .. lineIndex]
      local line = textRegion and textRegion:GetText()

      if line then
        if string.find(line, ITEM_DISENCHANT_NOT_DISENCHANTABLE, 1, true) then
          UIErrorsFrame:AddMessage(SPELL_FAILED_CANT_BE_DISENCHANTED, 1, 0.1, 0.1)
          DE.verificationError = SPELL_FAILED_CANT_BE_DISENCHANTED
        end

        local skillMatch = string.match(
          line,
          ITEM_DISENCHANT_MIN_SKILL:gsub("%(", "%%("):gsub("%)", "%%)"):gsub("%%s", ".+"):gsub("%%d", "(%%d+)")
        )
        if skillMatch and textRegion then
          local r, g, b = textRegion:GetTextColor()
          if r == 1 and g < 0.2 and b < 0.2 then
            local skillTooLowMessage = SPELL_FAILED_CANT_BE_DISENCHANTED_SKILL .. " (" .. skillMatch .. ")"
            UIErrorsFrame:AddMessage(skillTooLowMessage, 1, 0.1, 0.1)
            DE.verificationError = skillTooLowMessage
          end
        end
      end
    end

    DE.itemVerified = true
  end

  if DE.verificationError then
    DE:UpdateButtons(true, "")
  else
    DE:RefreshButtons()
  end
end

DE.SpellButton:SetScript("PostClick", function(self)
  local bag = self:GetAttribute("target-bag")
  local slot = self:GetAttribute("target-slot")

  if bag == "" or slot == "" or bag == nil or slot == nil then
    return
  end

  local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
  if not itemInfo then
    return
  end

  DE.clickedBagSlot = getBagSlotKey(bag, slot)
  DE.buttonClicked = true
  DE.trackedSlots[DE.clickedBagSlot] = {
    bag = bag,
    slot = slot,
    itemID = itemInfo.itemID,
    isLocked = false,
    isBeingDisenchanted = false,
  }
end)

DE.MainButton:SetScript("PreClick", function(_, _, down)
  if not isActiveClickPhase(down) then
    return
  end

  DE:RefreshButtons()

  if InCombatLockdown() or not DE.MainButton:IsEnabled() then
    return
  end

  DE.MainButton:SetAttribute("macrotext1", SmartRez:PrepareDisenchantMacro() or "")
end)

DE.HotkeyButton:SetScript("PreClick", function(_, _, down)
  if not isActiveClickPhase(down) then
    return
  end

  DE:RefreshButtons()

  if InCombatLockdown() or not DE.HotkeyButton:IsEnabled() then
    return
  end

  DE.HotkeyButton:SetAttribute("macrotext1", SmartRez:PrepareDisenchantMacro() or "")
end)

DE.MainButton:SetScript("PostClick", function(_, _, down)
  if InCombatLockdown() or not isActiveClickPhase(down) then
    return
  end

  DE.MainButton:SetAttribute("macrotext1", "")
end)

DE.HotkeyButton:SetScript("PostClick", function(_, _, down)
  if InCombatLockdown() or not isActiveClickPhase(down) then
    return
  end

  DE.HotkeyButton:SetAttribute("macrotext1", "")
end)

DE.Events:RegisterEvent("PLAYER_ENTERING_WORLD")
DE.Events:RegisterEvent("PLAYER_REGEN_DISABLED")
DE.Events:RegisterEvent("PLAYER_REGEN_ENABLED")
DE.Events:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
DE.Events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
DE.Events:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")

function SmartRez:HasDisenchantTarget()
  return DE:GetFirstTarget() ~= nil or DE:ShouldPrimeRemoteAccess()
end

function SmartRez:IsItemDisenchantable(itemID)
  if itemID == nil then
    return false
  end

  local cached = DE.itemDisenchantability[itemID]
  if cached ~= nil then
    return cached
  end

  local _, _, quality, _, _, _, _, _, equipLoc, _, _, classID = C_Item.GetItemInfo(itemID)
  if not quality or not classID then
    DE.itemDisenchantability[itemID] = false
    return false
  end

  local isArmorOrWeapon = classID == Enum.ItemClass.Armor or classID == Enum.ItemClass.Weapon
  local hasEquipLocation = type(equipLoc) == "string" and equipLoc ~= ""
  if not isArmorOrWeapon or not hasEquipLocation or quality < 2 or quality > 4 then
    DE.itemDisenchantability[itemID] = false
    return false
  end

  local isDisenchantable = scanTooltipForDisenchantability(itemID)
  DE.itemDisenchantability[itemID] = isDisenchantable
  return isDisenchantable
end

function SmartRez:GetAvailableDisenchantItemIDs()
  local itemIDs = {}
  local seen = {}

  self:ForEachCraftingItemSourceSlot(function(bag, slot)
    local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
    local itemID = itemInfo and itemInfo.itemID
    local itemLocation = itemID and ItemLocation:CreateFromBagAndSlot(bag, slot) or nil
    local isBound = itemLocation and C_Item.IsBound and C_Item.IsBound(itemLocation) or false
    if itemID and not isBound and not seen[itemID] and self:IsItemDisenchantable(itemID) then
      seen[itemID] = true
      itemIDs[#itemIDs + 1] = itemID
    end
  end)

  return itemIDs
end

function SmartRez:IsDisenchantLocked()
  return DE.disenchantCasting or DE.disenchantCastSuccess or DE.lootingInProgress
end

function SmartRez:GetDisenchantTarget()
  if self:IsDisenchantLocked() then
    return nil
  end

  return DE:GetFirstTarget()
end

function SmartRez:PrepareDisenchantMacro()
  local target = self:GetDisenchantTarget()
  if not target then
    if DE:ShouldPrimeRemoteAccess() then
      debugDisenchant("priming remote access")
      DE:OpenRemoteTargetAccess({
        bag = -1,
        slot = -1,
      })
    end

    return nil
  end

  if not DE:IsRemoteTargetReady(target) then
    debugDisenchant("target in remote storage, opening access")
    DE:OpenRemoteTargetAccess(target)
    return nil
  end

  debugDisenchant("prepared item=%d bag=%d slot=%d", target.itemID, target.bag, target.slot)
  return DE:BuildMacroText(target)
end

function SmartRez:RefreshDisenchantButton()
  DE:RefreshButtons()
end

DE:RefreshButtons()

SmartRez:RegisterBindableAction({
  key = "disenchant",
  label = "Disenchant",
  buttonName = "DisenchantBtn",
  order = 10,
})
