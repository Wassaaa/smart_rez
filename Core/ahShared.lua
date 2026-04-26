local SmartRez = _G.SmartRez
local C_AuctionHouse = C_AuctionHouse
local C_Container = C_Container

local DEFAULT_PRICE_TEXT = "1g"

local function trim(text)
	if type(text) ~= "string" then
		return nil
	end

	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	text = text:match("^%s*(.-)%s*$")
	if text == "" then
		return nil
	end
	return text
end

local function getItemString(itemLink, itemID)
	local TSM_API = _G.TSM_API
	if not (TSM_API and TSM_API.ToItemString) then
		return nil
	end

	local ok, itemString = pcall(TSM_API.ToItemString, itemLink or ("item:" .. tostring(itemID)))
	if ok and type(itemString) == "string" and itemString ~= "" then
		return itemString
	end
end

local function getTSMPrice(source, itemLink, itemID)
	local TSM_API = _G.TSM_API
	source = trim(source)
	if not (source and TSM_API and TSM_API.GetCustomPriceValue) then
		return nil, "not a fixed gold/silver price, and TSM custom prices are unavailable"
	end

	if TSM_API.IsCustomPriceValid then
		local ok, isValid, err = pcall(TSM_API.IsCustomPriceValid, source)
		if ok and isValid == false then
			return nil, err or "invalid TSM custom price"
		end
	end

	local itemString = getItemString(itemLink, itemID)
	if not itemString then
		return nil, "TSM item string could not be built"
	end

	local ok, value = pcall(TSM_API.GetCustomPriceValue, source, itemString)
	if ok and type(value) == "number" and value >= 0 then
		return math.floor(value)
	end

	return nil, "TSM custom price did not resolve"
end

function SmartRez:TrimAHText(text)
	return trim(text)
end

function SmartRez:ParseAHMoneyText(text)
	text = trim(text)
	if not text then
		return nil
	end

	local lowerText = text:lower():gsub(",", ""):gsub("%s+", "")
	local goldText = lowerText:match("(%d+)g")
	local silverText = lowerText:match("(%d+)s")

	if not goldText and not silverText then
		return nil
	end

	local gold = tonumber(goldText) or 0
	local silver = tonumber(silverText) or 0
	return math.max(0, math.floor(gold) * 10000 + math.floor(silver) * 100)
end

function SmartRez:FormatAHMoneyText(value)
	value = math.max(0, math.floor(tonumber(value) or 0))
	local gold = math.floor(value / 10000)
	local silver = math.floor((value % 10000) / 100)
	if gold > 0 then
		if silver > 0 then
			return string.format("%dg%ds", gold, silver)
		end
		return string.format("%dg", gold)
	end
	return string.format("%ds", silver)
end

function SmartRez:NormalizeAHPriceExpression(expression, fallback)
	expression = trim(expression)
	if not expression then
		return fallback or DEFAULT_PRICE_TEXT
	end

	local fixedPrice = self:ParseAHMoneyText(expression)
	if fixedPrice then
		return self:FormatAHMoneyText(fixedPrice)
	end
	return expression
end

function SmartRez:GetAHDefaultPriceExpression(itemLink, itemID, fallback)
	local recentPrice = getTSMPrice("DBRecent", itemLink, itemID)
	if recentPrice and recentPrice > 0 then
		return self:FormatAHMoneyText(recentPrice)
	end
	return fallback or DEFAULT_PRICE_TEXT
end

function SmartRez:GetAHPriceExpressionValue(expression, itemLink, itemID)
	local fixedPrice = self:ParseAHMoneyText(expression)
	if fixedPrice then
		return fixedPrice
	end
	return getTSMPrice(expression, itemLink, itemID)
end

function SmartRez:GetAHPriceDisplayText(expression)
	expression = self:NormalizeAHPriceExpression(expression)
	if not self:ParseAHMoneyText(expression) then
		return expression
	end
	return self.UI.ColorizeMoneySuffixes(expression)
end

function SmartRez:GetAHItemLinkFromLocation(location, itemID)
	if location and C_Item and C_Item.GetItemLink then
		local itemLink = C_Item.GetItemLink(location)
		if itemLink then
			return itemLink
		end
	end

	local _, itemLink = C_Item.GetItemInfo(itemID)
	return itemLink
end

function SmartRez:GetAHItemKey(location, itemID)
	if location and C_AuctionHouse and C_AuctionHouse.GetItemKeyFromItem then
		local ok, itemKey = pcall(C_AuctionHouse.GetItemKeyFromItem, location)
		if ok and type(itemKey) == "table" then
			return itemKey
		end
	end

	if C_AuctionHouse and C_AuctionHouse.MakeItemKey then
		local ok, itemKey = pcall(C_AuctionHouse.MakeItemKey, itemID)
		if ok and type(itemKey) == "table" then
			return itemKey
		end
	end
end

function SmartRez:IsAHReady()
	if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
		return false, "open the Auction House first"
	end

	if C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
		return false, "auction house throttle is not ready yet"
	end

	return true
end

function SmartRez:FindAHBagLocation(itemID)
	local foundLocation
	local foundBag
	local foundSlot
	local foundCount = 0

	self:ForEachPlayerBagSlot(function(bag, slot)
		if foundLocation then
			return
		end

		local itemInfo = C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
		if itemInfo and itemInfo.itemID == itemID then
			foundLocation = ItemLocation:CreateFromBagAndSlot(bag, slot)
			foundBag = bag
			foundSlot = slot
			foundCount = itemInfo.stackCount or 0
		end
	end)

	return foundLocation, foundBag, foundSlot, foundCount
end

function SmartRez:IsAHAuctionableLocation(location)
	if not location then
		return false
	end

	if AuctionHouseFrame and AuctionHouseFrame:IsShown() and C_AuctionHouse and C_AuctionHouse.IsSellItemValid then
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

function SmartRez:BuildAHPlayerBagSnapshot()
	local snapshot = {
		availableItemIDs = {},
		itemsByID = {},
		totalAvailableQuantity = 0,
		availableItemTypes = 0,
	}
	local seenItemIDs = {}

	self:ForEachPlayerBagSlot(function(bag, slot)
		local itemInfo = C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
		local itemID = itemInfo and itemInfo.itemID
		if not itemID then
			return
		end

		local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
		if not self:IsAHAuctionableLocation(location) then
			return
		end

		local entry = snapshot.itemsByID[itemID]
		if not entry then
			entry = {
				itemID = itemID,
				itemLink = self:GetAHItemLinkFromLocation(location, itemID),
				itemIcon = itemInfo.iconFileID,
				count = 0,
				firstBag = bag,
				firstSlot = slot,
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
	end)

	for _ in pairs(snapshot.itemsByID) do
		snapshot.availableItemTypes = snapshot.availableItemTypes + 1
	end

	return snapshot
end

function SmartRez:AddOrderedAHItem(config, itemID)
	for _, orderedItemID in ipairs(config.order or {}) do
		if orderedItemID == itemID then
			return
		end
	end
	config.order[#config.order + 1] = itemID
end

function SmartRez:RemoveOrderedAHItem(config, itemID)
	for index = #(config.order or {}), 1, -1 do
		if config.order[index] == itemID then
			table.remove(config.order, index)
		end
	end
	if #(config.order or {}) == 0 then
		config.scanCursor = 1
	elseif (config.scanCursor or 1) > #config.order then
		config.scanCursor = 1
	end
end
