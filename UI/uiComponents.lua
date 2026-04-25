local SmartRez = _G.SmartRez

---@type AceGUILib
local AceGUI = LibStub("AceGUI-3.0")

SmartRez.UI = SmartRez.UI or {}
SmartRez.iconPickerUi = SmartRez.iconPickerUi or {}

local UI = SmartRez.UI
local IconPickerUi = SmartRez.iconPickerUi

local CURSOR_BUTTON_WIDTH = 150
local CONTROL_SPACING = 14
local CONTROL_HINT_WIDTH = 330
local ITEM_ICON_SIZE = 36
local ITEM_ICON_WIDGET_SIZE = 56
local ITEM_ICON_BORDER_SIZE = 46
local ITEM_QUALITY_BADGE_SIZE = 27

function UI.Colorize(hexColor, text)
	return string.format("|cff%s%s|r", hexColor, tostring(text))
end

function UI.GetItemDisplay(itemID)
	if not itemID then
		return "Empty"
	end

	local itemName, itemLink, _, _, _, _, _, _, _, itemIcon = C_Item.GetItemInfo(itemID)
	return itemLink or itemName or ("item:" .. itemID), itemIcon
end

function UI.GetItemVisualInfo(itemID)
	if not itemID then
		return "Empty", nil, nil
	end

	local itemName, itemLink, _, _, _, _, _, _, _, itemIcon = C_Item.GetItemInfo(itemID)
	local reagentQuality = C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo and C_TradeSkillUI.GetItemReagentQualityByItemInfo(itemID) or nil
	return itemLink or itemName or ("item:" .. itemID), itemIcon, reagentQuality
end

function UI.GetDisplayFromLinkOrID(itemLink, itemID)
	if itemLink then
		local _, _, _, _, _, _, _, _, _, itemIcon = C_Item.GetItemInfo(itemLink)
		return itemLink, itemIcon
	end

	return UI.GetItemDisplay(itemID)
end

function UI.GetItemSetCount(itemSet)
	local count = 0

	for _ in pairs(itemSet or {}) do
		count = count + 1
	end

	return count
end

