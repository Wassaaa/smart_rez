local SmartRez = _G.SmartRez

local _C_GetContainerNumSlots = _G["C_Container"]["GetContainerNumSlots"]
local _C_GetContainerItemInfo = _G["C_Container"]["GetContainerItemInfo"]
local _C_SortBags = _G["C_Container"]["SortBags"]
local _C_TradeSkillUI_CraftSalvage = _G["C_TradeSkillUI"]["CraftSalvage"]
local _GetTime = _G["GetTime"]
local _ItemLocation = _G["ItemLocation"]
local _UnitCastingInfo = _G["UnitCastingInfo"]

function SmartRez:RebuildCraftSalvageCache()
	local cache = {}

	for key in pairs(self.craftSalvageActions) do
		cache[key] = nil
	end

	for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		for slot = 1, _C_GetContainerNumSlots(bag) do
			local itemInfo = _C_GetContainerItemInfo(bag, slot)
			if itemInfo then
				for key, config in pairs(self.craftSalvageActions) do
					if config.itemIDs[itemInfo.itemID] and itemInfo.stackCount >= config.requiredStack then
						local existingTarget = cache[key]
						local shouldReplace = existingTarget == nil

						if not shouldReplace and config.preferLargestStack and itemInfo.stackCount > existingTarget.itemInfo.stackCount then
							shouldReplace = true
						end

						if shouldReplace then
							cache[key] = {
								bag = bag,
								slot = slot,
								itemInfo = itemInfo,
							}
						end
					end
				end
			end
		end
	end

	self.craftSalvageCache = cache
	self.craftSalvageCacheDirty = false
end

function SmartRez:GetCraftSalvageTarget(key)
	if self.craftSalvageCacheDirty then
		self:RebuildCraftSalvageCache()
	end

	return self.craftSalvageCache[key]
end

function SmartRez:RegisterCraftSalvageAction(config)
	local itemLocation = _ItemLocation:CreateEmpty()
	local actionFrame = CreateFrame("Frame")
	local castStartTime, castEndTime = nil, nil
	local lastSortTime = 0

	config.requiredStack = config.requiredStack or 1
	if config.lockButton == nil then
		config.lockButton = true
	end
	self.craftSalvageActions[config.key] = config
	actionFrame.unBlockButton = 0
	actionFrame.btn = CreateFrame("Button", config.buttonName, UIParent, "SecureActionButtonTemplate")
	actionFrame.btn:RegisterForClicks("AnyUp", "AnyDown")

	if config.sortBagsOnLoad then
		_C_SortBags()
		self:MarkCraftSalvageCacheDirty()
	end

	actionFrame.btn:SetScript("OnClick", function()
		if actionFrame.unBlockButton > _GetTime() then
			return
		end

		local target = SmartRez:GetCraftSalvageTarget(config.key)
		if target then
			local casts = config.castCount and config.castCount(target.itemInfo) or 1
			itemLocation:SetBagAndSlot(target.bag, target.slot)
			if config.lockButton then
				actionFrame:RegisterEvents()
			else
				actionFrame:UnregisterAllEvents()
				actionFrame.unBlockButton = 0
			end
			_C_TradeSkillUI_CraftSalvage(config.recipeID, casts, itemLocation)
			SmartRez:MarkCraftSalvageCacheDirty()
			if config.lockButton then
				castStartTime, castEndTime = select(4, _UnitCastingInfo("player"))
				if castStartTime and castEndTime then
					actionFrame.unBlockButton = _GetTime() + ((castEndTime - castStartTime) / 1000)
				end
			end
		else
			actionFrame:UnregisterAllEvents()
			if config.sortBagsWhenEmpty and (_GetTime() - lastSortTime) >= 10 then
				_C_SortBags()
				lastSortTime = _GetTime()
				SmartRez:MarkCraftSalvageCacheDirty()
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
				actionFrame.unBlockButton = _GetTime()
				SmartRez:MarkCraftSalvageCacheDirty()
				actionFrame:UnregisterAllEvents()
			end
		end)
	end

	SmartRez:RegisterBindableAction({
		key = config.key,
		label = config.label,
		buttonName = config.buttonName,
		order = config.order,
	})
	SmartRez:MarkCraftSalvageCacheDirty()

	return actionFrame
end
