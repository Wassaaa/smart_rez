local SmartRez = _G.SmartRez
local APP_NAME = SmartRez.appName

local AceGUI = LibStub("AceGUI-3.0")

SmartRez.managedFrames = SmartRez.managedFrames or {}

local automationConfigFrame
local WINDOW_WIDTH = 680
local WINDOW_HEIGHT = 600
local CURSOR_BUTTON_WIDTH = 150
local ITEM_LABEL_WIDTH = 320
local BAG_COUNT_WIDTH = 85
local REMOVE_BUTTON_WIDTH = 90
local ROW_SPACING = 12
local CONTROL_SPACING = 14
local CONTROL_HINT_WIDTH = 330

local function colorize(hexColor, text)
	return string.format("|cff%s%s|r", hexColor, tostring(text))
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

local function getSortedItemIDs(itemSet)
	local itemIDs = {}

	for itemID in pairs(itemSet or {}) do
		table.insert(itemIDs, itemID)
	end

	table.sort(itemIDs)
	return itemIDs
end

-- AceGUI Flow layouts do not add consistent gutters on their own.
local function createHorizontalSpacer(width)
	local spacer = AceGUI:Create("Label")
	spacer:SetWidth(width or 10)
	spacer:SetText(" ")
	return spacer
end

local function addSectionSpacer(parent)
	local spacer = AceGUI:Create("Label")
	spacer:SetFullWidth(true)
	spacer:SetText(" ")
	parent:AddChild(spacer)
end

local function tryUseCursorItem(addItemFunc, missingItemMessage)
	local itemID = getCursorItemID()
	if not itemID then
		if missingItemMessage then
			print(missingItemMessage)
		end
		return false
	end

	addItemFunc(itemID)
	_G["ClearCursor"]()
	return true
end

local function createCursorItemButton(addItemFunc, missingItemMessage)
	local button = AceGUI:Create("Button")
	button:SetText("Add Cursor Item")
	button:SetWidth(CURSOR_BUTTON_WIDTH)
	button:SetCallback("OnClick", function()
		tryUseCursorItem(addItemFunc, missingItemMessage)
	end)
	return button
end

local function addWhitelistRows(parent, itemIDs, removeItemFunc)
	for _, itemID in ipairs(itemIDs) do
		local row = AceGUI:Create("SimpleGroup")
		row:SetFullWidth(true)
		row:SetLayout("Flow")
		parent:AddChild(row)

		local label = AceGUI:Create("InteractiveLabel")
		label:SetWidth(ITEM_LABEL_WIDTH)
		label:SetText(select(1, getItemDisplay(itemID)))
		row:AddChild(label)

		row:AddChild(createHorizontalSpacer(ROW_SPACING))

		local countLabel = AceGUI:Create("Label")
		countLabel:SetWidth(BAG_COUNT_WIDTH)
		countLabel:SetText(colorize("79C0FF", "Bags: " .. SmartRez:GetBagItemCount(itemID)))
		row:AddChild(countLabel)

		row:AddChild(createHorizontalSpacer(ROW_SPACING))

		local removeButton = AceGUI:Create("Button")
		removeButton:SetText("Remove")
		removeButton:SetWidth(REMOVE_BUTTON_WIDTH)
		removeButton:SetCallback("OnClick", function()
			removeItemFunc(itemID)
		end)
		row:AddChild(removeButton)
	end
end

local function renderItemWhitelistGroup(parent, config)
	local group = AceGUI:Create("InlineGroup")
	group:SetTitle(config.title)
	group:SetFullWidth(true)
	group:SetLayout("List")
	parent:AddChild(group)

	local help = AceGUI:Create("Label")
	help:SetFullWidth(true)
	help:SetText(colorize("A5D6FF", config.helpText))
	group:AddChild(help)

	if config.summaryText then
		local summary = AceGUI:Create("Label")
		summary:SetFullWidth(true)
		summary:SetText(config.summaryText)
		group:AddChild(summary)
	end

	addSectionSpacer(group)

	local controlRow = AceGUI:Create("SimpleGroup")
	controlRow:SetFullWidth(true)
	controlRow:SetLayout("Flow")
	group:AddChild(controlRow)

	controlRow:AddChild(createCursorItemButton(config.addItemFunc, config.missingItemMessage))
	controlRow:AddChild(createHorizontalSpacer(CONTROL_SPACING))

	local controlHint = AceGUI:Create("Label")
	controlHint:SetWidth(CONTROL_HINT_WIDTH)
	controlHint:SetText(colorize("7D8590", "Pick up an item and click the button."))
	controlRow:AddChild(controlHint)

	local itemIDs = getSortedItemIDs(config.getItemSet())
	if #itemIDs == 0 then
		local emptyLabel = AceGUI:Create("Label")
		emptyLabel:SetFullWidth(true)
		emptyLabel:SetText(config.emptyText or "No items configured yet.")
		group:AddChild(emptyLabel)
		return
	end

	addSectionSpacer(group)

	addWhitelistRows(group, itemIDs, config.removeItemFunc)
