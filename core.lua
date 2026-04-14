_G.SmartRez = LibStub("AceAddon-3.0"):NewAddon("SmartRez", "AceConsole-3.0", "AceEvent-3.0")
_G.SmartRez.appName = "Smart Rez"
_G.SmartRez.bindableActions = {}
_G.SmartRez.craftSalvageProfessions = {}
_G.SmartRez.craftSalvageRecipes = {}
_G.SmartRez.craftSalvageCache = {}
_G.SmartRez.craftSalvageCacheDirty = true
_G.SmartRez.craftRecipeActions = {}
_G.SmartRez.craftRecipeCache = {}
_G.SmartRez.craftRecipeCacheDirty = true
_G.SmartRez.knownProfessions = {}
_G.SmartRez.goldPrinterMinFreeSlots = 4
_G.SmartRez.tsmLabelClickCooldown = 0.25
_G.SmartRez.dbDefaults = {
	enabled = false,
	bindings = {},
	goldPrinter = {
		minFreeSlots = 4,
	},
	tsmLabelClick = {
		cooldown = 0.25,
		showMacroErrors = false,
	},
	disenchantWhitelist = {},
	salvageWhitelists = {},
	salvageSelections = {},
	recipeCrafts = {
		shardcraft = {
			label = "Shard Craft",
			recipeID = nil,
			requiredProfession = nil,
			openTradeSkillID = nil,
			useDefaultReagents = true,
			debug = false,
			reagents = {},
		},
	},
}

_G.SmartRez.Profession = {
	Alchemy = 171,
	Blacksmithing = 164,
	Cooking = 185,
	Enchanting = 333,
	Engineering = 202,
	Fishing = 356,
	Herbalism = 182,
	Inscription = 773,
	Jewelcrafting = 755,
	Leatherworking = 165,
	Mining = 186,
	Skinning = 393,
	Tailoring = 197,
}

function _G.SmartRez:RegisterBindableAction(action)
	self.bindableActions[action.key] = action
end

local function resolveActionValue(action, key)
	local value = action[key]
	if type(value) == "function" then
		return value(action)
	end
	return value
end

local function copyTable(source)
	local copied = {}
	for key, value in pairs(source or {}) do
		if type(value) == "table" then
			copied[key] = copyTable(value)
		else
			copied[key] = value
		end
	end
	return copied
end

local function mergeDefaults(target, defaults)
	for key, value in pairs(defaults or {}) do
		if type(value) == "table" then
			if type(target[key]) ~= "table" then
				target[key] = {}
			end
			mergeDefaults(target[key], value)
		elseif target[key] == nil then
			target[key] = value
		end
	end
end

function _G.SmartRez:EnsureConfig()
	if type(SmartRezDB) ~= "table" then
		SmartRezDB = {}
	end

	self.db = SmartRezDB
	mergeDefaults(self.db, self.dbDefaults)
	return self.db
end

function _G.SmartRez:GetDisenchantWhitelist()
	self:EnsureConfig()
	return self.db.disenchantWhitelist
end

function _G.SmartRez:GetGoldPrinterMinFreeSlots()
	self:EnsureConfig()
	return self.db.goldPrinter.minFreeSlots or self.goldPrinterMinFreeSlots
end

function _G.SmartRez:SetGoldPrinterMinFreeSlots(value)
	self:EnsureConfig()
	self.db.goldPrinter.minFreeSlots = value or self.goldPrinterMinFreeSlots
	if self.RefreshViews then
		self:RefreshViews()
	end
end

function _G.SmartRez:GetTSMLabelClickCooldown()
	self:EnsureConfig()
	local cooldown = self.db.tsmLabelClick.cooldown
	if type(cooldown) ~= "number" then
		return self.tsmLabelClickCooldown
	end
	return cooldown
end

function _G.SmartRez:SetTSMLabelClickCooldown(value)
	self:EnsureConfig()
	value = tonumber(value) or self.tsmLabelClickCooldown
	if value < 0 then
		value = 0
	elseif value > 1 then
		value = 1
	end
	self.db.tsmLabelClick.cooldown = value
	if self.RefreshViews then
		self:RefreshViews()
	end
end

function _G.SmartRez:GetTSMLabelClickShowMacroErrors()
	self:EnsureConfig()
	return self.db.tsmLabelClick.showMacroErrors ~= false
