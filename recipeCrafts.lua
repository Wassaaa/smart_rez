local SmartRez = _G.SmartRez

local function getShardCraftConfigValue(key)
	return SmartRez:GetRecipeCraftConfig("shardcraft")[key]
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
	reagents = function()
		return getShardCraftConfigValue("reagents")
	end,
})