end

local function renderDisenchantWhitelist(parent)
	renderItemWhitelistGroup(parent, {
		title = "Disenchant Items",
		helpText = "Items Gold Printer may disenchant.",
		getItemSet = function()
			return SmartRez:GetDisenchantWhitelist()
		end,
		addItemFunc = function(itemID)
			SmartRez:AddDisenchantWhitelistItem(itemID)
		end,
		removeItemFunc = function(itemID)
			SmartRez:RemoveDisenchantWhitelistItem(itemID)
		end,
		missingItemMessage = "Smart Rez: pick up an item first, then add it to the disenchant list.",
		emptyText = "No disenchant items configured yet.",
	})
end

local function renderRecipeCraftGroup(parent)
	local recipeGroup = AceGUI:Create("InlineGroup")
	recipeGroup:SetTitle("Shard Craft")
	recipeGroup:SetFullWidth(true)
	recipeGroup:SetLayout("List")
	parent:AddChild(recipeGroup)

	local recipeConfig = SmartRez:GetRecipeCraftConfig("shardcraft")

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
	recipeHelp:SetText(colorize("A5D6FF", "Save the active profession recipe and reagents for Gold Printer."))
	recipeGroup:AddChild(recipeHelp)

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
	reagentHeader:SetText(colorize("FFD866", "Reagents:"))
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
		emptyReagents:SetText("No reagents captured yet.")
		recipeGroup:AddChild(emptyReagents)
	end
end

local function renderGoldPrinterGroup(parent)
	local goldPrinterGroup = AceGUI:Create("InlineGroup")
	goldPrinterGroup:SetTitle("Gold Printer")
	goldPrinterGroup:SetFullWidth(true)
	goldPrinterGroup:SetLayout("List")
	parent:AddChild(goldPrinterGroup)

	local goldPrinterHelp = AceGUI:Create("Label")
	goldPrinterHelp:SetFullWidth(true)
	goldPrinterHelp:SetText(colorize("A5D6FF", "Crafts, then disenchants, then shatters."))
	goldPrinterGroup:AddChild(goldPrinterHelp)

	local goldPrinterStatus = AceGUI:Create("Label")
	goldPrinterStatus:SetFullWidth(true)
	goldPrinterStatus:SetText("Phase: " .. getGoldPrinterStatusText())
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
end

local function renderGoldPrinterTab(parent)
	renderDisenchantWhitelist(parent)
	renderRecipeCraftGroup(parent)
	renderGoldPrinterGroup(parent)
end

local function getAutomationTabValue(actionKey)
	return "salvage:" .. tostring(actionKey)
end

local function getAutomationTabAction(groupValue)
	local actionKey = type(groupValue) == "string" and groupValue:match("^salvage:(.+)$")
	if actionKey then
		return SmartRez:GetCraftSalvageAction(actionKey)
	end
end

local function buildAutomationTabs()
	local tabs = {
		{ text = "Gold Printer", value = "goldprinter" },
	}

	for _, action in ipairs(SmartRez:GetCraftSalvageActions()) do
		tabs[#tabs + 1] = {
			text = action.label,
			value = getAutomationTabValue(action.key),
		}
	end

	return tabs
end

local function isAutomationTabAvailable(groupValue)
	return groupValue == "goldprinter" or getAutomationTabAction(groupValue) ~= nil
end

