local SmartRez = _G.SmartRez

local _C_CraftRecipe = _G["C_TradeSkillUI"]["CraftRecipe"]
local _C_GetBaseProfessionInfo = _G["C_TradeSkillUI"]["GetBaseProfessionInfo"]
local _C_OpenTradeSkill = _G["C_TradeSkillUI"]["OpenTradeSkill"]
local _C_OpenRecipe = _G["C_TradeSkillUI"]["OpenRecipe"]
local _C_GetRecipeInfo = _G["C_TradeSkillUI"]["GetRecipeInfo"]
local _C_Item_GetItemCount = _G["C_Item"] and _G["C_Item"]["GetItemCount"]
local _GetTime = _G["GetTime"]
local _UnitCastingInfo = _G["UnitCastingInfo"]
local _floor = math.floor
local _min = math.min

local function resolveConfigValue(config, key)
	local value = config[key]
	if type(value) == "function" then
		return value(config)
	end
	return value
end

local function debugPrint(config, ...)
	if not resolveConfigValue(config, "debug") then
		return
	end

	print("Smart Rez:", config.label .. ":", ...)
end

local function getCurrencyCount(currencyID)
	if _G["C_CurrencyInfo"] and _G["C_CurrencyInfo"]["GetCurrencyInfo"] then
		local currencyInfo = _G["C_CurrencyInfo"]["GetCurrencyInfo"](currencyID)
		return currencyInfo and currencyInfo.quantity or 0
	end

	return 0
end

local function buildCraftingReagents(reagents, numCasts)
	local craftingReagents = {}

	for index, reagent in ipairs(reagents or {}) do
		craftingReagents[index] = {
			reagent = {
				itemID = reagent.itemID,
				currencyID = reagent.currencyID,
			},
			dataSlotIndex = reagent.dataSlotIndex or index,
			quantity = reagent.quantity * (numCasts or 1),
		}
	end

	if #craftingReagents == 0 then
		return nil
	end

	return craftingReagents
end

local function getAvailableReagentCount(reagent)
	if reagent.itemID then
		if _C_Item_GetItemCount then
			return _C_Item_GetItemCount(reagent.itemID, false, false, false, false)
		end
		return 0
	end

	if reagent.currencyID then
		return getCurrencyCount(reagent.currencyID)
	end

	return 0
end

local function getMaxCraftsFromReagents(reagents)
	local maxCrafts

	for _, reagent in ipairs(reagents or {}) do
		local availableCount = getAvailableReagentCount(reagent)
		local possibleCrafts = _floor(availableCount / reagent.quantity)

		if maxCrafts == nil or possibleCrafts < maxCrafts then
			maxCrafts = possibleCrafts
		end
	end

	return maxCrafts or 0
end

function SmartRez:RebuildCraftRecipeCache()
	local cache = {}

	for key, config in pairs(self.craftRecipeActions) do
		local requiredProfession = resolveConfigValue(config, "requiredProfession")
		local reagents = resolveConfigValue(config, "reagents")
		local useDefaultReagents = resolveConfigValue(config, "useDefaultReagents")

		if not requiredProfession or self:HasProfession(requiredProfession) then
			local maxCrafts = config.getMaxCasts and config.getMaxCasts(config) or getMaxCraftsFromReagents(reagents)
			local numCasts = maxCrafts > 0 and 1 or 0
			local maxAllowedCasts = resolveConfigValue(config, "maxCasts")
			local minRequiredCasts = resolveConfigValue(config, "minCasts") or 1

			debugPrint(config, "cache rebuild", "max", maxCrafts, "casts", numCasts)
			for index, reagent in ipairs(reagents or {}) do
				debugPrint(
					config,
					"reagent count",
					index,
					"item", reagent.itemID or "nil",
					"currency", reagent.currencyID or "nil",
					"need", reagent.quantity,
					"have", getAvailableReagentCount(reagent)
				)
			end

			if maxAllowedCasts then
				numCasts = _min(numCasts, maxAllowedCasts)
			end

			if numCasts >= minRequiredCasts then
				local craftingReagents
				if not useDefaultReagents then
					craftingReagents = config.buildCraftingReagents and config.buildCraftingReagents(numCasts, config) or buildCraftingReagents(reagents, numCasts)
				end
				cache[key] = {
					numCasts = numCasts,
					craftingReagents = craftingReagents,
					availableCasts = maxCrafts,
				}
			else
				cache[key] = nil
			end
		else
			cache[key] = nil
		end
	end

	self.craftRecipeCache = cache
	self.craftRecipeCacheDirty = false
end

function SmartRez:GetCraftRecipeTarget(key)
	if self.craftRecipeCacheDirty then
		self:RebuildCraftRecipeCache()
	end

	return self.craftRecipeCache[key]
end

