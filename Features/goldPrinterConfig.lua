local SmartRez = _G.SmartRez

local DEFAULT_GOLD_PRINTER_ROUTINE_KEY = "default"
local MANUAL_DISENCHANT_CONTEXT_KEY = "manual:enchanting"
local GOLD_PRINTER_RECIPE_ACTION_KEY = "shardcraft"
local DEFAULT_GOLD_PRINTER_CRAFT_RECIPE = {
	label = "Evercore Reconnaissance",
	recipeID = 1229864,
	requiredProfession = 202,
	openTradeSkillID = 202,
	requireProfessionOpen = true,
	useDefaultReagents = false,
	debug = false,
	reagentChoices = {
		[1] = 243581,
	},
}
local DEFAULT_GOLD_PRINTER_DISENCHANT_WHITELIST = {
	[244753] = true,
}
local DEFAULT_GOLD_PRINTER_SALVAGE_SELECTION = {
	openTradeSkillID = 333,
	requireProfessionOpen = true,
	sortBagsWhenEmpty = false,
	recipeKey = "shattering",
	requiredStack = 1,
	reagentSlots = {},
	preferLargestStack = false,
	professionKey = "enchanting",
	sortBagsOnLoad = false,
	requiredProfession = 333,
	professionLabel = "Enchanting",
	isDefault = false,
	salvageTargetItemIDs = {
		243602,
		243603,
	},
	label = "Radiant Shatter",
	recipeID = 1280394,
}
local DEFAULT_GOLD_PRINTER_SALVAGE_WHITELIST = {
	targetItems = {
		[243602] = true,
		[243603] = true,
	},
	reagentSlots = {},
}
local GOLD_PRINTER_COMPLETION_MODES = {
	untilNoTargets = "Until no targets",
	once = "Once, then next step",
	count = "Fixed number of actions",
	interval = "Timed priority",
}
local ensureDisenchantWhitelistStore

local function copyTable(source)
	local copied = {}

	for key, value in pairs(source or {}) do
		if type(value) == "table" then
			copied[key] = copyTable(value)
		else
			copied[key] = value
		end
	end

	return copied
end

local function refreshViews()
	if SmartRez.RefreshViews then
		SmartRez:RefreshViews()
	end
end