local function renderCraftSalvageTab(parent, action)
	local summary = AceGUI:Create("InlineGroup")
	summary:SetTitle(action.label)
	summary:SetFullWidth(true)
	summary:SetLayout("List")
	parent:AddChild(summary)

	local summaryLabel = AceGUI:Create("Label")
	summaryLabel:SetFullWidth(true)
	summaryLabel:SetText(string.format(
		"%s %s  |  %s %s",
		colorize("A5D6FF", "Stack:"),
		tostring(action.requiredStack or 1),
		colorize("A5D6FF", "Keybinds:"),
		"main settings"
	))
	summary:AddChild(summaryLabel)

	local target = SmartRez:GetCraftSalvageTarget(action.key)
	local targetLabel = AceGUI:Create("Label")
	targetLabel:SetFullWidth(true)
	if target then
		targetLabel:SetText(colorize("7EE787", "Target: ") .. string.format(
			"%s x%d",
			select(1, getItemDisplay(target.itemInfo.itemID)),
			target.itemInfo.stackCount or 0
		))
	else
		targetLabel:SetText(colorize("FFB86C", "Target: ") .. "none in bags")
	end
	summary:AddChild(targetLabel)

	renderItemWhitelistGroup(parent, {
		title = "Allowed Items",
		helpText = "Items allowed for " .. string.lower(action.label) .. ".",
		getItemSet = function()
			return SmartRez:GetCraftSalvageWhitelist(action.key)
		end,
		addItemFunc = function(itemID)
			SmartRez:AddCraftSalvageWhitelistItem(action.key, itemID)
		end,
		removeItemFunc = function(itemID)
			SmartRez:RemoveCraftSalvageWhitelistItem(action.key, itemID)
		end,
		missingItemMessage = "Smart Rez: pick up an item first, then add it to " .. string.lower(action.label) .. ".",
		emptyText = "No items configured yet.",
	})
end

local function renderAutomationFooter(parent)
	local footerGroup = AceGUI:Create("SimpleGroup")
	footerGroup:SetFullWidth(true)
	footerGroup:SetLayout("Flow")
	parent:AddChild(footerGroup)

	local closeButton = AceGUI:Create("Button")
	closeButton:SetText(CLOSE)
	closeButton:SetWidth(100)
	closeButton:SetCallback("OnClick", function()
		automationConfigFrame:Hide()
	end)
	footerGroup:AddChild(closeButton)
end

local function renderAutomationGroup(tabGroup, groupValue)
	tabGroup:ReleaseChildren()

	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetLayout("List")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	tabGroup:AddChild(scroll)

	if groupValue == "goldprinter" then
		renderGoldPrinterTab(scroll)
	else
		local action = getAutomationTabAction(groupValue)
		if action then
			renderCraftSalvageTab(scroll, action)
		end
	end

	renderAutomationFooter(scroll)
end

local function createAutomationConfigWindow()
	if automationConfigFrame then
		return automationConfigFrame
	end

	automationConfigFrame = AceGUI:Create("Window")
	automationConfigFrame:SetTitle(APP_NAME .. " Setup")
	automationConfigFrame:SetStatusText("")
	automationConfigFrame:SetWidth(WINDOW_WIDTH)
	automationConfigFrame:SetHeight(WINDOW_HEIGHT)
	automationConfigFrame:EnableResize(false)
	automationConfigFrame:SetLayout("Fill")
	automationConfigFrame.frame:SetFrameStrata("DIALOG")
	automationConfigFrame:SetCallback("OnClose", function(widget)
		widget:Hide()
	end)

	-- TabGroup works best with an outer Fill layout and an inner ScrollFrame per tab.
	automationConfigFrame.tabs = AceGUI:Create("TabGroup")
	automationConfigFrame.tabs:SetLayout("Fill")
	automationConfigFrame.tabs:SetCallback("OnGroupSelected", function(widget, _, groupValue)
		automationConfigFrame.selectedGroup = groupValue
		renderAutomationGroup(widget, groupValue)
	end)
	automationConfigFrame:AddChild(automationConfigFrame.tabs)

	function automationConfigFrame:Refresh()
		local tabs = buildAutomationTabs()
		self.tabs:SetTabs(tabs)

		local selectedGroup = self.selectedGroup
		if not selectedGroup or not isAutomationTabAvailable(selectedGroup) then
			selectedGroup = "goldprinter"
		end

		self.selectedGroup = selectedGroup
		self.tabs:SelectTab(selectedGroup)
	end

	table.insert(SmartRez.managedFrames, automationConfigFrame)
	return automationConfigFrame
end

function SmartRez:ShowAutomationConfigWindow()
	local configWindow = createAutomationConfigWindow()
	configWindow:Refresh()
	configWindow:Show()
end
