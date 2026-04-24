_G.SmartRez = LibStub("AceAddon-3.0"):NewAddon("SmartRez", "AceConsole-3.0", "AceEvent-3.0")
local SmartRez = _G.SmartRez
local C_TradeSkillUI = C_TradeSkillUI
local C_Container = C_Container
local GetProfessions = GetProfessions
local GetProfessionInfo = GetProfessionInfo
local _C_GetContainerNumSlots = C_Container and C_Container.GetContainerNumSlots
local _C_GetContainerItemInfo = C_Container and C_Container.GetContainerItemInfo
local _C_GetContainerNumFreeSlots = C_Container and C_Container.GetContainerNumFreeSlots
SmartRez.appName = "Smart Rez"
SmartRez.bindableActions = {}
SmartRez.craftSalvageProfessions = {}
SmartRez.craftSalvageRecipes = {}
SmartRez.craftSalvageCache = {}
SmartRez.craftSalvageCacheDirty = true
SmartRez.craftRecipeActions = {}
SmartRez.craftRecipeActionFrames = {}
SmartRez.craftRecipeCache = {}
SmartRez.craftRecipeCacheDirty = true
SmartRez.craftingItemCounts = {}
SmartRez.cachedFreeBagSlots = nil
SmartRez.knownProfessions = {}
SmartRez.goldPrinterMinFreeSlots = 4
SmartRez.tsmLabelClickCooldown = 0.25
SmartRez.dbDefaults = {
	enabled = false,
	bindings = {},
	goldPrinter = {
		minFreeSlots = 4,
	},
	tsmLabelClick = {
		cooldown = 0.25,
		showMacroErrors = false,
	},
	debug = {
		debug = false,
	},
	disenchantWhitelist = {},
	salvageWhitelists = {},
	salvageSelections = {},
	inventorySources = {
		playerBags = true,
		warbank = false,
	},
	bagValue = {
		priceSource = "DBRecent",
		onlyAuctionable = true,
		inventorySources = {
			playerBags = true,
			warbank = false,
		},
		whitelist = {},
	},
	professionProxy = {
		visible = true,
		point = {
			anchor = "TOP",
			relativePoint = "TOP",
			x = 0,
			y = -80,
		},
	},
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

SmartRez.Profession = {
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

function SmartRez:RegisterBindableAction(action)
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

local function normalizeInventorySources(inventorySources)
	local normalized = copyTable(inventorySources or {})
	local hasEnabledSource = false

	for sourceKey, defaultValue in pairs(SmartRez.dbDefaults.inventorySources or {}) do
		if normalized[sourceKey] == nil then
			normalized[sourceKey] = defaultValue
		end

		if normalized[sourceKey] == true then
			hasEnabledSource = true
		end
	end

	if not hasEnabledSource then
		normalized.playerBags = true
	end

	return normalized
end

local function getInventoryConstant(name, fallback)
	local inventoryConstants = Constants and Constants.InventoryConstants
	local value = inventoryConstants and inventoryConstants[name]

	if type(value) == "number" then
		return value
	end

	return fallback
end

local function appendContainerRange(containerIDs, firstContainerID, count)
	if type(firstContainerID) ~= "number" or type(count) ~= "number" or count <= 0 then
		return
	end

	for containerID = firstContainerID, (firstContainerID + count - 1) do
		containerIDs[#containerIDs + 1] = containerID
	end
end

function SmartRez:EnsureConfig()
	if type(SmartRezDB) ~= "table" then
		SmartRezDB = {}
	end

	self.db = SmartRezDB
	mergeDefaults(self.db, self.dbDefaults)
	return self.db
end

function SmartRez:GetDisenchantWhitelist()
	self:EnsureConfig()
	return self.db.disenchantWhitelist
end

function SmartRez:GetDebugEnabled()
	self:EnsureConfig()
	local debugConfig = self.db.debug
	if type(debugConfig) ~= "table" then
		debugConfig = {}
		self.db.debug = debugConfig
	end

	if debugConfig.debug == nil and type(self.db.disenchant) == "table" then
		debugConfig.debug = self.db.disenchant.debug == true
	end

	return debugConfig.debug == true
end

function SmartRez:SetDebugEnabled(value)
	self:EnsureConfig()
	if type(self.db.debug) ~= "table" then
		self.db.debug = {}
	end
	self.db.debug.debug = value == true
	if self.RefreshViews then
		self:RefreshViews()
	end
end

function SmartRez:GetGoldPrinterMinFreeSlots()
	self:EnsureConfig()
	return self.db.goldPrinter.minFreeSlots or self.goldPrinterMinFreeSlots
end

function SmartRez:SetGoldPrinterMinFreeSlots(value, skipRefresh)
	self:EnsureConfig()
	self.db.goldPrinter.minFreeSlots = value or self.goldPrinterMinFreeSlots
	if not skipRefresh and self.RefreshViews then
		self:RefreshViews()
	end
end

function SmartRez:GetTSMLabelClickCooldown()
	self:EnsureConfig()
	local cooldown = self.db.tsmLabelClick.cooldown
	if type(cooldown) ~= "number" then
		return self.tsmLabelClickCooldown
	end
	return cooldown
end

function SmartRez:SetTSMLabelClickCooldown(value)
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

function SmartRez:GetTSMLabelClickShowMacroErrors()
	self:EnsureConfig()
	return self.db.tsmLabelClick.showMacroErrors ~= false
end

function SmartRez:SetTSMLabelClickShowMacroErrors(value)
	self:EnsureConfig()
	self.db.tsmLabelClick.showMacroErrors = value ~= false
	if self.RefreshViews then
		self:RefreshViews()
	end
end

function SmartRez:SetDisenchantWhitelist(whitelist)
	self:EnsureConfig()
	self.db.disenchantWhitelist = whitelist or {}
	if self.RefreshDisenchantButton then
		self:RefreshDisenchantButton()
	end
end

function SmartRez:GetInventorySources()
	self:EnsureConfig()
	self.db.inventorySources = normalizeInventorySources(self.db.inventorySources)
	return self.db.inventorySources
end

function SmartRez:SetInventorySources(inventorySources)
	self:EnsureConfig()
	self.db.inventorySources = normalizeInventorySources(inventorySources or self.db.inventorySources)
	self:HandleInventoryChanged()
	if self.RefreshViews then
		self:RefreshViews()
	end
end

function SmartRez:GetRecipeCraftConfig(configKey)
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

function SmartRez:SetRecipeCraftConfig(configKey, recipeConfig)
	self:EnsureConfig()
	self.db.recipeCrafts[configKey] = recipeConfig or {}
end

function SmartRez:GetVisibleSchematicForm()
	local professionsFrame = ProfessionsFrame
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

function SmartRez:UpdateCurrentProfessionState()
	local schematicForm = self:GetVisibleSchematicForm()
	if not schematicForm or not schematicForm.GetRecipeInfo then
		self.currentProfessionState = nil
		return nil
	end

	local recipeInfo = schematicForm:GetRecipeInfo()
	local professionInfo = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()

	if not recipeInfo or not recipeInfo.recipeID or not professionInfo or not professionInfo.professionID then
		self.currentProfessionState = nil
		return nil
	end

	local recipeSchematic = schematicForm.recipeSchematic or C_TradeSkillUI.GetRecipeSchematic(recipeInfo.recipeID, false)
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

	local outputInfo = C_TradeSkillUI.GetRecipeOutputItemData and C_TradeSkillUI.GetRecipeOutputItemData(
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

function SmartRez:WatchProfessionFrame()
	if self.professionFrameWatched then
		return
	end

	local hookFrame = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.SchematicForm
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

	if hookFrame.RegisterCallback and ProfessionsRecipeSchematicFormMixin and ProfessionsRecipeSchematicFormMixin.Event then
		hookFrame:RegisterCallback(ProfessionsRecipeSchematicFormMixin.Event.AllocationsModified, updateState)
		hookFrame:RegisterCallback(ProfessionsRecipeSchematicFormMixin.Event.UseBestQualityModified, updateState)
	end

	self.professionFrameWatched = true
	self:UpdateCurrentProfessionState()
end

function SmartRez:AddDisenchantWhitelistItem(itemID, skipRefresh)
	if not itemID then
		return
	end

	local whitelist = self:GetDisenchantWhitelist()
	whitelist[itemID] = true
	if self.RefreshDisenchantButton then
		self:RefreshDisenchantButton()
	end
	if not skipRefresh then
		self:RefreshViews()
	end
end

function SmartRez:RemoveDisenchantWhitelistItem(itemID, skipRefresh)
	local whitelist = self:GetDisenchantWhitelist()
	whitelist[itemID] = nil
	if self.RefreshDisenchantButton then
		self:RefreshDisenchantButton()
	end
	if not skipRefresh then
		self:RefreshViews()
	end
end

function SmartRez:LoadRecipeCraftFromSelection(configKey)
	if not C_TradeSkillUI.GetRecipeSchematic then
		return false, "Recipe UI APIs are unavailable."
	end

	local currentState = self:UpdateCurrentProfessionState()
	if not currentState or not currentState.recipeID then
		local recipeConfig = self:GetRecipeCraftConfig(configKey)
		if recipeConfig.openTradeSkillID and C_TradeSkillUI.OpenTradeSkill then
			C_TradeSkillUI.OpenTradeSkill(recipeConfig.openTradeSkillID)
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

function SmartRez:RefreshKnownProfessions()
	local knownProfessions = {}
	local professionIndexes = { GetProfessions() }

	for _, professionIndex in ipairs(professionIndexes) do
		if professionIndex then
			local _, _, _, _, _, _, professionID = GetProfessionInfo(professionIndex)
			if professionID then
				knownProfessions[professionID] = true
			end
		end
	end

	if C_TradeSkillUI.GetChildProfessionInfos then
		for _, professionInfo in ipairs(C_TradeSkillUI.GetChildProfessionInfos() or {}) do
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

function SmartRez:HasProfession(professionID)
	return self.knownProfessions[professionID] == true
end

function SmartRez:GetBindableActions()
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

function SmartRez:MarkCraftSalvageCacheDirty()
	self.craftSalvageCacheDirty = true
end

function SmartRez:MarkCraftRecipeCacheDirty()
	self.craftRecipeCacheDirty = true
end

function SmartRez:RebuildInventoryCounts()
	local itemCounts = {}
	local freeSlots = 0

	self:ForEachCraftingItemSourceSlot(function(bag, slot)
		local itemInfo = _C_GetContainerItemInfo and _C_GetContainerItemInfo(bag, slot)
		if itemInfo and itemInfo.itemID then
			itemCounts[itemInfo.itemID] = (itemCounts[itemInfo.itemID] or 0) + (itemInfo.stackCount or 0)
		end
	end)

	for _, bag in ipairs(self:GetPlayerOutputBagContainerIDs()) do
		if _C_GetContainerNumFreeSlots then
			local bagFreeSlots, bagFamily = _C_GetContainerNumFreeSlots(bag)
			if bagFamily == 0 then
				freeSlots = freeSlots + (bagFreeSlots or 0)
			end
		else
			for slot = 1, (_C_GetContainerNumSlots and _C_GetContainerNumSlots(bag) or 0) do
				if not (_C_GetContainerItemInfo and _C_GetContainerItemInfo(bag, slot)) then
					freeSlots = freeSlots + 1
				end
			end
		end
	end

	self.craftingItemCounts = itemCounts
	self.cachedFreeBagSlots = freeSlots
end

function SmartRez:GetPlayerBagContainerIDs()
	local bagIndex = Enum and Enum.BagIndex or {}
	local containerIDs = {
		bagIndex.Backpack or BACKPACK_CONTAINER,
	}

	appendContainerRange(
		containerIDs,
		bagIndex.Bag_1 or ((bagIndex.Backpack or BACKPACK_CONTAINER) + 1),
		getInventoryConstant("NumBagSlots", NUM_BAG_SLOTS or 4)
	)

	if type(bagIndex.ReagentBag) == "number" and getInventoryConstant("NumReagentBagSlots", 0) > 0 then
		containerIDs[#containerIDs + 1] = bagIndex.ReagentBag
	end

	return containerIDs
end

function SmartRez:GetPlayerOutputBagContainerIDs()
	local bagIndex = Enum and Enum.BagIndex or {}
	local containerIDs = {
		bagIndex.Backpack or BACKPACK_CONTAINER,
	}

	appendContainerRange(
		containerIDs,
		bagIndex.Bag_1 or ((bagIndex.Backpack or BACKPACK_CONTAINER) + 1),
		getInventoryConstant("NumBagSlots", NUM_BAG_SLOTS or 4)
	)

	return containerIDs
end

function SmartRez:GetWarbankContainerIDs()
	local bagIndex = Enum and Enum.BagIndex or {}
	local containerIDs = {}

	appendContainerRange(
		containerIDs,
		bagIndex.AccountBankTab_1,
		getInventoryConstant("NumAccountBankSlots", 0)
	)

	return containerIDs
end

function SmartRez:GetCraftingItemSourceContainerIDs()
	local inventorySources = self:GetInventorySources()
	local containerIDs = {}

	local function appendContainers(sourceContainerIDs)
		for _, containerID in ipairs(sourceContainerIDs) do
			containerIDs[#containerIDs + 1] = containerID
		end
	end

	if inventorySources.playerBags ~= false then
		appendContainers(self:GetPlayerBagContainerIDs())
	end

	if inventorySources.warbank == true then
		appendContainers(self:GetWarbankContainerIDs())
	end

	return containerIDs
end

function SmartRez:ForEachContainerSlot(containerIDs, callback)
	for _, bag in ipairs(containerIDs or {}) do
		local numSlots = _C_GetContainerNumSlots and _C_GetContainerNumSlots(bag) or 0

		for slot = 1, numSlots do
			if callback(bag, slot) then
				return true
			end
		end
	end

	return false
end

function SmartRez:ForEachCraftingItemSourceSlot(callback)
	return self:ForEachContainerSlot(self:GetCraftingItemSourceContainerIDs(), callback)
end

function SmartRez:ForEachPlayerBagSlot(callback)
	return self:ForEachContainerSlot(self:GetPlayerBagContainerIDs(), callback)
end

function SmartRez:GetCraftingItemCount(itemID)
	if not itemID then
		return 0
	end

	if self.craftingItemCounts == nil then
		self:RebuildInventoryCounts()
	end

	return self.craftingItemCounts[itemID] or 0
end

function SmartRez:GetFreeBagSlots()
	if self.cachedFreeBagSlots == nil then
		self:RebuildInventoryCounts()
	end

	return self.cachedFreeBagSlots or 0
end

function SmartRez:HandleInventoryChanged()
	self:RebuildInventoryCounts()
	self:MarkCraftSalvageCacheDirty()
	self:MarkCraftRecipeCacheDirty()

	if self.RebuildCraftSalvageCache then
		self:RebuildCraftSalvageCache()
	end

	if self.RebuildCraftRecipeCache then
		self:RebuildCraftRecipeCache()
	end

	if self.RefreshDisenchantButton then
		self:RefreshDisenchantButton()
	end
end

function SmartRez:HandleProfessionsChanged()
	self:RefreshKnownProfessions()
	self:MarkCraftSalvageCacheDirty()
	self:MarkCraftRecipeCacheDirty()

	if self.RefreshViews then
		self:RefreshViews()
	end
end

function SmartRez:OnEnable()
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
_G["BINDING_NAME_CLICK LowModeToggleBtn:LeftButton"] = "Toggle Low Mode"
