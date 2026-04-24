local SmartRez = _G.SmartRez
local APP_NAME = SmartRez.appName

---@type AceGUILib
local AceGUI = LibStub("AceGUI-3.0")

---@class SmartRezOptionsWindow: AceGUIWindow
---@field frame table
---@field enableCheck AceGUICheckBox
---@field status AceGUILabel
---@field statusGroup AceGUIContainer
---@field providerLabels table<string, AceGUILabel>
---@field values table<string, AceGUILabel>
---@field toggleButton AceGUIButton
---@field configButton AceGUIButton
---@field closeButton AceGUIButton
local optionsFrame

SmartRez.overridePopupStatusProviders = SmartRez.overridePopupStatusProviders or {}

function SmartRez:RegisterOverridePopupStatusProvider(config)
  if type(config) ~= "table" or type(config.key) ~= "string" or config.key == "" then
    return
  end
  if type(config.getText) ~= "function" then
    return
  end

  self.overridePopupStatusProviders[config.key] = {
    key = config.key,
    label = config.label or config.key,
    order = config.order or 100,
    getText = config.getText,
  }
end

function SmartRez:GetOverridePopupStatusProviders()
  local providers = {}
  for _, provider in pairs(self.overridePopupStatusProviders or {}) do
    table.insert(providers, provider)
  end
  table.sort(providers, function(left, right)
    if left.order == right.order then
      return left.key < right.key
    end
    return left.order < right.order
  end)
  return providers
end

local function ensureProviderStatusLabels(frame)
  frame.providerLabels = frame.providerLabels or {}
  for _, provider in ipairs(SmartRez:GetOverridePopupStatusProviders()) do
    if not frame.providerLabels[provider.key] then
      local label = AceGUI:Create("Label")
      label:SetFullWidth(true)
      frame.statusGroup:AddChild(label)
      frame.providerLabels[provider.key] = label
    end
  end
end

