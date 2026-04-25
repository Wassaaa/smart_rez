local SmartRez = _G.SmartRez

---@type AceGUILib
local AceGUI = LibStub("AceGUI-3.0")

local UI = SmartRez.UI

local function mutateGoldPrinterConfig(callback)
	if SmartRez.CaptureAutomationConfigScrollStatus then
		SmartRez:CaptureAutomationConfigScrollStatus()
	end
	callback()
end

local function getGoldPrinterStatusText()
	local phase = SmartRez:GetGoldPrinterPhase()
	if phase == "craft" or phase == "recipeCraft" then
		return UI.Colorize("7EE787", SmartRez:GetGoldPrinterPhaseLabel())
	end
	if phase == "disenchant" then
		return UI.Colorize("FFD866", SmartRez:GetGoldPrinterPhaseLabel())
	end
	if phase == "shatter" or phase == "craftSalvage" then
		return UI.Colorize("7AA2F7", SmartRez:GetGoldPrinterPhaseLabel())
	end
	return UI.Colorize("C0CAF5", SmartRez:GetGoldPrinterPhaseLabel())
end

local function renderGoldPrinterDisenchantWhitelist(parent, routineKey, stepIndex)
	UI.RenderDisenchantWhitelist(parent, {
		contextKey = SmartRez:GetGoldPrinterRoutineStepDisenchantContextKey(routineKey, stepIndex),
		title = "Step " .. tostring(stepIndex) .. " Disenchant Targets",
		helpText = "This whitelist belongs only to this Gold Printer routine step.",
		controlHintText = "Click icons to choose what this Gold Printer disenchant step may target. Leaving it empty means this step will have no work.",
	})
end

local function renderGoldPrinterCraftSalvageWhitelistSections(parent, routineKey, stepIndex, selection)
	local professionKey = selection and selection.professionKey or nil
	local profession = professionKey and SmartRez:GetCraftSalvageProfession(professionKey) or nil
	local contextKey = SmartRez:GetGoldPrinterRoutineStepCraftSalvageContextKey(routineKey, stepIndex, professionKey)

	if not profession or not selection then
		UI.AddLabel(parent, "Step " .. tostring(stepIndex) .. " has no configured salvage profession or selection yet.", "FFB86C")
		return
	end

	UI.RenderCraftSalvageWhitelistSections(parent, profession, selection, contextKey, "Step " .. tostring(stepIndex) .. " ")
end

local function getRecipeCraftCompactSlotLabel(reagentSlot, requiredIndex)
	local slotLabel = tostring(reagentSlot.label or ("Slot " .. tostring(reagentSlot.dataSlotIndex)))
	if reagentSlot.required ~= false then
		return "Reagent " .. tostring(requiredIndex) .. ": " .. slotLabel .. " (required)"
	end

	slotLabel = slotLabel:gsub("^Add%s+", "")
	slotLabel = slotLabel:gsub("^Amplify%s+", "")
	return slotLabel .. " (optional)"
end

local function isRecipeCraftSocketSlot(reagentSlot)
	return reagentSlot
		and (
			reagentSlot.slotKind == "socket"
			or reagentSlot.reagentType == 3
			or reagentSlot.label == "Socket"
		)
end

local function renderGoldPrinterRecipeCraftIconRow(parent, stepIndex, reagentSlot, requiredIndex)
	if isRecipeCraftSocketSlot(reagentSlot) then
		return
	end
	if #(reagentSlot.allowedItemIDs or {}) == 0 then
		return
	end

	local function getSelectedItemID()
		local selectedSet = SmartRez:GetGoldPrinterRecipeCraftReagentWhitelist(stepIndex, reagentSlot.dataSlotIndex)
		for _, itemID in ipairs(reagentSlot.allowedItemIDs or {}) do
			if selectedSet[itemID] then
				return itemID
			end
		end
	end

	UI.RenderIconSingleChoiceRow(parent, {
		label = getRecipeCraftCompactSlotLabel(reagentSlot, requiredIndex),
		availableItemIDs = reagentSlot.allowedItemIDs,
		allowClear = reagentSlot.required == false,
		getSelectedItemID = getSelectedItemID,
		onChoiceChanged = function(itemID)
			SmartRez:SetGoldPrinterRecipeCraftReagentChoice(stepIndex, reagentSlot.dataSlotIndex, itemID, true)
		end,
	})
