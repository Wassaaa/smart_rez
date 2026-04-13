local SmartRez = _G.SmartRez
local Profession = SmartRez.Profession

-- Recipes stay code-defined, while each profession keeps a saved selected recipe.
SmartRez:RegisterCraftSalvageRecipe({
	key = "thalassian_filet",
	label = "Thalassian Filet",
	professionKey = "cooking",
	order = 20,
	recipeID = 1259655,
	requiredStack = 5,
})

SmartRez:RegisterCraftSalvageRecipe({
	key = "prospecting",
	label = "Prospecting",
	professionKey = "jewelcrafting",
	order = 30,
	recipeID = 434018,
	requiredStack = 5,
})

SmartRez:RegisterCraftSalvageRecipe({
	key = "thaumaturgy",
	label = "Thaumaturgy",
	professionKey = "alchemy",
	order = 40,
	recipeID = 430315,
	requiredStack = 20,
	sortBagsOnLoad = true,
	sortBagsWhenEmpty = true,
})

SmartRez:RegisterCraftSalvageRecipe({
	key = "shattering",
	label = "Shattering",
	professionKey = "enchanting",
	order = 50,
	recipeID = 1280394,
	requiredStack = 1,
	preferLargestStack = true,
})

SmartRez:RegisterCraftSalvageRecipe({
	key = "recycling",
	label = "Recycling",
	professionKey = "engineering",
	order = 60,
	recipeID = 1229930,
	requiredStack = 5,
	sortBagsOnLoad = true,
	sortBagsWhenEmpty = true,
})

SmartRez:RegisterCraftSalvageRecipe({
	key = "milling",
	label = "Milling",
	professionKey = "inscription",
	order = 70,
	recipeID = 1269575,
	requiredStack = 10,
	preferLargestStack = true,
	sortBagsOnLoad = true,
	sortBagsWhenEmpty = true,
})

-- Profession binds and tabs use these stable keys, regardless of the selected recipe.
SmartRez:RegisterCraftSalvageProfession({
	key = "cooking",
	label = "Cooking",
	buttonName = "CookingBtn",
	order = 20,
	professionID = Profession.Cooking,
	defaultRecipeKey = "thalassian_filet",
})

SmartRez:RegisterCraftSalvageProfession({
	key = "jewelcrafting",
	label = "Jewelcrafting",
	buttonName = "ProspectingBtn",
	order = 30,
	professionID = Profession.Jewelcrafting,
	defaultRecipeKey = "prospecting",
})

SmartRez:RegisterCraftSalvageProfession({
	key = "alchemy",
	label = "Alchemy",
	buttonName = "ThaumaturgyBtn",
	order = 40,
	professionID = Profession.Alchemy,
	defaultRecipeKey = "thaumaturgy",
})

SmartRez:RegisterCraftSalvageProfession({
	key = "enchanting",
	label = "Enchanting",
	buttonName = "ShatterBtn",
	order = 50,
	professionID = Profession.Enchanting,
	defaultRecipeKey = "shattering",
})

SmartRez:RegisterCraftSalvageProfession({
	key = "engineering",
	label = "Engineering",
	buttonName = "RecyclingBtn",
	order = 60,
	professionID = Profession.Engineering,
	defaultRecipeKey = "recycling",
})

SmartRez:RegisterCraftSalvageProfession({
	key = "inscription",
	label = "Inscription",
	buttonName = "MillingBtn",
	order = 70,
	professionID = Profession.Inscription,
	defaultRecipeKey = "milling",
})
