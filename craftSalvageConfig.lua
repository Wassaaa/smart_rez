local SmartRez = _G.SmartRez

local _C_GetContainerNumSlots = _G["C_Container"]["GetContainerNumSlots"]
local _C_GetContainerItemInfo = _G["C_Container"]["GetContainerItemInfo"]

-- Keep salvage whitelists character-scoped since inventory and professions differ per alt.
function SmartRez:GetCraftSalvageWhitelist(actionKey)
	self:EnsureConfig()
	return self.db.char.salvageWhitelists[actionKey]
end

function SmartRez:AddCraftSalvageWhitelistItem(actionKey, itemID)
	if not actionKey or not itemID or not self.craftSalvageActions[actionKey] then
		return
	end

	self:EnsureConfig()

	if type(self.db.char.salvageWhitelists[actionKey]) ~= "table" then
		self.db.char.salvageWhitelists[actionKey] = {}
	end

	self.db.char.salvageWhitelists[actionKey][itemID] = true
	self:MarkCraftSalvageCacheDirty()
	self:RefreshViews()
end

function SmartRez:RemoveCraftSalvageWhitelistItem(actionKey, itemID)
	local whitelist = self:GetCraftSalvageWhitelist(actionKey)
	if not whitelist then
		return
	end

	whitelist[itemID] = nil
	self:MarkCraftSalvageCacheDirty()
	self:RefreshViews()
end

function SmartRez:GetCraftSalvageAction(actionKey)
	return self.craftSalvageActions[actionKey]
end

function SmartRez:GetCraftSalvageActions()
	local actions = {}

	for _, action in pairs(self.craftSalvageActions) do
		table.insert(actions, action)
	end

	table.sort(actions, function(left, right)
		if left.order == right.order then
			return tostring(left.label) < tostring(right.label)
		end

		return (left.order or 0) < (right.order or 0)
	end)

	return actions
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