end

local function renderGoldPrinterRecipeCraftSlotSections(parent, stepIndex, recipeConfig)
	local hasRows = false
	local requiredIndex = 0
	for _, reagentSlot in ipairs(recipeConfig and recipeConfig.reagentSlots or {}) do
		if reagentSlot.required ~= false and not isRecipeCraftSocketSlot(reagentSlot) then
			requiredIndex = requiredIndex + 1
		end
		if not isRecipeCraftSocketSlot(reagentSlot) and #(reagentSlot.allowedItemIDs or {}) > 0 then
			hasRows = true
		end
	end

	if not hasRows then
		return
	end

	local group = UI.CreateCard(parent, "Recipe Reagents")

	requiredIndex = 0
	for _, reagentSlot in ipairs(recipeConfig and recipeConfig.reagentSlots or {}) do
		if reagentSlot.required ~= false and not isRecipeCraftSocketSlot(reagentSlot) then
			requiredIndex = requiredIndex + 1
		end
		renderGoldPrinterRecipeCraftIconRow(group, stepIndex, reagentSlot, requiredIndex)
	end
end

local function renderRecipeCraftStepControls(stepGroup, stepIndex, step)
	UI.AddLabel(stepGroup, UI.Colorize("A5D6FF", "Recipe: ") .. tostring(step.recipeConfig and step.recipeConfig.label or "Unset"))

	if step.recipeConfig then
		UI.AddLabel(stepGroup, UI.Colorize("7EE787", "Output: ") .. select(1, UI.GetDisplayFromLinkOrID(step.recipeConfig.outputItemLink, step.recipeConfig.outputItemID)))
	end

	local recipeButton = AceGUI:Create("Button")
	recipeButton:SetText("Use Open Recipe")
	recipeButton:SetWidth(180)
	recipeButton:SetCallback("OnClick", function()
		local ok, err = SmartRez:CaptureGoldPrinterRecipeStep(stepIndex)
		if not ok and err then
			print("Smart Rez:", err)
		end
	end)
	stepGroup:AddChild(recipeButton)

	if step.recipeConfig then
		local requireProfessionOpen = AceGUI:Create("CheckBox")
		requireProfessionOpen:SetLabel("Require profession window open")
		requireProfessionOpen:SetValue(step.recipeConfig.requireProfessionOpen ~= false)
		requireProfessionOpen:SetCallback("OnValueChanged", function(_, _, value)
			SmartRez:SetGoldPrinterRecipeCraftRequireProfessionOpen(stepIndex, value == true, true)
		end)
		stepGroup:AddChild(requireProfessionOpen)

		UI.AddLabel(stepGroup, "Turn this off only for recipes you have verified can craft directly by recipe ID without the profession window/backend being opened first.", "7D8590")
	end

	if step.recipeConfig and (step.recipeConfig.unsupportedRequiredSlot or false) then
		UI.AddLabel(stepGroup, "This recipe still has a required non-item reagent slot that Smart Rez cannot drive yet.", "FFB86C")
	end
end

