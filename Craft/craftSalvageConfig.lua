local SmartRez = _G.SmartRez

local _C_OpenTradeSkill = C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill
local _C_GetRecipeInfo = C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo
local _C_GetRecipeSchematic = C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic
local _C_GetSalvagableItemIDs = C_TradeSkillUI and C_TradeSkillUI.GetSalvagableItemIDs

local LEGACY_SALVAGE_ACTION_KEY_BY_PROFESSION = {
	alchemy = "thaumaturgy",
	cooking = "cooking",
	enchanting = "shattering",
	engineering = "recycling",
	inscription = "milling",
	jewelcrafting = "prospecting",
}

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

local function getSortedConfigs(configMap, availableOnly)
	local configs = {}

	for _, config in pairs(configMap or {}) do
		if not availableOnly or not config.professionID or SmartRez:HasProfession(config.professionID) then
			configs[#configs + 1] = config
		end
	end

	table.sort(configs, function(left, right)
		if left.order == right.order then
			return tostring(left.label) < tostring(right.label)
		end

		return (left.order or 0) < (right.order or 0)
	end)

	return configs
end

local function getCraftSalvageWhitelistStorageKey(professionKey, selection)
	if selection and selection.recipeKey then
		return "recipe:" .. tostring(selection.recipeKey)
	end

	if selection and selection.recipeID then
		return "recipeid:" .. tostring(selection.recipeID)
	end

	return "profession:" .. tostring(professionKey)
end

local function getLegacyWhitelistSourceKeys(professionKey)
	local keys = {
		professionKey,
		"profession:" .. tostring(professionKey),
	}

	local legacyActionKey = LEGACY_SALVAGE_ACTION_KEY_BY_PROFESSION[professionKey]
	if legacyActionKey and legacyActionKey ~= professionKey then
		keys[#keys + 1] = legacyActionKey
	end

	return keys
end

local function mergeSelectionDefaults(selection, fallback)
	if not fallback then
		return selection
	end

	for key, value in pairs(fallback) do
		if selection[key] == nil then
			selection[key] = value
		end
	end

	return selection
end

local function syncSelectionWithRegisteredRecipe(selection, fallback)
	if not fallback then
		return selection
	end

	selection.recipeKey = fallback.recipeKey or selection.recipeKey
	selection.label = fallback.label or selection.label
	selection.requiredProfession = fallback.requiredProfession or selection.requiredProfession
	selection.openTradeSkillID = fallback.openTradeSkillID or selection.openTradeSkillID
	selection.requiredStack = fallback.requiredStack or selection.requiredStack
	selection.salvageTargetItemIDs = copyTable(fallback.salvageTargetItemIDs or selection.salvageTargetItemIDs)
	selection.reagentSlots = copyTable(fallback.reagentSlots or selection.reagentSlots)
	selection.preferLargestStack = fallback.preferLargestStack == true
	selection.sortBagsOnLoad = fallback.sortBagsOnLoad == true
	selection.sortBagsWhenEmpty = fallback.sortBagsWhenEmpty == true

	return selection
end

local function findRequiredStackInReagents(reagents)
	for _, reagent in ipairs(reagents or {}) do
		if reagent.quantity and reagent.quantity > 0 then
			return reagent.quantity
		end

		if reagent.quantityRequired and reagent.quantityRequired > 0 then
			return reagent.quantityRequired
		end
	end
end

local function getRequiredStackFromReagents(reagents)
	return findRequiredStackInReagents(reagents) or 1
end

local function getRequiredReagentSlots(recipeSchematic)
	local requiredSlots = {}

	for _, reagentSlot in ipairs(recipeSchematic and recipeSchematic.reagentSlotSchematics or {}) do
		if reagentSlot.required ~= false and reagentSlot.quantityRequired and reagentSlot.quantityRequired > 0 then
			requiredSlots[#requiredSlots + 1] = reagentSlot
		end
	end

	return requiredSlots
end

local function getRequiredStackFromSchematic(recipeSchematic)
	if recipeSchematic and recipeSchematic.quantityMin and recipeSchematic.quantityMin > 0 then
		return recipeSchematic.quantityMin
	end

	if recipeSchematic and recipeSchematic.quantityMax and recipeSchematic.quantityMax > 0 then
		return recipeSchematic.quantityMax
	end

	local reagentQuantity = findRequiredStackInReagents(getRequiredReagentSlots(recipeSchematic))
	if reagentQuantity and reagentQuantity > 0 then
		return reagentQuantity
	end
end

local function getRequiredStackFromCurrentState(currentState)
	if not currentState then
		return nil
	end

	if currentState.outputQuantityMin and currentState.outputQuantityMin > 0 then
		return currentState.outputQuantityMin
	end

	if currentState.outputQuantityMax and currentState.outputQuantityMax > 0 then
		return currentState.outputQuantityMax
	end

	local reagentQuantity = findRequiredStackInReagents(currentState.reagents)
	if reagentQuantity and reagentQuantity > 0 then
		return reagentQuantity
	end
end

local function getSalvageTargetItemIDs(recipeID)
	local itemIDs = {}

	for _, itemID in ipairs(_C_GetSalvagableItemIDs and _C_GetSalvagableItemIDs(recipeID) or {}) do
		if itemID then
			itemIDs[#itemIDs + 1] = itemID
		end
	end

	return itemIDs
end

local function getReagentSlotsFromSchematic(recipeSchematic)
	local reagentSlots = {}

	for _, reagentSlot in ipairs(getRequiredReagentSlots(recipeSchematic)) do
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

	return reagentSlots
end

local function getCurrentRecipeState(professionID, recipeID)
	local currentState = SmartRez.currentProfessionState

	if currentState and currentState.recipeID == recipeID and currentState.requiredProfession == professionID then
		return currentState
	end
end

local function getResolvedRecipeDetailsByID(professionID, recipeID, fallbackLabel, fallbackRequiredStack)
	local label = fallbackLabel
	local requiredStack = fallbackRequiredStack
	local currentState = getCurrentRecipeState(professionID, recipeID)
	local salvageTargetItemIDs = {}
	local reagentSlots = {}

	if _C_GetRecipeSchematic then
		local recipeSchematic = _C_GetRecipeSchematic(recipeID, false)
		if recipeSchematic and recipeSchematic.name then
			label = recipeSchematic.name
		end
		requiredStack = getRequiredStackFromSchematic(recipeSchematic) or requiredStack
		reagentSlots = getReagentSlotsFromSchematic(recipeSchematic)
	end

	if _C_GetRecipeInfo then
		local recipeInfo = _C_GetRecipeInfo(recipeID)
		if recipeInfo and recipeInfo.name then
			label = recipeInfo.name
		end
	end

	salvageTargetItemIDs = getSalvageTargetItemIDs(recipeID)

	if currentState then
		label = currentState.label or label
		requiredStack = requiredStack or getRequiredStackFromCurrentState(currentState)
	end

	return {
		label = label,
		requiredStack = requiredStack or 1,
		salvageTargetItemIDs = salvageTargetItemIDs,
		reagentSlots = reagentSlots,
	}
end

local function getResolvedRecipeDetails(profession, recipeConfig)
	return getResolvedRecipeDetailsByID(
		profession.professionID,
		recipeConfig.recipeID,
		recipeConfig.label,
		recipeConfig.requiredStack
	)
end

local function buildSelectionFromRecipe(profession, recipeConfig, isDefault)
	if not profession or not recipeConfig then
		return nil
	end

	local resolvedDetails = getResolvedRecipeDetails(profession, recipeConfig)

	return {
		professionKey = profession.key,
		professionLabel = profession.label,
		recipeKey = recipeConfig.key,
		label = resolvedDetails.label,
		recipeID = recipeConfig.recipeID,
		requiredProfession = profession.professionID,
		openTradeSkillID = profession.professionID,
		requiredStack = resolvedDetails.requiredStack,
		salvageTargetItemIDs = resolvedDetails.salvageTargetItemIDs,
		reagentSlots = resolvedDetails.reagentSlots,
		preferLargestStack = recipeConfig.preferLargestStack == true,
		sortBagsOnLoad = recipeConfig.sortBagsOnLoad == true,
		sortBagsWhenEmpty = recipeConfig.sortBagsWhenEmpty == true,
		isDefault = isDefault == true,
	}
end

function SmartRez:RegisterCraftSalvageRecipe(config)
	self.craftSalvageRecipes[config.key] = config
	self:MarkCraftSalvageCacheDirty()
end

function SmartRez:GetCraftSalvageRecipe(recipeKey)
	return self.craftSalvageRecipes[recipeKey]
end

function SmartRez:FindCraftSalvageRecipeByRecipeID(recipeID, professionKey)
	for _, recipeConfig in pairs(self.craftSalvageRecipes) do
		if recipeConfig.recipeID == recipeID and (not professionKey or recipeConfig.professionKey == professionKey) then
			return recipeConfig
		end
	end
end

function SmartRez:GetCraftSalvageRecipes(professionKey)
	local recipes = {}

	for _, recipeConfig in ipairs(getSortedConfigs(self.craftSalvageRecipes)) do
		if not professionKey or recipeConfig.professionKey == professionKey then
			recipes[#recipes + 1] = recipeConfig
		end
	end

	return recipes
end

function SmartRez:GetCraftSalvageProfession(professionKey)
	return self.craftSalvageProfessions[professionKey]
end

function SmartRez:GetCraftSalvageProfessions(availableOnly)
	return getSortedConfigs(self.craftSalvageProfessions, availableOnly)
end

function SmartRez:GetCraftSalvageWhitelistStorageKey(professionKey, contextKey)
	if contextKey then
		return "context:" .. tostring(contextKey)
	end

	local selection = professionKey and self:GetCraftSalvageSelection(professionKey) or nil
	return getCraftSalvageWhitelistStorageKey(professionKey, selection)
end

local function normalizeCraftSalvageWhitelistStorage(storage)
	if type(storage) ~= "table" then
		return {
			targetItems = {},
			reagentSlots = {},
		}
	end

	if storage.targetItems or storage.reagentSlots then
		if type(storage.targetItems) ~= "table" then
			storage.targetItems = {}
		end
		if type(storage.reagentSlots) ~= "table" then
			storage.reagentSlots = {}
		end
		return storage
	end

	return {
		targetItems = storage,
		reagentSlots = {},
	}
end

-- Keep salvage whitelists character-scoped and tied to the currently selected recipe.
function SmartRez:GetCraftSalvageWhitelistStorage(professionKey, contextKey)
	self:EnsureConfig()

	local resolvedContextKey = contextKey or self:GetActiveCraftSalvageWhitelistContextKey(professionKey)
	local storageKey = self:GetCraftSalvageWhitelistStorageKey(professionKey, resolvedContextKey)
	local whitelists = self.db.salvageWhitelists

	if not resolvedContextKey and type(whitelists[storageKey]) ~= "table" then
		for _, sourceKey in ipairs(getLegacyWhitelistSourceKeys(professionKey)) do
			if sourceKey ~= storageKey and type(whitelists[sourceKey]) == "table" then
				whitelists[storageKey] = whitelists[sourceKey]
				whitelists[sourceKey] = nil
				break
			end
		end
	end

	whitelists[storageKey] = normalizeCraftSalvageWhitelistStorage(whitelists[storageKey])
	return whitelists[storageKey]
end

function SmartRez:GetCraftSalvageWhitelist(professionKey, contextKey)
	return self:GetCraftSalvageWhitelistStorage(professionKey, contextKey).targetItems
end

function SmartRez:GetCraftSalvageReagentWhitelist(professionKey, dataSlotIndex, contextKey)
	local storage = self:GetCraftSalvageWhitelistStorage(professionKey, contextKey)

	if type(storage.reagentSlots[dataSlotIndex]) ~= "table" then
		storage.reagentSlots[dataSlotIndex] = {}
	end

	return storage.reagentSlots[dataSlotIndex]
end

local function itemListContains(itemIDs, itemID)
	for _, allowedItemID in ipairs(itemIDs or {}) do
		if allowedItemID == itemID then
			return true
		end
	end

	return false
end

function SmartRez:AddCraftSalvageWhitelistItem(professionKey, itemID, skipRefresh, contextKey)
	if not professionKey or not itemID or not self.craftSalvageProfessions[professionKey] then
		return
	end

	local selection = self:GetCraftSalvageSelection(professionKey)
	if not itemListContains(selection and selection.salvageTargetItemIDs, itemID) then
		print("Smart Rez:", "That item is not in the recipe's salvage target list.")
		return
	end

	local whitelist = self:GetCraftSalvageWhitelist(professionKey, contextKey)
	whitelist[itemID] = true
	self:MarkCraftSalvageCacheDirty()
	if not skipRefresh then
		self:RefreshViews()
	end
end

function SmartRez:AddCraftSalvageReagentWhitelistItem(professionKey, dataSlotIndex, itemID, skipRefresh, contextKey)
	if not professionKey or not dataSlotIndex or not itemID or not self.craftSalvageProfessions[professionKey] then
		return
	end

	local reagentSlots = self:GetCraftSalvageReagentSlots(professionKey)
	local slotFound = false
	for _, reagentSlot in ipairs(reagentSlots) do
		if reagentSlot.dataSlotIndex == dataSlotIndex then
			slotFound = true
			if not itemListContains(reagentSlot.allowedItemIDs, itemID) then
				print("Smart Rez:", "That item is not allowed in this reagent slot.")
				return
			end
		end
	end

	if not slotFound then
		return
	end

	local whitelist = self:GetCraftSalvageReagentWhitelist(professionKey, dataSlotIndex, contextKey)
	whitelist[itemID] = true
	self:MarkCraftSalvageCacheDirty()
	if not skipRefresh then
		self:RefreshViews()
	end
end

function SmartRez:RemoveCraftSalvageWhitelistItem(professionKey, itemID, skipRefresh, contextKey)
	local whitelist = self:GetCraftSalvageWhitelist(professionKey, contextKey)
	whitelist[itemID] = nil
	self:MarkCraftSalvageCacheDirty()
	if not skipRefresh then
		self:RefreshViews()
	end
end

function SmartRez:RemoveCraftSalvageReagentWhitelistItem(professionKey, dataSlotIndex, itemID, skipRefresh, contextKey)
	local whitelist = self:GetCraftSalvageReagentWhitelist(professionKey, dataSlotIndex, contextKey)
	whitelist[itemID] = nil
	self:MarkCraftSalvageCacheDirty()
	if not skipRefresh then
		self:RefreshViews()
	end
end

local function buildAllowedItemSet(allowedItemIDs, customWhitelist)
	local allowedItems = {}
	local hasCustomFilter = next(customWhitelist or {}) ~= nil

	if hasCustomFilter then
		for _, itemID in ipairs(allowedItemIDs or {}) do
			if customWhitelist[itemID] then
				allowedItems[itemID] = true
			end
		end
	else
		for _, itemID in ipairs(allowedItemIDs or {}) do
			allowedItems[itemID] = true
		end
	end

	return allowedItems
end

function SmartRez:GetCraftSalvageAllowedTargetItems(professionKey, contextKey)
	local selection = self:GetCraftSalvageSelection(professionKey)
	return buildAllowedItemSet(selection and selection.salvageTargetItemIDs, self:GetCraftSalvageWhitelist(professionKey, contextKey))
end

function SmartRez:GetCraftSalvageReagentSlots(professionKey)
	local selection = self:GetCraftSalvageSelection(professionKey)
	return selection and selection.reagentSlots or {}
end

function SmartRez:GetCraftSalvageAllowedReagentItems(professionKey, dataSlotIndex, contextKey)
	local reagentSlots = self:GetCraftSalvageReagentSlots(professionKey)

	for _, reagentSlot in ipairs(reagentSlots) do
		if reagentSlot.dataSlotIndex == dataSlotIndex then
			return buildAllowedItemSet(reagentSlot.allowedItemIDs, self:GetCraftSalvageReagentWhitelist(professionKey, dataSlotIndex, contextKey))
		end
	end

	return {}
end

function SmartRez:GetCraftSalvageSelection(professionKey)
	self:EnsureConfig()

	local profession = self:GetCraftSalvageProfession(professionKey)
	if not profession then
		return nil
	end

	if self.activeCraftSalvageSelections and type(self.activeCraftSalvageSelections[professionKey]) == "table" then
		return self.activeCraftSalvageSelections[professionKey]
	end

	local savedSelection = self.db.salvageSelections[professionKey]
	if type(savedSelection) == "table" and savedSelection.recipeID then
		local selection = copyTable(savedSelection)
		local registeredRecipe = selection.recipeKey and self:GetCraftSalvageRecipe(selection.recipeKey)
			or self:FindCraftSalvageRecipeByRecipeID(selection.recipeID, professionKey)
		local fallback = buildSelectionFromRecipe(profession, registeredRecipe, false)

		mergeSelectionDefaults(selection, fallback)
		syncSelectionWithRegisteredRecipe(selection, fallback)
		selection.professionKey = profession.key
		selection.professionLabel = profession.label
		selection.requiredProfession = selection.requiredProfession or profession.professionID
		selection.openTradeSkillID = selection.openTradeSkillID or profession.professionID
		selection.requiredStack = selection.requiredStack or 1
		selection.salvageTargetItemIDs = selection.salvageTargetItemIDs or {}
		selection.reagentSlots = selection.reagentSlots or {}
		selection.isDefault = false
		return selection
	end

	-- Keep DB entries empty until the user picks something custom.
	local defaultRecipe = profession.defaultRecipeKey and self:GetCraftSalvageRecipe(profession.defaultRecipeKey) or nil
	return buildSelectionFromRecipe(profession, defaultRecipe, true)
end

function SmartRez:SetCraftSalvageSelection(professionKey, selection)
	local profession = self:GetCraftSalvageProfession(professionKey)
	if not profession then
		return
	end

	self:EnsureConfig()
	self.db.salvageSelections[professionKey] = copyTable(selection or {})
	self:MarkCraftSalvageCacheDirty()
	self:RefreshViews()
end

function SmartRez:LoadCraftSalvageSelectionFromCurrentRecipe(professionKey)
	if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic) then
		return false, "Recipe UI APIs are unavailable."
	end

	local profession = self:GetCraftSalvageProfession(professionKey)
	if not profession then
		return false, "Unknown profession tab."
	end

	local currentState = self:UpdateCurrentProfessionState()
	if not currentState or not currentState.recipeID then
		if _C_OpenTradeSkill then
			_C_OpenTradeSkill(profession.professionID)
			return false, "Opened " .. profession.label .. ". Select a recipe, then click again."
		end
		return false, "Select a recipe in the profession window first."
	end

	if currentState.requiredProfession ~= profession.professionID then
		if _C_OpenTradeSkill then
			_C_OpenTradeSkill(profession.professionID)
		end
		return false, "Opened " .. profession.label .. ". Select a recipe there, then click again."
	end

	local registeredRecipe = self:FindCraftSalvageRecipeByRecipeID(currentState.recipeID, professionKey)
	local resolvedDetails = getResolvedRecipeDetailsByID(
		profession.professionID,
		currentState.recipeID,
		currentState.label,
		getRequiredStackFromCurrentState(currentState)
	)
	local selection = registeredRecipe and buildSelectionFromRecipe(profession, registeredRecipe, false) or {
		professionKey = profession.key,
		professionLabel = profession.label,
		label = resolvedDetails.label,
		recipeID = currentState.recipeID,
		requiredProfession = profession.professionID,
		openTradeSkillID = profession.professionID,
		requiredStack = resolvedDetails.requiredStack,
		salvageTargetItemIDs = resolvedDetails.salvageTargetItemIDs,
		reagentSlots = resolvedDetails.reagentSlots,
		preferLargestStack = false,
		sortBagsOnLoad = false,
		sortBagsWhenEmpty = false,
	}

	selection.recipeKey = registeredRecipe and registeredRecipe.key or nil
	selection.label = resolvedDetails.label or selection.label
	selection.recipeID = currentState.recipeID
	selection.requiredStack = resolvedDetails.requiredStack or selection.requiredStack or 1
	selection.salvageTargetItemIDs = resolvedDetails.salvageTargetItemIDs or selection.salvageTargetItemIDs or {}
	selection.reagentSlots = resolvedDetails.reagentSlots or selection.reagentSlots or {}
	selection.isDefault = false

	self:SetCraftSalvageSelection(professionKey, selection)
	return true
end

function SmartRez:GetBagItemCount(itemID)
	return self:GetCraftingItemCount(itemID)
end
