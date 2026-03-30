SmartRezDB = SmartRezDB or {}

local SmartRez = _G.SmartRez
local APP_NAME = SmartRez.appName

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local AceGUI = LibStub("AceGUI-3.0")

local DEFAULTS = {
	enabled = false,
	bindings = {},
}

local function trim(text)
	return (text or ""):match("^%s*(.-)%s*$")
end

local function getActions()
	return SmartRez:GetBindableActions()
end

local function getBindingValue(actionKey)
	return trim(SmartRezDB.bindings and SmartRezDB.bindings[actionKey] or ""):upper()
end

local function getBindingDisplay(actionKey)
	local binding = getBindingValue(actionKey)
	if binding == "" then
		return NOT_BOUND
	end
	return binding
end

local function initializeDB()
	if SmartRezDB.enabled == nil then
		SmartRezDB.enabled = DEFAULTS.enabled
	end

	if type(SmartRezDB.bindings) ~= "table" then
		SmartRezDB.bindings = {}
	end

	if SmartRezDB.bindings.thaumaturgy == nil and SmartRezDB.bindings.thauma ~= nil then
		SmartRezDB.bindings.thaumaturgy = SmartRezDB.bindings.thauma
	end

	if SmartRezDB.bindings.shattering == nil and SmartRezDB.bindings.shatter ~= nil then
		SmartRezDB.bindings.shattering = SmartRezDB.bindings.shatter
	end

	for key, value in pairs(DEFAULTS.bindings) do
		if SmartRezDB.bindings[key] == nil then
			SmartRezDB.bindings[key] = value
		end
		SmartRezDB.bindings[key] = trim(SmartRezDB.bindings[key])
	end

	for _, action in ipairs(getActions()) do
		if SmartRezDB.bindings[action.key] == nil then
			SmartRezDB.bindings[action.key] = ""
		end
		SmartRezDB.bindings[action.key] = trim(SmartRezDB.bindings[action.key])
	end
end

local overrideFrame = CreateFrame("Frame", "SmartRezOverrideFrame", UIParent)
local managedFrames = {}
local optionsPanel

local function refreshViews()
	for _, frame in ipairs(managedFrames) do
		if frame.Refresh then
			frame:Refresh()
		end
	end

	AceConfigRegistry:NotifyChange(APP_NAME)
end

local function applyOverrideBindings()
	if InCombatLockdown() then
		return false
	end

	ClearOverrideBindings(overrideFrame)

	if not SmartRezDB.enabled then
		return true
	end

	for _, action in ipairs(getActions()) do
		local binding = getBindingValue(action.key)
		if binding ~= "" and _G[action.buttonName] then
			SetOverrideBindingClick(overrideFrame, true, binding, action.buttonName, "LeftButton")
		end
	end

	return true
end

function SmartRez:RefreshViews()
	refreshViews()
end

function SmartRez:ApplyOverrideBindings()
	return applyOverrideBindings()
end

function SmartRez:SetEnabled(enabled, silent)
	if InCombatLockdown() then
		print("Smart Rez: cannot change override binds during combat.")
		refreshViews()
		return
	end

	SmartRezDB.enabled = enabled and true or false
	applyOverrideBindings()

	if not silent then
		if SmartRezDB.enabled then
			print("Smart Rez: override keybinds enabled.")
		else
			print("Smart Rez: override keybinds disabled.")
		end
	end

	refreshViews()
end

function SmartRez:ToggleEnabled()
	self:SetEnabled(not SmartRezDB.enabled)
end

local function setBindingValue(actionKey, binding)
	if InCombatLockdown() then
		print("Smart Rez: cannot change override binds during combat.")
		refreshViews()
		return
	end

	SmartRezDB.bindings[actionKey] = trim(binding):upper()
	applyOverrideBindings()
	refreshViews()
end

