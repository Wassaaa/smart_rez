local SmartRez = _G.SmartRez

SmartRez:RegisterCraftSalvageAction({
  key = "cooking",
  label = "Cooking",
  buttonName = "CookingBtn",
  order = 20,
  recipeID = 445118,
  requiredStack = 5,
})

SmartRez:RegisterCraftSalvageAction({
  key = "prospecting",
  label = "Prospecting",
  buttonName = "ProspectingBtn",
  order = 30,
  recipeID = 434018,
  requiredStack = 5,
})

SmartRez:RegisterCraftSalvageAction({
  key = "thaumaturgy",
  label = "Thaumaturgy",
  buttonName = "ThaumaturgyBtn",
  order = 40,
  recipeID = 430315,
  requiredStack = 20,
  sortBagsOnLoad = true,
  sortBagsWhenEmpty = true,
})

SmartRez:RegisterCraftSalvageAction({
  key = "shattering",
  label = "Shattering",
  buttonName = "ShatterBtn",
  order = 50,
  recipeID = 1280394,
  requiredStack = 1,
  preferLargestStack = true,
})

SmartRez:RegisterCraftSalvageAction({
  key = "recycling",
  label = "Recycling",
  buttonName = "RecyclingBtn",
  order = 60,
  recipeID = 1229930,
  requiredStack = 5,
  sortBagsOnLoad = true,
  sortBagsWhenEmpty = true,
})

SmartRez:RegisterCraftSalvageAction({
  key = "milling",
  label = "Milling",
  buttonName = "MillingBtn",
  order = 70,
  recipeID = 1269575,
  requiredStack = 10,
  preferLargestStack = true,
  sortBagsOnLoad = true,
  sortBagsWhenEmpty = true,
})
