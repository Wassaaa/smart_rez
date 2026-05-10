local SmartRez = _G.SmartRez
local TSM_API = _G.TSM_API
local C_Container = C_Container
local C_AuctionHouse = C_AuctionHouse
local DEFAULT_PRICE_SOURCE = "DBRecent"

local function refreshViews()
	if SmartRez.RefreshViews then
		SmartRez:RefreshViews()
	end
end

local function trim(text)
	if type(text) ~= "string" then
		return nil
	end

	text = text:match("^%s*(.-)%s*$")
	if text == "" then
		return nil
	end

	return text
end

local function ensureBagValueConfig()
	SmartRez:EnsureConfig()

	if type(SmartRez.db.bagValue) ~= "table" then
		SmartRez.db.bagValue = {}
	end

	local bagValueConfig = SmartRez.db.bagValue
	if type(bagValueConfig.whitelist) ~= "table" then
		bagValueConfig.whitelist = {}
	end
	if type(bagValueConfig.items) ~= "table" then
		bagValueConfig.items = {}
	end
	if type(bagValueConfig.order) ~= "table" then
		bagValueConfig.order = {}
	end
	if type(bagValueConfig.inventorySources) ~= "table" then
		bagValueConfig.inventorySources = {}
	end

	local normalizedWhitelist = {}
	for itemID, selected in pairs(bagValueConfig.whitelist) do
		if selected then
			local numericItemID = tonumber(itemID)
			if numericItemID then
				normalizedWhitelist[numericItemID] = true
			end
		end
	end
	bagValueConfig.whitelist = normalizedWhitelist

	local normalizedItems = {}
	for itemID, itemConfig in pairs(bagValueConfig.items) do
		local numericItemID = tonumber(itemID)
		if numericItemID and type(itemConfig) == "table" then
			normalizedItems[numericItemID] = {
				priceSource = trim(itemConfig.priceSource),
			}
		end
	end
	bagValueConfig.items = normalizedItems

	local seen = {}
	local order = {}
	for _, itemID in ipairs(bagValueConfig.order) do
		local numericItemID = tonumber(itemID)
		if numericItemID and bagValueConfig.whitelist[numericItemID] and not seen[numericItemID] then
			seen[numericItemID] = true
			order[#order + 1] = numericItemID
		end
	end
	for itemID in pairs(bagValueConfig.whitelist) do
		if not seen[itemID] then
			seen[itemID] = true
			order[#order + 1] = itemID
		end
	end
	bagValueConfig.order = order

	bagValueConfig.priceSource = trim(bagValueConfig.priceSource) or DEFAULT_PRICE_SOURCE
	if bagValueConfig.onlyAuctionable == nil then
		bagValueConfig.onlyAuctionable = true
	end
	if bagValueConfig.inventorySources.playerBags == nil then
		bagValueConfig.inventorySources.playerBags = true
	end
	if bagValueConfig.inventorySources.warbank == nil then
		bagValueConfig.inventorySources.warbank = false
	end
	if bagValueConfig.inventorySources.playerBags ~= true and bagValueConfig.inventorySources.warbank ~= true then
		bagValueConfig.inventorySources.playerBags = true
	end

	return bagValueConfig
end

local function addOrderedBagValueItem(config, itemID)
	for _, orderedItemID in ipairs(config.order or {}) do
		if orderedItemID == itemID then
			return
		end
	end
	config.order[#config.order + 1] = itemID
end

local function removeOrderedBagValueItem(config, itemID)
	for index = #(config.order or {}), 1, -1 do
		if config.order[index] == itemID then
			table.remove(config.order, index)
		end
	end
end

local function ensureBagValueItemConfig(itemID)
	local config = ensureBagValueConfig()
	itemID = tonumber(itemID)
	if not itemID then
		return {}
	end

	if type(config.items[itemID]) ~= "table" then
		config.items[itemID] = {}
	end

	local itemConfig = config.items[itemID]
	itemConfig.priceSource = trim(itemConfig.priceSource)
	return itemConfig
end

local function getBagValueItemPriceSource(config, itemID)
	local itemConfig = config and config.items and config.items[itemID] or nil
	return trim(itemConfig and itemConfig.priceSource) or config.priceSource
end

local function formatMoney(value)
	value = math.max(0, math.floor(tonumber(value) or 0))

	local gold = math.floor(value / 10000)
	local silver = math.floor((value % 10000) / 100)
	if gold > 0 then
		return string.format("%dg %ds", gold, silver)
	end

	return string.format("%ds", silver)
end

local function getItemString(itemLink, itemID)
	if not (TSM_API and TSM_API.ToItemString) then
		return nil
	end

	local input = itemLink or ("item:" .. tostring(itemID))
	local ok, itemString = pcall(TSM_API.ToItemString, input)
	if ok and type(itemString) == "string" and itemString ~= "" then
		return itemString
	end

	return nil
end

local function getUnitPrice(expression, itemLink, itemID, cache)
	if not (TSM_API and TSM_API.GetCustomPriceValue) then
		return nil
	end

	local cacheKey = tostring(expression) .. "\031" .. tostring(itemLink or itemID)
	if cache[cacheKey] ~= nil then
		return cache[cacheKey] or nil
	end

	local itemString = getItemString(itemLink, itemID)
	if not itemString then
		cache[cacheKey] = false
		return nil
	end

	local ok, value = pcall(TSM_API.GetCustomPriceValue, expression, itemString)
	if ok and type(value) == "number" then
		cache[cacheKey] = value
		return value
	end

	cache[cacheKey] = false
	return nil
end

local function getItemLinkFromLocation(location, itemID)
	if location and C_Item.GetItemLink then
		local itemLink = C_Item.GetItemLink(location)
		if itemLink then
			return itemLink
		end
	end

	local _, itemLink = C_Item.GetItemInfo(itemID)
	return itemLink
end

function SmartRez:GetBagValueConfig()
	return ensureBagValueConfig()
end

function SmartRez:GetBagValueWhitelist()
	return ensureBagValueConfig().whitelist
end

function SmartRez:GetBagValueInventorySources()
	local bagValueConfig = ensureBagValueConfig()
	return bagValueConfig.inventorySources
end

local function ensureBagValueWarbankProxy(inventorySources)
	if not inventorySources or inventorySources.warbank ~= true then
		return
	end

	if not SmartRez.OpenProfessionProxy then
		return
	end

	local professionID = SmartRez.GetDefaultProfessionProxyProfessionID and SmartRez:GetDefaultProfessionProxyProfessionID() or nil
	if professionID then
		SmartRez:OpenProfessionProxy(professionID)
	end
end

function SmartRez:SetBagValueInventorySources(inventorySources)
	local bagValueConfig = ensureBagValueConfig()
	local updatedSources = bagValueConfig.inventorySources
	if type(inventorySources) == "table" then
		if inventorySources.playerBags ~= nil then
			updatedSources.playerBags = inventorySources.playerBags == true
		end
		if inventorySources.warbank ~= nil then
			updatedSources.warbank = inventorySources.warbank == true
		end
	end

	if updatedSources.playerBags ~= true and updatedSources.warbank ~= true then
		updatedSources.playerBags = true
	end

	bagValueConfig.inventorySources = updatedSources
	ensureBagValueWarbankProxy(updatedSources)
	refreshViews()
end

function SmartRez:GetBagValuePriceSource()
	return ensureBagValueConfig().priceSource
end

function SmartRez:SetBagValuePriceSource(priceSource, skipRefresh)
	ensureBagValueConfig().priceSource = trim(priceSource) or DEFAULT_PRICE_SOURCE
	if not skipRefresh then
		refreshViews()
	end
end

function SmartRez:GetBagValueOrderedItemIDs()
	return ensureBagValueConfig().order
end

function SmartRez:GetBagValueItemConfig(itemID)
	return ensureBagValueItemConfig(itemID)
end

function SmartRez:GetBagValueItemPriceSourceDisplayText(itemID)
	return ensureBagValueItemConfig(itemID).priceSource or ""
end

function SmartRez:SetBagValueItemPriceSource(itemID, priceSource, skipRefresh)
	local itemConfig = ensureBagValueItemConfig(itemID)
	itemConfig.priceSource = trim(priceSource)
	if not skipRefresh then
		refreshViews()
	end
end

function SmartRez:GetBagValueOnlyAuctionable()
	return ensureBagValueConfig().onlyAuctionable == true
end

function SmartRez:SetBagValueOnlyAuctionable(enabled)
	ensureBagValueConfig().onlyAuctionable = enabled == true
	refreshViews()
end

function SmartRez:AddBagValueWhitelistItem(itemID, skipRefresh)
	if not itemID then
		return
	end

	local config = ensureBagValueConfig()
	config.whitelist[itemID] = true
	addOrderedBagValueItem(config, itemID)
	if not skipRefresh then
		refreshViews()
	end
end

function SmartRez:RemoveBagValueWhitelistItem(itemID, skipRefresh)
	local config = ensureBagValueConfig()
	config.whitelist[itemID] = nil
	config.items[itemID] = nil
	removeOrderedBagValueItem(config, itemID)
	if not skipRefresh then
		refreshViews()
	end
end

function SmartRez:IsBagValueItemAuctionable(location)
	if not location then
		return false
	end

	if C_AuctionHouse and C_AuctionHouse.IsSellItemValid then
		local ok, isValid = pcall(C_AuctionHouse.IsSellItemValid, location, false)
		if ok then
			return isValid == true
		end
	end

	if C_Item and C_Item.IsBound then
		local ok, isBound = pcall(C_Item.IsBound, location)
		if ok then
			return isBound ~= true
		end
	end

	return true
end

function SmartRez:GetBagValueSourceContainerIDs()
	local inventorySources = self:GetBagValueInventorySources()
	local containerIDs = {}

	local function appendContainers(sourceContainerIDs)
		for _, containerID in ipairs(sourceContainerIDs or {}) do
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

function SmartRez:ForEachBagValueSourceSlot(callback)
	return self:ForEachContainerSlot(self:GetBagValueSourceContainerIDs(), callback)
end

function SmartRez:BuildBagValueSnapshot()
	local config = ensureBagValueConfig()
	local expression = config.priceSource
	local whitelist = config.whitelist
	local inventorySources = config.inventorySources
	local snapshot = {
		priceSource = expression,
		onlyAuctionable = config.onlyAuctionable == true,
		inventorySources = inventorySources,
		isTSMAvailable = TSM_API ~= nil,
		hasSelection = next(whitelist) ~= nil,
		availableItemIDs = {},
		itemsByID = {},
		totalAvailableQuantity = 0,
		totalSelectedQuantity = 0,
		totalSelectedValue = 0,
		selectedItemTypes = 0,
		availableItemTypes = 0,
		missingPriceQuantity = 0,
		invalidPriceMessage = nil,
	}

	local priceValidityCache = {}
	local function getPriceExpressionError(priceExpression)
		if not (snapshot.isTSMAvailable and TSM_API.IsCustomPriceValid) then
			return nil
		end

		if priceValidityCache[priceExpression] ~= nil then
			return priceValidityCache[priceExpression] or nil
		end

		local ok, isValid, err = pcall(TSM_API.IsCustomPriceValid, priceExpression)
		if ok and isValid == false then
			priceValidityCache[priceExpression] = err or "Invalid TSM custom price."
		else
			priceValidityCache[priceExpression] = false
		end

		return priceValidityCache[priceExpression] or nil
	end

	if snapshot.isTSMAvailable and TSM_API.IsCustomPriceValid then
		snapshot.invalidPriceMessage = getPriceExpressionError(expression)
	end

	local seenItemIDs = {}
	local priceCache = {}
	self:ForEachBagValueSourceSlot(function(bag, slot)
		local itemInfo = C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
		local itemID = itemInfo and itemInfo.itemID
		if not itemID then
			return
		end

		local itemLocation = ItemLocation:CreateFromBagAndSlot(bag, slot)
		local isAuctionable = self:IsBagValueItemAuctionable(itemLocation)
		if snapshot.onlyAuctionable and not isAuctionable then
			return
		end

		local entry = snapshot.itemsByID[itemID]
		if not entry then
			entry = {
				itemID = itemID,
				itemLink = getItemLinkFromLocation(itemLocation, itemID),
				itemIcon = itemInfo.iconFileID,
				count = 0,
				totalValue = 0,
				pricedQuantity = 0,
				missingPriceQuantity = 0,
				minUnitPrice = nil,
				maxUnitPrice = nil,
				priceSource = getBagValueItemPriceSource(config, itemID),
				usesDefaultPriceSource = trim(config.items[itemID] and config.items[itemID].priceSource) == nil,
				invalidPriceMessage = nil,
			}
			snapshot.itemsByID[itemID] = entry
		end

		if not seenItemIDs[itemID] then
			seenItemIDs[itemID] = true
			snapshot.availableItemIDs[#snapshot.availableItemIDs + 1] = itemID
		end

		local stackCount = itemInfo.stackCount or 0
		entry.count = entry.count + stackCount
		snapshot.totalAvailableQuantity = snapshot.totalAvailableQuantity + stackCount

		if whitelist[itemID] then
			snapshot.totalSelectedQuantity = snapshot.totalSelectedQuantity + stackCount

			local unitPrice
			local itemPriceSource = getBagValueItemPriceSource(config, itemID)
			local invalidPriceMessage = getPriceExpressionError(itemPriceSource)
			entry.priceSource = itemPriceSource
			entry.usesDefaultPriceSource = trim(config.items[itemID] and config.items[itemID].priceSource) == nil
			entry.invalidPriceMessage = invalidPriceMessage
			if not invalidPriceMessage then
				unitPrice = getUnitPrice(itemPriceSource, entry.itemLink, itemID, priceCache)
			end

			if type(unitPrice) == "number" then
				local stackValue = unitPrice * stackCount
				entry.totalValue = entry.totalValue + stackValue
				entry.pricedQuantity = entry.pricedQuantity + stackCount
				entry.minUnitPrice = entry.minUnitPrice and math.min(entry.minUnitPrice, unitPrice) or unitPrice
				entry.maxUnitPrice = entry.maxUnitPrice and math.max(entry.maxUnitPrice, unitPrice) or unitPrice
				snapshot.totalSelectedValue = snapshot.totalSelectedValue + stackValue
			else
				entry.missingPriceQuantity = entry.missingPriceQuantity + stackCount
				snapshot.missingPriceQuantity = snapshot.missingPriceQuantity + stackCount
			end
		end
	end)

	for itemID, entry in pairs(snapshot.itemsByID) do
		snapshot.availableItemTypes = snapshot.availableItemTypes + 1
		if whitelist[itemID] and entry.count > 0 then
			snapshot.selectedItemTypes = snapshot.selectedItemTypes + 1
		end
	end

	snapshot.totalSelectedValueText = formatMoney(snapshot.totalSelectedValue)
	return snapshot
end
