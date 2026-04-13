local SmartRez = _G.SmartRez
local APP_NAME = SmartRez.appName

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local AceGUI = LibStub("AceGUI-3.0")

local function trim(text)
	return (text or ""):match("^%s*(.-)%s*$")
end

local function getProfileDB()
	SmartRez:EnsureConfig()
	return SmartRez.db.profile
end

local function colorize(hexColor, text)
	return string.format("|cff%s%s|r", hexColor, tostring(text))
end

local function getModeStatusText()
	if getProfileDB().enabled then
		return colorize("7EE787", "Enabled")
	end
	return colorize("FFB86C", "Disabled")
end

local function getGoldPrinterStatusText()
	local phase = SmartRez:GetGoldPrinterPhase()
	if phase == "craft" then
		return colorize("7EE787", SmartRez:GetGoldPrinterPhaseLabel())
	end
	if phase == "disenchant" then
		return colorize("FFD866", SmartRez:GetGoldPrinterPhaseLabel())
	end
	if phase == "shatter" then
		return colorize("7AA2F7", SmartRez:GetGoldPrinterPhaseLabel())
	end
	return colorize("C0CAF5", SmartRez:GetGoldPrinterPhaseLabel())
end

local function getTSMLabelClickCooldownText()
	return colorize("79C0FF", string.format("%.2fs", SmartRez:GetTSMLabelClickCooldown()))
end

local function getActions()
	return SmartRez:GetBindableActions()
end

local function getBindingValue(actionKey)
	return trim(getProfileDB().bindings[actionKey] or ""):upper()
end

local function getBindingDisplay(actionKey)
	local binding = getBindingValue(actionKey)
	if binding == "" then
		return colorize("7D8590", NOT_BOUND)
	end
	return colorize("79C0FF", binding)
end

local LEGACY_BINDING_KEY_MAP = {
	milling = "inscription",
	prospecting = "jewelcrafting",
	recycling = "engineering",
	shatter = "enchanting",
	shattering = "enchanting",
	thauma = "alchemy",
	thaumaturgy = "alchemy",
}

local function initializeDB()
	local profile = getProfileDB()

	for oldKey, newKey in pairs(LEGACY_BINDING_KEY_MAP) do
		local oldBinding = trim(profile.bindings[oldKey])
		local newBinding = trim(profile.bindings[newKey])
		if oldBinding ~= "" and newBinding == "" then
			profile.bindings[newKey] = oldBinding
		end
	end

	for _, action in ipairs(getActions()) do
		if profile.bindings[action.key] == nil then
			profile.bindings[action.key] = ""
		end
		profile.bindings[action.key] = trim(profile.bindings[action.key])
	end
end

local overrideFrame = CreateFrame("Frame", "SmartRezOverrideFrame", UIParent)
-- Standalone UI files register here so RefreshViews can redraw them together.
SmartRez.managedFrames = SmartRez.managedFrames or {}
local managedFrames = SmartRez.managedFrames
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

	if not getProfileDB().enabled then
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

	local profile = getProfileDB()
	profile.enabled = enabled and true or false
	applyOverrideBindings()

	if not silent then
		if profile.enabled then
			print("Smart Rez: override keybinds enabled.")
		else
			print("Smart Rez: override keybinds disabled.")
		end
	end

	refreshViews()
end

function SmartRez:ToggleEnabled()
	self:SetEnabled(not getProfileDB().enabled)
end

