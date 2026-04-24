local SmartRez = _G.SmartRez
local APP_NAME = SmartRez.appName

---@type AceGUILib
local AceGUI = LibStub("AceGUI-3.0")

SmartRez.managedFrames = SmartRez.managedFrames or {}

---@class SmartRezAutomationWindow: AceGUIWindow
---@field frame table
---@field tabs AceGUITabGroup
---@field selectedGroup string?
---@field scrollStatuses table<string, table>
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
local ITEM_ICON_SIZE = 36
local ITEM_ICON_WIDGET_SIZE = 56
local ITEM_ICON_BORDER_SIZE = 46
local ITEM_QUALITY_BADGE_SIZE = 27

---@class SmartRezBagValueSnapshotItem
---@field itemID number
---@field itemLink string?
---@field itemIcon number?
---@field count number
---@field totalValue number
---@field pricedQuantity number
---@field missingPriceQuantity number
---@field minUnitPrice number?
---@field maxUnitPrice number?

---@class SmartRezBagValueSnapshot
---@field priceSource string
---@field onlyAuctionable boolean
---@field inventorySources table
---@field isTSMAvailable boolean
---@field hasSelection boolean
---@field availableItemIDs number[]
---@field itemsByID table<number, SmartRezBagValueSnapshotItem>
---@field totalAvailableQuantity number
---@field totalSelectedQuantity number
---@field totalSelectedValue number
---@field totalSelectedValueText string
---@field selectedItemTypes number
---@field availableItemTypes number
---@field missingPriceQuantity number
---@field invalidPriceMessage string?

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

	local itemName, itemLink, _, _, _, _, _, _, _, itemIcon = C_Item.GetItemInfo(itemID)
	return itemLink or itemName or ("item:" .. itemID), itemIcon
end

local function getItemVisualInfo(itemID)
	if not itemID then
		return "Empty", nil, nil
	end

	local itemName, itemLink, _, _, _, _, _, _, _, itemIcon = C_Item.GetItemInfo(itemID)
	local reagentQuality = C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo and C_TradeSkillUI.GetItemReagentQualityByItemInfo(itemID) or nil
	return itemLink or itemName or ("item:" .. itemID), itemIcon, reagentQuality
end

local function getDisplayFromLinkOrID(itemLink, itemID)
	if itemLink then
		local _, _, _, _, _, _, _, _, _, itemIcon = C_Item.GetItemInfo(itemLink)
		return itemLink, itemIcon
	end

	return getItemDisplay(itemID)
end

local function getCursorItemID()
	local cursorType, itemID = GetCursorInfo()
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

