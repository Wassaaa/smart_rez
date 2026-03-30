local SmartRez = _G.SmartRez

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
