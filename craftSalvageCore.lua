local SmartRez = _G.SmartRez

local _C_GetContainerItemInfo = C_Container.GetContainerItemInfo
local _C_SortBags = C_Container.SortBags
local _C_TradeSkillUI_CraftSalvage = C_TradeSkillUI.CraftSalvage
local _GetTime = GetTime
local _ItemLocation = ItemLocation
local _floor = math.floor
local _huge = math.huge

local SALVAGE_START_TIMEOUT_SECONDS = 1
local SALVAGE_ACTIVITY_TIMEOUT_SECONDS = 2
local SALVAGE_SORT_SETTLE_SECONDS = 1

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

local function isHigherBagSlotCandidate(bag, slot, existingBag, existingSlot)
	if bag ~= existingBag then
		return bag > existingBag
	end

	return slot > existingSlot
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

					if not shouldReplace and isHigherBagSlotCandidate(bag, slot, existingTarget.bag, existingTarget.slot) then
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

function SmartRez:GetBestCraftSalvageLiveTarget(professionKey)
	local selection = self:GetCraftSalvageSelection(professionKey)
	local professionConfig = self.craftSalvageProfessions[professionKey]
	if not selection or not professionConfig or not selection.recipeID or not selection.requiredStack or not self:HasProfession(professionConfig.professionID) then
		return nil
	end

	local reagentPlan = self:BuildCraftSalvageReagentPlan(professionKey, _huge)
	local hasRequiredReagents = #(selection.reagentSlots or {}) > 0
	local allowedTargets = self:GetCraftSalvageAllowedTargetItems(professionKey)
	local bestTarget = nil

	self:ForEachCraftingItemSourceSlot(function(bag, slot)
		local itemInfo = _C_GetContainerItemInfo(bag, slot)
		if not itemInfo or not allowedTargets[itemInfo.itemID] then
			return
		end

		local targetCasts = selection.requiredStack > 0 and _floor(itemInfo.stackCount / selection.requiredStack) or 0
		local availableCasts = reagentPlan and math.min(targetCasts, reagentPlan.maxCasts) or (hasRequiredReagents and 0 or targetCasts)
		if availableCasts <= 0 then
			return
		end

		local shouldReplace = bestTarget == nil
		if not shouldReplace and isHigherBagSlotCandidate(bag, slot, bestTarget.bag, bestTarget.slot) then
			shouldReplace = true
		end

		if shouldReplace then
			bestTarget = {
				bag = bag,
				slot = slot,
				itemInfo = itemInfo,
				availableCasts = availableCasts,
			}
		end
	end)

	return bestTarget
end

function SmartRez:GetCraftSalvageTarget(professionKey)
	if self.craftSalvageCacheDirty then
		self:RebuildCraftSalvageCache()
	end

	return self.craftSalvageCache[professionKey]
end