end

function _G.SmartRez:SetTSMLabelClickShowMacroErrors(value)
	self:EnsureConfig()
	self.db.tsmLabelClick.showMacroErrors = value ~= false
	if self.RefreshViews then
		self:RefreshViews()
	end
end

function _G.SmartRez:SetDisenchantWhitelist(whitelist)
	self:EnsureConfig()
	self.db.disenchantWhitelist = whitelist or {}
end

function _G.SmartRez:GetRecipeCraftConfig(configKey)
	self:EnsureConfig()
	if type(self.db.recipeCrafts[configKey]) ~= "table" then
		local defaultConfig = self.dbDefaults.recipeCrafts[configKey] or {}
		self.db.recipeCrafts[configKey] = copyTable(defaultConfig)
	end

	local recipeConfig = self.db.recipeCrafts[configKey]
	local defaultConfig = self.dbDefaults.recipeCrafts[configKey]
	if defaultConfig then
		mergeDefaults(recipeConfig, defaultConfig)
	end

	return recipeConfig
end

function _G.SmartRez:SetRecipeCraftConfig(configKey, recipeConfig)
	self:EnsureConfig()
	self.db.recipeCrafts[configKey] = recipeConfig or {}
end

function _G.SmartRez:GetVisibleSchematicForm()
	local professionsFrame = _G["ProfessionsFrame"]
	if professionsFrame and professionsFrame.CraftingPage and professionsFrame.CraftingPage.SchematicForm and professionsFrame.CraftingPage.SchematicForm:IsVisible() then
		return professionsFrame.CraftingPage.SchematicForm
	end

	local ordersPage = professionsFrame and professionsFrame.OrdersPage and professionsFrame.OrdersPage.OrderView
	if ordersPage and ordersPage.OrderDetails and ordersPage.OrderDetails.SchematicForm and ordersPage.OrderDetails.SchematicForm:IsVisible() then
		return ordersPage.OrderDetails.SchematicForm
	end
end

local function buildCraftingReagentsFromConfig(reagents)
	local craftingReagents = {}

	for index, reagent in ipairs(reagents or {}) do
		if reagent.itemID or reagent.currencyID then
			craftingReagents[#craftingReagents + 1] = {
				reagent = {
					itemID = reagent.itemID,
					currencyID = reagent.currencyID,
				},
				dataSlotIndex = reagent.dataSlotIndex or index,
				quantity = reagent.quantity,
			}
		end
	end

	if #craftingReagents == 0 then
		return nil
	end

	return craftingReagents
end

function _G.SmartRez:UpdateCurrentProfessionState()
	local schematicForm = self:GetVisibleSchematicForm()
	if not schematicForm or not schematicForm.GetRecipeInfo then
		self.currentProfessionState = nil
		return nil
	end

	local recipeInfo = schematicForm:GetRecipeInfo()
	local professionInfo = _G["C_TradeSkillUI"]["GetBaseProfessionInfo"] and _G["C_TradeSkillUI"]["GetBaseProfessionInfo"]()

	if not recipeInfo or not recipeInfo.recipeID or not professionInfo or not professionInfo.professionID then
		self.currentProfessionState = nil
		return nil
	end

	local recipeSchematic = schematicForm.recipeSchematic or _G["C_TradeSkillUI"]["GetRecipeSchematic"](recipeInfo.recipeID, false)
	local currentTransaction = schematicForm.GetTransaction and schematicForm:GetTransaction() or nil
	local reagents = {}

	for slotIndex, reagentSlot in ipairs(recipeSchematic and recipeSchematic.reagentSlotSchematics or {}) do
		if reagentSlot.quantityRequired and reagentSlot.quantityRequired > 0 and (reagentSlot.required ~= false) then
			local selectedItemID = reagentSlot.reagents and reagentSlot.reagents[1] and reagentSlot.reagents[1].itemID or nil
			local slotAllocations = currentTransaction and currentTransaction.GetAllocations and currentTransaction:GetAllocations(slotIndex) or nil

			if slotAllocations and slotAllocations.FindAllocationByReagent then
				for _, reagent in ipairs(reagentSlot.reagents or {}) do
					local allocation = slotAllocations:FindAllocationByReagent(reagent)
					if allocation and allocation.GetQuantity and allocation:GetQuantity() > 0 then
						selectedItemID = reagent.itemID
						break
					end
				end
			end

			reagents[#reagents + 1] = {
				itemID = selectedItemID,
				quantity = reagentSlot.quantityRequired,
				dataSlotIndex = reagentSlot.dataSlotIndex or slotIndex,
				slotIndex = slotIndex,
			}
		end
	end

	local outputInfo = _G["C_TradeSkillUI"]["GetRecipeOutputItemData"] and _G["C_TradeSkillUI"]["GetRecipeOutputItemData"](
		recipeInfo.recipeID,
		buildCraftingReagentsFromConfig(reagents)
	)

	self.currentProfessionState = {
		label = recipeSchematic and recipeSchematic.name or recipeInfo.name,
		recipeID = recipeInfo.recipeID,
		requiredProfession = professionInfo.professionID,
		openTradeSkillID = professionInfo.professionID,
		reagents = reagents,
		outputQuantityMin = recipeSchematic and recipeSchematic.quantityMin or 1,
		outputQuantityMax = recipeSchematic and recipeSchematic.quantityMax or 1,
		outputItemLink = outputInfo and outputInfo.hyperlink or recipeInfo.hyperlink,
		outputItemID = outputInfo and outputInfo.itemID or nil,
		outputIcon = outputInfo and outputInfo.icon or recipeInfo.icon,
	}

	return self.currentProfessionState
