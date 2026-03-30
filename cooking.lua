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
