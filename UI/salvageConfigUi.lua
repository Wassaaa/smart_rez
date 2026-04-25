local SmartRez = _G.SmartRez

---@type AceGUILib
local AceGUI = LibStub("AceGUI-3.0")

local UI = SmartRez.UI

local function renderCraftSalvageWhitelistSections(parent, profession, selection, contextKey, titlePrefix)
	if not profession or not selection then
		UI.AddLabel(parent, "This salvage section has no configured profession or selection yet.", "FFB86C")
		return
	end

	local whitelistLabel = selection.label or profession.label
	UI.RenderIconMultiPicker(parent, {
		title = (titlePrefix or "") .. "Salvage Targets",
		helpText = "Items " .. whitelistLabel .. " may salvage. Pick the exact targets this whitelist is allowed to use.",
		summaryText = UI.Colorize("79C0FF", "Whitelist entries: " .. tostring(UI.GetItemSetCount(SmartRez:GetCraftSalvageWhitelist(profession.key, contextKey)))),
		getSummaryText = function()
			return UI.Colorize("79C0FF", "Whitelist entries: " .. tostring(UI.GetItemSetCount(SmartRez:GetCraftSalvageWhitelist(profession.key, contextKey))))
		end,
		availableItemIDs = selection.salvageTargetItemIDs or {},
		getSelectedSet = function()
			return SmartRez:GetCraftSalvageWhitelist(profession.key, contextKey)
		end,
		addItemFunc = function(itemID)
			SmartRez:AddCraftSalvageWhitelistItem(profession.key, itemID, true, contextKey)
		end,
		removeItemFunc = function(itemID)
			SmartRez:RemoveCraftSalvageWhitelistItem(profession.key, itemID, true, contextKey)
		end,
		controlHintText = "Click icons to choose allowed salvage targets. Leaving it empty means no salvage targets are allowed.",
	})

	for _, reagentSlot in ipairs(selection.reagentSlots or {}) do
		UI.RenderIconMultiPicker(parent, {
			title = (titlePrefix or "") .. tostring(reagentSlot.label or ("Reagent Slot " .. tostring(reagentSlot.dataSlotIndex))),
			helpText = string.format(
				"Items allowed in this reagent slot. Click icons to build a narrowed list from the %d API-reported options. Need %d per cast.",
				#(reagentSlot.allowedItemIDs or {}),
				reagentSlot.quantityRequired or 0
			),
			summaryText = UI.Colorize("79C0FF", string.format(
				"Need: %d  |  Whitelist entries: %d",
				reagentSlot.quantityRequired or 0,
				UI.GetItemSetCount(SmartRez:GetCraftSalvageReagentWhitelist(profession.key, reagentSlot.dataSlotIndex, contextKey))
			)),
			getSummaryText = function()
				return UI.Colorize("79C0FF", string.format(
					"Need: %d  |  Whitelist entries: %d",
					reagentSlot.quantityRequired or 0,
					UI.GetItemSetCount(SmartRez:GetCraftSalvageReagentWhitelist(profession.key, reagentSlot.dataSlotIndex, contextKey))
				))
			end,
			availableItemIDs = reagentSlot.allowedItemIDs or {},
			getSelectedSet = function()
				return SmartRez:GetCraftSalvageReagentWhitelist(profession.key, reagentSlot.dataSlotIndex, contextKey)
			end,
			addItemFunc = function(itemID)
				SmartRez:AddCraftSalvageReagentWhitelistItem(profession.key, reagentSlot.dataSlotIndex, itemID, true, contextKey)
			end,
			removeItemFunc = function(itemID)
				SmartRez:RemoveCraftSalvageReagentWhitelistItem(profession.key, reagentSlot.dataSlotIndex, itemID, true, contextKey)
			end,
		})
	end
end

function UI.RenderCraftSalvageWhitelistSections(parent, profession, selection, contextKey, titlePrefix)
	renderCraftSalvageWhitelistSections(parent, profession, selection, contextKey, titlePrefix)
end

---@param parent AceGUIContainer
function UI.RenderCraftSalvageTab(parent, profession)
	local selection = SmartRez:GetCraftSalvageSelection(profession.key)
	local sourceText = "none"
	if selection then
		sourceText = selection.isDefault and "default" or "saved"
	end

	local summary = UI.CreateCard(parent, profession.label)
	UI.AddLabel(summary, string.format(
		"%s %s  |  %s %s  |  %s %s",
		UI.Colorize("A5D6FF", "Recipe:"),
		tostring(selection and selection.label or "Unset"),
		UI.Colorize("A5D6FF", "ID:"),
		tostring(selection and selection.recipeID or "Unset"),
		UI.Colorize("A5D6FF", "Stack:"),
		tostring(selection and selection.requiredStack or 1)
	))

	UI.AddLabel(summary, string.format(
		"%s %s  |  %s %s",
		UI.Colorize("A5D6FF", "Source:"),
		sourceText,
		UI.Colorize("A5D6FF", "Keybinds:"),
		"main settings"
	))

	UI.AddLabel(summary, "Open this profession, select a salvage recipe, then click Use Selected Recipe.", "A5D6FF")

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

	if selection then
		local requireProfessionOpen = AceGUI:Create("CheckBox")
		requireProfessionOpen:SetLabel("Require profession window open")
		requireProfessionOpen:SetValue(selection.requireProfessionOpen ~= false)
		requireProfessionOpen:SetCallback("OnValueChanged", function(_, _, value)
			SmartRez:SetCraftSalvageRequireProfessionOpen(profession.key, value == true, true)
		end)
		summary:AddChild(requireProfessionOpen)

		UI.AddLabel(summary, "Turn this off only for salvage recipes you have verified can craft directly without the profession window/backend being opened first.", "7D8590")
	end

	UI.AddSectionSpacer(summary)

	local target = SmartRez:GetCraftSalvageTarget(profession.key)
	if target then
		UI.AddLabel(summary, UI.Colorize("7EE787", "Target: ") .. string.format(
			"%s x%d",
			select(1, UI.GetItemDisplay(target.itemInfo.itemID)),
			target.itemInfo.stackCount or 0
		))
	else
		UI.AddLabel(summary, UI.Colorize("FFB86C", "Target: ") .. "none in configured storage")
	end

	UI.RenderInventorySourcesGroup(parent)
	renderCraftSalvageWhitelistSections(parent, profession, selection)

	if profession.key == "enchanting" then
		UI.RenderDisenchantWhitelist(parent, {
			contextKey = SmartRez:GetManualDisenchantWhitelistContextKey(),
			controlHintText = "Click icons to choose what the manual Disenchant button is allowed to target. Leaving it empty means no manual disenchant targets are available.",
		})
	end
end
