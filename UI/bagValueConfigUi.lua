local SmartRez = _G.SmartRez

---@type AceGUILib
local AceGUI = LibStub("AceGUI-3.0")

local UI = SmartRez.UI
local RESET_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
local POPUP_ICON = "Interface\\Buttons\\UI-Panel-BiggerButton-Up"
local CONFIG_ICON = "Interface\\GossipFrame\\BinderGossipIcon"

local bagValueDisplayState = {
	lastDisplayedTotal = nil,
	lastDelta = 0,
	baselineTotal = nil,
	baselineTime = nil,
}
local bagValuePopupFrame
local bagValuePopupSnapshot
local bagValueRateRefreshers = {}
local bagValueRateTicker

local function colorMoneyText(text)
	text = tostring(text or "")
	text = text:gsub("g", UI.Colorize("FFD866", "g"))
	text = text:gsub("s", UI.Colorize("C0C0C0", "s"))
	return text
end

local function formatBagValueDelta(value)
	value = math.floor(tonumber(value) or 0)
	if value == 0 then
		return ""
	end

	return UI.Colorize(value > 0 and "7EE787" or "FF7B72", colorMoneyText(UI.FormatMoneyDelta(value)))
end

local function getNow()
	if GetTimePreciseSec then
		return GetTimePreciseSec()
	end
	return GetTime()
end

local function resetBagValueRate(snapshot)
	snapshot = snapshot or SmartRez:BuildBagValueSnapshot()
	bagValueDisplayState.baselineTotal = snapshot.totalSelectedValue or 0
	bagValueDisplayState.baselineTime = getNow()
	bagValueDisplayState.lastDisplayedTotal = snapshot.totalSelectedValue or 0
	bagValueDisplayState.lastDelta = 0
end

local function getBagValueElapsedText()
	if not bagValueDisplayState.baselineTime then
		return UI.Colorize("7D8590", "0s")
	end

	local elapsed = math.max(0, math.floor(getNow() - bagValueDisplayState.baselineTime))
	if elapsed >= 3600 then
		return UI.Colorize("7D8590", string.format("%dh %02dm", math.floor(elapsed / 3600), math.floor((elapsed % 3600) / 60)))
	elseif elapsed >= 60 then
		return UI.Colorize("7D8590", string.format("%dm %02ds", math.floor(elapsed / 60), elapsed % 60))
	end

	return UI.Colorize("7D8590", tostring(elapsed) .. "s")
end

local function getBagValuePerHourText(snapshot)
	snapshot = snapshot or SmartRez:BuildBagValueSnapshot()
	if not bagValueDisplayState.baselineTotal or not bagValueDisplayState.baselineTime then
		resetBagValueRate(snapshot)
	end

	local elapsed = math.max(1, getNow() - (bagValueDisplayState.baselineTime or getNow()))
	local delta = (snapshot.totalSelectedValue or 0) - (bagValueDisplayState.baselineTotal or 0)
	local perHour = math.floor(delta * 3600 / elapsed)
	local color = perHour >= 0 and "7EE787" or "FF7B72"
	return UI.Colorize(color, colorMoneyText(UI.FormatMoneyDelta(perHour)) .. "/h")
end

local function refreshOpenBagValuePopupValue()
	if bagValuePopupFrame and bagValuePopupFrame:IsShown() and bagValuePopupFrame.refreshValue then
		bagValuePopupSnapshot = SmartRez:BuildBagValueSnapshot()
		bagValuePopupFrame.refreshValue()
	end
end

