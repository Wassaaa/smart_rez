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

local function colorize(hexColor, text)
	return string.format("|cff%s%s|r", hexColor, tostring(text))
end

local function getModeStatusText()
	if SmartRezDB.enabled then
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

local function getActions()
	return SmartRez:GetBindableActions()
end

local function getBindingValue(actionKey)
	return trim(SmartRezDB.bindings and SmartRezDB.bindings[actionKey] or ""):upper()
end

local function getBindingDisplay(actionKey)
	local binding = getBindingValue(actionKey)
	if binding == "" then
		return colorize("7D8590", NOT_BOUND)
	end
	return colorize("79C0FF", binding)
end

local function initializeDB()
	if SmartRez.EnsureConfig then
		SmartRez:EnsureConfig()
	end

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
local automationConfigFrame

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
local showAutomationConfigWindow

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
		showAutomationConfigWindow()
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
		self.enableCheck:SetValue(SmartRezDB.enabled)
		self.status:SetText("Status: " .. getModeStatusText())
		self.goldPrinterStatus:SetText("Gold Printer: " .. getGoldPrinterStatusText())

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

local function getItemDisplay(itemID)
	if not itemID then
		return "Empty"
	end

	local itemName, itemLink, _, _, _, _, _, _, _, itemIcon = _G["GetItemInfo"](itemID)
	return itemLink or itemName or ("item:" .. itemID), itemIcon
end

local function getDisplayFromLinkOrID(itemLink, itemID)
	if itemLink then
		local _, _, _, _, _, _, _, _, _, itemIcon = _G["GetItemInfo"](itemLink)
		return itemLink, itemIcon
	end

	return getItemDisplay(itemID)
end

local function getCursorItemID()
	local cursorType, itemID = _G["GetCursorInfo"]()
	if cursorType == "item" and itemID then
		return itemID
	end
end

