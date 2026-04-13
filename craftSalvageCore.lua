local SmartRez = _G.SmartRez

local _C_GetContainerNumSlots = _G["C_Container"]["GetContainerNumSlots"]
local _C_GetContainerItemInfo = _G["C_Container"]["GetContainerItemInfo"]
local _C_SortBags = _G["C_Container"]["SortBags"]
local _C_TradeSkillUI_CraftSalvage = _G["C_TradeSkillUI"]["CraftSalvage"]
local _GetTime = _G["GetTime"]
local _ItemLocation = _G["ItemLocation"]

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
	local lastSortTime = 0

	config.requiredStack = config.requiredStack or 1
	self.craftSalvageActions[config.key] = config
	actionFrame.btn = CreateFrame("Button", config.buttonName, UIParent, "SecureActionButtonTemplate")
	actionFrame.btn:RegisterForClicks("AnyUp", "AnyDown")

	if config.sortBagsOnLoad then
		_C_SortBags()
		self:MarkCraftSalvageCacheDirty()
	end

	actionFrame.btn:SetScript("OnClick", function()
		local target = SmartRez:GetCraftSalvageTarget(config.key)
		if target then
			local casts = math.floor(target.itemInfo.stackCount / config.requiredStack)
			itemLocation:SetBagAndSlot(target.bag, target.slot)
			_C_TradeSkillUI_CraftSalvage(config.recipeID, casts, itemLocation)
			SmartRez:MarkCraftSalvageCacheDirty()
		else
			if config.sortBagsWhenEmpty and (_GetTime() - lastSortTime) >= 10 then
				_C_SortBags()
				lastSortTime = _GetTime()
				SmartRez:MarkCraftSalvageCacheDirty()
			end
		end
	end)

	SmartRez:RegisterBindableAction({
		key = config.key,
		label = config.label,
		buttonName = config.buttonName,
		order = config.order,
	})
	SmartRez:MarkCraftSalvageCacheDirty()

	return actionFrame
end