local function renderCraftSalvageStepControls(stepGroup, stepIndex, step)
	UI.AddLabel(stepGroup, string.format(
		"%s %s  |  %s %s",
		UI.Colorize("A5D6FF", "Recipe:"),
		tostring(step.selection and step.selection.label or "Unset"),
		UI.Colorize("A5D6FF", "Profession:"),
		tostring(step.selection and step.selection.professionLabel or "Unset")
	))

	local recipeButton = AceGUI:Create("Button")
	recipeButton:SetText("Use Open Recipe")
	recipeButton:SetWidth(180)
	recipeButton:SetCallback("OnClick", function()
		local ok, err = SmartRez:CaptureGoldPrinterSalvageStep(stepIndex)
		if not ok and err then
			print("Smart Rez:", err)
		end
	end)
	stepGroup:AddChild(recipeButton)

	if step.selection then
		local requireProfessionOpen = AceGUI:Create("CheckBox")
		requireProfessionOpen:SetLabel("Require profession window open")
		requireProfessionOpen:SetValue(step.selection.requireProfessionOpen ~= false)
		requireProfessionOpen:SetCallback("OnValueChanged", function(_, _, value)
			SmartRez:SetGoldPrinterSalvageRequireProfessionOpen(stepIndex, value == true, true)
		end)
		stepGroup:AddChild(requireProfessionOpen)

		UI.AddLabel(stepGroup, "Turn this off only for salvage recipes you have verified can craft directly without the profession window/backend being opened first.", "7D8590")
	end
end

local function renderStepCompletionControls(stepGroup, stepIndex, step)
	---@type AceGUIDropdown
	local completionDropdown = AceGUI:Create("Dropdown")
	completionDropdown:SetFullWidth(true)
	completionDropdown:SetLabel("Completion")
	completionDropdown:SetList(SmartRez:GetGoldPrinterStepCompletionModeList())
	completionDropdown:SetValue(step.completionMode or "untilNoTargets")
	completionDropdown:SetCallback("OnValueChanged", function(_, _, value)
		mutateGoldPrinterConfig(function()
			SmartRez:SetGoldPrinterRoutineStepCompletionMode(stepIndex, value)
		end)
	end)
	stepGroup:AddChild(completionDropdown)

	if step.completionMode == "count" or step.completionMode == "interval" then
		local countSlider = AceGUI:Create("Slider")
		countSlider:SetFullWidth(true)
		countSlider:SetLabel(step.completionMode == "interval" and "Actions per interval" or "Actions before next step")
		countSlider:SetSliderValues(1, 20, 1)
		countSlider:SetValue(step.actionCount or 1)
		countSlider:SetCallback("OnValueChanged", function(_, _, value)
			SmartRez:SetGoldPrinterRoutineStepActionCount(stepIndex, math.floor((value or 1) + 0.5), true)
		end)
		stepGroup:AddChild(countSlider)
	end

	if step.completionMode == "interval" then
		local intervalBox = AceGUI:Create("EditBox")
		intervalBox:SetFullWidth(true)
		intervalBox:SetLabel("Interval seconds")
		intervalBox:SetText(tostring(step.intervalSeconds or 900))
		intervalBox:SetCallback("OnEnterPressed", function(_, _, value)
			mutateGoldPrinterConfig(function()
				SmartRez:SetGoldPrinterRoutineStepIntervalSeconds(stepIndex, value)
			end)
		end)
		stepGroup:AddChild(intervalBox)
	end
end

local function renderStepButtons(stepGroup, stepIndex)
	local stepButtons = AceGUI:Create("SimpleGroup")
	stepButtons:SetFullWidth(true)
	stepButtons:SetLayout("Flow")
	stepGroup:AddChild(stepButtons)

	local upButton = AceGUI:Create("Button")
	upButton:SetText("Up")
	upButton:SetWidth(80)
	upButton:SetCallback("OnClick", function()
		mutateGoldPrinterConfig(function()
			SmartRez:MoveGoldPrinterRoutineStep(stepIndex, -1)
		end)
	end)
	stepButtons:AddChild(upButton)

	local downButton = AceGUI:Create("Button")
	downButton:SetText("Down")
	downButton:SetWidth(80)
	downButton:SetCallback("OnClick", function()
		mutateGoldPrinterConfig(function()
			SmartRez:MoveGoldPrinterRoutineStep(stepIndex, 1)
		end)
	end)
	stepButtons:AddChild(downButton)

	local removeButton = AceGUI:Create("Button")
	removeButton:SetText("Remove")
	removeButton:SetWidth(100)
	removeButton:SetCallback("OnClick", function()
		mutateGoldPrinterConfig(function()
			SmartRez:RemoveGoldPrinterRoutineStep(stepIndex)
		end)
	end)
	stepButtons:AddChild(removeButton)
