local SmartRez = _G.SmartRez
local UI = SmartRez.UI

---@param parent AceGUIContainer
function UI.RenderDisenchantWhitelist(parent, config)
	config = config or {}
	local contextKey = config.contextKey or SmartRez:GetManualDisenchantWhitelistContextKey()
	local selectedSet = SmartRez:GetDisenchantWhitelist(contextKey)
	local title = config.title or "Disenchant Targets"
	local helpText = config.helpText or "Enchantable items found in the current inventory sources. Click icons to limit the manual Disenchant button to a smaller set."
	local controlHintText = config.controlHintText or "Click icons to choose what the Disenchant button is allowed to target. Leaving it empty means no disenchant targets are available."

	UI.RenderIconMultiPicker(parent, {
		title = title,
		helpText = helpText,
		summaryText = UI.Colorize("79C0FF", "Whitelist entries: " .. tostring(UI.GetItemSetCount(selectedSet))),
		getSummaryText = function()
			return UI.Colorize("79C0FF", "Whitelist entries: " .. tostring(UI.GetItemSetCount(SmartRez:GetDisenchantWhitelist(contextKey))))
		end,
		availableItemIDs = UI.MergeAvailableAndSelectedItemIDs(SmartRez:GetAvailableDisenchantItemIDs(), selectedSet),
		getSelectedSet = function()
			return SmartRez:GetDisenchantWhitelist(contextKey)
		end,
		addItemFunc = function(itemID)
			SmartRez:AddDisenchantWhitelistItem(itemID, true, contextKey)
		end,
		removeItemFunc = function(itemID)
			SmartRez:RemoveDisenchantWhitelistItem(itemID, true, contextKey)
		end,
		emptyText = "No disenchantable items were found in the configured inventory sources.",
		controlHintText = controlHintText,
	})
end