local function registerBagValueRateRefresher(callback)
	if type(callback) ~= "function" then
		return
	end

	bagValueRateRefreshers[#bagValueRateRefreshers + 1] = callback
	if bagValueRateTicker or not (C_Timer and C_Timer.NewTicker) then
		return
	end

	bagValueRateTicker = C_Timer.NewTicker(1, function()
		local activeRefreshers = {}
		for _, refresher in ipairs(bagValueRateRefreshers) do
			local ok, keep = pcall(refresher)
			if ok and keep ~= false then
				activeRefreshers[#activeRefreshers + 1] = refresher
			end
		end

		bagValueRateRefreshers = activeRefreshers
		if #activeRefreshers == 0 and bagValueRateTicker then
			bagValueRateTicker:Cancel()
			bagValueRateTicker = nil
		end
	end)
end

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

---@param parent AceGUIContainer
---@param snapshotRef fun(): SmartRezBagValueSnapshot
---@param config? table
function UI.RenderBagValueDisplay(parent, snapshotRef, config)
	config = config or {}
	local snapshot = snapshotRef()
	local group = UI.CreateCard(parent, "Auctionable Bag Value")
	local displayedTotal = snapshot.totalSelectedValue or 0

	if bagValueDisplayState.lastDisplayedTotal == nil then
		bagValueDisplayState.lastDisplayedTotal = displayedTotal
	end
	if not bagValueDisplayState.baselineTotal or not bagValueDisplayState.baselineTime then
		resetBagValueRate(snapshot)
	end

	local rateRow = AceGUI:Create("SimpleGroup")
	rateRow:SetFullWidth(true)
	rateRow:SetLayout("Flow")
	group:AddChild(rateRow)

	local isPopupDisplay = config.showPopupButton == false
	local rateSpacer = AceGUI:Create("Label")
	rateSpacer:SetWidth(isPopupDisplay and 58 or 250)
	rateSpacer:SetText("")
	rateRow:AddChild(rateSpacer)

	---@type AceGUILabel
	local timerLabel = AceGUI:Create("Label")
	timerLabel:SetWidth(72)
	timerLabel:SetText(getBagValueElapsedText())
	timerLabel:SetJustifyH("RIGHT")
	timerLabel:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
	rateRow:AddChild(timerLabel)

	---@type AceGUILabel
	local rateLabel = AceGUI:Create("Label")
	rateLabel:SetWidth(isPopupDisplay and 170 or 180)
	rateLabel:SetText(getBagValuePerHourText(snapshot))
	rateLabel:SetJustifyH("RIGHT")
	rateLabel:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
	rateRow:AddChild(rateLabel)

	local resetGap = AceGUI:Create("Label")
	resetGap:SetWidth(14)
	resetGap:SetText("")
	rateRow:AddChild(resetGap)

	local refreshTotalLabels

	UI.CreateIconButton(rateRow, {
		texture = RESET_ICON,
		text = "R",
		width = 34,
		iconSize = 16,
		tooltip = "Reset value timer",
		tooltipNote = "Starts a fresh gold/hour baseline from the current total.",
		onClick = function()
			resetBagValueRate(snapshotRef())
			if refreshTotalLabels then
				refreshTotalLabels()
			else
				rateLabel:SetText(getBagValuePerHourText(snapshotRef()))
			end
			refreshOpenBagValuePopupValue()
		end,
	})

	if config.showPopupButton ~= false then
		UI.CreateIconButton(rateRow, {
			texture = POPUP_ICON,
			text = "P",
			width = 34,
			iconSize = 30,
			tooltip = "Open bag value popup",
			onClick = function()
				SmartRez:ShowBagValuePopup()
				if refreshTotalLabels then
					refreshTotalLabels()
				end
			end,
		})
	end

	if config.showConfigButton == true then
		UI.CreateIconButton(rateRow, {
			texture = CONFIG_ICON,
			text = "C",
			width = 34,
			iconSize = 16,
			tooltip = "Open bag value config",
			tooltipNote = "Edit tracked item whitelists and value source settings.",
			onClick = function()
				SmartRez:ShowAutomationConfigWindow("bagvalue")
			end,
		})
	end

	---@type AceGUILabel
	local totalLabel = AceGUI:Create("Label")
	totalLabel:SetFullWidth(true)
	totalLabel:SetText(colorMoneyText(snapshot.totalSelectedValueText))
	totalLabel:SetJustifyH("CENTER")
	totalLabel:SetFont("Fonts\\FRIZQT__.TTF", 28, "OUTLINE")
	group:AddChild(totalLabel)

	---@type AceGUILabel
	local deltaLabel = AceGUI:Create("Label")
	deltaLabel:SetFullWidth(true)
	deltaLabel:SetText(formatBagValueDelta(bagValueDisplayState.lastDelta or 0))
	deltaLabel:SetJustifyH("CENTER")
	deltaLabel:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
	group:AddChild(deltaLabel)

	local deltaSpacer = AceGUI:Create("Label")
	deltaSpacer:SetFullWidth(true)
	deltaSpacer:SetText(" ")
	deltaSpacer:SetFont("Fonts\\FRIZQT__.TTF", 5, "")
	group:AddChild(deltaSpacer)

	refreshTotalLabels = function()
		local current = snapshotRef()
		local currentTotal = current.totalSelectedValue or 0
		local delta = currentTotal - (bagValueDisplayState.lastDisplayedTotal or currentTotal)
		if delta ~= 0 then
			bagValueDisplayState.lastDelta = delta
		end
		totalLabel:SetText(colorMoneyText(current.totalSelectedValueText))
		deltaLabel:SetText(formatBagValueDelta(bagValueDisplayState.lastDelta or 0))
		timerLabel:SetText(getBagValueElapsedText())
		rateLabel:SetText(getBagValuePerHourText(current))
		bagValueDisplayState.lastDisplayedTotal = currentTotal
	end

	registerBagValueRateRefresher(function()
		if not group:IsShown() then
			return false
		end

		timerLabel:SetText(getBagValueElapsedText())
		rateLabel:SetText(getBagValuePerHourText(snapshotRef()))
		return true
	end)

	if config.registerInventoryRefresher ~= false and SmartRez.RegisterAutomationConfigInventoryRefresher then
		SmartRez:RegisterAutomationConfigInventoryRefresher(refreshTotalLabels)
	end

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
		UI.AddLabel(group, "TradeSkillMaster is not loaded, so Smart Rez cannot evaluate the selected item values yet.", "FFB86C")
	elseif snapshot.invalidPriceMessage then
		UI.AddLabel(group, "Price error: " .. tostring(snapshot.invalidPriceMessage), "FF7B72")
	elseif snapshot.missingPriceQuantity > 0 then
		UI.AddLabel(group, "Missing price data for " .. tostring(snapshot.missingPriceQuantity) .. " selected item(s).", "FFD866")
	end

	if not snapshot.hasSelection then
		UI.AddLabel(group, "No items selected yet. Click icons below to build your tracked set.", "7D8590")
	end

	return refreshTotalLabels
end

---@class SmartRezBagValuePopupWindow: AceGUIWindow
---@field refreshValue? fun()

function SmartRez:ShowBagValuePopup()
	---@type SmartRezBagValueSnapshot
	bagValuePopupSnapshot = self:BuildBagValueSnapshot()
	resetBagValueRate(bagValuePopupSnapshot)

	if not bagValuePopupFrame then
		---@type SmartRezBagValuePopupWindow
		bagValuePopupFrame = AceGUI:Create("Window")
		bagValuePopupFrame:SetTitle("Smart Rez Bag Value")
		bagValuePopupFrame:SetStatusText("")
		bagValuePopupFrame:SetWidth(430)
		bagValuePopupFrame:SetHeight(240)
		bagValuePopupFrame:EnableResize(false)
		bagValuePopupFrame:SetLayout("List")
		bagValuePopupFrame.frame:SetFrameStrata("DIALOG")
		bagValuePopupFrame:SetCallback("OnClose", function(widget)
			widget:Hide()
		end)

		function bagValuePopupFrame:Refresh(reason)
			bagValuePopupSnapshot = SmartRez:BuildBagValueSnapshot()
			if reason == "inventory" and self.refreshValue then
				self.refreshValue()
				return
			end

			self:ReleaseChildren()
			self.refreshValue = UI.RenderBagValueDisplay(self, function()
				return bagValuePopupSnapshot
			end, {
				showPopupButton = false,
				showConfigButton = true,
				registerInventoryRefresher = false,
			})
		end

		SmartRez:RegisterManagedFrame(bagValuePopupFrame)
	end

	bagValuePopupFrame:Refresh()
	bagValuePopupFrame:Show()
end

---@param parent AceGUIContainer
function UI.RenderBagValueTab(parent)
	local snapshot = SmartRez:BuildBagValueSnapshot()
	local currentSnapshot = snapshot
	if SmartRez.RegisterAutomationConfigInventoryRefresher then
		SmartRez:RegisterAutomationConfigInventoryRefresher(function()
			currentSnapshot = SmartRez:BuildBagValueSnapshot()
		end)
	end

	UI.RenderInventorySourcesGroup(parent, {
		title = "Value Sources",
		helpText = "Choose where Smart Rez looks for bag-value items. This source selection is separate from crafting, salvage, and disenchant. Enabling warbank here will prime the profession proxy backend so warbank items can enumerate.",
		getSources = function()
			return SmartRez:GetBagValueInventorySources()
		end,
		setSources = function(updatedSources)
			SmartRez:SetBagValueInventorySources(updatedSources)
		end,
	})
	local refreshTotalLabels = UI.RenderBagValueDisplay(parent, function()
		return currentSnapshot
	end, {
		showPopupButton = true,
	})

	UI.RenderIconMultiPicker(parent, {
		title = "Tracked Auction Items",
		helpText = "Items from the enabled source groups. Click icons to include or exclude them from the value total.",
		summaryText = UI.Colorize("79C0FF", string.format(
			"Available item types: %d  |  Visible quantity: %d",
			snapshot.availableItemTypes,
			snapshot.totalAvailableQuantity
		)),
		availableItemIDs = snapshot.availableItemIDs,
		getSelectedSet = function()
			return SmartRez:GetBagValueWhitelist()
		end,
		getItemCount = function(itemID)
			local itemData = currentSnapshot.itemsByID[itemID]
			return itemData and itemData.count or 0
		end,
		getIconLabel = function(itemID)
			local itemData = currentSnapshot.itemsByID[itemID]
			local itemCount = itemData and itemData.count or 0
			return UI.Colorize(itemCount > 0 and "79C0FF" or "7D8590", tostring(itemCount))
		end,
		getSummaryText = function()
			return UI.Colorize("79C0FF", string.format(
				"Available item types: %d  |  Visible quantity: %d",
				currentSnapshot.availableItemTypes,
				currentSnapshot.totalAvailableQuantity
			))
		end,
		addTooltipLines = function(tooltip, itemID, _, isSelected)
			local itemData = currentSnapshot.itemsByID[itemID]
			local itemCount = itemData and itemData.count or 0
			tooltip:AddLine(" ")
			tooltip:AddLine("Stored: " .. tostring(itemCount), 0.48, 0.75, 1)
			if itemData and itemData.pricedQuantity > 0 then
				if itemData.minUnitPrice and itemData.maxUnitPrice and itemData.minUnitPrice == itemData.maxUnitPrice then
					tooltip:AddLine("Unit value: " .. UI.FormatMoney(itemData.minUnitPrice), 0.49, 0.91, 0.53)
				else
					tooltip:AddLine("Unit value: varies", 0.49, 0.91, 0.53)
				end
				tooltip:AddLine("Selected subtotal: " .. UI.FormatMoney(itemData.totalValue), 0.49, 0.91, 0.53)
			end
			if itemData and itemData.missingPriceQuantity > 0 then
				tooltip:AddLine("Missing price on: " .. tostring(itemData.missingPriceQuantity), 1, 0.72, 0.4)
			end
			tooltip:AddLine(isSelected and "Included in total" or "Not included in total", isSelected and 0.49 or 0.49, isSelected and 0.91 or 0.52, isSelected and 0.53 or 0.56)
		end,
		addItemFunc = function(itemID)
			SmartRez:AddBagValueWhitelistItem(itemID, true)
			currentSnapshot = SmartRez:BuildBagValueSnapshot()
			refreshTotalLabels()
			refreshOpenBagValuePopupValue()
		end,
		removeItemFunc = function(itemID)
			SmartRez:RemoveBagValueWhitelistItem(itemID, true)
			currentSnapshot = SmartRez:BuildBagValueSnapshot()
			refreshTotalLabels()
			refreshOpenBagValuePopupValue()
		end,
		emptySelectionText = "No tracked items selected yet. Click icons to start building the total.",
		selectedStatusTextPrefix = "Tracking ",
		selectedStatusTextSuffix = " item(s). Click highlighted icons to remove them from the total.",
		controlHintText = "Click icons to choose which item types count toward the total. Leaving it empty means the total stays at zero.",
		emptyText = "No visible items matched the current source and auctionability filters.",
	})
end