end

local function renderGoldPrinterStep(parent, routineKey, stepTypeList, stepIndex, step)
	local stepGroup = UI.CreateCard(parent, "Step " .. tostring(stepIndex))

	UI.AddLabel(stepGroup, SmartRez:GetGoldPrinterRoutineStepLabel(step), "79C0FF")

	---@type AceGUIDropdown
	local stepTypeDropdown = AceGUI:Create("Dropdown")
	stepTypeDropdown:SetFullWidth(true)
	stepTypeDropdown:SetLabel("Step type")
	stepTypeDropdown:SetList(stepTypeList)
	stepTypeDropdown:SetValue(step.type)
	stepTypeDropdown:SetCallback("OnValueChanged", function(_, _, value)
		mutateGoldPrinterConfig(function()
			SmartRez:SetGoldPrinterRoutineStepType(stepIndex, value)
		end)
	end)
	stepGroup:AddChild(stepTypeDropdown)

	renderStepCompletionControls(stepGroup, stepIndex, step)

	if step.type == "recipeCraft" then
		renderRecipeCraftStepControls(stepGroup, stepIndex, step)
	elseif step.type == "craftSalvage" then
		renderCraftSalvageStepControls(stepGroup, stepIndex, step)
	end

	renderStepButtons(stepGroup, stepIndex)

	if step.type == "disenchant" then
		renderGoldPrinterDisenchantWhitelist(parent, routineKey, stepIndex)
	elseif step.type == "recipeCraft" then
		renderGoldPrinterRecipeCraftSlotSections(parent, stepIndex, step.recipeConfig)
	elseif step.type == "craftSalvage" then
		renderGoldPrinterCraftSalvageWhitelistSections(parent, routineKey, stepIndex, step.selection)
	end
end

local function renderAddStepButtons(parent)
	local addStepButtons = AceGUI:Create("SimpleGroup")
	addStepButtons:SetFullWidth(true)
	addStepButtons:SetLayout("Flow")
	parent:AddChild(addStepButtons)

	local addCraftStep = AceGUI:Create("Button")
	addCraftStep:SetText("Add Craft Step")
	addCraftStep:SetWidth(140)
	addCraftStep:SetCallback("OnClick", function()
		mutateGoldPrinterConfig(function()
			SmartRez:AddGoldPrinterRoutineStep("recipeCraft")
		end)
	end)
	addStepButtons:AddChild(addCraftStep)

	local addDisenchantStep = AceGUI:Create("Button")
	addDisenchantStep:SetText("Add Disenchant Step")
	addDisenchantStep:SetWidth(160)
	addDisenchantStep:SetCallback("OnClick", function()
		mutateGoldPrinterConfig(function()
			SmartRez:AddGoldPrinterRoutineStep("disenchant")
		end)
	end)
	addStepButtons:AddChild(addDisenchantStep)

	local addSalvageStep = AceGUI:Create("Button")
	addSalvageStep:SetText("Add Salvage Step")
	addSalvageStep:SetWidth(150)
	addSalvageStep:SetCallback("OnClick", function()
		mutateGoldPrinterConfig(function()
			SmartRez:AddGoldPrinterRoutineStep("craftSalvage")
		end)
	end)
	addStepButtons:AddChild(addSalvageStep)
end