end

function _G.SmartRez:WatchProfessionFrame()
	if self.professionFrameWatched then
		return
	end

	local hookFrame = _G["ProfessionsFrame"] and _G["ProfessionsFrame"]["CraftingPage"] and _G["ProfessionsFrame"]["CraftingPage"]["SchematicForm"]
	if not hookFrame then
		return
	end

	local function updateState()
		self:UpdateCurrentProfessionState()
		if self.RefreshViews then
			self:RefreshViews()
		end
	end

	hooksecurefunc(hookFrame, "Init", updateState)

	if hookFrame.RegisterCallback and _G["ProfessionsRecipeSchematicFormMixin"] and _G["ProfessionsRecipeSchematicFormMixin"]["Event"] then
		hookFrame:RegisterCallback(_G["ProfessionsRecipeSchematicFormMixin"]["Event"]["AllocationsModified"], updateState)
		hookFrame:RegisterCallback(_G["ProfessionsRecipeSchematicFormMixin"]["Event"]["UseBestQualityModified"], updateState)
	end

	self.professionFrameWatched = true
	self:UpdateCurrentProfessionState()
end

function _G.SmartRez:AddDisenchantWhitelistItem(itemID)
	if not itemID then
		return
	end

	local whitelist = self:GetDisenchantWhitelist()
	whitelist[itemID] = true
	self:RefreshViews()
end

function _G.SmartRez:RemoveDisenchantWhitelistItem(itemID)
	local whitelist = self:GetDisenchantWhitelist()
	whitelist[itemID] = nil
	self:RefreshViews()
end

function _G.SmartRez:LoadRecipeCraftFromSelection(configKey)
	if not (_G["C_TradeSkillUI"] and _G["C_TradeSkillUI"]["GetRecipeSchematic"]) then
		return false, "Recipe UI APIs are unavailable."
	end

	local currentState = self:UpdateCurrentProfessionState()
	if not currentState or not currentState.recipeID then
		local recipeConfig = self:GetRecipeCraftConfig(configKey)
		if recipeConfig.openTradeSkillID and _G["C_TradeSkillUI"] and _G["C_TradeSkillUI"]["OpenTradeSkill"] then
			_G["C_TradeSkillUI"]["OpenTradeSkill"](recipeConfig.openTradeSkillID)
			return false, "Opened the profession window. Select a recipe, then click again."
		end
		return false, "Select a recipe in the profession window first."
	end

	self:SetRecipeCraftConfig(configKey, {
		label = currentState.label,
		recipeID = currentState.recipeID,
		requiredProfession = currentState.requiredProfession,
		openTradeSkillID = currentState.openTradeSkillID,
		useDefaultReagents = true,
		debug = false,
		reagents = copyTable(currentState.reagents or {}),
		outputQuantityMin = currentState.outputQuantityMin,
		outputQuantityMax = currentState.outputQuantityMax,
		outputItemLink = currentState.outputItemLink,
		outputItemID = currentState.outputItemID,
		outputIcon = currentState.outputIcon,
	})

	self:MarkCraftRecipeCacheDirty()
	self:RefreshViews()

	return true