local function setBindingValue(actionKey, binding)
	if InCombatLockdown() then
		print("Smart Rez: cannot change override binds during combat.")
		refreshViews()
		return
	end

	getProfileDB().bindings[actionKey] = trim(binding):upper()
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
	optionsFrame:SetHeight(400)
	optionsFrame:EnableResize(false)
	optionsFrame:SetLayout("List")
	optionsFrame.frame:SetFrameStrata("DIALOG")
	optionsFrame:SetCallback("OnClose", function(widget)
		widget:Hide()
	end)

	local intro = AceGUI:Create("Label")
	intro:SetFullWidth(true)
	intro:SetText(colorize("FFD866", "Override Keybind Mode"))
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

	local statusGroup = AceGUI:Create("InlineGroup")
	statusGroup:SetTitle("Status")
	statusGroup:SetFullWidth(true)
	statusGroup:SetLayout("List")
	stateGroup:AddChild(statusGroup)

	optionsFrame.status = AceGUI:Create("Label")
	optionsFrame.status:SetFullWidth(true)
	statusGroup:AddChild(optionsFrame.status)

	optionsFrame.goldPrinterStatus = AceGUI:Create("Label")
	optionsFrame.goldPrinterStatus:SetFullWidth(true)
	statusGroup:AddChild(optionsFrame.goldPrinterStatus)

	optionsFrame.tsmLabelClickCooldown = AceGUI:Create("Label")
	optionsFrame.tsmLabelClickCooldown:SetFullWidth(true)
	statusGroup:AddChild(optionsFrame.tsmLabelClickCooldown)

	local bindsGroup = AceGUI:Create("InlineGroup")
	bindsGroup:SetTitle("Current Binds")
	bindsGroup:SetFullWidth(true)
	bindsGroup:SetLayout("List")
	optionsFrame:AddChild(bindsGroup)

	optionsFrame.values = {}
	for _, action in ipairs(getActions()) do
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
		value:SetText(getBindingDisplay(action.key))
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
		self.enableCheck:SetValue(getProfileDB().enabled)
		self.status:SetText("Status: " .. getModeStatusText())
		self.goldPrinterStatus:SetText("Gold Printer: " .. getGoldPrinterStatusText())
		self.tsmLabelClickCooldown:SetText("TSM Label Click Cooldown: " .. getTSMLabelClickCooldownText())

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
						return getProfileDB().enabled
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
		tsmlabelclick = {
			type = "group",
			name = "TSM Label Click",
			inline = true,
			order = 15,
			args = {
				help = {
					type = "description",
					name = "Controls the shared cooldown for /sr tsm and /sr tsms label clicks.",
					order = 10,
					fontSize = "medium",
				},
				showmacroerrors = {
					type = "toggle",
					name = "Show macro error messages",
					desc = "Print chat errors when /sr tsm or /sr tsms can't find the needed TSM UI or button.",
					order = 15,
					set = function(_, value)
						SmartRez:SetTSMLabelClickShowMacroErrors(value)
					end,
					get = function()
						return SmartRez:GetTSMLabelClickShowMacroErrors()
					end,
				},
				cooldown = {
					type = "range",
					name = "TSM label click cooldown",
					desc = "Shared cooldown for /sr tsm and /sr tsms button clicks.",
					order = 20,
					min = 0,
					max = 1,
					step = 0.05,
					isPercent = false,
					set = function(_, value)
						SmartRez:SetTSMLabelClickCooldown(value)
					end,
					get = function()
						return SmartRez:GetTSMLabelClickCooldown()
					end,
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
				openconfig = {
					type = "execute",
					name = "Open Setup",
					order = 15,
					func = function()
						SmartRez:ShowAutomationConfigWindow()
					end,
				},
				slashhint = {
					type = "description",
					name = "Slash commands: /sr, /sr on, /sr off, /sr toggle, /sr pop, /sr setup, /sr tsm <label>, /sr tsms <mail|ah|prof> <label>",
					order = 25,
					fontSize = "medium",
				},
			},
		},
	}

	for index, action in ipairs(getActions()) do
		args.general.args[action.key] = {
			type = "keybinding",
			name = action.label,
			order = 40 + index,
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
	local raw = trim(msg)
	local command = raw:lower()
	local tsmsRestriction, tsmsLabel = raw:match("^tsms%s+(%S+)%s+(.+)$")
	local tsmMailLabel = raw:match("^tsm%s+mail%s+(.+)$")
	local tsmLabel = raw:match("^tsm%s+(.+)$")

	if command == "" or command == "config" then
		openSettingsCategory()
	elseif command == "setup" or command == "items" then
		SmartRez:ShowAutomationConfigWindow()
	elseif tsmsRestriction and tsmsLabel then
		self:ClickVisibleTSMButton(tsmsLabel, tsmsRestriction)
	elseif tsmMailLabel then
		self:ClickVisibleTSMButton(tsmMailLabel, "mail")
	elseif tsmLabel then
		self:ClickVisibleTSMButton(tsmLabel)
	elseif command == "on" then
		self:SetEnabled(true)
	elseif command == "off" then
		self:SetEnabled(false)
	elseif command == "toggle" then
		self:ToggleEnabled()
	elseif command == "pop" then
		toggleOptionsPopup()
	else
		print("Smart Rez commands: /sr, /sr on, /sr off, /sr toggle, /sr pop, /sr setup, /sr tsm <label>, /sr tsm mail <label>, /sr tsms <mail|ah|prof> <label>")
	end
end
