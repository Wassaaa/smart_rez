local SmartRez = _G.SmartRez

local _C_CraftRecipe = C_TradeSkillUI.CraftRecipe
local _C_GetRecipeInfo = C_TradeSkillUI.GetRecipeInfo
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
	if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
		local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(currencyID)
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
		return SmartRez:GetCraftingSpendableItemCount(reagent.itemID)
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
			local maxCrafts = getMaxCraftsFromReagents(reagents)
			local numCasts = maxCrafts
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
	if config.lockButton == nil then
		config.lockButton = true
	end

	self.craftRecipeActions[config.key] = config
	local actionController = self:CreateCraftActionController({
		key = config.key,
		label = config.label,
		debugPrefix = "Smart Rez: " .. config.label,
		debugEnabled = function()
			return resolveConfigValue(config, "debug") == true or (SmartRez.GetDebugEnabled and SmartRez:GetDebugEnabled() == true)
		end,
		startTimeoutSeconds = 1,
		activityTimeoutSeconds = 2,
		activityReason = "craft in progress",
		activityTimeoutReason = "craft in progress timeout",
		startTimeoutReason = "craft start timeout",
		markDirty = function()
			SmartRez:MarkCraftRecipeCacheDirty()
		end,
		registerEvents = function(controller)
			controller.frame:RegisterEvent("TRADE_SKILL_CRAFT_BEGIN")
			controller.frame:RegisterEvent("UPDATE_TRADESKILL_CAST_STOPPED")
			controller.frame:RegisterEvent("BAG_UPDATE_DELAYED")
			controller.frame:RegisterEvent("UNIT_SPELLCAST_START")
			controller.frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
			controller.frame:RegisterEvent("UNIT_SPELLCAST_STOP")
			controller.frame:RegisterEvent("UNIT_SPELLCAST_FAILED")
			controller.frame:RegisterEvent("UNIT_SPELLCAST_FAILED_QUIET")
			controller.frame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
		end,
	})
	local actionFrame = actionController.frame
	self.craftRecipeActionFrames[config.key] = actionController
	self:CreateCraftActionButton(actionController, config.buttonName, function()
		local recipeID = resolveConfigValue(config, "recipeID")
		local openTradeSkillID = resolveConfigValue(config, "openTradeSkillID")
		local recipeLevel = resolveConfigValue(config, "recipeLevel")
		local orderID = resolveConfigValue(config, "orderID")
		local applyConcentration = resolveConfigValue(config, "applyConcentration")
		local requiredProfession = resolveConfigValue(config, "requiredProfession")
		local requireProfessionOpen = resolveConfigValue(config, "requireProfessionOpen") ~= false
		local useDefaultReagents = resolveConfigValue(config, "useDefaultReagents")

		if requireProfessionOpen and not SmartRez:EnsureCraftProfessionOpen(actionController, openTradeSkillID) then
			return
		end

		if requireProfessionOpen then
			SmartRez:OpenCraftRecipeByID(actionController, recipeID)
		end

		actionController.expectedSpellID = recipeID

		if _C_GetRecipeInfo then
			local recipeInfo = _C_GetRecipeInfo(recipeID)
			debugPrint(
				config,
				"recipe info",
				recipeInfo and "ok" or "nil",
				"learned", recipeInfo and tostring(recipeInfo.learned) or "nil",
				"disabled", recipeInfo and tostring(recipeInfo.disabled) or "nil"
			)
			if recipeInfo and (not recipeInfo.learned or recipeInfo.disabled) then
				debugPrint(config, "stopping on recipe info gate")
				return
			elseif not recipeInfo and requireProfessionOpen then
				debugPrint(config, "stopping on missing recipe info")
				return
			end
		end

		local target = SmartRez:GetCraftRecipeTarget(config.key)
		if not target then
			debugPrint(config, "no craft target", "profession", requiredProfession and tostring(SmartRez:HasProfession(requiredProfession)) or "none")
			actionController:Debug("unlock request", "no craft target", actionController:GetLockState())
			actionController:Unlock("no craft target")
			return
		end

		debugPrint(config, "craft target", "casts", target.numCasts, "available", target.availableCasts, "defaultReagents", tostring(useDefaultReagents), "requireProfessionOpen", tostring(requireProfessionOpen))

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
			actionController:BeginPendingStart(actionController.expectedSpellID)
		else
			actionController:Debug("unlock request", "lock disabled", actionController:GetLockState())
			actionController:Unlock("lock disabled")
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

		if config.lockButton and result == false then
			actionController:Debug("unlock request", "craft call failed", actionController:GetLockState())
			actionController:Unlock("craft call failed")
		end
	end)

	actionFrame:SetScript("OnEvent", function(_, eventName, ...)
		actionController:HandleCraftEvent(eventName, ...)
	end)

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

function SmartRez:IsCraftRecipeActionBlocked(key)
	local actionController = self.craftRecipeActionFrames and self.craftRecipeActionFrames[key]
	if not actionController or not actionController.IsBlocked then
		return false
	end

	return actionController:IsBlocked()
end