local function getSortedConfigs(configMap, labelKey)
	local configs = {}

	for _, config in pairs(configMap or {}) do
		configs[#configs + 1] = config
	end

	table.sort(configs, function(left, right)
		local leftOrder = left.order or 0
		local rightOrder = right.order or 0
		if leftOrder == rightOrder then
			return tostring(left[labelKey] or left.key) < tostring(right[labelKey] or right.key)
		end

		return leftOrder < rightOrder
	end)

	return configs
end

local function getDefaultRoutineSteps()
	return {
		{
			type = "recipeCraft",
			recipeConfig = copyTable(DEFAULT_GOLD_PRINTER_CRAFT_RECIPE),
		},
		{
			type = "disenchant",
		},
		{
			type = "craftSalvage",
			selection = copyTable(DEFAULT_GOLD_PRINTER_SALVAGE_SELECTION),
		},
	}
end

local function getDefaultRoutineMinFreeSlots()
	return SmartRez.db and SmartRez.db.goldPrinter and SmartRez.db.goldPrinter.minFreeSlots or SmartRez.goldPrinterMinFreeSlots
end

local function buildDefaultRoutine()
	return {
		key = DEFAULT_GOLD_PRINTER_ROUTINE_KEY,
		label = "Default Routine",
		minFreeSlots = getDefaultRoutineMinFreeSlots(),
		steps = getDefaultRoutineSteps(),
	}
end

local function getGoldPrinterSalvageTargetItemIDs(recipeID)
	local itemIDs = {}
	for _, itemID in ipairs(C_TradeSkillUI.GetSalvagableItemIDs and C_TradeSkillUI.GetSalvagableItemIDs(recipeID) or {}) do
		if itemID then
			itemIDs[#itemIDs + 1] = itemID
		end
	end
	return itemIDs
end

local function getGoldPrinterSalvageReagentSlots(recipeID)
	local reagentSlots = {}
	local recipeSchematic = C_TradeSkillUI.GetRecipeSchematic and C_TradeSkillUI.GetRecipeSchematic(recipeID, false) or nil

	for _, reagentSlot in ipairs(recipeSchematic and recipeSchematic.reagentSlotSchematics or {}) do
		if reagentSlot.required ~= false and reagentSlot.quantityRequired and reagentSlot.quantityRequired > 0 then
			local allowedItemIDs = {}
			for _, reagent in ipairs(reagentSlot.reagents or {}) do
				if reagent.itemID then
					allowedItemIDs[#allowedItemIDs + 1] = reagent.itemID
				end
			end

			reagentSlots[#reagentSlots + 1] = {
				slotIndex = reagentSlot.slotIndex,
				dataSlotIndex = reagentSlot.dataSlotIndex or reagentSlot.slotIndex,
				label = reagentSlot.slotInfo and reagentSlot.slotInfo.slotText or ("Slot " .. tostring(reagentSlot.slotIndex)),
				quantityRequired = reagentSlot.quantityRequired or 0,
				allowedItemIDs = allowedItemIDs,
			}
		end
	end

	return reagentSlots
end

local function getGoldPrinterRequiredStack(currentState)
	if currentState and currentState.outputQuantityMin and currentState.outputQuantityMin > 0 then
		return currentState.outputQuantityMin
	end
	if currentState and currentState.outputQuantityMax and currentState.outputQuantityMax > 0 then
		return currentState.outputQuantityMax
	end
	return 1
end

local function normalizeRoutineStep(step)
	if type(step) ~= "table" then
		step = {}
	end

	local stepType = step.type
	if stepType ~= "recipeCraft" and stepType ~= "craftSalvage" and stepType ~= "disenchant" then
		stepType = "recipeCraft"
	end

	local normalized = {
		type = stepType,
		completionMode = step.completionMode or "untilNoTargets",
		actionCount = math.max(1, math.floor(tonumber(step.actionCount) or 1)),
		intervalSeconds = math.max(1, math.floor(tonumber(step.intervalSeconds) or 900)),
	}

	if not GOLD_PRINTER_COMPLETION_MODES[normalized.completionMode] then
		normalized.completionMode = "untilNoTargets"
	end

	if stepType == "recipeCraft" then
		normalized.recipeConfig = copyTable(step.recipeConfig)
		if normalized.recipeConfig then
			if normalized.recipeConfig.requireProfessionOpen == nil then
				normalized.recipeConfig.requireProfessionOpen = true
			end
			SmartRez:HydrateRecipeCraftConfig(normalized.recipeConfig)
			SmartRez:RefreshRecipeCraftResolvedConfig(normalized.recipeConfig)
		end
	elseif stepType == "craftSalvage" then
		normalized.selection = copyTable(step.selection)
		if normalized.selection and normalized.selection.requireProfessionOpen == nil then
			normalized.selection.requireProfessionOpen = true
		end
	end

	return normalized
end

local function normalizeRoutine(routineKey, routine)
	if type(routine) ~= "table" then
		routine = {}
	end

	local normalized = {
		key = routineKey,
		label = routine.label or (routineKey == DEFAULT_GOLD_PRINTER_ROUTINE_KEY and "Default Routine" or ("Routine " .. tostring(routineKey))),
		minFreeSlots = tonumber(routine.minFreeSlots) or getDefaultRoutineMinFreeSlots(),
		steps = {},
	}

	for _, step in ipairs(routine.steps or {}) do
		normalized.steps[#normalized.steps + 1] = normalizeRoutineStep(step)
	end

	if #normalized.steps == 0 and routineKey == DEFAULT_GOLD_PRINTER_ROUTINE_KEY then
		normalized.steps = getDefaultRoutineSteps()
	end

	return normalized
end

local function ensureGoldPrinterConfig()
	SmartRez:EnsureConfig()

	local goldPrinterConfig = SmartRez.db.goldPrinter
	if type(goldPrinterConfig) ~= "table" then
		goldPrinterConfig = {}
		SmartRez.db.goldPrinter = goldPrinterConfig
	end

	if type(goldPrinterConfig.routines) ~= "table" then
		goldPrinterConfig.routines = {}
	end

	if type(goldPrinterConfig.selectedRoutineKey) ~= "string" or goldPrinterConfig.selectedRoutineKey == "" then
		goldPrinterConfig.selectedRoutineKey = DEFAULT_GOLD_PRINTER_ROUTINE_KEY
	end

	if type(goldPrinterConfig.routines[DEFAULT_GOLD_PRINTER_ROUTINE_KEY]) ~= "table" then
		goldPrinterConfig.routines[DEFAULT_GOLD_PRINTER_ROUTINE_KEY] = buildDefaultRoutine()
	end

	for routineKey, routine in pairs(goldPrinterConfig.routines) do
		goldPrinterConfig.routines[routineKey] = normalizeRoutine(routineKey, routine)
	end

	if not goldPrinterConfig.routines[goldPrinterConfig.selectedRoutineKey] then
		goldPrinterConfig.selectedRoutineKey = DEFAULT_GOLD_PRINTER_ROUTINE_KEY
	end

	ensureDisenchantWhitelistStore()
	if type(SmartRez.db.salvageWhitelists) ~= "table" then
		SmartRez.db.salvageWhitelists = {}
	end
	if type(SmartRez.db.salvageWhitelists["context:goldprinter:default:step:3:salvage:enchanting"]) ~= "table" then
		SmartRez.db.salvageWhitelists["context:goldprinter:default:step:3:salvage:enchanting"] = copyTable(DEFAULT_GOLD_PRINTER_SALVAGE_WHITELIST)
	end

	return goldPrinterConfig
end

ensureDisenchantWhitelistStore = function()
	SmartRez:EnsureConfig()

	if type(SmartRez.db.disenchantWhitelists) ~= "table" then
		SmartRez.db.disenchantWhitelists = {}
	end

	local store = SmartRez.db.disenchantWhitelists
	if type(store[MANUAL_DISENCHANT_CONTEXT_KEY]) ~= "table" then
		store[MANUAL_DISENCHANT_CONTEXT_KEY] = copyTable(SmartRez.db.disenchantWhitelist or {})
	end
	if type(store["goldprinter:default:step:2:disenchant"]) ~= "table" then
		store["goldprinter:default:step:2:disenchant"] = copyTable(DEFAULT_GOLD_PRINTER_DISENCHANT_WHITELIST)
	end

	return store
end

function SmartRez:GetManualDisenchantWhitelistContextKey()
	return MANUAL_DISENCHANT_CONTEXT_KEY
end

function SmartRez:GetActiveDisenchantWhitelistContextKey()
	return self.activeDisenchantWhitelistContextKey or MANUAL_DISENCHANT_CONTEXT_KEY
end

function SmartRez:SetActiveDisenchantWhitelistContextKey(contextKey)
	self.activeDisenchantWhitelistContextKey = contextKey or MANUAL_DISENCHANT_CONTEXT_KEY
end

function SmartRez:GetDisenchantWhitelist(contextKey)
	local resolvedContextKey = contextKey or self:GetActiveDisenchantWhitelistContextKey()
	local store = ensureDisenchantWhitelistStore()
	if type(store[resolvedContextKey]) ~= "table" then
		store[resolvedContextKey] = {}
	end

	if resolvedContextKey == MANUAL_DISENCHANT_CONTEXT_KEY then
		self.db.disenchantWhitelist = store[resolvedContextKey]
	end

	return store[resolvedContextKey]
end

function SmartRez:SetDisenchantWhitelist(whitelist, contextKey)
	local resolvedContextKey = contextKey or self:GetActiveDisenchantWhitelistContextKey()
	ensureDisenchantWhitelistStore()[resolvedContextKey] = whitelist or {}
	if resolvedContextKey == MANUAL_DISENCHANT_CONTEXT_KEY then
		self.db.disenchantWhitelist = ensureDisenchantWhitelistStore()[resolvedContextKey]
	end
	self:RefreshDisenchantButton()
	refreshViews()
end

function SmartRez:AddDisenchantWhitelistItem(itemID, skipRefresh, contextKey)
	if not itemID then
		return
	end

	self:GetDisenchantWhitelist(contextKey)[itemID] = true
	self:RefreshDisenchantButton()
	if not skipRefresh then
		refreshViews()
	end
end

function SmartRez:RemoveDisenchantWhitelistItem(itemID, skipRefresh, contextKey)
	self:GetDisenchantWhitelist(contextKey)[itemID] = nil
	self:RefreshDisenchantButton()
	if not skipRefresh then
		refreshViews()
	end
end

function SmartRez:GetGoldPrinterConfig()
	return ensureGoldPrinterConfig()
end

function SmartRez:GetGoldPrinterRoutine(routineKey)
	local config = ensureGoldPrinterConfig()
	local resolvedRoutineKey = routineKey or config.selectedRoutineKey
	return config.routines[resolvedRoutineKey]
end

function SmartRez:GetGoldPrinterRoutines()
	local config = ensureGoldPrinterConfig()
	local routines = {}

	for _, routine in pairs(config.routines) do
		routines[#routines + 1] = routine
	end

	table.sort(routines, function(left, right)
		if left.key == DEFAULT_GOLD_PRINTER_ROUTINE_KEY then
			return true
		end
		if right.key == DEFAULT_GOLD_PRINTER_ROUTINE_KEY then
			return false
		end
		return tostring(left.label or left.key) < tostring(right.label or right.key)
	end)

	return routines
end

function SmartRez:GetGoldPrinterSelectedRoutineKey()
	return ensureGoldPrinterConfig().selectedRoutineKey
end

function SmartRez:SetGoldPrinterSelectedRoutineKey(routineKey)
	local config = ensureGoldPrinterConfig()
	if not config.routines[routineKey] then
		return
	end

	config.selectedRoutineKey = routineKey
	refreshViews()
end

function SmartRez:GetGoldPrinterRoutineList()
	local routineList = {}
	for _, routine in ipairs(self:GetGoldPrinterRoutines()) do
		routineList[routine.key] = routine.label or routine.key
	end
	return routineList
end

function SmartRez:CreateGoldPrinterRoutine()
	local config = ensureGoldPrinterConfig()
	local index = 2
	local routineKey = "routine_" .. tostring(index)
	while config.routines[routineKey] do
		index = index + 1
		routineKey = "routine_" .. tostring(index)
	end

	config.routines[routineKey] = normalizeRoutine(routineKey, {
		label = "Routine " .. tostring(index),
		minFreeSlots = self:GetGoldPrinterMinFreeSlots(),
		steps = {},
	})
	config.selectedRoutineKey = routineKey
	refreshViews()
end

function SmartRez:DeleteSelectedGoldPrinterRoutine()
	local config = ensureGoldPrinterConfig()
	local routineKey = config.selectedRoutineKey
	if routineKey == DEFAULT_GOLD_PRINTER_ROUTINE_KEY then
		return
	end

	config.routines[routineKey] = nil
	config.selectedRoutineKey = DEFAULT_GOLD_PRINTER_ROUTINE_KEY
	refreshViews()
end

function SmartRez:RenameSelectedGoldPrinterRoutine(label)
	local routine = self:GetGoldPrinterRoutine()
	if not routine then
		return
	end

	label = tostring(label or ""):match("^%s*(.-)%s*$")
	if label == "" then
		return
	end

	routine.label = label
	refreshViews()
end

function SmartRez:GetGoldPrinterRoutineSteps()
	local routine = self:GetGoldPrinterRoutine()
	return routine and routine.steps or {}
end

function SmartRez:SetGoldPrinterRoutineMinFreeSlots(value, routineKey)
	local routine = self:GetGoldPrinterRoutine(routineKey)
	if not routine then
		return
	end

	routine.minFreeSlots = math.max(0, math.floor(tonumber(value) or self.goldPrinterMinFreeSlots))
	refreshViews()
end

function SmartRez:GetGoldPrinterMinFreeSlots()
	local routine = self:GetGoldPrinterRoutine()
	return routine and routine.minFreeSlots or (self.db and self.db.goldPrinter and self.db.goldPrinter.minFreeSlots) or self.goldPrinterMinFreeSlots
end

function SmartRez:SetGoldPrinterMinFreeSlots(value, skipRefresh)
	local routine = self:GetGoldPrinterRoutine()
	local minFreeSlots = math.max(0, math.floor(tonumber(value) or self.goldPrinterMinFreeSlots))

	if routine then
		routine.minFreeSlots = minFreeSlots
	end

	self:EnsureConfig()
	self.db.goldPrinter.minFreeSlots = minFreeSlots
	if not skipRefresh then
		refreshViews()
	end
end

function SmartRez:AddGoldPrinterRoutineStep(stepType)
	local routine = self:GetGoldPrinterRoutine()
	if not routine then
		return
	end

	routine.steps[#routine.steps + 1] = normalizeRoutineStep({
		type = stepType,
	})
	refreshViews()
end

function SmartRez:RemoveGoldPrinterRoutineStep(stepIndex)
	local routine = self:GetGoldPrinterRoutine()
	if not routine or #routine.steps == 0 then
		return
	end

	table.remove(routine.steps, stepIndex)
	refreshViews()
end

function SmartRez:MoveGoldPrinterRoutineStep(stepIndex, direction)
	local routine = self:GetGoldPrinterRoutine()
	if not routine then
		return
	end

	local targetIndex = stepIndex + direction
	if targetIndex < 1 or targetIndex > #routine.steps then
		return
	end

	routine.steps[stepIndex], routine.steps[targetIndex] = routine.steps[targetIndex], routine.steps[stepIndex]
	refreshViews()
end

function SmartRez:SetGoldPrinterRoutineStepType(stepIndex, stepType)
	local routine = self:GetGoldPrinterRoutine()
	if not routine or not routine.steps[stepIndex] then
		return
	end

	routine.steps[stepIndex] = normalizeRoutineStep({
		type = stepType,
	})
	refreshViews()
end

function SmartRez:GetGoldPrinterStepCompletionModeList()
	return copyTable(GOLD_PRINTER_COMPLETION_MODES)
end

function SmartRez:SetGoldPrinterRoutineStepCompletionMode(stepIndex, completionMode)
	local routine = self:GetGoldPrinterRoutine()
	local step = routine and routine.steps[stepIndex] or nil
	if not step or not GOLD_PRINTER_COMPLETION_MODES[completionMode] then
		return
	end

	step.completionMode = completionMode
	refreshViews()
end

function SmartRez:SetGoldPrinterRoutineStepActionCount(stepIndex, value, skipRefresh)
	local routine = self:GetGoldPrinterRoutine()
	local step = routine and routine.steps[stepIndex] or nil
	if not step then
		return
	end

	step.actionCount = math.max(1, math.floor(tonumber(value) or 1))
	if not skipRefresh then
		refreshViews()
	end
end

function SmartRez:SetGoldPrinterRoutineStepIntervalSeconds(stepIndex, value)
	local routine = self:GetGoldPrinterRoutine()
	local step = routine and routine.steps[stepIndex] or nil
	if not step then
		return
	end

	step.intervalSeconds = math.max(1, math.floor(tonumber(value) or 900))
	refreshViews()
end

function SmartRez:GetGoldPrinterRecipeActionKey()
	return GOLD_PRINTER_RECIPE_ACTION_KEY
end

function SmartRez:GetCraftSalvageProfessionByProfessionID(professionID)
	for _, profession in pairs(self.craftSalvageProfessions or {}) do
		if profession.professionID == professionID then
			return profession
		end
	end
end

function SmartRez:CaptureGoldPrinterRecipeStep(stepIndex)
	local routine = self:GetGoldPrinterRoutine()
	local step = routine and routine.steps[stepIndex] or nil
	if not step or step.type ~= "recipeCraft" then
		return false, "That step is not a recipe craft step."
	end

	local currentState = self:UpdateCurrentProfessionState()
	if not currentState or not currentState.recipeID then
		return false, "Select a recipe in the profession window first."
	end

	local requireProfessionOpen = not (step.recipeConfig and step.recipeConfig.requireProfessionOpen == false)
	step.recipeConfig = {
		label = currentState.label,
		recipeID = currentState.recipeID,
		requiredProfession = currentState.requiredProfession,
		openTradeSkillID = currentState.openTradeSkillID,
		requireProfessionOpen = requireProfessionOpen,
		useDefaultReagents = false,
		debug = false,
		reagents = copyTable(currentState.reagents or {}),
		reagentSlots = copyTable(currentState.reagentSlots or {}),
		outputQuantityMin = currentState.outputQuantityMin,
		outputQuantityMax = currentState.outputQuantityMax,
		outputItemLink = currentState.outputItemLink,
		outputItemID = currentState.outputItemID,
		outputIcon = currentState.outputIcon,
	}
	self:MarkCraftRecipeCacheDirty()
	refreshViews()
	return true
end

local function getGoldPrinterRecipeStepAndSlot(stepIndex, dataSlotIndex)
	local routine = SmartRez:GetGoldPrinterRoutine()
	local step = routine and routine.steps[stepIndex] or nil
	if not step or step.type ~= "recipeCraft" or type(step.recipeConfig) ~= "table" then
		return nil, nil
	end

	for _, reagentSlot in ipairs(step.recipeConfig.reagentSlots or {}) do
		if reagentSlot.dataSlotIndex == dataSlotIndex then
			reagentSlot.selectedItemIDs = reagentSlot.selectedItemIDs or {}
			return step, reagentSlot
		end
	end

	return step, nil
end

function SmartRez:GetGoldPrinterRecipeCraftReagentWhitelist(stepIndex, dataSlotIndex)
	local _, reagentSlot = getGoldPrinterRecipeStepAndSlot(stepIndex, dataSlotIndex)
	return reagentSlot and reagentSlot.selectedItemIDs or {}
end

function SmartRez:AddGoldPrinterRecipeCraftReagentWhitelistItem(stepIndex, dataSlotIndex, itemID)
	local step, reagentSlot = getGoldPrinterRecipeStepAndSlot(stepIndex, dataSlotIndex)
	if not step or not reagentSlot or not itemID then
		return
	end

	for _, allowedItemID in ipairs(reagentSlot.allowedItemIDs or {}) do
		if allowedItemID == itemID then
			reagentSlot.selectedItemIDs = {
				[itemID] = true,
			}
			step.recipeConfig.reagentChoices = step.recipeConfig.reagentChoices or {}
			step.recipeConfig.reagentChoices[dataSlotIndex] = itemID
			SmartRez:RefreshRecipeCraftResolvedConfig(step.recipeConfig)
			SmartRez:MarkCraftRecipeCacheDirty()
			refreshViews()
			return
		end
	end
end

function SmartRez:SetGoldPrinterRecipeCraftReagentChoice(stepIndex, dataSlotIndex, itemID, skipRefresh)
	local step, reagentSlot = getGoldPrinterRecipeStepAndSlot(stepIndex, dataSlotIndex)
	if not step or not reagentSlot then
		return
	end

	reagentSlot.selectedItemIDs = {}
	step.recipeConfig.reagentChoices = step.recipeConfig.reagentChoices or {}
	step.recipeConfig.reagentChoices[dataSlotIndex] = nil
	if itemID then
		for _, allowedItemID in ipairs(reagentSlot.allowedItemIDs or {}) do
			if allowedItemID == itemID then
				reagentSlot.selectedItemIDs[itemID] = true
				step.recipeConfig.reagentChoices[dataSlotIndex] = itemID
				break
			end
		end
	end

	SmartRez:RefreshRecipeCraftResolvedConfig(step.recipeConfig)
	SmartRez:MarkCraftRecipeCacheDirty()
	if not skipRefresh then
		refreshViews()
	end
end

function SmartRez:SetGoldPrinterRecipeCraftRequireProfessionOpen(stepIndex, requireProfessionOpen, skipRefresh)
	local routine = self:GetGoldPrinterRoutine()
	local step = routine and routine.steps[stepIndex] or nil
	if not step or step.type ~= "recipeCraft" or type(step.recipeConfig) ~= "table" then
		return
	end

	step.recipeConfig.requireProfessionOpen = requireProfessionOpen == true
	self:MarkCraftRecipeCacheDirty()
	if not skipRefresh then
		refreshViews()
	end
end

function SmartRez:RemoveGoldPrinterRecipeCraftReagentWhitelistItem(stepIndex, dataSlotIndex, itemID)
	local step, reagentSlot = getGoldPrinterRecipeStepAndSlot(stepIndex, dataSlotIndex)
	if not step or not reagentSlot or not itemID then
		return
	end

	reagentSlot.selectedItemIDs[itemID] = nil
	step.recipeConfig.reagentChoices = step.recipeConfig.reagentChoices or {}
	if step.recipeConfig.reagentChoices[dataSlotIndex] == itemID then
		step.recipeConfig.reagentChoices[dataSlotIndex] = nil
	end
	SmartRez:RefreshRecipeCraftResolvedConfig(step.recipeConfig)
	SmartRez:MarkCraftRecipeCacheDirty()
	refreshViews()
end

function SmartRez:CaptureGoldPrinterSalvageStep(stepIndex)
	local routine = self:GetGoldPrinterRoutine()
	local step = routine and routine.steps[stepIndex] or nil
	if not step or step.type ~= "craftSalvage" then
		return false, "That step is not a salvage craft step."
	end

	local currentState = self:UpdateCurrentProfessionState()
	if not currentState or not currentState.recipeID or not currentState.requiredProfession then
		return false, "Select a recipe in the profession window first."
	end

	local profession = self:GetCraftSalvageProfessionByProfessionID(currentState.requiredProfession)
	if not profession then
		return false, "No Smart Rez salvage action exists for that profession yet."
	end

	local registeredRecipe = self:FindCraftSalvageRecipeByRecipeID(currentState.recipeID, profession.key)
	local requireProfessionOpen = not (step.selection and step.selection.requireProfessionOpen == false)
	local resolvedDetails = {
		label = currentState.label,
		requiredStack = getGoldPrinterRequiredStack(currentState),
		salvageTargetItemIDs = getGoldPrinterSalvageTargetItemIDs(currentState.recipeID),
		reagentSlots = getGoldPrinterSalvageReagentSlots(currentState.recipeID),
	}

	step.selection = {
		professionKey = profession.key,
		professionLabel = profession.label,
		recipeKey = registeredRecipe and registeredRecipe.key or nil,
		label = resolvedDetails.label,
		recipeID = currentState.recipeID,
		requiredProfession = currentState.requiredProfession,
		openTradeSkillID = currentState.openTradeSkillID,
		requireProfessionOpen = requireProfessionOpen,
		requiredStack = resolvedDetails.requiredStack or 1,
		salvageTargetItemIDs = resolvedDetails.salvageTargetItemIDs or {},
		reagentSlots = resolvedDetails.reagentSlots or {},
		preferLargestStack = false,
		sortBagsOnLoad = false,
		sortBagsWhenEmpty = false,
		isDefault = false,
	}
	refreshViews()
	return true
end

function SmartRez:SetGoldPrinterSalvageRequireProfessionOpen(stepIndex, requireProfessionOpen, skipRefresh)
	local routine = self:GetGoldPrinterRoutine()
	local step = routine and routine.steps[stepIndex] or nil
	if not step or step.type ~= "craftSalvage" or type(step.selection) ~= "table" then
		return
	end

	step.selection.requireProfessionOpen = requireProfessionOpen == true
	self:MarkCraftSalvageCacheDirty()
	if not skipRefresh then
		refreshViews()
	end
end

function SmartRez:GetGoldPrinterRoutineStepTypeList()
	return {
		recipeCraft = "Recipe Craft",
		craftSalvage = "Salvage",
		disenchant = "Disenchant",
	}
end

function SmartRez:GetGoldPrinterRoutineStepLabel(step)
	if not step then
		return "Idle"
	end

	if step.type == "recipeCraft" then
		local recipeConfig = step.recipeConfig
		return recipeConfig and recipeConfig.label and ("Craft: " .. tostring(recipeConfig.label)) or "Craft: Unset"
	end

	if step.type == "craftSalvage" then
		local selection = step.selection
		return selection and selection.label and ("Salvage: " .. tostring(selection.label)) or "Salvage: Unset"
	end

	if step.type == "disenchant" then
		return "Disenchant"
	end

	return "Idle"
end

function SmartRez:GetGoldPrinterRoutineStepDisenchantContextKey(routineKey, stepIndex)
	return string.format("goldprinter:%s:step:%d:disenchant", tostring(routineKey), tonumber(stepIndex) or 0)
end

function SmartRez:GetGoldPrinterRoutineStepCraftSalvageContextKey(routineKey, stepIndex, professionKey)
	return string.format("goldprinter:%s:step:%d:salvage:%s", tostring(routineKey), tonumber(stepIndex) or 0, tostring(professionKey or "unknown"))
end

function SmartRez:SetActiveCraftSalvageWhitelistContextKey(professionKey, contextKey)
	self.activeCraftSalvageWhitelistContextKeys = self.activeCraftSalvageWhitelistContextKeys or {}
	if professionKey then
		self.activeCraftSalvageWhitelistContextKeys[professionKey] = contextKey
	end
end

function SmartRez:GetActiveCraftSalvageWhitelistContextKey(professionKey)
	local contextKeys = self.activeCraftSalvageWhitelistContextKeys
	return contextKeys and contextKeys[professionKey] or nil
end

function SmartRez:SetActiveRecipeCraftConfig(configKey, recipeConfig)
	self.activeRecipeCraftConfigs = self.activeRecipeCraftConfigs or {}
	if recipeConfig then
		self.activeRecipeCraftConfigs[configKey] = recipeConfig
	else
		self.activeRecipeCraftConfigs[configKey] = nil
	end
	self:MarkCraftRecipeCacheDirty()
end

function SmartRez:SetActiveCraftSalvageSelection(professionKey, selection)
	self.activeCraftSalvageSelections = self.activeCraftSalvageSelections or {}
	if professionKey then
		self.activeCraftSalvageSelections[professionKey] = selection
	end
end

function SmartRez:ClearActiveGoldPrinterStepContexts()
	self.activeGoldPrinterStepContextToken = nil
	self.activeDisenchantWhitelistContextKey = MANUAL_DISENCHANT_CONTEXT_KEY
	self.activeCraftSalvageWhitelistContextKeys = {}
	self.activeRecipeCraftConfigs = {}
	self.activeCraftSalvageSelections = {}
end

function SmartRez:ActivateGoldPrinterRoutineStepContexts(routineKey, stepIndex, step)
	local contextSubject = step and (step.recipeConfig or step.selection) or nil
	local contextToken = string.format(
		"%s:%d:%s:%s",
		tostring(routineKey),
		tonumber(stepIndex) or 0,
		tostring(step and step.type or "none"),
		tostring(contextSubject)
	)
	if self.activeGoldPrinterStepContextToken == contextToken then
		return false
	end

	self:ClearActiveGoldPrinterStepContexts()
	self.activeGoldPrinterStepContextToken = contextToken

	if not step then
		return true
	end

	if step.type == "disenchant" then
		self:SetActiveDisenchantWhitelistContextKey(self:GetGoldPrinterRoutineStepDisenchantContextKey(routineKey, stepIndex))
	elseif step.type == "craftSalvage" then
		local selection = step.selection
		local professionKey = selection and selection.professionKey or nil
		if professionKey then
			self:SetActiveCraftSalvageSelection(professionKey, selection)
			self:SetActiveCraftSalvageWhitelistContextKey(
				professionKey,
				self:GetGoldPrinterRoutineStepCraftSalvageContextKey(routineKey, stepIndex, professionKey)
			)
		end
	elseif step.type == "recipeCraft" and step.recipeConfig then
		self:SetActiveRecipeCraftConfig(GOLD_PRINTER_RECIPE_ACTION_KEY, step.recipeConfig)
	end

	return true
end