function SmartRez:RegisterCraftRecipeAction(config)
	local actionFrame = CreateFrame("Frame")
	local castStartTime, castEndTime = nil, nil

	if config.lockButton == nil then
		config.lockButton = true
	end

	self.craftRecipeActions[config.key] = config
	actionFrame.unBlockButton = 0
	actionFrame.btn = CreateFrame("Button", config.buttonName, UIParent, "SecureActionButtonTemplate")
	actionFrame.btn:RegisterForClicks("AnyUp", "AnyDown")

	actionFrame.btn:SetScript("OnClick", function()
		if actionFrame.unBlockButton > _GetTime() then
			debugPrint(config, "blocked", actionFrame.unBlockButton - _GetTime())
			return
		end

		local recipeID = resolveConfigValue(config, "recipeID")
		local openTradeSkillID = resolveConfigValue(config, "openTradeSkillID")
		local recipeLevel = resolveConfigValue(config, "recipeLevel")
		local orderID = resolveConfigValue(config, "orderID")
		local applyConcentration = resolveConfigValue(config, "applyConcentration")
		local requiredProfession = resolveConfigValue(config, "requiredProfession")
		local useDefaultReagents = resolveConfigValue(config, "useDefaultReagents")

		if openTradeSkillID then
			local professionInfo = _C_GetBaseProfessionInfo and _C_GetBaseProfessionInfo()
			if not professionInfo or professionInfo.professionID ~= openTradeSkillID then
				debugPrint(config, "opening profession", openTradeSkillID, "current", professionInfo and professionInfo.professionID or "nil")
				_C_OpenTradeSkill(openTradeSkillID)
				return
			end
			debugPrint(config, "profession ready", professionInfo.professionID)
		end

		if _C_OpenRecipe then
			debugPrint(config, "opening recipe", recipeID)
			_C_OpenRecipe(recipeID)
		end

		if _C_GetRecipeInfo then
			local recipeInfo = _C_GetRecipeInfo(recipeID)
			debugPrint(
				config,
				"recipe info",
				recipeInfo and "ok" or "nil",
				"learned", recipeInfo and tostring(recipeInfo.learned) or "nil",
				"disabled", recipeInfo and tostring(recipeInfo.disabled) or "nil"
			)
			if not recipeInfo or not recipeInfo.learned or recipeInfo.disabled then
				debugPrint(config, "stopping on recipe info gate")
				return
			end
		end

		local target = SmartRez:GetCraftRecipeTarget(config.key)
		if not target then
			debugPrint(config, "no craft target", "profession", requiredProfession and tostring(SmartRez:HasProfession(requiredProfession)) or "none")
			actionFrame:UnregisterAllEvents()
			return
		end

		debugPrint(config, "craft target", "casts", target.numCasts, "available", target.availableCasts, "defaultReagents", tostring(useDefaultReagents))

		if target.craftingReagents then
			for index, reagent in ipairs(target.craftingReagents) do
				debugPrint(
					config,
					"reagent",
					index,
					"slot", reagent.dataSlotIndex,
					"item", reagent.reagent and reagent.reagent.itemID or "nil",
					"currency", reagent.reagent and reagent.reagent.currencyID or "nil",
					"qty", reagent.quantity
				)
			end
		end

		if config.lockButton then
			actionFrame:RegisterEvents()
		else
			actionFrame:UnregisterAllEvents()
			actionFrame.unBlockButton = 0
		end

		local result = _C_CraftRecipe(
			recipeID,
			target.numCasts,
			target.craftingReagents,
			recipeLevel,
			orderID,
			applyConcentration
		)
		debugPrint(config, "craft call result", tostring(result))
		SmartRez:MarkCraftRecipeCacheDirty()

		if config.lockButton then
			castStartTime, castEndTime = select(4, _UnitCastingInfo("player"))
			debugPrint(config, "cast info", castStartTime or "nil", castEndTime or "nil")
			if castStartTime and castEndTime then
				actionFrame.unBlockButton = _GetTime() + ((castEndTime - castStartTime) / 1000)
			end
		end
	end)

	function actionFrame:RegisterEvents()
		self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
		self:RegisterEvent("UNIT_SPELLCAST_STOP")
		self:RegisterEvent("UNIT_SPELLCAST_FAILED")
		self:RegisterEvent("UNIT_SPELLCAST_FAILED_QUIET")
		self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
		self:SetScript("OnEvent", function(_, eventName, eventData)
			if eventData == "player" then
				debugPrint(config, "spell event", eventName)
				actionFrame.unBlockButton = _GetTime()
				SmartRez:MarkCraftRecipeCacheDirty()
				actionFrame:UnregisterAllEvents()
			end
		end)
	end

	SmartRez:RegisterBindableAction({
		key = config.key,
		label = config.label,
		buttonName = config.buttonName,
		order = config.order,
		requiredProfession = config.requiredProfession,
	})
	SmartRez:MarkCraftRecipeCacheDirty()

	return actionFrame
end