local toggleButton = CreateFrame("Button", "SmartRezModeToggleBtn", UIParent)
toggleButton:RegisterForClicks("LeftButtonUp")
toggleButton:SetScript("OnClick", function()
	SmartRez:ToggleEnabled()
end)

local optionsFrame

local function createOptionsPopup()
	if optionsFrame then
		return optionsFrame
	end

	optionsFrame = AceGUI:Create("Window")
	optionsFrame:SetTitle(APP_NAME)
	optionsFrame:SetStatusText("")
	optionsFrame:SetWidth(420)
	optionsFrame:SetHeight(320)
	optionsFrame:EnableResize(false)
	optionsFrame:SetLayout("Flow")
	optionsFrame.frame:SetFrameStrata("DIALOG")
	optionsFrame:SetCallback("OnClose", function(widget)
		widget:Hide()
	end)

	local intro = AceGUI:Create("Label")
	intro:SetFullWidth(true)
	intro:SetText("Override keybind mode")
	optionsFrame:AddChild(intro)

	local help = AceGUI:Create("Label")
	help:SetFullWidth(true)
	help:SetText("These keys only take over while Smart Rez mode is enabled.")
	optionsFrame:AddChild(help)

	local hint = AceGUI:Create("Label")
	hint:SetFullWidth(true)
	hint:SetText("Binds are set in the options screen. This popup only shows the current values.")
	optionsFrame:AddChild(hint)

	local stateGroup = AceGUI:Create("InlineGroup")
	stateGroup:SetTitle("Mode")
	stateGroup:SetFullWidth(true)
	stateGroup:SetLayout("Flow")
	optionsFrame:AddChild(stateGroup)

	optionsFrame.enableCheck = AceGUI:Create("CheckBox")
	optionsFrame.enableCheck:SetLabel("Enable Smart Rez override binds")
	optionsFrame.enableCheck:SetFullWidth(true)
	optionsFrame.enableCheck:SetCallback("OnValueChanged", function(_, _, value)
		SmartRez:SetEnabled(value)
	end)
	stateGroup:AddChild(optionsFrame.enableCheck)

	optionsFrame.status = AceGUI:Create("Label")
	optionsFrame.status:SetFullWidth(true)
	stateGroup:AddChild(optionsFrame.status)

	local bindsGroup = AceGUI:Create("InlineGroup")
	bindsGroup:SetTitle("Current Binds")
	bindsGroup:SetFullWidth(true)
	bindsGroup:SetLayout("Flow")
	optionsFrame:AddChild(bindsGroup)

	optionsFrame.values = {}
	for _, action in ipairs(getActions()) do
		local label = AceGUI:Create("Label")
		label:SetWidth(120)
		label:SetText(action.label)
		bindsGroup:AddChild(label)

		local value = AceGUI:Create("InteractiveLabel")
		value:SetWidth(220)
		value:SetText(getBindingDisplay(action.key))
		bindsGroup:AddChild(value)

		optionsFrame.values[action.key] = value
	end

	local buttonGroup = AceGUI:Create("SimpleGroup")
	buttonGroup:SetFullWidth(true)
	buttonGroup:SetLayout("Flow")
	optionsFrame:AddChild(buttonGroup)

	optionsFrame.toggleButton = AceGUI:Create("Button")
	optionsFrame.toggleButton:SetText("Toggle Mode")
	optionsFrame.toggleButton:SetWidth(120)
	optionsFrame.toggleButton:SetCallback("OnClick", function()
		SmartRez:ToggleEnabled()
	end)
	buttonGroup:AddChild(optionsFrame.toggleButton)

	optionsFrame.closeButton = AceGUI:Create("Button")
	optionsFrame.closeButton:SetText(CLOSE)
	optionsFrame.closeButton:SetWidth(100)
	optionsFrame.closeButton:SetCallback("OnClick", function()
		optionsFrame:Hide()
	end)
	buttonGroup:AddChild(optionsFrame.closeButton)

	function optionsFrame:Refresh()
		self.enableCheck:SetValue(SmartRezDB.enabled)

		if SmartRezDB.enabled then
			self.status:SetText("Status: Enabled")
		else
			self.status:SetText("Status: Disabled")
		end

		for _, action in ipairs(getActions()) do
			self.values[action.key]:SetText(getBindingDisplay(action.key))
		end
	end

	table.insert(managedFrames, optionsFrame)
	return optionsFrame