local function getSortedAvailableItemIDs(itemIDs)
	local sortedItemIDs = {}

	for _, itemID in ipairs(itemIDs or {}) do
		sortedItemIDs[#sortedItemIDs + 1] = itemID
	end

	table.sort(sortedItemIDs, function(leftItemID, rightItemID)
		local leftName = C_Item.GetItemNameByID(leftItemID) or tostring(leftItemID)
		local rightName = C_Item.GetItemNameByID(rightItemID) or tostring(rightItemID)
		if leftName == rightName then
			return leftItemID < rightItemID
		end
		return leftName < rightName
	end)

	return sortedItemIDs
end

local function getItemSetCount(itemSet)
	local count = 0

	for _ in pairs(itemSet or {}) do
		count = count + 1
	end

	return count
end

local function formatMoney(value)
	value = math.max(0, math.floor(tonumber(value) or 0))

	if GetMoneyString then
		return GetMoneyString(value, true)
	end

	local gold = math.floor(value / 10000)
	local silver = math.floor((value % 10000) / 100)
	local copper = value % 100
	return string.format("%dg %ds %dc", gold, silver, copper)
end

local function normalizeCraftingQuality(reagentQuality, useMidnightIcon)
	if not reagentQuality or reagentQuality < 1 then
		return nil, false
	end

	if reagentQuality > 10 then
		return reagentQuality - 10, true
	end

	return reagentQuality, useMidnightIcon == true
end

local function shouldUseMidnightQualityIcons(itemIDs)
	local minQuality, maxQuality = nil, nil
	local qualityCount = 0
	local seenQualities = {}

	for _, itemID in ipairs(itemIDs or {}) do
		local reagentQuality = C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo and C_TradeSkillUI.GetItemReagentQualityByItemInfo(itemID) or nil
		local normalizedQuality, encodedMidnight = normalizeCraftingQuality(reagentQuality, false)

		if encodedMidnight then
			return true
		end

		if normalizedQuality and not seenQualities[normalizedQuality] then
			seenQualities[normalizedQuality] = true
			qualityCount = qualityCount + 1
			minQuality = minQuality and math.min(minQuality, normalizedQuality) or normalizedQuality
			maxQuality = maxQuality and math.max(maxQuality, normalizedQuality) or normalizedQuality
		end
	end

	return qualityCount == 2 and minQuality == 1 and maxQuality == 2
end

---@param icon AceGUIIcon
local function updateFilterIconChrome(icon, reagentQuality, useMidnightIcon, isSelected)
	if not icon.frame or not icon.image then
		return
	end

	if not icon.qualityBadge then
		local qualityBadge = icon.frame:CreateTexture(nil, "ARTWORK")
		qualityBadge:SetSize(ITEM_QUALITY_BADGE_SIZE, ITEM_QUALITY_BADGE_SIZE)
		qualityBadge:SetPoint("CENTER", icon.image, "TOPLEFT", 0, 0)
		icon.qualityBadge = qualityBadge
	end

	if not icon.selectionGlow then
		local selectionGlow = icon.frame:CreateTexture(nil, "OVERLAY")
		selectionGlow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
		selectionGlow:SetBlendMode("ADD")
		selectionGlow:SetSize(ITEM_ICON_BORDER_SIZE + 10, ITEM_ICON_BORDER_SIZE + 10)
		selectionGlow:SetPoint("CENTER", icon.image, "CENTER", 0, 0)
		icon.selectionGlow = selectionGlow
	end

	local normalizedQuality, normalizedUseMidnightIcon = normalizeCraftingQuality(reagentQuality, useMidnightIcon)
	if normalizedQuality and normalizedQuality > 0 then
		local atlasName = string.format(
			normalizedUseMidnightIcon and "Professions-Icon-Quality-12-Tier%d" or "Professions-Icon-Quality-Tier%d",
			normalizedQuality
		)
		if icon.qualityBadge.SetAtlas then
			icon.qualityBadge:SetAtlas(atlasName, true)
			icon.qualityBadge:SetSize(ITEM_QUALITY_BADGE_SIZE, ITEM_QUALITY_BADGE_SIZE)
			icon.qualityBadge:Show()
		else
			icon.qualityBadge:Hide()
		end
	else
		icon.qualityBadge:Hide()
	end

	if isSelected then
		icon.selectionGlow:SetVertexColor(0.45, 0.95, 0.55, 1)
		icon.selectionGlow:Show()
	else
		icon.selectionGlow:Hide()
	end
end

-- AceGUI Flow layouts do not add consistent gutters on their own.
local function createHorizontalSpacer(width)
	local spacer = AceGUI:Create("Label")
	spacer:SetWidth(width or 10)
	spacer:SetText(" ")
	return spacer
end

---@param parent AceGUIContainer
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
	ClearCursor()
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

local function getInventorySourcesSummary(inventorySources)
	inventorySources = inventorySources or SmartRez:GetInventorySources()
	local enabledSources = {}

	if inventorySources.playerBags ~= false then
		enabledSources[#enabledSources + 1] = "bags"
	end

	if inventorySources.warbank == true then
		enabledSources[#enabledSources + 1] = "warbank"
	end

	return table.concat(enabledSources, ", ")
end

---@param parent AceGUIContainer
local function renderInventorySourcesGroup(parent, config)
	config = config or {}
	local getSources = config.getSources or function()
		return SmartRez:GetInventorySources()
	end
	local setSources = config.setSources or function(updatedSources)
		SmartRez:SetInventorySources(updatedSources)
	end
	local title = config.title or "Inventory Sources"
	local helpText = config.helpText or "Choose where Smart Rez looks for crafting, salvage, and disenchant items. Some flows may still require the relevant Blizzard UI to be opened first. Warbank support is available, but it is currently safest to leave it off unless you are actively testing it."
	local inventorySources = getSources()
	local group = AceGUI:Create("InlineGroup")
	group:SetTitle(title)
	group:SetFullWidth(true)
	group:SetLayout("List")
	parent:AddChild(group)

	local help = AceGUI:Create("Label")
	help:SetFullWidth(true)
	help:SetText(colorize("A5D6FF", helpText))
	group:AddChild(help)

	local summary = AceGUI:Create("Label")
	summary:SetFullWidth(true)
	summary:SetText(colorize("79C0FF", "Currently using: " .. getInventorySourcesSummary(inventorySources)))
	group:AddChild(summary)

	local function setSource(sourceKey, enabled)
		local updatedSources = getSources()
		updatedSources[sourceKey] = enabled == true
		setSources(updatedSources)
	end

	local bagCheck = AceGUI:Create("CheckBox")
	bagCheck:SetLabel("Use player bags")
	bagCheck:SetValue(inventorySources.playerBags ~= false)
	bagCheck:SetCallback("OnValueChanged", function(_, _, value)
		setSource("playerBags", value)
	end)
	group:AddChild(bagCheck)

	local warbankCheck = AceGUI:Create("CheckBox")
	warbankCheck:SetLabel("Use warbank")
	warbankCheck:SetValue(inventorySources.warbank == true)
	warbankCheck:SetCallback("OnValueChanged", function(_, _, value)
		setSource("warbank", value)
	end)
	group:AddChild(warbankCheck)
end

---@param parent AceGUIContainer
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
		countLabel:SetText(colorize("79C0FF", "Stored: " .. SmartRez:GetBagItemCount(itemID)))
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

---@param parent AceGUIContainer
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

---@param parent AceGUIContainer
local function renderItemIconFilterGroup(parent, config)
	local group = AceGUI:Create("InlineGroup")
	group:SetTitle(config.title)
	group:SetFullWidth(true)
	group:SetLayout("List")
	parent:AddChild(group)

	local help = AceGUI:Create("Label")
	help:SetFullWidth(true)
	help:SetText(colorize("A5D6FF", config.helpText))
	group:AddChild(help)

	local summary
	if config.summaryText then
		summary = AceGUI:Create("Label")
		summary:SetFullWidth(true)
		summary:SetText(config.summaryText)
		group:AddChild(summary)
	end

	local selectedSet = config.getSelectedSet()
	local selectedCount = getItemSetCount(selectedSet)
	local useMidnightQualityIcons = shouldUseMidnightQualityIcons(config.availableItemIDs)

	local statusLabel = AceGUI:Create("Label")
	statusLabel:SetFullWidth(true)
	local function updateStatusLabel()
		selectedSet = config.getSelectedSet()
		selectedCount = getItemSetCount(selectedSet)
		statusLabel:SetText(colorize(
			"7D8590",
			selectedCount == 0 and (config.emptySelectionText or "No whitelist entries. Click icons to build one, or leave it empty.")
				or ((config.selectedStatusTextPrefix or "Selected ") .. tostring(selectedCount) .. (config.selectedStatusTextSuffix or " item(s). Click highlighted icons to remove them."))
		))
	end
	updateStatusLabel()
	group:AddChild(statusLabel)

	local controlRow = AceGUI:Create("SimpleGroup")
	controlRow:SetFullWidth(true)
	controlRow:SetLayout("Flow")
	group:AddChild(controlRow)

	local controlHint = AceGUI:Create("Label")
	controlHint:SetWidth(CONTROL_HINT_WIDTH + 120)
	controlHint:SetText(colorize("7D8590", config.controlHintText or "Click icons to toggle the whitelist. Leaving it empty means no whitelist restriction."))
	controlRow:AddChild(controlHint)

	addSectionSpacer(group)

	local iconGrid = AceGUI:Create("SimpleGroup")
	iconGrid:SetFullWidth(true)
	iconGrid:SetLayout("Flow")
	group:AddChild(iconGrid)

	if #(config.availableItemIDs or {}) == 0 then
		local emptyLabel = AceGUI:Create("Label")
		emptyLabel:SetFullWidth(true)
		emptyLabel:SetText(config.emptyText or "No API items are available for this filter yet.")
		iconGrid:AddChild(emptyLabel)
		return
	end

	for _, itemID in ipairs(getSortedAvailableItemIDs(config.availableItemIDs)) do
		local _, itemIcon, reagentQuality = getItemVisualInfo(itemID)
		local itemCount = config.getItemCount and config.getItemCount(itemID) or SmartRez:GetBagItemCount(itemID)
		local isExplicitlySelected = selectedSet[itemID] == true
		local isSelected = isExplicitlySelected

		---@type AceGUIIcon
		local icon = AceGUI:Create("Icon")
		icon:SetWidth(ITEM_ICON_WIDGET_SIZE)
		icon:SetHeight(ITEM_ICON_WIDGET_SIZE + 16)
		icon:SetImage(itemIcon or 134400)
		icon:SetImageSize(ITEM_ICON_SIZE, ITEM_ICON_SIZE)
		if config.getIconLabel then
			icon:SetLabel(config.getIconLabel(itemID, itemCount))
		else
			icon:SetLabel(colorize(itemCount > 0 and "79C0FF" or "7D8590", tostring(itemCount)))
		end
		local function updateIconSelectionState()
			selectedSet = config.getSelectedSet()
			isExplicitlySelected = selectedSet[itemID] == true
			isSelected = isExplicitlySelected

			if icon.frame and icon.frame.LockHighlight and icon.frame.UnlockHighlight then
				if isSelected then
					icon.frame:LockHighlight()
				else
					icon.frame:UnlockHighlight()
				end
			end

			updateFilterIconChrome(icon, reagentQuality, useMidnightQualityIcons, isSelected)
			updateStatusLabel()
			if summary and config.getSummaryText then
				summary:SetText(config.getSummaryText())
			end
		end
		icon:SetCallback("OnClick", function()
			if isExplicitlySelected then
				config.removeItemFunc(itemID)
			else
				config.addItemFunc(itemID)
			end
			updateIconSelectionState()
		end)
		icon:SetCallback("OnEnter", function(widget)
			GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
			GameTooltip:SetItemByID(itemID)
			if config.addTooltipLines then
				config.addTooltipLines(GameTooltip, itemID, itemCount, isSelected)
			else
				GameTooltip:AddLine(" ")
				GameTooltip:AddLine(itemCount > 0 and ("Stored: " .. tostring(itemCount)) or "Stored: 0", 0.48, 0.75, 1)
				GameTooltip:AddLine(isSelected and "Whitelisted" or "Not whitelisted", isSelected and 0.49 or 0.49, isSelected and 0.91 or 0.52, isSelected and 0.53 or 0.56)
			end
			GameTooltip:Show()
		end)
		icon:SetCallback("OnLeave", function()
			GameTooltip:Hide()
		end)

		updateIconSelectionState()

		if icon.image and icon.image.SetVertexColor then
			if itemCount > 0 then
				icon.image:SetVertexColor(1, 1, 1, 1)
			else
				icon.image:SetVertexColor(0.65, 0.65, 0.65, 0.85)
			end
		end

		iconGrid:AddChild(icon)
	end
end

---@param parent AceGUIContainer
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

---@param parent AceGUIContainer
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

---@param parent AceGUIContainer
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
		SmartRez:SetGoldPrinterMinFreeSlots(math.floor((value or 1) + 0.5), true)
	end)
	goldPrinterGroup:AddChild(goldPrinterSlider)

end

---@param parent AceGUIContainer
local function renderGoldPrinterTab(parent)
	renderInventorySourcesGroup(parent)
	renderDisenchantWhitelist(parent)
	renderRecipeCraftGroup(parent)
	renderGoldPrinterGroup(parent)
end

---@param parent AceGUIContainer
---@param snapshot SmartRezBagValueSnapshot
local function renderBagValueSummaryGroup(parent, snapshot)
	local group = AceGUI:Create("InlineGroup")
	group:SetTitle("Auctionable Bag Value")
	group:SetFullWidth(true)
	group:SetLayout("List")
	parent:AddChild(group)

	local help = AceGUI:Create("Label")
	help:SetFullWidth(true)
	help:SetText(colorize("A5D6FF", "Select item types below and Smart Rez will keep a live total for those items across the enabled source groups."))
	group:AddChild(help)

	local totalLabel = AceGUI:Create("Label")
	totalLabel:SetFullWidth(true)
	totalLabel:SetText(colorize("7EE787", "Selected value: ") .. snapshot.totalSelectedValueText)
	group:AddChild(totalLabel)

	local countsLabel = AceGUI:Create("Label")
	countsLabel:SetFullWidth(true)
	countsLabel:SetText(string.format(
		"%s %d/%d  |  %s %d  |  %s %s",
		colorize("A5D6FF", "Selected items:"),
		snapshot.selectedItemTypes,
		snapshot.availableItemTypes,
		colorize("A5D6FF", "Selected quantity:"),
		snapshot.totalSelectedQuantity,
		colorize("A5D6FF", "Sources:"),
		getInventorySourcesSummary(snapshot.inventorySources)
	))
	group:AddChild(countsLabel)

	---@type AceGUIEditBox
	local priceEdit = AceGUI:Create("EditBox")
	priceEdit:SetFullWidth(true)
	priceEdit:SetLabel("TSM price source / custom price")
	priceEdit:SetText(snapshot.priceSource)
	priceEdit:SetCallback("OnEnterPressed", function(_, _, value)
		SmartRez:SetBagValuePriceSource(value)
	end)
	group:AddChild(priceEdit)

	local filterCheck = AceGUI:Create("CheckBox")
	filterCheck:SetLabel("Only show auctionable items")
	filterCheck:SetValue(snapshot.onlyAuctionable)
	filterCheck:SetCallback("OnValueChanged", function(_, _, value)
		SmartRez:SetBagValueOnlyAuctionable(value)
	end)
	group:AddChild(filterCheck)

	if not snapshot.isTSMAvailable then
		local warning = AceGUI:Create("Label")
		warning:SetFullWidth(true)
		warning:SetText(colorize("FFB86C", "TradeSkillMaster is not loaded, so Smart Rez cannot evaluate the selected item values yet."))
		group:AddChild(warning)
	elseif snapshot.invalidPriceMessage then
		local warning = AceGUI:Create("Label")
		warning:SetFullWidth(true)
		warning:SetText(colorize("FF7B72", "Price error: " .. tostring(snapshot.invalidPriceMessage)))
		group:AddChild(warning)
	elseif snapshot.missingPriceQuantity > 0 then
		local warning = AceGUI:Create("Label")
		warning:SetFullWidth(true)
		warning:SetText(colorize("FFD866", "Missing price data for " .. tostring(snapshot.missingPriceQuantity) .. " selected item(s)."))
		group:AddChild(warning)
	end

	if not snapshot.hasSelection then
		local hint = AceGUI:Create("Label")
		hint:SetFullWidth(true)
		hint:SetText(colorize("7D8590", "No items selected yet. Click icons below to build your tracked set."))
		group:AddChild(hint)
	end
end

---@param parent AceGUIContainer
local function renderBagValueTab(parent)
	local snapshot = SmartRez:BuildBagValueSnapshot()
	renderInventorySourcesGroup(parent, {
		title = "Value Sources",
		helpText = "Choose where Smart Rez looks for bag-value items. This source selection is separate from crafting, salvage, and disenchant. Enabling warbank here will prime the profession proxy backend so warbank items can enumerate.",
		getSources = function()
			return SmartRez:GetBagValueInventorySources()
		end,
		setSources = function(updatedSources)
			SmartRez:SetBagValueInventorySources(updatedSources)
		end,
	})
	renderBagValueSummaryGroup(parent, snapshot)

	renderItemIconFilterGroup(parent, {
		title = "Tracked Auction Items",
		helpText = "Items from the enabled source groups. Click icons to include or exclude them from the value total.",
		summaryText = colorize("79C0FF", string.format(
			"Available item types: %d  |  Visible quantity: %d",
			snapshot.availableItemTypes,
			snapshot.totalAvailableQuantity
		)),
		getSummaryText = nil,
		availableItemIDs = snapshot.availableItemIDs,
		getSelectedSet = function()
			return SmartRez:GetBagValueWhitelist()
		end,
		getItemCount = function(itemID)
			local itemData = snapshot.itemsByID[itemID]
			return itemData and itemData.count or 0
		end,
		getIconLabel = function(itemID)
			local itemData = snapshot.itemsByID[itemID]
			local itemCount = itemData and itemData.count or 0
			return colorize(itemCount > 0 and "79C0FF" or "7D8590", tostring(itemCount))
		end,
		addTooltipLines = function(tooltip, itemID, _, isSelected)
			local itemData = snapshot.itemsByID[itemID]
			local itemCount = itemData and itemData.count or 0
			tooltip:AddLine(" ")
			tooltip:AddLine("Stored: " .. tostring(itemCount), 0.48, 0.75, 1)
			if itemData and itemData.pricedQuantity > 0 then
				if itemData.minUnitPrice and itemData.maxUnitPrice and itemData.minUnitPrice == itemData.maxUnitPrice then
					tooltip:AddLine("Unit value: " .. formatMoney(itemData.minUnitPrice), 0.49, 0.91, 0.53)
				else
					tooltip:AddLine("Unit value: varies", 0.49, 0.91, 0.53)
				end
				tooltip:AddLine("Selected subtotal: " .. formatMoney(itemData.totalValue), 0.49, 0.91, 0.53)
			end
			if itemData and itemData.missingPriceQuantity > 0 then
				tooltip:AddLine("Missing price on: " .. tostring(itemData.missingPriceQuantity), 1, 0.72, 0.4)
			end
			tooltip:AddLine(isSelected and "Included in total" or "Not included in total", isSelected and 0.49 or 0.49, isSelected and 0.91 or 0.52, isSelected and 0.53 or 0.56)
		end,
		addItemFunc = function(itemID)
			SmartRez:AddBagValueWhitelistItem(itemID)
		end,
		removeItemFunc = function(itemID)
			SmartRez:RemoveBagValueWhitelistItem(itemID)
		end,
		emptySelectionText = "No tracked items selected yet. Click icons to start building the total.",
		selectedStatusTextPrefix = "Tracking ",
		selectedStatusTextSuffix = " item(s). Click highlighted icons to remove them from the total.",
		controlHintText = "Click icons to choose which item types count toward the total. Leaving it empty means the total stays at zero.",
		emptyText = "No visible items matched the current source and auctionability filters.",
	})
end

local function getAutomationTabValue(professionKey)
	return "salvage:" .. tostring(professionKey)
end

local function getAutomationTabProfession(groupValue)
	local professionKey = type(groupValue) == "string" and groupValue:match("^salvage:(.+)$")
	if professionKey then
		return SmartRez:GetCraftSalvageProfession(professionKey)
	end
end

local function buildAutomationTabs()
	local tabs = {
		{ text = "Gold Printer", value = "goldprinter" },
		{ text = "Bag Value", value = "bagvalue" },
	}

	for _, profession in ipairs(SmartRez:GetCraftSalvageProfessions(true)) do
		tabs[#tabs + 1] = {
			text = profession.label,
			value = getAutomationTabValue(profession.key),
		}
	end

	return tabs
end

local function isAutomationTabAvailable(groupValue)
	if groupValue == "goldprinter" then
		return true
	end

	if groupValue == "bagvalue" then
		return true
	end

	local profession = getAutomationTabProfession(groupValue)
	return profession ~= nil and SmartRez:HasProfession(profession.professionID)
end

---@param parent AceGUIContainer
local function renderCraftSalvageTab(parent, profession)
	local selection = SmartRez:GetCraftSalvageSelection(profession.key)
	local whitelistLabel = selection and selection.label or profession.label
	local sourceText = "none"
	if selection then
		sourceText = selection.isDefault and "default" or "saved"
	end

	local summary = AceGUI:Create("InlineGroup")
	summary:SetTitle(profession.label)
	summary:SetFullWidth(true)
	summary:SetLayout("List")
	parent:AddChild(summary)

	local summaryLabel = AceGUI:Create("Label")
	summaryLabel:SetFullWidth(true)
	summaryLabel:SetText(string.format(
		"%s %s  |  %s %s  |  %s %s",
		colorize("A5D6FF", "Recipe:"),
		tostring(selection and selection.label or "Unset"),
		colorize("A5D6FF", "ID:"),
		tostring(selection and selection.recipeID or "Unset"),
		colorize("A5D6FF", "Stack:"),
		tostring(selection and selection.requiredStack or 1)
	))
	summary:AddChild(summaryLabel)

	local sourceLabel = AceGUI:Create("Label")
	sourceLabel:SetFullWidth(true)
	sourceLabel:SetText(string.format(
		"%s %s  |  %s %s",
		colorize("A5D6FF", "Source:"),
		sourceText,
		colorize("A5D6FF", "Keybinds:"),
		"main settings"
	))
	summary:AddChild(sourceLabel)

	local recipeHelp = AceGUI:Create("Label")
	recipeHelp:SetFullWidth(true)
	recipeHelp:SetText(colorize("A5D6FF", "Open this profession, select a salvage recipe, then click Use Selected Recipe."))
	summary:AddChild(recipeHelp)

	local recipeButton = AceGUI:Create("Button")
	recipeButton:SetText("Use Selected Recipe")
	recipeButton:SetWidth(200)
	recipeButton:SetCallback("OnClick", function()
		local ok, err = SmartRez:LoadCraftSalvageSelectionFromCurrentRecipe(profession.key)
		if not ok and err then
			print("Smart Rez:", err)
		end
	end)
	summary:AddChild(recipeButton)

	addSectionSpacer(summary)

	local target = SmartRez:GetCraftSalvageTarget(profession.key)
	local targetLabel = AceGUI:Create("Label")
	targetLabel:SetFullWidth(true)
	if target then
		targetLabel:SetText(colorize("7EE787", "Target: ") .. string.format(
			"%s x%d",
			select(1, getItemDisplay(target.itemInfo.itemID)),
			target.itemInfo.stackCount or 0
		))
	else
		targetLabel:SetText(colorize("FFB86C", "Target: ") .. "none in configured storage")
	end
	summary:AddChild(targetLabel)

	renderInventorySourcesGroup(parent)

	renderItemIconFilterGroup(parent, {
		title = "Salvage Targets",
		helpText = "Items " .. whitelistLabel .. " may salvage. Click icons to build a narrowed target list, or leave it empty.",
		summaryText = colorize("79C0FF", "Whitelist entries: " .. tostring(getItemSetCount(SmartRez:GetCraftSalvageWhitelist(profession.key)))),
		getSummaryText = function()
			return colorize("79C0FF", "Whitelist entries: " .. tostring(getItemSetCount(SmartRez:GetCraftSalvageWhitelist(profession.key))))
		end,
		availableItemIDs = selection and selection.salvageTargetItemIDs or {},
		getSelectedSet = function()
			return SmartRez:GetCraftSalvageWhitelist(profession.key)
		end,
		addItemFunc = function(itemID)
			SmartRez:AddCraftSalvageWhitelistItem(profession.key, itemID, true)
		end,
		removeItemFunc = function(itemID)
			SmartRez:RemoveCraftSalvageWhitelistItem(profession.key, itemID, true)
		end,
	})

	for _, reagentSlot in ipairs(selection and selection.reagentSlots or {}) do
		renderItemIconFilterGroup(parent, {
			title = reagentSlot.label or ("Reagent Slot " .. tostring(reagentSlot.dataSlotIndex)),
			helpText = string.format(
				"Items allowed in this reagent slot. Click icons to build a narrowed list from the %d API-reported options. Need %d per cast.",
				#(reagentSlot.allowedItemIDs or {}),
				reagentSlot.quantityRequired or 0
			),
			summaryText = colorize("79C0FF", string.format(
				"Need: %d  |  Whitelist entries: %d",
				reagentSlot.quantityRequired or 0,
				getItemSetCount(SmartRez:GetCraftSalvageReagentWhitelist(profession.key, reagentSlot.dataSlotIndex))
			)),
			getSummaryText = function()
				return colorize("79C0FF", string.format(
					"Need: %d  |  Whitelist entries: %d",
					reagentSlot.quantityRequired or 0,
					getItemSetCount(SmartRez:GetCraftSalvageReagentWhitelist(profession.key, reagentSlot.dataSlotIndex))
				))
			end,
			availableItemIDs = reagentSlot.allowedItemIDs or {},
			getSelectedSet = function()
				return SmartRez:GetCraftSalvageReagentWhitelist(profession.key, reagentSlot.dataSlotIndex)
			end,
			addItemFunc = function(itemID)
				SmartRez:AddCraftSalvageReagentWhitelistItem(profession.key, reagentSlot.dataSlotIndex, itemID, true)
			end,
			removeItemFunc = function(itemID)
				SmartRez:RemoveCraftSalvageReagentWhitelistItem(profession.key, reagentSlot.dataSlotIndex, itemID, true)
			end,
		})
	end
end

---@param parent AceGUIContainer
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

---@param tabGroup AceGUITabGroup
local function renderAutomationGroup(tabGroup, groupValue)
	tabGroup:ReleaseChildren()

	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetLayout("List")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	if automationConfigFrame then
		automationConfigFrame.scrollStatuses = automationConfigFrame.scrollStatuses or {}
		automationConfigFrame.scrollStatuses[groupValue] = automationConfigFrame.scrollStatuses[groupValue] or {}
		scroll:SetStatusTable(automationConfigFrame.scrollStatuses[groupValue])
	end
	tabGroup:AddChild(scroll)

	if groupValue == "goldprinter" then
		renderGoldPrinterTab(scroll)
	elseif groupValue == "bagvalue" then
		renderBagValueTab(scroll)
	else
		local profession = getAutomationTabProfession(groupValue)
		if profession then
			renderCraftSalvageTab(scroll, profession)
		end
	end

	renderAutomationFooter(scroll)
end

local function createAutomationConfigWindow()
	if automationConfigFrame then
		return automationConfigFrame
	end

	---@type SmartRezAutomationWindow
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
	automationConfigFrame.scrollStatuses = {}

	-- TabGroup works best with an outer Fill layout and an inner ScrollFrame per tab.
	automationConfigFrame.tabs = AceGUI:Create("TabGroup")
	automationConfigFrame.tabs:SetLayout("Fill")
	automationConfigFrame.tabs:SetCallback("OnGroupSelected", function(_, _, groupValue)
		automationConfigFrame.selectedGroup = groupValue
		renderAutomationGroup(automationConfigFrame.tabs, groupValue)
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
