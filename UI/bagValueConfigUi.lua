local SmartRez = _G.SmartRez

---@type AceGUILib
local AceGUI = LibStub("AceGUI-3.0")

local UI = SmartRez.UI

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
---@param snapshot SmartRezBagValueSnapshot
local function renderBagValueSummaryGroup(parent, snapshot)
	local group = UI.CreateCard(parent, "Auctionable Bag Value")

	UI.AddLabel(group, "Select item types below and Smart Rez will keep a live total for those items across the enabled source groups.", "A5D6FF")
	UI.AddLabel(group, UI.Colorize("7EE787", "Selected value: ") .. snapshot.totalSelectedValueText)
	UI.AddLabel(group, string.format(
		"%s %d/%d  |  %s %d  |  %s %s",
		UI.Colorize("A5D6FF", "Selected items:"),
		snapshot.selectedItemTypes,
		snapshot.availableItemTypes,
		UI.Colorize("A5D6FF", "Selected quantity:"),
		snapshot.totalSelectedQuantity,
		UI.Colorize("A5D6FF", "Sources:"),
		UI.GetInventorySourcesSummary(snapshot.inventorySources)
	))

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
end

---@param parent AceGUIContainer
function UI.RenderBagValueTab(parent)
	local snapshot = SmartRez:BuildBagValueSnapshot()
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
	renderBagValueSummaryGroup(parent, snapshot)

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
			local itemData = snapshot.itemsByID[itemID]
			return itemData and itemData.count or 0
		end,
		getIconLabel = function(itemID)
			local itemData = snapshot.itemsByID[itemID]
			local itemCount = itemData and itemData.count or 0
			return UI.Colorize(itemCount > 0 and "79C0FF" or "7D8590", tostring(itemCount))
		end,
		addTooltipLines = function(tooltip, itemID, _, isSelected)
			local itemData = snapshot.itemsByID[itemID]
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