local function createAutomationConfigWindow()
	if automationConfigFrame then
		return automationConfigFrame
	end

	automationConfigFrame = AceGUI:Create("Window")
	automationConfigFrame:SetTitle(APP_NAME .. " Config")
	automationConfigFrame:SetStatusText("")
	automationConfigFrame:SetWidth(620)
	automationConfigFrame:SetHeight(560)
	automationConfigFrame:EnableResize(false)
	automationConfigFrame:SetLayout("Fill")
	automationConfigFrame.frame:SetFrameStrata("DIALOG")
	automationConfigFrame:SetCallback("OnClose", function(widget)
		widget:Hide()
	end)

	automationConfigFrame.scroll = AceGUI:Create("ScrollFrame")
	automationConfigFrame.scroll:SetLayout("List")
	automationConfigFrame:AddChild(automationConfigFrame.scroll)

	function automationConfigFrame:Refresh()
		self.scroll:ReleaseChildren()

		local disenchantGroup = AceGUI:Create("InlineGroup")
		disenchantGroup:SetTitle("Disenchant Whitelist")
		disenchantGroup:SetFullWidth(true)
		disenchantGroup:SetLayout("List")
		self.scroll:AddChild(disenchantGroup)

		local disenchantHelp = AceGUI:Create("Label")
		disenchantHelp:SetFullWidth(true)
		disenchantHelp:SetText(colorize("A5D6FF", "Pick up an item, then click Add Cursor Item."))
		disenchantGroup:AddChild(disenchantHelp)

		local disenchantSpacer = AceGUI:Create("Label")
		disenchantSpacer:SetFullWidth(true)
		disenchantSpacer:SetText(" ")
		disenchantGroup:AddChild(disenchantSpacer)

		local addDisenchantButton = AceGUI:Create("Button")
		addDisenchantButton:SetText("Add Cursor Item")
		addDisenchantButton:SetWidth(170)
		addDisenchantButton:SetCallback("OnClick", function()
			local itemID = getCursorItemID()
			if not itemID then
				print("Smart Rez: pick up an item first, then click Add Cursor Item.")
				return
			end
			SmartRez:AddDisenchantWhitelistItem(itemID)
			_G["ClearCursor"]()
		end)
		disenchantGroup:AddChild(addDisenchantButton)

		local whitelistIDs = {}
		for itemID in pairs(SmartRez:GetDisenchantWhitelist()) do
			table.insert(whitelistIDs, itemID)
		end
		table.sort(whitelistIDs)

		for _, itemID in ipairs(whitelistIDs) do
			local row = AceGUI:Create("SimpleGroup")
			row:SetFullWidth(true)
			row:SetLayout("Flow")
			disenchantGroup:AddChild(row)

			local label = AceGUI:Create("InteractiveLabel")
			label:SetWidth(430)
			label:SetText(select(1, getItemDisplay(itemID)))
			row:AddChild(label)

			local removeButton = AceGUI:Create("Button")
			removeButton:SetText("Remove Item")
			removeButton:SetWidth(110)
			removeButton:SetCallback("OnClick", function()
				SmartRez:RemoveDisenchantWhitelistItem(itemID)
			end)
			row:AddChild(removeButton)
		end

		local recipeGroup = AceGUI:Create("InlineGroup")
		recipeGroup:SetTitle("Shard Craft")
		recipeGroup:SetFullWidth(true)
		recipeGroup:SetLayout("List")
		self.scroll:AddChild(recipeGroup)

		local recipeConfig = SmartRez:GetRecipeCraftConfig("shardcraft")
		local currentState = SmartRez.currentProfessionState

		local recipeSummary = AceGUI:Create("Label")
		recipeSummary:SetFullWidth(true)
		recipeSummary:SetText(string.format(
			"%s %s  |  %s %s  |  %s %s",
			colorize("A5D6FF", "Recipe:"),
			tostring(recipeConfig.label or "Unset"),
			colorize("A5D6FF", "ID:"),
			tostring(recipeConfig.recipeID or "Unset"),
			colorize("A5D6FF", "Profession:"),
			tostring(recipeConfig.requiredProfession or "Unset")
		))
		recipeGroup:AddChild(recipeSummary)

		local recipeHelp = AceGUI:Create("Label")
		recipeHelp:SetFullWidth(true)
		recipeHelp:SetText(colorize("A5D6FF", "Use Selected Recipe to save the active profession recipe and reagents."))
		recipeGroup:AddChild(recipeHelp)

		local recipeSpacer = AceGUI:Create("Label")
		recipeSpacer:SetFullWidth(true)
		recipeSpacer:SetText(" ")
		recipeGroup:AddChild(recipeSpacer)

		local recipeButton = AceGUI:Create("Button")
		recipeButton:SetText("Use Selected Recipe")
		recipeButton:SetWidth(200)
		recipeButton:SetCallback("OnClick", function()
			local ok, err = SmartRez:LoadRecipeCraftFromSelection("shardcraft")
			if not ok and err then
				print("Smart Rez:", err)
			end
		end)
		recipeGroup:AddChild(recipeButton)

		local recipeButtonSpacer = AceGUI:Create("Label")
		recipeButtonSpacer:SetFullWidth(true)
		recipeButtonSpacer:SetText(" ")
		recipeGroup:AddChild(recipeButtonSpacer)

		local resultLabel = AceGUI:Create("InteractiveLabel")
		resultLabel:SetFullWidth(true)
		resultLabel:SetText(colorize("7EE787", "Crafting: ") .. select(1, getDisplayFromLinkOrID(recipeConfig.outputItemLink, recipeConfig.outputItemID)))
		recipeGroup:AddChild(resultLabel)

		local reagentSpacer = AceGUI:Create("Label")
		reagentSpacer:SetFullWidth(true)
		reagentSpacer:SetText(" ")
		recipeGroup:AddChild(reagentSpacer)

		local reagentHeader = AceGUI:Create("Label")
		reagentHeader:SetFullWidth(true)
		reagentHeader:SetText(colorize("FFD866", "Using reagents:"))
		recipeGroup:AddChild(reagentHeader)

		for reagentIndex, reagent in ipairs(recipeConfig.reagents or {}) do
			local reagentLabel = AceGUI:Create("InteractiveLabel")
			reagentLabel:SetFullWidth(true)
			reagentLabel:SetText(string.format(
				"%d. x%s %s",
				reagentIndex,
				tostring(reagent.quantity or "?"),
				select(1, getItemDisplay(reagent.itemID))
			))
			recipeGroup:AddChild(reagentLabel)
		end

		if #(recipeConfig.reagents or {}) == 0 then
			local emptyReagents = AceGUI:Create("Label")
			emptyReagents:SetFullWidth(true)
			emptyReagents:SetText("No reagents captured yet. Use Selected Recipe first.")
			recipeGroup:AddChild(emptyReagents)
		end

		local goldPrinterGroup = AceGUI:Create("InlineGroup")
		goldPrinterGroup:SetTitle("Gold Printer")
		goldPrinterGroup:SetFullWidth(true)
		goldPrinterGroup:SetLayout("List")
		self.scroll:AddChild(goldPrinterGroup)

		local goldPrinterHelp = AceGUI:Create("Label")
		goldPrinterHelp:SetFullWidth(true)
		goldPrinterHelp:SetText(colorize("A5D6FF", "Crafts first, then disenchants, then shatters."))
		goldPrinterGroup:AddChild(goldPrinterHelp)

		local goldPrinterStatus = AceGUI:Create("Label")
		goldPrinterStatus:SetFullWidth(true)
		goldPrinterStatus:SetText("Current phase: " .. getGoldPrinterStatusText())
		goldPrinterGroup:AddChild(goldPrinterStatus)

		local goldPrinterSlider = AceGUI:Create("Slider")
		goldPrinterSlider:SetFullWidth(true)
		goldPrinterSlider:SetLabel("Minimum free bag slots to keep while crafting")
		goldPrinterSlider:SetSliderValues(1, 20, 1)
		goldPrinterSlider:SetValue(SmartRez:GetGoldPrinterMinFreeSlots())
		goldPrinterSlider:SetCallback("OnValueChanged", function(_, _, value)
			SmartRez:SetGoldPrinterMinFreeSlots(math.floor((value or 1) + 0.5))
		end)
		goldPrinterGroup:AddChild(goldPrinterSlider)

		local footerGroup = AceGUI:Create("SimpleGroup")
		footerGroup:SetFullWidth(true)
		footerGroup:SetLayout("Flow")
		self.scroll:AddChild(footerGroup)

		local closeButton = AceGUI:Create("Button")
		closeButton:SetText(CLOSE)
		closeButton:SetWidth(100)
		closeButton:SetCallback("OnClick", function()
			automationConfigFrame:Hide()
		end)
		footerGroup:AddChild(closeButton)
	end

	table.insert(managedFrames, automationConfigFrame)
	return automationConfigFrame
end

showAutomationConfigWindow = function()
	local configWindow = createAutomationConfigWindow()
	configWindow:Refresh()
	configWindow:Show()
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
				goldprinterslots = {
					type = "range",
					name = "Gold Printer minimum free bag slots",
					order = 40,
					min = 1,
					max = 20,
					step = 1,
					set = function(_, value)
						SmartRez:SetGoldPrinterMinFreeSlots(value)
					end,
					get = function()
						return SmartRez:GetGoldPrinterMinFreeSlots()
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
					name = "Open Automation Config",
					order = 15,
					func = function()
						showAutomationConfigWindow()
					end,
				},
				slashhint = {
					type = "description",
					name = "Slash commands: /sr, /sr on, /sr off, /sr toggle, /sr pop, /sr setup",
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
		showAutomationConfigWindow()
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