end

local function showOptionsPopup()
	local popup = createOptionsPopup()
	popup:Refresh()
	popup:Show()
end

local function toggleOptionsPopup()
	local popup = createOptionsPopup()
	if popup.frame:IsShown() then
		popup:Hide()
	else
		popup:Refresh()
		popup:Show()
	end
end

local function buildAceOptions()
	local args = {
		general = {
			type = "group",
			name = "Override keybind settings",
			inline = true,
			order = 10,
			args = {
				enabled = {
					type = "toggle",
					name = "Enable Smart Rez override binds",
					order = 10,
					set = function(_, value)
						SmartRez:SetEnabled(value)
					end,
					get = function()
						return SmartRezDB.enabled
					end,
				},
				help = {
					type = "description",
					name = "These keys only take over while Smart Rez mode is enabled.",
					order = 20,
					fontSize = "medium",
				},
				capture = {
					type = "description",
					name = "Click a bind field, then press any key, mouse button, or mouse wheel. Press Escape to clear.",
					order = 30,
					fontSize = "medium",
				},
			},
		},
		utility = {
			type = "group",
			name = "Utility",
			inline = true,
			order = 20,
			args = {
				openpopup = {
					type = "execute",
					name = "Open Popup UI",
					order = 10,
					func = function()
						showOptionsPopup()
					end,
				},
				slashhint = {
					type = "description",
					name = "Slash commands: /sr, /sr on, /sr off, /sr toggle, /sr pop",
					order = 20,
					fontSize = "medium",
				},
			},
		},
	}

	for index, action in ipairs(getActions()) do
		args.general.args[action.key] = {
			type = "keybinding",
			name = action.label,
			order = 30 + index,
			set = function(_, value)
				setBindingValue(action.key, value or "")
			end,
			get = function()
				local binding = getBindingValue(action.key)
				if binding == "" then
					return nil
				end
				return binding
			end,
		}
	end

	return {
		type = "group",
		name = APP_NAME,
		args = args,
	}
end

local function openSettingsCategory()
	if not optionsPanel then
		return
	end

	if Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(optionsPanel.name or APP_NAME)
		Settings.OpenToCategory(optionsPanel.name or APP_NAME)
	elseif InterfaceOptionsFrame_OpenToCategory then
		InterfaceOptionsFrame_OpenToCategory(optionsPanel)
		InterfaceOptionsFrame_OpenToCategory(optionsPanel)
	end
end

function SmartRez:OnInitialize()
	if self.RefreshKnownProfessions then
		self:RefreshKnownProfessions()
	end

	initializeDB()
	applyOverrideBindings()

	AceConfig:RegisterOptionsTable(APP_NAME, buildAceOptions)
	optionsPanel = AceConfigDialog:AddToBlizOptions(APP_NAME, APP_NAME)

	refreshViews()

	self:RegisterChatCommand("smartrez", "ChatCommand")
	self:RegisterChatCommand("sr", "ChatCommand")
end

function SmartRez:ChatCommand(msg)
	local command = trim(msg):lower()

	if command == "" or command == "config" then
		openSettingsCategory()
	elseif command == "on" then
		self:SetEnabled(true)
	elseif command == "off" then
		self:SetEnabled(false)
	elseif command == "toggle" then
		self:ToggleEnabled()
	elseif command == "pop" then
		toggleOptionsPopup()
	else
		print("Smart Rez commands: /sr, /sr on, /sr off, /sr toggle, /sr pop")
	end
end
