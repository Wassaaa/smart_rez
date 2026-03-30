local SmartRez = _G.SmartRez

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
