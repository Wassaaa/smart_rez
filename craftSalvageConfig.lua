local SmartRez = _G.SmartRez

local _C_GetContainerNumSlots = _G["C_Container"]["GetContainerNumSlots"]
local _C_GetContainerItemInfo = _G["C_Container"]["GetContainerItemInfo"]
local _C_OpenTradeSkill = _G["C_TradeSkillUI"] and _G["C_TradeSkillUI"]["OpenTradeSkill"]
local _C_GetRecipeInfo = _G["C_TradeSkillUI"] and _G["C_TradeSkillUI"]["GetRecipeInfo"]
local _C_GetRecipeSchematic = _G["C_TradeSkillUI"] and _G["C_TradeSkillUI"]["GetRecipeSchematic"]

local LEGACY_SALVAGE_KEY_BY_PROFESSION = {
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

local function getRequiredStackFromSchematic(recipeSchematic)
	return findRequiredStackInReagents(recipeSchematic and recipeSchematic.reagentSlotSchematics)
end

local function getResolvedRecipeLabel(profession, recipeConfig)
	local label = recipeConfig.label
	local currentState = SmartRez.currentProfessionState

	if currentState and currentState.recipeID == recipeConfig.recipeID and currentState.requiredProfession == profession.professionID then
		label = currentState.label or label
	end

	if _C_GetRecipeSchematic then
		local recipeSchematic = _C_GetRecipeSchematic(recipeConfig.recipeID, false)
		if recipeSchematic and recipeSchematic.name then
			label = recipeSchematic.name
		end
	end

	if _C_GetRecipeInfo then
		local recipeInfo = _C_GetRecipeInfo(recipeConfig.recipeID)
		if recipeInfo and recipeInfo.name then
			label = recipeInfo.name
		end
	end

	return label
end

local function getResolvedRecipeDetails(profession, recipeConfig)
	local label = getResolvedRecipeLabel(profession, recipeConfig)
	local requiredStack = recipeConfig.requiredStack or 1
	local currentState = SmartRez.currentProfessionState

	if currentState and currentState.recipeID == recipeConfig.recipeID and currentState.requiredProfession == profession.professionID then
		requiredStack = getRequiredStackFromReagents(currentState.reagents)
	end

	if _C_GetRecipeSchematic then
		local recipeSchematic = _C_GetRecipeSchematic(recipeConfig.recipeID, false)
		if recipeSchematic then
			requiredStack = getRequiredStackFromSchematic(recipeSchematic) or requiredStack
		end
	end

	return {
		label = label,
		requiredStack = requiredStack,
	}
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
		preferLargestStack = recipeConfig.preferLargestStack == true,
		sortBagsOnLoad = recipeConfig.sortBagsOnLoad == true,
		sortBagsWhenEmpty = recipeConfig.sortBagsWhenEmpty == true,
		isDefault = isDefault == true,
	}
end

function SmartRez:RegisterCraftSalvageRecipe(config)
	config.requiredStack = config.requiredStack or 1
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

-- Keep salvage whitelists character-scoped since inventory and professions differ per alt.
function SmartRez:GetCraftSalvageWhitelist(professionKey)
	self:EnsureConfig()

	if type(self.db.char.salvageWhitelists[professionKey]) ~= "table" then
		local legacyKey = LEGACY_SALVAGE_KEY_BY_PROFESSION[professionKey]
		local legacyWhitelist = legacyKey and self.db.char.salvageWhitelists[legacyKey]

		if type(legacyWhitelist) == "table" then
			self.db.char.salvageWhitelists[professionKey] = legacyWhitelist
		else
			self.db.char.salvageWhitelists[professionKey] = {}
		end
	end

	return self.db.char.salvageWhitelists[professionKey]
end

function SmartRez:AddCraftSalvageWhitelistItem(professionKey, itemID)
	if not professionKey or not itemID or not self.craftSalvageProfessions[professionKey] then
		return
	end

	local whitelist = self:GetCraftSalvageWhitelist(professionKey)
	whitelist[itemID] = true
	self:MarkCraftSalvageCacheDirty()
	self:RefreshViews()
end

function SmartRez:RemoveCraftSalvageWhitelistItem(professionKey, itemID)
	local whitelist = self:GetCraftSalvageWhitelist(professionKey)
	whitelist[itemID] = nil
	self:MarkCraftSalvageCacheDirty()
	self:RefreshViews()
end

function SmartRez:GetCraftSalvageSelection(professionKey)
	self:EnsureConfig()

	local profession = self:GetCraftSalvageProfession(professionKey)
	if not profession then
		return nil
	end

	local savedSelection = self.db.char.salvageSelections[professionKey]
	if type(savedSelection) == "table" and savedSelection.recipeID then
		local selection = copyTable(savedSelection)
		local registeredRecipe = selection.recipeKey and self:GetCraftSalvageRecipe(selection.recipeKey) or nil
		local fallback = buildSelectionFromRecipe(profession, registeredRecipe, false)

		mergeSelectionDefaults(selection, fallback)
		selection.professionKey = profession.key
		selection.professionLabel = profession.label
		selection.requiredProfession = selection.requiredProfession or profession.professionID
		selection.openTradeSkillID = selection.openTradeSkillID or profession.professionID
		selection.requiredStack = selection.requiredStack or 1
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
	self.db.char.salvageSelections[professionKey] = copyTable(selection or {})
	self:MarkCraftSalvageCacheDirty()
	self:RefreshViews()
end

function SmartRez:LoadCraftSalvageSelectionFromCurrentRecipe(professionKey)
	if not (_G["C_TradeSkillUI"] and _G["C_TradeSkillUI"]["GetRecipeSchematic"]) then
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
	local selection = registeredRecipe and buildSelectionFromRecipe(profession, registeredRecipe, false) or {
		professionKey = profession.key,
		professionLabel = profession.label,
		requiredProfession = profession.professionID,
		openTradeSkillID = profession.professionID,
		requiredStack = getRequiredStackFromReagents(currentState.reagents),
		preferLargestStack = false,
		sortBagsOnLoad = false,
		sortBagsWhenEmpty = false,
	}

	selection.recipeKey = registeredRecipe and registeredRecipe.key or nil
	selection.label = currentState.label or selection.label
	selection.recipeID = currentState.recipeID
	selection.isDefault = false

	self:SetCraftSalvageSelection(professionKey, selection)
	return true
end

function SmartRez:GetBagItemCount(itemID)
	if not itemID then
		return 0
	end

	local itemCount = 0

	for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		for slot = 1, _C_GetContainerNumSlots(bag) do
			local itemInfo = _C_GetContainerItemInfo(bag, slot)
			if itemInfo and itemInfo.itemID == itemID then
				itemCount = itemCount + (itemInfo.stackCount or 0)
			end
		end
	end

	return itemCount
end