local function renderGoldPrinterGroup(parent)
	local goldPrinterGroup = UI.CreateCard(parent, "Gold Printer")
	UI.AddLabel(goldPrinterGroup, "Build a routine out of recipe-craft, disenchant, and salvage steps. This first draft still reuses your existing recipe selections and buttons, but Gold Printer now has its own per-step whitelists.", "A5D6FF")

	---@type AceGUIDropdown
	local routineDropdown = AceGUI:Create("Dropdown")
	routineDropdown:SetFullWidth(true)
	routineDropdown:SetLabel("Active routine")
	routineDropdown:SetList(SmartRez:GetGoldPrinterRoutineList())
	routineDropdown:SetValue(SmartRez:GetGoldPrinterSelectedRoutineKey())
	routineDropdown:SetCallback("OnValueChanged", function(_, _, value)
		mutateGoldPrinterConfig(function()
			SmartRez:SetGoldPrinterSelectedRoutineKey(value)
		end)
	end)
	goldPrinterGroup:AddChild(routineDropdown)

	---@type AceGUIEditBox
	local routineName = AceGUI:Create("EditBox")
	routineName:SetFullWidth(true)
	routineName:SetLabel("Routine name")
	routineName:SetText((SmartRez:GetGoldPrinterRoutine() or {}).label or "")
	routineName:SetCallback("OnEnterPressed", function(_, _, value)
		mutateGoldPrinterConfig(function()
			SmartRez:RenameSelectedGoldPrinterRoutine(value)
		end)
	end)
	goldPrinterGroup:AddChild(routineName)

	local routineButtons = AceGUI:Create("SimpleGroup")
	routineButtons:SetFullWidth(true)
	routineButtons:SetLayout("Flow")
	goldPrinterGroup:AddChild(routineButtons)

	local newRoutineButton = AceGUI:Create("Button")
	newRoutineButton:SetText("New Routine")
	newRoutineButton:SetWidth(140)
	newRoutineButton:SetCallback("OnClick", function()
		mutateGoldPrinterConfig(function()
			SmartRez:CreateGoldPrinterRoutine()
		end)
	end)
	routineButtons:AddChild(newRoutineButton)

	local deleteRoutineButton = AceGUI:Create("Button")
	deleteRoutineButton:SetText("Delete Routine")
	deleteRoutineButton:SetWidth(140)
	deleteRoutineButton:SetCallback("OnClick", function()
		mutateGoldPrinterConfig(function()
			SmartRez:DeleteSelectedGoldPrinterRoutine()
		end)
	end)
	routineButtons:AddChild(deleteRoutineButton)

	UI.AddLabel(goldPrinterGroup, "Phase: " .. getGoldPrinterStatusText())

	local goldPrinterSlider = AceGUI:Create("Slider")
	goldPrinterSlider:SetFullWidth(true)
	goldPrinterSlider:SetLabel("Minimum free bag slots to keep during this routine")
	goldPrinterSlider:SetSliderValues(1, 20, 1)
	goldPrinterSlider:SetValue(SmartRez:GetGoldPrinterMinFreeSlots())
	goldPrinterSlider:SetCallback("OnValueChanged", function(_, _, value)
		SmartRez:SetGoldPrinterMinFreeSlots(math.floor((value or 1) + 0.5), true)
	end)
	goldPrinterGroup:AddChild(goldPrinterSlider)
end

---@param parent AceGUIContainer
function UI.RenderGoldPrinterTab(parent)
	UI.RenderInventorySourcesGroup(parent)
	renderGoldPrinterGroup(parent)

	local routineKey = SmartRez:GetGoldPrinterSelectedRoutineKey()
	local stepTypeList = SmartRez:GetGoldPrinterRoutineStepTypeList()
	for stepIndex, step in ipairs(SmartRez:GetGoldPrinterRoutineSteps()) do
		renderGoldPrinterStep(parent, routineKey, stepTypeList, stepIndex, step)
	end

	renderAddStepButtons(parent)
end
