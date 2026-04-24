local function printLine(...)
	print("SmartRez Recipe Probe:", ...)
end

local function getVisibleSchematicForm()
	local professionsFrame = ProfessionsFrame
	if professionsFrame and professionsFrame.CraftingPage and professionsFrame.CraftingPage.SchematicForm and professionsFrame.CraftingPage.SchematicForm:IsVisible() then
		return professionsFrame.CraftingPage.SchematicForm
	end

	local ordersPage = professionsFrame and professionsFrame.OrdersPage
	if ordersPage and ordersPage.OrderDetails and ordersPage.OrderDetails.SchematicForm and ordersPage.OrderDetails.SchematicForm:IsVisible() then
		return ordersPage.OrderDetails.SchematicForm
	end

	return nil
end

local function getSelectedRecipeID()
	local schematicForm = getVisibleSchematicForm()
	if not schematicForm or not schematicForm.GetRecipeInfo then
		printLine("no visible schematic form")
		return nil
	end

	local recipeInfo = schematicForm:GetRecipeInfo()
	local recipeID = recipeInfo and recipeInfo.recipeID or nil
	if not recipeID then
		printLine("no selected recipe")
		return nil
	end

	return recipeID
end

local function probeRecipeSchematic(recipeID)
	recipeID = recipeID or getSelectedRecipeID()
	if not recipeID then
		return
	end

	local schematic = C_TradeSkillUI.GetRecipeSchematic and C_TradeSkillUI.GetRecipeSchematic(recipeID, false) or nil
	if not schematic then
		printLine("no schematic", recipeID)
		return
	end

	printLine("recipe", recipeID)
	printLine("schematic", "qtyMin", schematic.quantityMin or "nil", "qtyMax", schematic.quantityMax or "nil", "slotCount", #(schematic.reagentSlotSchematics or {}))

	for slotIndex, reagentSlot in ipairs(schematic.reagentSlotSchematics or {}) do
		printLine(
			"slot",
			slotIndex,
			"slotIndex", reagentSlot.slotIndex or "nil",
			"dataSlotIndex", reagentSlot.dataSlotIndex or "nil",
			"required", tostring(reagentSlot.required),
			"quantityRequired", reagentSlot.quantityRequired or "nil",
			"reagentType", reagentSlot.reagentType or "nil",
			"slotText", reagentSlot.slotInfo and reagentSlot.slotInfo.slotText or "nil",
			"reagentCount", #(reagentSlot.reagents or {})
		)

		for reagentIndex, reagent in ipairs(reagentSlot.reagents or {}) do
			printLine(
				"  reagent",
				reagentIndex,
				"itemID", reagent.itemID or "nil",
				"quantity", reagent.quantity or reagent.quantityRequired or "nil",
				"dataSlotIndex", reagent.dataSlotIndex or "nil"
			)
		end
	end
end

local function probeOptionalReagents(recipeID)
	recipeID = recipeID or getSelectedRecipeID()
	if not recipeID then
		return
	end

	local optionalSlots = C_TradeSkillUI.GetOptionalReagentInfo and C_TradeSkillUI.GetOptionalReagentInfo(recipeID) or nil
	if not optionalSlots then
		printLine("no optional reagent info", recipeID)
		return
	end

	printLine("recipe", recipeID, "optionalSlotCount", #optionalSlots)
	for slotIndex, slot in ipairs(optionalSlots) do
		printLine(
			"optional",
			slotIndex,
			"requiredSkillRank", slot.requiredSkillRank or "nil",
			"lockedReason", slot.lockedReason or "nil",
			"slotText", slot.slotText or "nil",
			"optionCount", #(slot.options or {})
		)

		for optionIndex, optionID in ipairs(slot.options or {}) do
			printLine("  option", optionIndex, optionID)
		end
	end
end

local function probeAll(recipeID)
	probeRecipeSchematic(recipeID)
	probeOptionalReagents(recipeID)
end

_G.SmartRezRecipeProbe = {
	schematic = probeRecipeSchematic,
	optional = probeOptionalReagents,
	all = probeAll,
}

printLine("loaded", "use SmartRezRecipeProbe.schematic()", "SmartRezRecipeProbe.optional()", "SmartRezRecipeProbe.all()")
