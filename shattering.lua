local SmartRez = _G.SmartRez

SmartRez:RegisterCraftSalvageAction({
  key = "shattering",
  label = "Shattering",
  buttonName = "ShatterBtn",
  order = 50,
  recipeID = 1280394,
  requiredStack = 1,
  lockButton = false,
  preferLargestStack = true,
  castCount = function(itemInfo)
    return itemInfo.stackCount
  end,
  itemIDs = {
    [243602] = true,
    [243603] = true,
  },
})
