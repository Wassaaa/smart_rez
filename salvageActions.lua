local SmartRez = _G.SmartRez

SmartRez:RegisterCraftSalvageAction({
  key = "cooking",
  label = "Cooking",
  buttonName = "CookingBtn",
  order = 20,
  recipeID = 445118,
  requiredStack = 5,
  itemIDs = {
    [223512] = true, -- Beef
    [225911] = true, -- Bee
  },
})

SmartRez:RegisterCraftSalvageAction({
  key = "prospecting",
  label = "Prospecting",
  buttonName = "ProspectingBtn",
  order = 30,
  recipeID = 434018,
  requiredStack = 5,
  itemIDs = {
    [210934] = true, -- Aqirite r2
    [210933] = true, -- Aqirite r1
  },
})

SmartRez:RegisterCraftSalvageAction({
  key = "thaumaturgy",
  label = "Thaumaturgy",
  buttonName = "ThaumaturgyBtn",
  order = 40,
  recipeID = 430315,
  requiredStack = 20,
  itemIDs = {
    [210796] = true, -- Mycobloom r1
    [210797] = true, -- Mycobloom r2
    [211802] = true, -- Ominous Transmutagen
    [211804] = true, -- Volatile Transmutagen
    [211803] = true, -- Mercurial Transmutagen
    [212667] = true, -- Gloom Chitin r1
    [212668] = true, -- Gloom Chitin r2
    [212665] = true, -- Leather r2
    [210937] = true, -- Ironclaw r2
    [210806] = true, -- Blossom r2
  },
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
  itemIDs = {
    [243602] = true,
    [243603] = true,
  },
})

SmartRez:RegisterCraftSalvageAction({
  key = "recycling",
  label = "Recycling",
  buttonName = "RecyclingBtn",
  order = 60,
  recipeID = 1229930,
  requiredStack = 5,
  itemIDs = {
    [239702] = true, -- Imbued Bright Linen Bolt r1
    [245807] = true, -- Powder Pigment r1
  },
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
  itemIDs = {
    [236761] = true, -- Tranquility Bloom r1
  },
  sortBagsOnLoad = true,
  sortBagsWhenEmpty = true,
})