end

function _G.SmartRez:RefreshKnownProfessions()
	local knownProfessions = {}
	local professionIndexes = { _G["GetProfessions"]() }

	for _, professionIndex in ipairs(professionIndexes) do
		if professionIndex then
			local _, _, _, _, _, _, professionID = _G["GetProfessionInfo"](professionIndex)
			if professionID then
				knownProfessions[professionID] = true
			end
		end
	end

	if _G["C_TradeSkillUI"] and _G["C_TradeSkillUI"]["GetChildProfessionInfos"] then
		for _, professionInfo in ipairs(_G["C_TradeSkillUI"]["GetChildProfessionInfos"]() or {}) do
			if professionInfo.professionID then
				knownProfessions[professionInfo.professionID] = true
			end
			if professionInfo.parentProfessionID then
				knownProfessions[professionInfo.parentProfessionID] = true
			end
		end
	end

	self.knownProfessions = knownProfessions
end

function _G.SmartRez:HasProfession(professionID)
	return self.knownProfessions[professionID] == true
end

function _G.SmartRez:GetBindableActions()
	local actions = {}
	for _, action in pairs(self.bindableActions) do
		local requiredProfession = resolveActionValue(action, "requiredProfession")
		if not requiredProfession or self:HasProfession(requiredProfession) then
			table.insert(actions, {
				key = action.key,
				label = resolveActionValue(action, "label"),
				buttonName = action.buttonName,
				order = action.order,
				requiredProfession = requiredProfession,
			})
		end
	end
	table.sort(actions, function(left, right)
		return left.order < right.order
	end)
	return actions
end

function _G.SmartRez:MarkCraftSalvageCacheDirty()
	self.craftSalvageCacheDirty = true
end

function _G.SmartRez:MarkCraftRecipeCacheDirty()
	self.craftRecipeCacheDirty = true
end

function _G.SmartRez:GetFreeBagSlots()
	local freeSlots = 0

	for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
		if _G["C_Container"]["GetContainerNumFreeSlots"] then
			local bagFreeSlots, bagFamily = _G["C_Container"]["GetContainerNumFreeSlots"](bag)
			if bagFamily == 0 then
				freeSlots = freeSlots + (bagFreeSlots or 0)
			end
		else
			for slot = 1, _G["C_Container"]["GetContainerNumSlots"](bag) do
				if not _G["C_Container"]["GetContainerItemInfo"](bag, slot) then
					freeSlots = freeSlots + 1
				end
			end
		end
	end

	return freeSlots
end

function _G.SmartRez:HandleInventoryChanged()
	self:MarkCraftSalvageCacheDirty()
	self:MarkCraftRecipeCacheDirty()

	if self.RebuildCraftSalvageCache then
		self:RebuildCraftSalvageCache()
	end

	if self.RebuildCraftRecipeCache then
		self:RebuildCraftRecipeCache()
	end
end

function _G.SmartRez:HandleProfessionsChanged()
	self:RefreshKnownProfessions()
	self:MarkCraftSalvageCacheDirty()
	self:MarkCraftRecipeCacheDirty()

	if self.RefreshViews then
		self:RefreshViews()
	end
end

function _G.SmartRez:OnEnable()
	self:RegisterEvent("BAG_UPDATE_DELAYED", "HandleInventoryChanged")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "HandleInventoryChanged")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "HandleProfessionsChanged")
	self:RegisterEvent("SKILL_LINES_CHANGED", "HandleProfessionsChanged")
	self:RegisterEvent("TRADE_SKILL_SHOW", "WatchProfessionFrame")
	self:HandleProfessionsChanged()
	self:HandleInventoryChanged()
	self:WatchProfessionFrame()
end

_G["BINDING_HEADER_SMARTREZ"] = "Smart Rez"
_G["BINDING_NAME_CLICK SmartRezModeToggleBtn:LeftButton"] = "Toggle Smart Rez Mode"
