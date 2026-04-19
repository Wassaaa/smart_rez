local SmartRez = _G.SmartRez

local _C_GetContainerItemInfo = C_Container.GetContainerItemInfo
local _C_SortBags = C_Container.SortBags
local _C_TradeSkillUI_CraftSalvage = C_TradeSkillUI.CraftSalvage
local _C_GetBaseProfessionInfo = C_TradeSkillUI.GetBaseProfessionInfo
local _C_OpenTradeSkill = C_TradeSkillUI.OpenTradeSkill
local _C_OpenRecipe = C_TradeSkillUI.OpenRecipe
local _GetTime = GetTime
local _ItemLocation = ItemLocation
local _floor = math.floor
local _huge = math.huge

local function buildCraftingReagents(reagents, numCasts)
	local craftingReagents = {}

	for index, reagent in ipairs(reagents or {}) do
		craftingReagents[index] = {
			reagent = {
				itemID = reagent.itemID,
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

function SmartRez:BuildCraftSalvageReagentPlan(professionKey, maxCasts)
	local selection = self:GetCraftSalvageSelection(professionKey)
	local reagentPlan = {
		reagents = {},
		maxCasts = maxCasts or _huge,
	}

	for _, reagentSlot in ipairs(selection and selection.reagentSlots or {}) do
		local allowedItems = self:GetCraftSalvageAllowedReagentItems(professionKey, reagentSlot.dataSlotIndex)
		local bestItemID, bestPossibleCasts = nil, 0

		for _, itemID in ipairs(reagentSlot.allowedItemIDs or {}) do
			if allowedItems[itemID] then
				local itemCount = self:GetCraftingItemCount(itemID)
				local possibleCasts = reagentSlot.quantityRequired > 0 and _floor(itemCount / reagentSlot.quantityRequired) or 0

				if possibleCasts > bestPossibleCasts then
					bestItemID = itemID
					bestPossibleCasts = possibleCasts
				end
			end
		end

		if not bestItemID or bestPossibleCasts <= 0 then
			return nil
		end

		reagentPlan.maxCasts = math.min(reagentPlan.maxCasts, bestPossibleCasts)
		reagentPlan.reagents[#reagentPlan.reagents + 1] = {
			itemID = bestItemID,
			dataSlotIndex = reagentSlot.dataSlotIndex,
			quantity = reagentSlot.quantityRequired,
		}
	end

	if reagentPlan.maxCasts == _huge then
		reagentPlan.maxCasts = maxCasts or 0
	end

	reagentPlan.craftingReagents = buildCraftingReagents(reagentPlan.reagents, reagentPlan.maxCasts)
	return reagentPlan
end

function SmartRez:RebuildCraftSalvageCache()
	local cache = {}
	local activeProfessions = {}

	for professionKey, professionConfig in pairs(self.craftSalvageProfessions) do
		local selection = self:GetCraftSalvageSelection(professionKey)
		if selection and selection.recipeID and selection.requiredStack and self:HasProfession(professionConfig.professionID) then
			local reagentPlan = self:BuildCraftSalvageReagentPlan(professionKey, _huge)
			activeProfessions[professionKey] = {
				selection = selection,
				allowedTargets = self:GetCraftSalvageAllowedTargetItems(professionKey),
				reagentPlan = reagentPlan,
			}
		end
	end

	self:ForEachCraftingItemSourceSlot(function(bag, slot)
		local itemInfo = _C_GetContainerItemInfo(bag, slot)
		if itemInfo then
			for professionKey, professionState in pairs(activeProfessions) do
				local selection = professionState.selection
				local reagentPlan = professionState.reagentPlan
				local hasRequiredReagents = #(selection.reagentSlots or {}) > 0
				local targetCasts = selection.requiredStack > 0 and _floor(itemInfo.stackCount / selection.requiredStack) or 0
				local availableCasts = reagentPlan and math.min(targetCasts, reagentPlan.maxCasts) or (hasRequiredReagents and 0 or targetCasts)

				if professionState.allowedTargets[itemInfo.itemID] and availableCasts > 0 then
					local existingTarget = cache[professionKey]
					local shouldReplace = existingTarget == nil

					if not shouldReplace and selection.preferLargestStack and itemInfo.stackCount > existingTarget.itemInfo.stackCount then
						shouldReplace = true
					end

					if shouldReplace then
						cache[professionKey] = {
							bag = bag,
							slot = slot,
							itemInfo = itemInfo,
							availableCasts = availableCasts,
						}
					end
				end
			end
		end
	end)

	self.craftSalvageCache = cache
	self.craftSalvageCacheDirty = false
end

function SmartRez:GetCraftSalvageTarget(professionKey)
	if self.craftSalvageCacheDirty then
		self:RebuildCraftSalvageCache()
	end

	return self.craftSalvageCache[professionKey]
end

function SmartRez:RegisterCraftSalvageProfession(config)
	local itemLocation = _ItemLocation:CreateEmpty()
	local actionFrame = CreateFrame("Frame")
	local lastSortTime = 0

	self.craftSalvageProfessions[config.key] = config
	actionFrame.btn = CreateFrame("Button", config.buttonName, UIParent, "SecureActionButtonTemplate")
	actionFrame.btn:RegisterForClicks("AnyUp", "AnyDown")

	local selection = self:GetCraftSalvageSelection(config.key)
	if selection and selection.sortBagsOnLoad and self:HasProfession(config.professionID) then
		_C_SortBags()
		self:MarkCraftSalvageCacheDirty()
	end

	actionFrame.btn:SetScript("OnClick", function()
		if not SmartRez:HasProfession(config.professionID) then
			return
		end

		local selection = SmartRez:GetCraftSalvageSelection(config.key)
		if not selection or not selection.recipeID then
			return
		end

		local openTradeSkillID = selection.openTradeSkillID or config.professionID
		if openTradeSkillID then
			local professionInfo = _C_GetBaseProfessionInfo and _C_GetBaseProfessionInfo()
			if not professionInfo or professionInfo.professionID ~= openTradeSkillID then
				_C_OpenTradeSkill(openTradeSkillID)
				return
			end
		end

		if _C_OpenRecipe then
			_C_OpenRecipe(selection.recipeID)
		end

		local target = SmartRez:GetCraftSalvageTarget(config.key)
		if target and target.itemInfo.stackCount >= selection.requiredStack then
			local maxTargetCasts = _floor(target.itemInfo.stackCount / selection.requiredStack)
			local reagentPlan = SmartRez:BuildCraftSalvageReagentPlan(config.key, maxTargetCasts)
			local hasRequiredReagents = #(selection.reagentSlots or {}) > 0
			local casts = reagentPlan and reagentPlan.maxCasts or (hasRequiredReagents and 0 or maxTargetCasts)
			if casts > 0 then
				itemLocation:SetBagAndSlot(target.bag, target.slot)
				_C_TradeSkillUI_CraftSalvage(selection.recipeID, casts, itemLocation, reagentPlan and reagentPlan.craftingReagents or nil)
				SmartRez:MarkCraftSalvageCacheDirty()
			end
		elseif selection.sortBagsWhenEmpty and (_GetTime() - lastSortTime) >= 10 then
			_C_SortBags()
			lastSortTime = _GetTime()
			SmartRez:MarkCraftSalvageCacheDirty()
		end
	end)

	SmartRez:RegisterBindableAction({
		key = config.key,
		label = config.label,
		buttonName = config.buttonName,
		order = config.order,
		requiredProfession = config.professionID,
	})
	SmartRez:MarkCraftSalvageCacheDirty()

	return actionFrame
end