function UI.MergeAvailableAndSelectedItemIDs(availableItemIDs, selectedSet)
	local mergedItemIDs = {}
	local seen = {}

	for _, itemID in ipairs(availableItemIDs or {}) do
		if itemID and not seen[itemID] then
			seen[itemID] = true
			mergedItemIDs[#mergedItemIDs + 1] = itemID
		end
	end

	for itemID, selected in pairs(selectedSet or {}) do
		if selected and itemID and not seen[itemID] then
			seen[itemID] = true
			mergedItemIDs[#mergedItemIDs + 1] = itemID
		end
	end

	return mergedItemIDs
end

function UI.FormatMoney(value)
	value = math.max(0, math.floor(tonumber(value) or 0))

	local gold = math.floor(value / 10000)
	local silver = math.floor((value % 10000) / 100)
	if gold > 0 then
		return string.format("%dg %ds", gold, silver)
	end

	return string.format("%ds", silver)
end

function UI.FormatMoneyDelta(value)
	value = math.floor(tonumber(value) or 0)
	local prefix = value >= 0 and "+" or "-"
	return prefix .. UI.FormatMoney(math.abs(value))
end

function UI.CreateIconButton(parent, config)
	config = config or {}

	local button = AceGUI:Create("Button")
	button:SetWidth(config.width or 32)
	button:SetText(config.text or "")
	button:SetCallback("OnClick", function()
		if config.onClick then
			config.onClick()
		end
	end)

	if config.tooltip then
		button:SetCallback("OnEnter", function(widget)
			GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
			GameTooltip:AddLine(config.tooltip, 1, 1, 1)
			if config.tooltipNote then
				GameTooltip:AddLine(config.tooltipNote, 0.65, 0.78, 1, true)
			end
			GameTooltip:Show()
		end)
		button:SetCallback("OnLeave", function()
			GameTooltip:Hide()
		end)
	end

	parent:AddChild(button)

	local iconSize = config.iconSize or 16
	local frame = button.frame
	if frame and (config.texture or config.atlas) then
		button.iconTexture = button.iconTexture or frame:CreateTexture(nil, "OVERLAY")
		button.iconTexture:ClearAllPoints()
		button.iconTexture:SetSize(iconSize, iconSize)
		button.iconTexture:SetPoint("CENTER", frame, "CENTER", 0, 0)
		if config.atlas and button.iconTexture.SetAtlas then
			button.iconTexture:SetAtlas(config.atlas)
		else
			button.iconTexture:SetTexture(config.texture)
		end
		button.iconTexture:Show()
		button:SetCallback("OnRelease", function(widget)
			if widget.iconTexture then
				widget.iconTexture:SetTexture(nil)
				widget.iconTexture:Hide()
			end
		end)
	end

	return button
end

function UI.GetWindowStatus(windowKey, defaults)
	SmartRez:EnsureConfig()
	if type(SmartRez.db.uiWindows) ~= "table" then
		SmartRez.db.uiWindows = {}
	end

	local status = SmartRez.db.uiWindows[windowKey]
	if type(status) ~= "table" then
		status = {}
		SmartRez.db.uiWindows[windowKey] = status
	end

	for key, value in pairs(defaults or {}) do
		if status[key] == nil then
			status[key] = value
		end
	end

	return status
end

local function getCursorItemID()
	local cursorType, itemID = GetCursorInfo()
	if cursorType == "item" and itemID then
		return itemID
	end
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

function UI.CreateHorizontalSpacer(width)
	local spacer = AceGUI:Create("Label")
	spacer:SetWidth(width or 10)
	spacer:SetText(" ")
	return spacer
end

---@param parent AceGUIContainer
function UI.AddSectionSpacer(parent)
	local spacer = AceGUI:Create("Label")
	spacer:SetFullWidth(true)
	spacer:SetText(" ")
	parent:AddChild(spacer)
end

---@param parent AceGUIContainer
function UI.CreateCard(parent, title)
	local group = AceGUI:Create("InlineGroup")
	group:SetTitle(title)
	group:SetFullWidth(true)
	group:SetLayout("List")
	parent:AddChild(group)
	return group
end

---@param parent AceGUIContainer
function UI.AddLabel(parent, text, color)
	local label = AceGUI:Create("Label")
	label:SetFullWidth(true)
	label:SetText(color and UI.Colorize(color, text) or text)
	parent:AddChild(label)
	return label
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

function UI.CreateCursorItemButton(addItemFunc, missingItemMessage)
	local button = AceGUI:Create("Button")
	button:SetText("Add Cursor Item")
	button:SetWidth(CURSOR_BUTTON_WIDTH)
	button:SetCallback("OnClick", function()
		tryUseCursorItem(addItemFunc, missingItemMessage)
	end)
	return button
end

function UI.GetInventorySourcesSummary(inventorySources)
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
function UI.RenderInventorySourcesGroup(parent, config)
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
	local group = UI.CreateCard(parent, title)

	UI.AddLabel(group, helpText, "A5D6FF")
	UI.AddLabel(group, "Currently using: " .. UI.GetInventorySourcesSummary(inventorySources), "79C0FF")

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
function UI.RenderIconMultiPicker(parent, config)
	local group = UI.CreateCard(parent, config.title)

	UI.AddLabel(group, config.helpText, "A5D6FF")

	local summary
	if config.summaryText then
		summary = UI.AddLabel(group, config.summaryText)
	end

	local selectedSet = config.getSelectedSet() or {}
	local displayItemIDs = UI.MergeAvailableAndSelectedItemIDs(config.availableItemIDs, selectedSet)
	local selectedCount = UI.GetItemSetCount(selectedSet)
	local useMidnightQualityIcons = shouldUseMidnightQualityIcons(displayItemIDs)

	local statusLabel = AceGUI:Create("Label")
	statusLabel:SetFullWidth(true)
	local function updateStatusLabel()
		selectedSet = config.getSelectedSet()
		selectedCount = UI.GetItemSetCount(selectedSet)
		statusLabel:SetText(UI.Colorize(
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
	controlHint:SetText(UI.Colorize("7D8590", config.controlHintText or "Click icons to toggle the whitelist. Leaving it empty means no whitelist restriction."))
	controlRow:AddChild(controlHint)

	UI.AddSectionSpacer(group)

	local iconGrid = AceGUI:Create("SimpleGroup")
	iconGrid:SetFullWidth(true)
	iconGrid:SetLayout("Flow")
	group:AddChild(iconGrid)

	if #displayItemIDs == 0 then
		UI.AddLabel(iconGrid, config.emptyText or "No API items are available for this filter yet.")
		return
	end

	for _, itemID in ipairs(getSortedAvailableItemIDs(displayItemIDs)) do
		local _, itemIcon, reagentQuality = UI.GetItemVisualInfo(itemID)
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
			icon:SetLabel(UI.Colorize(itemCount > 0 and "79C0FF" or "7D8590", tostring(itemCount)))
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
		local function updateIconInventoryState()
			itemCount = config.getItemCount and config.getItemCount(itemID) or SmartRez:GetBagItemCount(itemID)
			if config.getIconLabel then
				icon:SetLabel(config.getIconLabel(itemID, itemCount))
			else
				icon:SetLabel(UI.Colorize(itemCount > 0 and "79C0FF" or "7D8590", tostring(itemCount)))
			end
			if icon.image and icon.image.SetVertexColor then
				if itemCount > 0 then
					icon.image:SetVertexColor(1, 1, 1, 1)
				else
					icon.image:SetVertexColor(0.65, 0.65, 0.65, 0.85)
				end
			end
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
		if SmartRez.RegisterAutomationConfigInventoryRefresher then
			SmartRez:RegisterAutomationConfigInventoryRefresher(updateIconInventoryState)
		end

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
function UI.RenderIconSingleChoiceRow(parent, config)
	local row = AceGUI:Create("SimpleGroup")
	row:SetFullWidth(true)
	row:SetLayout("List")
	parent:AddChild(row)

	UI.AddLabel(row, config.label or "Item Choice", "A5D6FF")

	local availableItemIDs = config.availableItemIDs or {}
	if #availableItemIDs == 0 then
		UI.AddLabel(row, config.emptyText or "No item choices are available.")
		return
	end

	local iconRow = AceGUI:Create("SimpleGroup")
	iconRow:SetFullWidth(true)
	iconRow:SetLayout("Flow")
	row:AddChild(iconRow)

	local icons = {}
	local useMidnightQualityIcons = shouldUseMidnightQualityIcons(availableItemIDs)

	local function updateAllIcons()
		local selectedItemID = config.getSelectedItemID and config.getSelectedItemID() or nil
		for itemID, iconData in pairs(icons) do
			local isSelected = selectedItemID == itemID
			if iconData.icon.frame and iconData.icon.frame.LockHighlight and iconData.icon.frame.UnlockHighlight then
				if isSelected then
					iconData.icon.frame:LockHighlight()
				else
					iconData.icon.frame:UnlockHighlight()
				end
			end
			updateFilterIconChrome(iconData.icon, iconData.reagentQuality, useMidnightQualityIcons, isSelected)
		end
	end

	for _, itemID in ipairs(getSortedAvailableItemIDs(availableItemIDs)) do
		local rowItemID = itemID
		local _, itemIcon, reagentQuality = UI.GetItemVisualInfo(rowItemID)
		local itemCount = config.getItemCount and config.getItemCount(rowItemID) or SmartRez:GetBagItemCount(rowItemID)

		---@type AceGUIIcon
		local icon = AceGUI:Create("Icon")
		icon:SetWidth(config.iconWidth or ITEM_ICON_WIDGET_SIZE)
		icon:SetHeight(config.iconHeight or (ITEM_ICON_WIDGET_SIZE + 12))
		icon:SetImage(itemIcon or 134400)
		icon:SetImageSize(config.iconImageSize or ITEM_ICON_SIZE, config.iconImageSize or ITEM_ICON_SIZE)
		if config.getIconLabel then
			icon:SetLabel(config.getIconLabel(rowItemID, itemCount))
		else
			icon:SetLabel(UI.Colorize(itemCount > 0 and "79C0FF" or "7D8590", tostring(itemCount)))
		end
		icon:SetCallback("OnClick", function()
			local selectedItemID = config.getSelectedItemID and config.getSelectedItemID() or nil
			local nextItemID = rowItemID
			if selectedItemID == rowItemID and config.allowClear then
				nextItemID = nil
			end
			if config.onChoiceChanged then
				config.onChoiceChanged(nextItemID, rowItemID)
			end
			updateAllIcons()
		end)
		icon:SetCallback("OnEnter", function(widget)
			local selectedItemID = config.getSelectedItemID and config.getSelectedItemID() or nil
			local isSelected = selectedItemID == rowItemID
			GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
			GameTooltip:SetItemByID(rowItemID)
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(itemCount > 0 and ("Stored: " .. tostring(itemCount)) or "Stored: 0", 0.48, 0.75, 1)
			GameTooltip:AddLine(isSelected and "Selected" or "Not selected", 0.49, isSelected and 0.91 or 0.52, isSelected and 0.53 or 0.56)
			if config.addTooltipLines then
				config.addTooltipLines(GameTooltip, rowItemID, itemCount, isSelected)
			end
			GameTooltip:Show()
		end)
		icon:SetCallback("OnLeave", function()
			GameTooltip:Hide()
		end)
		local function updateIconInventoryState()
			itemCount = config.getItemCount and config.getItemCount(rowItemID) or SmartRez:GetBagItemCount(rowItemID)
			if config.getIconLabel then
				icon:SetLabel(config.getIconLabel(rowItemID, itemCount))
			else
				icon:SetLabel(UI.Colorize(itemCount > 0 and "79C0FF" or "7D8590", tostring(itemCount)))
			end
		end
		if SmartRez.RegisterAutomationConfigInventoryRefresher then
			SmartRez:RegisterAutomationConfigInventoryRefresher(updateIconInventoryState)
		end

		icons[rowItemID] = {
			icon = icon,
			reagentQuality = reagentQuality,
		}
		iconRow:AddChild(icon)
	end

	updateAllIcons()
end

IconPickerUi.RenderMultiSelectGroup = UI.RenderIconMultiPicker
IconPickerUi.RenderSingleChoiceRow = UI.RenderIconSingleChoiceRow
