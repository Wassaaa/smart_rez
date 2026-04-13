local SmartRez = _G.SmartRez

local _C_GetContainerNumSlots = _G["C_Container"]["GetContainerNumSlots"]
local _C_GetContainerItemInfo = _G["C_Container"]["GetContainerItemInfo"]
local _C_SortBags = _G["C_Container"]["SortBags"]
local _C_TradeSkillUI_CraftSalvage = _G["C_TradeSkillUI"]["CraftSalvage"]
local _GetTime = _G["GetTime"]
local _ItemLocation = _G["ItemLocation"]

function SmartRez:RebuildCraftSalvageCache()
	local cache = {}
	local activeProfessions = {}

	for professionKey, professionConfig in pairs(self.craftSalvageProfessions) do
		local selection = self:GetCraftSalvageSelection(professionKey)
		if selection and selection.recipeID and selection.requiredStack and self:HasProfession(professionConfig.professionID) then
			activeProfessions[professionKey] = {
				selection = selection,
				whitelist = self:GetCraftSalvageWhitelist(professionKey),
			}
		end
	end

	for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		for slot = 1, _C_GetContainerNumSlots(bag) do
			local itemInfo = _C_GetContainerItemInfo(bag, slot)
			if itemInfo then
				for professionKey, professionState in pairs(activeProfessions) do
					local selection = professionState.selection
					local whitelist = professionState.whitelist

					if whitelist[itemInfo.itemID] and itemInfo.stackCount >= selection.requiredStack then
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

		local target = SmartRez:GetCraftSalvageTarget(config.key)
		if target then
			local casts = math.floor(target.itemInfo.stackCount / selection.requiredStack)
			if casts > 0 then
				itemLocation:SetBagAndSlot(target.bag, target.slot)
				_C_TradeSkillUI_CraftSalvage(selection.recipeID, casts, itemLocation)
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