local function createOptionsPopup()
  if optionsFrame then
    return optionsFrame
  end

  ---@type SmartRezOptionsWindow
  optionsFrame = AceGUI:Create("Window")
  optionsFrame:SetTitle(APP_NAME)
  optionsFrame:SetStatusText("")
  optionsFrame:SetWidth(420)
  optionsFrame:SetHeight(400)
  optionsFrame:EnableResize(false)
  optionsFrame:SetLayout("List")
  optionsFrame.frame:SetFrameStrata("DIALOG")
  optionsFrame:SetCallback("OnClose", function(widget)
    widget:Hide()
  end)

  local intro = AceGUI:Create("Label")
  intro:SetFullWidth(true)
  intro:SetText(SmartRez:Colorize("FFD866", "Override Keybind Mode"))
  optionsFrame:AddChild(intro)

  local help = AceGUI:Create("Label")
  help:SetFullWidth(true)
  help:SetText("Override binds only apply while Smart Rez mode is on.")
  optionsFrame:AddChild(help)

  local hint = AceGUI:Create("Label")
  hint:SetFullWidth(true)
  hint:SetText("Set keys in Options. This popup shows status and current binds.")
  optionsFrame:AddChild(hint)

  local topSpacer = AceGUI:Create("Label")
  topSpacer:SetFullWidth(true)
  topSpacer:SetText(" ")
  optionsFrame:AddChild(topSpacer)

  local stateGroup = AceGUI:Create("InlineGroup")
  stateGroup:SetTitle("Mode")
  stateGroup:SetFullWidth(true)
  stateGroup:SetLayout("List")
  optionsFrame:AddChild(stateGroup)

  optionsFrame.enableCheck = AceGUI:Create("CheckBox")
  optionsFrame.enableCheck:SetLabel("Enable Smart Rez override binds")
  optionsFrame.enableCheck:SetFullWidth(true)
  optionsFrame.enableCheck:SetCallback("OnValueChanged", function(_, _, value)
    SmartRez:SetEnabled(value)
  end)
  stateGroup:AddChild(optionsFrame.enableCheck)

  optionsFrame.statusGroup = AceGUI:Create("InlineGroup")
  optionsFrame.statusGroup:SetTitle("Status")
  optionsFrame.statusGroup:SetFullWidth(true)
  optionsFrame.statusGroup:SetLayout("List")
  stateGroup:AddChild(optionsFrame.statusGroup)

  optionsFrame.status = AceGUI:Create("Label")
  optionsFrame.status:SetFullWidth(true)
  optionsFrame.statusGroup:AddChild(optionsFrame.status)
  ensureProviderStatusLabels(optionsFrame)

  local bindsGroup = AceGUI:Create("InlineGroup")
  bindsGroup:SetTitle("Current Binds")
  bindsGroup:SetFullWidth(true)
  bindsGroup:SetLayout("List")
  optionsFrame:AddChild(bindsGroup)

  optionsFrame.values = {}
  for _, action in ipairs(SmartRez:GetOverrideBindingActions()) do
    local row = AceGUI:Create("SimpleGroup")
    row:SetFullWidth(true)
    row:SetLayout("Flow")
    bindsGroup:AddChild(row)

    local label = AceGUI:Create("Label")
    label:SetWidth(170)
    label:SetText(action.label)
    row:AddChild(label)

    local value = AceGUI:Create("Label")
    value:SetWidth(180)
    value:SetText(SmartRez:GetOverrideBindingDisplay(action.key))
    row:AddChild(value)

    optionsFrame.values[action.key] = value
  end

  local bottomSpacer = AceGUI:Create("Label")
  bottomSpacer:SetFullWidth(true)
  bottomSpacer:SetText(" ")
  optionsFrame:AddChild(bottomSpacer)

  local buttonGroup = AceGUI:Create("SimpleGroup")
  buttonGroup:SetFullWidth(true)
  buttonGroup:SetLayout("Flow")
  optionsFrame:AddChild(buttonGroup)

  optionsFrame.toggleButton = AceGUI:Create("Button")
  optionsFrame.toggleButton:SetText("Toggle Mode")
  optionsFrame.toggleButton:SetWidth(125)
  optionsFrame.toggleButton:SetCallback("OnClick", function()
    SmartRez:ToggleEnabled()
  end)
  buttonGroup:AddChild(optionsFrame.toggleButton)

  optionsFrame.configButton = AceGUI:Create("Button")
  optionsFrame.configButton:SetText("Open Setup")
  optionsFrame.configButton:SetWidth(125)
  optionsFrame.configButton:SetCallback("OnClick", function()
    SmartRez:ShowAutomationConfigWindow()
  end)
  buttonGroup:AddChild(optionsFrame.configButton)

  optionsFrame.closeButton = AceGUI:Create("Button")
  optionsFrame.closeButton:SetText(CLOSE)
  optionsFrame.closeButton:SetWidth(100)
  optionsFrame.closeButton:SetCallback("OnClick", function()
    optionsFrame:Hide()
  end)
  buttonGroup:AddChild(optionsFrame.closeButton)

  function optionsFrame:Refresh()
    self.enableCheck:SetValue(SmartRez:GetConfigDB().enabled)
    self.status:SetText("Status: " .. SmartRez:GetOverrideModeStatusText())

    ensureProviderStatusLabels(self)
    for _, provider in ipairs(SmartRez:GetOverridePopupStatusProviders()) do
      local label = self.providerLabels[provider.key]
      if label then
        label:SetText(provider.label .. ": " .. tostring(provider.getText()))
      end
    end

    for _, action in ipairs(SmartRez:GetOverrideBindingActions()) do
      self.values[action.key]:SetText(SmartRez:GetOverrideBindingDisplay(action.key))
    end
  end

  SmartRez:RegisterManagedFrame(optionsFrame)
  return optionsFrame
end

function SmartRez:ShowOverrideBindingPopup()
  local popup = createOptionsPopup()
  popup:Refresh()
  popup:Show()
end

function SmartRez:ToggleOverrideBindingPopup()
  local popup = createOptionsPopup()
  if popup:IsShown() then
    popup:Hide()
  else
    popup:Refresh()
    popup:Show()
  end
end
