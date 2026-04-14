local SmartRez = _G.SmartRez
local _floor = math.floor

local function getShardCraftConfigValue(key)
	return SmartRez:GetRecipeCraftConfig("shardcraft")[key]
end

local function getShardCraftBagLimitedCasts()
	local freeSlotsToSpend = SmartRez:GetFreeBagSlots() - SmartRez:GetGoldPrinterMinFreeSlots()
	if freeSlotsToSpend <= 0 then
		return 0
	end

	-- Treat each possible output item as consuming one free slot. This is conservative,
	-- but it keeps Gold Printer from overfilling bags when the craft is spammed.
	local outputQuantityMax = tonumber(getShardCraftConfigValue("outputQuantityMax")) or 1
	local outputPerCraft = math.max(1, outputQuantityMax)
	return _floor(freeSlotsToSpend / outputPerCraft)
end

SmartRez:RegisterCraftRecipeAction({
	key = "shardcraft",
	label = "Shard Craft",
	buttonName = "ShardCraftBtn",
	order = 60,
	requiredProfession = function()
		return getShardCraftConfigValue("requiredProfession")
	end,
	recipeID = function()
		return getShardCraftConfigValue("recipeID")
	end,
	openTradeSkillID = function()
		return getShardCraftConfigValue("openTradeSkillID")
	end,
	useDefaultReagents = function()
		return getShardCraftConfigValue("useDefaultReagents")
	end,
	debug = function()
		return getShardCraftConfigValue("debug")
	end,
	maxCasts = function()
		return getShardCraftBagLimitedCasts()
	end,
	reagents = function()
		return getShardCraftConfigValue("reagents")
	end,
})