function SmartRez:RegisterCraftSalvageProfession(config)
	local itemLocation = _ItemLocation:CreateEmpty()
	local lastSortTime = 0
	local bagSortSettling = false
	local lastSalvageTargetItemID = nil

	self.craftSalvageProfessions[config.key] = config
	self.craftSalvageActionFrames = self.craftSalvageActionFrames or {}
	local actionController = self:CreateCraftActionController({
		key = config.key,
		label = config.label,
		debugPrefix = "SmartRez Salvage " .. config.key,
		startTimeoutSeconds = SALVAGE_START_TIMEOUT_SECONDS,
		activityTimeoutSeconds = SALVAGE_ACTIVITY_TIMEOUT_SECONDS,
		activityTimeoutReason = "salvage activity timeout",
		startTimeoutReason = "craft start timeout",
		markDirty = function()
			SmartRez:MarkCraftSalvageCacheDirty()
		end,
		registerEvents = function(controller)
			controller.frame:RegisterEvent("TRADE_SKILL_CRAFT_BEGIN")
			controller.frame:RegisterEvent("BAG_UPDATE_DELAYED")
			controller.frame:RegisterEvent("UNIT_SPELLCAST_FAILED")
			controller.frame:RegisterEvent("UNIT_SPELLCAST_FAILED_QUIET")
			controller.frame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
		end,
	})
	self.craftSalvageActionFrames[config.key] = actionController
	local actionFrame = actionController.frame

	local selection = self:GetCraftSalvageSelection(config.key)
	if selection and selection.sortBagsOnLoad and self:HasProfession(config.professionID) then
		_C_SortBags()
		self:MarkCraftSalvageCacheDirty()
	end

	self:CreateCraftActionButton(actionController, config.buttonName, function()
		if bagSortSettling and not actionController:IsBlocked() then
			bagSortSettling = false
		end

		if not SmartRez:HasProfession(config.professionID) then
			actionController:Debug("skip", "profession missing")
			return
		end

		local selection = SmartRez:GetCraftSalvageSelection(config.key)
		if not selection or not selection.recipeID then
			actionController:Debug("skip", "no salvage selection")
			return
		end

		local openTradeSkillID = selection.openTradeSkillID or config.professionID
		if not SmartRez:EnsureCraftProfessionOpen(actionController, openTradeSkillID) then
			return
		end

		SmartRez:OpenCraftRecipeByID(actionController, selection.recipeID)
		if SmartRez.RebuildInventoryCounts then
			SmartRez:RebuildInventoryCounts()
		end
		SmartRez:MarkCraftSalvageCacheDirty()
		SmartRez:RebuildCraftSalvageCache()

		local target = SmartRez:GetBestCraftSalvageLiveTarget(config.key)
		local currentTargetItemInfo = target and _C_GetContainerItemInfo(target.bag, target.slot) or nil
		if currentTargetItemInfo and currentTargetItemInfo.itemID == target.itemInfo.itemID and currentTargetItemInfo.stackCount >= selection.requiredStack then
			local maxTargetCasts = _floor(currentTargetItemInfo.stackCount / selection.requiredStack)
			local reagentPlan = SmartRez:BuildCraftSalvageReagentPlan(config.key, maxTargetCasts)
			local hasRequiredReagents = #(selection.reagentSlots or {}) > 0
			local casts = reagentPlan and reagentPlan.maxCasts or (hasRequiredReagents and 0 or maxTargetCasts)
			if casts > 0 then
				local inventorySources = SmartRez:GetInventorySources()
				local partialWarbankTarget = inventorySources.warbank == true
					and SmartRez.GetWarbankPartialStackTarget
					and SmartRez:GetWarbankPartialStackTarget(currentTargetItemInfo.itemID, selection.requiredStack)
					or nil
				if partialWarbankTarget then
					if SmartRez:GetFreeBagSlots() <= 0 then
						actionController:Debug("skip", "no free bag slots for partial warbank grab")
						return
					end

					actionController:Debug(
						"grabbing partial warbank stack",
						"item", partialWarbankTarget.itemID or "nil",
						"bag", partialWarbankTarget.bag or "nil",
						"slot", partialWarbankTarget.slot or "nil",
						"stack", partialWarbankTarget.stackCount or "nil"
					)
					if SmartRez.TryGrabWarbankTarget and SmartRez:TryGrabWarbankTarget(partialWarbankTarget) then
						SmartRez:MarkCraftSalvageCacheDirty()
						if SmartRez.RebuildInventoryCounts then
							SmartRez:RebuildInventoryCounts()
						end
						return
					end

					actionController:Debug("skip", "failed to grab partial warbank stack")
				end

				actionController:Debug(
					"salvage target",
					"item", currentTargetItemInfo.itemID or "nil",
					"bag", target.bag or "nil",
					"slot", target.slot or "nil",
					"stack", currentTargetItemInfo.stackCount or "nil",
					"requiredStack", selection.requiredStack or "nil",
					"casts", casts
				)
				lastSalvageTargetItemID = currentTargetItemInfo.itemID
				itemLocation:SetBagAndSlot(target.bag, target.slot)
				actionController:BeginPendingStart(selection.recipeID)
				_C_TradeSkillUI_CraftSalvage(selection.recipeID, casts, itemLocation, reagentPlan and reagentPlan.craftingReagents or nil)
				SmartRez:MarkCraftSalvageCacheDirty()
				return
			end
			actionController:Debug("skip", "no salvage casts after reagent plan")
		elseif selection.sortBagsWhenEmpty and (_GetTime() - lastSortTime) >= 10 then
			actionController:Debug("sorting bags", "empty target state")
			_C_SortBags()
			lastSortTime = _GetTime()
			SmartRez:MarkCraftSalvageCacheDirty()
		else
			actionController:Debug(
				"skip",
				"no valid salvage target",
				"target", currentTargetItemInfo and (currentTargetItemInfo.itemID or "present") or (target and (target.itemInfo.itemID or "present") or "nil"),
				"stack", currentTargetItemInfo and currentTargetItemInfo.stackCount or "nil",
				"requiredStack", selection.requiredStack or "nil"
			)
		end
	end)

	actionFrame:SetScript("OnEvent", function(_, eventName, ...)
		if eventName == "TRADE_SKILL_CRAFT_BEGIN" then
			actionController:HandleTradeSkillCraftBegin(..., "salvage activity", SALVAGE_ACTIVITY_TIMEOUT_SECONDS)
			return
		end

		if eventName == "BAG_UPDATE_DELAYED" then
			if actionController:HandleBagUpdateWhileWaitingForSpace() then
				return
			end
		end

		if eventName == "UNIT_SPELLCAST_FAILED" or eventName == "UNIT_SPELLCAST_FAILED_QUIET" then
			local unitToken, _, spellID = ...
			actionController:HandleUnitSpellcastFailed(unitToken, spellID, "spell failed")
			return
		end

		if eventName == "UNIT_SPELLCAST_INTERRUPTED" then
			local unitToken, _, spellID = ...
			local selection = SmartRez:GetCraftSalvageSelection(config.key)
			if unitToken ~= "player" or not selection or spellID ~= selection.recipeID then
				return
			end

			if not actionController:IsBlocked() then
				return
			end

			actionController:Debug("spell event", eventName, unitToken, spellID or "nil")
			actionController:Unlock("spell interrupted")
			if bagSortSettling then
				return
			end

			if not lastSalvageTargetItemID then
				return
			end

			if not SmartRez.StartPlayerBagItemRestack or not SmartRez:StartPlayerBagItemRestack(lastSalvageTargetItemID) then
				return
			end

			bagSortSettling = true
			actionController:Debug("restacking item", lastSalvageTargetItemID, "after spell interrupted")
			if SmartRez.RebuildInventoryCounts then
				SmartRez:RebuildInventoryCounts()
			end
			SmartRez:MarkCraftSalvageCacheDirty()
			actionController:BeginExternalWait(SALVAGE_SORT_SETTLE_SECONDS, "bag restack settle", "bag restack settle timeout")
			actionFrame:RegisterEvent("BAG_UPDATE_DELAYED")
			return
		end

		if eventName == "BAG_UPDATE_DELAYED" and bagSortSettling then
			if SmartRez.RebuildInventoryCounts then
				SmartRez:RebuildInventoryCounts()
			end
			SmartRez:MarkCraftSalvageCacheDirty()
			if SmartRez:IsPlayerBagItemRestackActive(lastSalvageTargetItemID) then
				actionController:SetTimeoutSilently(SALVAGE_SORT_SETTLE_SECONDS)
				return
			end

			bagSortSettling = false
			if SmartRez:GetFreeBagSlots() <= 0 then
				actionController:BeginBagSpaceWait(nil, "waiting for bag space")
				return
			end

			actionController:Unlock("bag restack settled")
			return
		end

		if not actionController:IsBlocked() and bagSortSettling then
			bagSortSettling = false
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

function SmartRez:IsCraftSalvageActionBlocked(key)
	local actionController = self.craftSalvageActionFrames and self.craftSalvageActionFrames[key]
	if not actionController or not actionController.IsBlocked then
		return false
	end

	return actionController:IsBlocked()
end
