local SmartRez = _G.SmartRez
local DISENCHANT_SPELL_ID = 13262
local FALLBACK_UNLOCK_SECONDS = 3
local PRESTART_RETRY_DELAY = 0.35
local DEBUG_DISENCHANT = false
local button
local setLocked

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
        return itemInfo.itemID
      end
    end
  end
end

local function buildDisenchantMacroText(itemID)
  return "/cast [nochanneling] Disenchant\n/use item:" .. itemID
end

local function beginDisenchantAttempt()
  if button.isLocked then
    return nil
  end

  local itemID = findDisenchantTarget()
  if not itemID then
    return nil
  end

  debugPrint("preclick item", itemID)
  setLocked(true)
  button.awaitingStart = true
  button.castStarted = false
  button.awaitingLoot = false
  button.unlockAt = GetTime() + FALLBACK_UNLOCK_SECONDS
  return buildDisenchantMacroText(itemID)
end

function SmartRez:HasDisenchantTarget()
  return findDisenchantTarget() ~= nil
end

function SmartRez:IsDisenchantLocked()
  return button.isLocked == true
end

function SmartRez:PrepareDisenchantMacro()
  return beginDisenchantAttempt()
end

button = CreateFrame("Button", "DisenchantBtn", nil, "SecureActionButtonTemplate")
local watcher = CreateFrame("Frame")

button:RegisterForClicks("AnyDown")
button:SetAttribute("type", "macro")
button.isLocked = false
button.unlockAt = 0
button.awaitingStart = false
button.castStarted = false
button.awaitingLoot = false

function setLocked(value)
  button.isLocked = value
  debugPrint("lock", tostring(value))
end

local function unlockButton()
  debugPrint("unlock")
  setLocked(false)
  button.unlockAt = 0
  button.awaitingStart = false
  button.castStarted = false
  button.awaitingLoot = false
  button:SetAttribute("macrotext", nil)
end

watcher:RegisterEvent("UNIT_SPELLCAST_START")
watcher:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
watcher:RegisterEvent("UNIT_SPELLCAST_FAILED")
watcher:RegisterEvent("UNIT_SPELLCAST_FAILED_QUIET")
watcher:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
watcher:RegisterEvent("LOOT_CLOSED")
watcher:RegisterEvent("BAG_UPDATE_DELAYED")
watcher:RegisterEvent("ITEM_PUSH")
watcher:SetScript("OnUpdate", function(_, elapsed)
  if button.isLocked and button.unlockAt > 0 and GetTime() >= button.unlockAt then
    debugPrint("fallback timeout")
    unlockButton()
  end
end)
watcher:SetScript("OnEvent", function(_, eventName, ...)
  if eventName == "LOOT_CLOSED" or eventName == "BAG_UPDATE_DELAYED" or eventName == "ITEM_PUSH" then
    debugPrint("loot event", eventName, tostring(button.awaitingLoot))
    if button.awaitingLoot then
      unlockButton()
    end
    return
  end

  local unitTarget, _, spellID = ...
  if unitTarget ~= "player" or spellID ~= DISENCHANT_SPELL_ID then
    return
  end

  if eventName == "UNIT_SPELLCAST_START" then
    button.awaitingStart = false
    button.castStarted = true
    button.awaitingLoot = false
    setLocked(true)
    button:SetAttribute("macrotext", nil)
    return
  end

  if eventName == "UNIT_SPELLCAST_SUCCEEDED" then
    button.awaitingStart = false
    button.castStarted = false
    button.awaitingLoot = true
    button.unlockAt = GetTime() + FALLBACK_UNLOCK_SECONDS
    return
  end

  if not button.castStarted and button.awaitingStart then
    debugPrint("pre-start failure", eventName)
    button.unlockAt = GetTime() + PRESTART_RETRY_DELAY
    return
  end

  debugPrint("spellcast failed", eventName)
  unlockButton()
end)

button:SetScript("PreClick", function(self)
  if InCombatLockdown() then
    return
  end

  if self.isLocked then
    if not self.awaitingStart then
      self:SetAttribute("macrotext", nil)
    end
    return
  end

  local macroText = beginDisenchantAttempt()
  if macroText then
    self.awaitingStart = button.awaitingStart
    self.castStarted = button.castStarted
    self.awaitingLoot = button.awaitingLoot
    self.unlockAt = button.unlockAt
    self:SetAttribute("macrotext", macroText)
  else
    unlockButton()
  end
end)

button:SetScript("PostClick", function(self)
  if not self.awaitingStart then
    return
  end

  self:SetAttribute("macrotext", nil)
end)

SmartRez:RegisterBindableAction({
  key = "disenchant",
  label = "Disenchant",
  buttonName = "DisenchantBtn",
  order = 10,
})
