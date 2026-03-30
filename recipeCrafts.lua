local SmartRez = _G.SmartRez

local PROF_ENGINEERING = SmartRez.Profession.Engineering

local RECIPE_SHARD_CRAFT = 1229869
local ITEM_SHARD_CRAFT_REAGENT = 243582

SmartRez:RegisterCraftRecipeAction({
  key = "shardcraft",
  label = "Shard Craft",
  buttonName = "ShardCraftBtn",
  order = 60,
  requiredProfession = PROF_ENGINEERING,
  recipeID = RECIPE_SHARD_CRAFT,
  openTradeSkillID = PROF_ENGINEERING,
  useDefaultReagents = true,
  debug = true,
  reagents = {
    { itemID = ITEM_SHARD_CRAFT_REAGENT, quantity = 1, dataSlotIndex = 1 },
  },
})
