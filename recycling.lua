local SmartRez = _G.SmartRez

SmartRez:RegisterCraftSalvageAction({
  key = "recycling",
  label = "recycling",
  buttonName = "recyclingBtn",
  order = 60,
  recipeID = 1229930,
  requiredStack = 5,
  itemIDs = {
    [239702] = true, -- Imbued Bright Linen Bolt r2
    [245807] = true, -- Pigment r2
  },
  sortBagsOnLoad = true,
  sortBagsWhenEmpty = true,
})
