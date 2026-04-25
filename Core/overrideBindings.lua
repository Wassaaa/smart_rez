local SmartRez = _G.SmartRez
local APP_NAME = SmartRez.appName

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")

local overrideFrame = CreateFrame("Frame", "SmartRezOverrideFrame", UIParent)

local LEGACY_BINDING_KEY_MAP = {
  milling = "inscription",
  prospecting = "jewelcrafting",
  recycling = "engineering",
  shatter = "enchanting",
  shattering = "enchanting",
  thauma = "alchemy",
  thaumaturgy = "alchemy",
}

function SmartRez:TrimText(text)
  return (text or ""):match("^%s*(.-)%s*$")
end

function SmartRez:GetConfigDB()
  self:EnsureConfig()
  return self.db
end

function SmartRez:Colorize(hexColor, text)
  return string.format("|cff%s%s|r", hexColor, tostring(text))
end

function SmartRez:GetOverrideBindingActions()
  return self:GetBindableActions()
end

function SmartRez:GetOverrideBindingValue(actionKey)
  return self:TrimText(self:GetConfigDB().bindings[actionKey] or ""):upper()
end

function SmartRez:GetOverrideBindingDisplay(actionKey)
  local binding = self:GetOverrideBindingValue(actionKey)
  if binding == "" then
    return self:Colorize("7D8590", NOT_BOUND)
  end
  return self:Colorize("79C0FF", binding)
end

function SmartRez:GetOverrideModeStatusText()
  if self:GetConfigDB().enabled then
    return self:Colorize("7EE787", "Enabled")
  end
  return self:Colorize("FFB86C", "Disabled")
end

function SmartRez:RegisterManagedFrame(frame)
  self.managedFrames = self.managedFrames or {}
  table.insert(self.managedFrames, frame)
end

function SmartRez:RefreshViews(reason)
  for _, frame in ipairs(self.managedFrames or {}) do
    if frame.Refresh and (not frame.IsShown or frame:IsShown()) then
      frame:Refresh(reason)
    end
  end

  AceConfigRegistry:NotifyChange(APP_NAME)
end

function SmartRez:InitializeOverrideBindingDB()
  local config = self:GetConfigDB()

  for oldKey, newKey in pairs(LEGACY_BINDING_KEY_MAP) do
    local oldBinding = self:TrimText(config.bindings[oldKey])
    local newBinding = self:TrimText(config.bindings[newKey])
    if oldBinding ~= "" and newBinding == "" then
      config.bindings[newKey] = oldBinding
    end
  end

  for _, action in ipairs(self:GetOverrideBindingActions()) do
    if config.bindings[action.key] == nil then
      config.bindings[action.key] = ""
    end
    config.bindings[action.key] = self:TrimText(config.bindings[action.key])
  end
end

function SmartRez:ApplyOverrideBindings()
  if InCombatLockdown() then
    return false
  end

  ClearOverrideBindings(overrideFrame)

  if not self:GetConfigDB().enabled then
    return true
  end

  for _, action in ipairs(self:GetOverrideBindingActions()) do
    local binding = self:GetOverrideBindingValue(action.key)
    if binding ~= "" and _G[action.buttonName] then
      SetOverrideBindingClick(overrideFrame, true, binding, action.buttonName, "LeftButton")
    end
  end

  return true
end

function SmartRez:SetEnabled(enabled, silent)
  if InCombatLockdown() then
    print("Smart Rez: cannot change override binds during combat.")
    self:RefreshViews()
    return
  end

  local config = self:GetConfigDB()
  config.enabled = enabled and true or false
  self:ApplyOverrideBindings()

  if not silent then
    if config.enabled then
      print("Smart Rez: override keybinds enabled.")
    else
      print("Smart Rez: override keybinds disabled.")
    end
  end

  self:RefreshViews()
end

function SmartRez:ToggleEnabled()
  self:SetEnabled(not self:GetConfigDB().enabled)
end

function SmartRez:SetOverrideBindingValue(actionKey, binding)
  if InCombatLockdown() then
    print("Smart Rez: cannot change override binds during combat.")
    self:RefreshViews()
    return
  end

  self:GetConfigDB().bindings[actionKey] = self:TrimText(binding):upper()
  self:ApplyOverrideBindings()
  self:RefreshViews()
end

function SmartRez:OpenSettingsCategory()
  local optionsPanel = self.overrideOptionsPanel
  if not optionsPanel then
    return
  end

  if Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(optionsPanel.name or APP_NAME)
    Settings.OpenToCategory(optionsPanel.name or APP_NAME)
  end
end

local toggleButton = CreateFrame("Button", "SmartRezModeToggleBtn", UIParent)
toggleButton:RegisterForClicks("LeftButtonUp")
toggleButton:SetScript("OnClick", function()
  SmartRez:ToggleEnabled()
end)

function SmartRez:OnInitialize()
  if self.RefreshKnownProfessions then
    self:RefreshKnownProfessions()
  end

  if self.InitializeProfessionProxy then
    self:InitializeProfessionProxy()
  end

  self:InitializeOverrideBindingDB()
  self:ApplyOverrideBindings()

  if self.BuildOverrideBindingOptions then
    AceConfig:RegisterOptionsTable(APP_NAME, function()
      return self:BuildOverrideBindingOptions()
    end)
    self.overrideOptionsPanel = AceConfigDialog:AddToBlizOptions(APP_NAME, APP_NAME)
  end

  self:RefreshViews()

  self:RegisterChatCommand("smartrez", "ChatCommand")
  self:RegisterChatCommand("sr", "ChatCommand")
end
