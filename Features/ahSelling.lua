local SmartRez = _G.SmartRez
local C_AuctionHouse = C_AuctionHouse
local C_Container = C_Container

local BUTTON_NAME = "SmartRezAHSellButton"
local DEFAULT_MIN_PRICE_TEXT = "1g"
local DEFAULT_STACK_SIZE = 1
local DEFAULT_AUCTION_DURATION = 1
local MIN_AH_PRICE_INCREMENT = 100
local PREFIX = "Smart Rez AH Sell:"
local SCAN_TIMEOUT_SECONDS = 10
local ITEM_KEY_RETRY_SECONDS = 0.1

local ahSellingFrame = CreateFrame("Frame")
local activeScan
local preparedPost
local pendingPost
local latestScanByItemID = {}

local function isDebugEnabled()
	return SmartRez.GetDebugEnabled and SmartRez:GetDebugEnabled()
end

local SEARCH_EVENTS = {
	"COMMODITY_SEARCH_RESULTS_UPDATED",
	"ITEM_SEARCH_RESULTS_UPDATED",
	"AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
	"AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED",
	"AUCTION_HOUSE_THROTTLED_MESSAGE_SENT",
	"AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED",
	"AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
	"AUCTION_HOUSE_BROWSE_FAILURE",
	"AUCTION_HOUSE_AUCTION_CREATED",
	"AUCTION_HOUSE_POST_ERROR",
	"AUCTION_MULTISELL_UPDATE",
	"AUCTION_MULTISELL_FAILURE",
	"UI_ERROR_MESSAGE",
}

local function refreshViews()
	if SmartRez.RefreshViews then
		SmartRez:RefreshViews()
	end
end

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

local function ensureAHSellingConfig()
	SmartRez:EnsureConfig()

	if type(SmartRez.db.ahSelling) ~= "table" then
		SmartRez.db.ahSelling = {}
	end

	local config = SmartRez.db.ahSelling
	if type(config.whitelist) ~= "table" then
		config.whitelist = {}
	end
	if type(config.items) ~= "table" then
		config.items = {}
	end
	if type(config.order) ~= "table" then
		config.order = {}
	end

	local normalizedWhitelist = {}
	for itemID, selected in pairs(config.whitelist) do
		if selected then
			local numericItemID = tonumber(itemID)
			if numericItemID then
				normalizedWhitelist[numericItemID] = true
			end
		end
	end
	config.whitelist = normalizedWhitelist

	local seen = {}
	local order = {}
	for _, itemID in ipairs(config.order) do
		local numericItemID = tonumber(itemID)
		if numericItemID and config.whitelist[numericItemID] and not seen[numericItemID] then
			seen[numericItemID] = true
			order[#order + 1] = numericItemID
		end
	end
	for itemID in pairs(config.whitelist) do
		if not seen[itemID] then
			seen[itemID] = true
			order[#order + 1] = itemID
		end
	end
	config.order = order

	config.scanCursor = math.max(1, math.floor(tonumber(config.scanCursor) or 1))
	if #config.order > 0 and config.scanCursor > #config.order then
		config.scanCursor = 1
	end

	return config
end

local function addOrderedAHSellingItem(config, itemID)
	for _, orderedItemID in ipairs(config.order) do
		if orderedItemID == itemID then
			return
		end
	end
	config.order[#config.order + 1] = itemID
end

local function removeOrderedAHSellingItem(config, itemID)
	for index = #config.order, 1, -1 do
		if config.order[index] == itemID then
			table.remove(config.order, index)
		end
	end
	if #config.order == 0 then
		config.scanCursor = 1
	elseif (config.scanCursor or 1) > #config.order then
		config.scanCursor = 1
	end
end

local function advanceScanCursorFrom(index)
	local config = ensureAHSellingConfig()
	if #config.order == 0 then
		config.scanCursor = 1
		return
	end
	config.scanCursor = (index % #config.order) + 1
end

local function ensureItemConfig(itemID)
	local config = ensureAHSellingConfig()
	if type(config.items[itemID]) ~= "table" then
		config.items[itemID] = {}
	end

	local itemConfig = config.items[itemID]
	itemConfig.stackSize = math.max(1, math.floor(tonumber(itemConfig.stackSize) or DEFAULT_STACK_SIZE))
	itemConfig.minPriceExpression = trim(itemConfig.minPriceExpression)
		or trim(itemConfig.minPriceType == "tsm" and itemConfig.tsmMinPriceSource or itemConfig.fixedMinPriceText)
		or DEFAULT_MIN_PRICE_TEXT
	return itemConfig
end

local function parseMoneyText(text)
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

local function formatMoneyText(value)
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

local function normalizeMinPriceExpression(expression)
	expression = trim(expression)
	if not expression then
		return DEFAULT_MIN_PRICE_TEXT
	end

	local fixedPrice = parseMoneyText(expression)
	if fixedPrice then
		return formatMoneyText(fixedPrice)
	end
	return expression
end

local function getDefaultMinPriceExpression(itemLink, itemID)
	local recentPrice = getTSMPrice("DBRecent", itemLink, itemID)
	if recentPrice and recentPrice > 0 then
		return formatMoneyText(recentPrice)
	end
	return DEFAULT_MIN_PRICE_TEXT
end

local function getItemLinkFromLocation(location, itemID)
	if location and C_Item and C_Item.GetItemLink then
		local itemLink = C_Item.GetItemLink(location)
		if itemLink then
			return itemLink
		end
	end

	local _, itemLink = C_Item.GetItemInfo(itemID)
	return itemLink
end

local function line(...)
	print(...)
end

local function debugLine(...)
	if isDebugEnabled() then
		print(PREFIX, ...)
	end
end

local function formatMoneyColored(value, color)
	return SmartRez.UI.FormatMoneyColored(value, color)
end

local function colorText(text, color)
	return SmartRez.UI.Colorize(color, text)
end

local function refreshAHSellingScanViews()
	if SmartRez.RefreshAHSellingConfigSurfaces then
		SmartRez:RefreshAHSellingConfigSurfaces(true)
	elseif SmartRez.RefreshViews then
		SmartRez:RefreshViews()
	end
end

local function recordLatestScan(itemID, lowestPrice, minPrice)
	if not itemID then
		return
	end

	local blockedByMin = type(lowestPrice) == "number" and type(minPrice) == "number" and lowestPrice < minPrice
	latestScanByItemID[itemID] = {
		lowestPrice = lowestPrice,
		minPrice = minPrice,
		blockedByMin = blockedByMin,
		scannedAt = GetTime and GetTime() or 0,
	}
	refreshAHSellingScanViews()
end

local function formatItemKey(itemKey)
	if type(itemKey) ~= "table" then
		return tostring(itemKey)
	end

	return string.format(
		"%s/%s/%s/%s",
		tostring(itemKey.itemID),
		tostring(itemKey.itemLevel or 0),
		tostring(itemKey.itemSuffix or 0),
		tostring(itemKey.battlePetSpeciesID or 0)
	)
end

local function itemKeysMatch(left, right)
	if type(left) ~= "table" or type(right) ~= "table" then
		return false
	end

	return left.itemID == right.itemID
		and (left.itemLevel or 0) == (right.itemLevel or 0)
		and (left.itemSuffix or 0) == (right.itemSuffix or 0)
		and (left.battlePetSpeciesID or 0) == (right.battlePetSpeciesID or 0)
end

local function getItemKey(location, itemID)
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

local function getAuctionHouseReady()
	if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
		return false, "open the Auction House first"
	end

	if C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
		return false, "auction house throttle is not ready yet"
	end

	return true
end

local function stopScanUpdate()
	ahSellingFrame:SetScript("OnUpdate", nil)
end

local function clearActiveScan()
	activeScan = nil
	stopScanUpdate()
end

local function completeActiveScan()
	if activeScan then
		activeScan.completed = true
	end
	clearActiveScan()
end

local function hasActiveScanLock()
	if not activeScan then
		return false
	end

	local now = GetTime and GetTime() or 0
	local startedAt = activeScan.startedAt or now
	if now - startedAt <= SCAN_TIMEOUT_SECONDS then
		return true
	end

	debugLine("scan timeout", activeScan.itemLink or ("item:" .. tostring(activeScan.itemID)), "clearing lock")
	clearActiveScan()
	return false
end

local function getSortForScan(isCommodity)
	if isCommodity then
		return { sortOrder = 0, reverseSort = false }
	end
	return { sortOrder = 4, reverseSort = false }
end

local function findPostLocation(itemID)
	local foundLocation
	local foundBag
	local foundSlot
	local foundCount = 0

	SmartRez:ForEachPlayerBagSlot(function(bag, slot)
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

local function getCandidatePostPrice(lowestPrice, minPrice, lowestIsPlayer)
	local function normalizePostPrice(price)
		if type(price) ~= "number" then
			return nil
		end
		return math.max(MIN_AH_PRICE_INCREMENT, math.floor(price / MIN_AH_PRICE_INCREMENT) * MIN_AH_PRICE_INCREMENT)
	end

	if type(lowestPrice) ~= "number" then
		return normalizePostPrice(minPrice)
	end

	if lowestIsPlayer then
		return normalizePostPrice(lowestPrice)
	end

	local postPrice = normalizePostPrice(lowestPrice)
	if type(minPrice) == "number" and postPrice < minPrice then
		return nil
	end
	return postPrice
end

local function getPostQuantity(scan, lowestIsPlayer, frontQuantity)
	local targetQuantity = math.max(1, math.floor(tonumber(scan.stackSize) or DEFAULT_STACK_SIZE))
	local availableCount = math.max(0, math.floor(tonumber(scan.availableCount) or targetQuantity))
	local alreadyPosted = lowestIsPlayer and math.max(0, math.floor(tonumber(frontQuantity) or 0)) or 0
	local neededQuantity = math.max(0, targetQuantity - alreadyPosted)
	local availablePostCount = availableCount

	if C_AuctionHouse and C_AuctionHouse.GetAvailablePostCount then
		local ok, postCount = pcall(C_AuctionHouse.GetAvailablePostCount, scan.location)
		if ok and type(postCount) == "number" then
			availablePostCount = math.min(availablePostCount, math.max(0, math.floor(postCount)))
		end
	end

	return math.min(neededQuantity, availablePostCount), alreadyPosted, targetQuantity, availablePostCount
end

local function prepareActiveScanPost(candidatePrice, lowestIsPlayer, frontQuantity)
	if not activeScan then
		return
	end

	local quantity, alreadyPosted, targetQuantity, availablePostCount = getPostQuantity(activeScan, lowestIsPlayer, frontQuantity)
	if quantity <= 0 then
		line(
			activeScan.itemLink or ("item:" .. tostring(activeScan.itemID)),
			colorText("on top", "79C0FF"),
			colorText("x" .. tostring(alreadyPosted), "79C0FF"),
			colorText("at", "79C0FF"),
			formatMoneyColored(candidatePrice, "79C0FF")
		)
		return
	end

	local duration = activeScan.duration or DEFAULT_AUCTION_DURATION
	preparedPost = {
		itemID = activeScan.itemID,
		itemLink = activeScan.itemLink,
		location = activeScan.location,
		bag = activeScan.bag,
		slot = activeScan.slot,
		isCommodity = activeScan.isCommodity,
		duration = duration,
		quantity = quantity,
		unitPrice = candidatePrice,
	}
	debugLine(activeScan.itemLink or ("item:" .. tostring(activeScan.itemID)), "x" .. tostring(quantity), "ready at", SmartRez.UI.FormatMoney(candidatePrice), "click again")
end

local function executePreparedPost()
	if not preparedPost then
		return false
	end

	local post = preparedPost
	local location = post.location
	local bag = post.bag
	local slot = post.slot
	local foundCount
	if post.isCommodity then
		location, bag, slot, foundCount = findPostLocation(post.itemID)
	elseif post.bag and post.slot then
		location = ItemLocation:CreateFromBagAndSlot(post.bag, post.slot)
	end
	if not location then
		line(post.itemLink or ("item:" .. tostring(post.itemID)), "post failed", "item no longer found in bags")
		preparedPost = nil
		return true
	end
	debugLine("post slot", tostring(bag), tostring(slot), "count", tostring(foundCount or "?"))

	local ok, needsConfirmationOrError
	if post.isCommodity then
		pendingPost = {
			itemID = post.itemID,
			itemLink = post.itemLink,
			quantity = post.quantity,
			unitPrice = post.unitPrice,
			startedAt = GetTime and GetTime() or 0,
		}
		ok, needsConfirmationOrError = pcall(C_AuctionHouse.PostCommodity, location, post.duration, post.quantity, post.unitPrice)
	else
		pendingPost = {
			itemID = post.itemID,
			itemLink = post.itemLink,
			quantity = post.quantity,
			unitPrice = post.unitPrice,
			startedAt = GetTime and GetTime() or 0,
		}
		ok, needsConfirmationOrError = pcall(C_AuctionHouse.PostItem, location, post.duration, post.quantity, nil, post.unitPrice)
	end

	if not ok then
		line(post.itemLink or ("item:" .. tostring(post.itemID)), "post failed", tostring(needsConfirmationOrError))
		pendingPost = nil
		preparedPost = nil
		return true
	end
	debugLine("post call returned", tostring(needsConfirmationOrError), post.isCommodity and "PostCommodity" or "PostItem")

	if needsConfirmationOrError and post.isCommodity then
		if AuctionHouseFrame and AuctionHouseFrame.CommoditiesSellFrame and AuctionHouseFrame.CommoditiesSellFrame.CachePendingPost then
			pcall(AuctionHouseFrame.CommoditiesSellFrame.CachePendingPost, AuctionHouseFrame.CommoditiesSellFrame, location, post.duration, post.quantity, post.unitPrice)
		end
		debugLine("cached pending commodity post")
		debugLine("post submitted", post.itemLink or ("item:" .. tostring(post.itemID)), "qty", tostring(post.quantity), "unit", SmartRez.UI.FormatMoney(post.unitPrice))
	elseif needsConfirmationOrError then
		if post.isCommodity and AuctionHouseFrame and AuctionHouseFrame.CommoditiesSellFrame and AuctionHouseFrame.CommoditiesSellFrame.CachePendingPost then
			pcall(AuctionHouseFrame.CommoditiesSellFrame.CachePendingPost, AuctionHouseFrame.CommoditiesSellFrame, location, post.duration, post.quantity, post.unitPrice)
		elseif (not post.isCommodity) and AuctionHouseFrame and AuctionHouseFrame.ItemSellFrame and AuctionHouseFrame.ItemSellFrame.CachePendingPost then
			pcall(AuctionHouseFrame.ItemSellFrame.CachePendingPost, AuctionHouseFrame.ItemSellFrame, location, post.duration, post.quantity, nil, post.unitPrice)
		end
		debugLine("post submitted; Blizzard confirmation may be pending", post.itemLink or ("item:" .. tostring(post.itemID)), "qty", tostring(post.quantity), "unit", SmartRez.UI.FormatMoney(post.unitPrice))
	else
		debugLine("post submitted", post.itemLink or ("item:" .. tostring(post.itemID)), "qty", tostring(post.quantity), "unit", SmartRez.UI.FormatMoney(post.unitPrice))
	end
	preparedPost = nil
	return true
end

local function processCommodityScan(itemID)
	if not activeScan or activeScan.itemID ~= itemID then
		return
	end

	local resultCount = C_AuctionHouse.GetNumCommoditySearchResults(itemID)
	debugLine("commodity results", tostring(resultCount), activeScan.itemLink or ("item:" .. tostring(itemID)))
	local first = resultCount > 0 and C_AuctionHouse.GetCommoditySearchResultInfo(itemID, 1) or nil
	local lowestPrice = first and first.unitPrice or nil
	local lowestIsPlayer = first and first.containsOwnerItem and first.owners and first.owners[1] == "player"
	if first then
		debugLine("lowest", "unit", tostring(first.unitPrice), "qty", tostring(first.quantity), "owner", lowestIsPlayer and "player" or tostring(first.owners and first.owners[1]))
	end
	recordLatestScan(itemID, lowestPrice, activeScan.minPrice)

	local candidatePrice = getCandidatePostPrice(lowestPrice, activeScan.minPrice, lowestIsPlayer)
	if candidatePrice then
		debugLine("post candidate", "stack", tostring(activeScan.stackSize), "unit", SmartRez.UI.FormatMoney(candidatePrice))
		prepareActiveScanPost(candidatePrice, lowestIsPlayer, first and first.quantity)
	else
		line(activeScan.itemLink or ("item:" .. tostring(activeScan.itemID)), colorText("below min", "FF7B72"))
	end
	completeActiveScan()
end

local function processItemScan(itemKey)
	if not activeScan or not itemKeysMatch(activeScan.itemKey, itemKey) then
		return
	end

	local resultCount = C_AuctionHouse.GetNumItemSearchResults(itemKey)
	debugLine("item results", tostring(resultCount), activeScan.itemLink or ("item:" .. tostring(activeScan.itemID)), "key", formatItemKey(itemKey))
	local first = resultCount > 0 and C_AuctionHouse.GetItemSearchResultInfo(itemKey, 1) or nil
	local lowestPrice = first and (first.buyoutAmount or first.bidAmount) or nil
	local lowestIsPlayer = first and first.owners and first.owners[1] == "player"
	if first then
		debugLine("lowest", "buyout", tostring(first.buyoutAmount), "bid", tostring(first.bidAmount), "qty", tostring(first.quantity), "owner", lowestIsPlayer and "player" or tostring(first.owners and first.owners[1]), "auctionID", tostring(first.auctionID))
	end
	recordLatestScan(activeScan.itemID, lowestPrice, activeScan.minPrice)

	local candidatePrice = getCandidatePostPrice(lowestPrice, activeScan.minPrice, lowestIsPlayer)
	if candidatePrice then
		debugLine("post candidate", "stack", tostring(activeScan.stackSize), "unit", SmartRez.UI.FormatMoney(candidatePrice))
		prepareActiveScanPost(candidatePrice, lowestIsPlayer, first and first.quantity)
	else
		line(activeScan.itemLink or ("item:" .. tostring(activeScan.itemID)), colorText("below min", "FF7B72"))
	end
	completeActiveScan()
end

local function ensureScanEvents()
	for _, eventName in ipairs(SEARCH_EVENTS) do
		pcall(ahSellingFrame.RegisterEvent, ahSellingFrame, eventName)
	end
end

local function attemptActiveScanSearch()
	if not activeScan then
		stopScanUpdate()
		return
	end

	local now = GetTime and GetTime() or 0
	if now - (activeScan.startedAt or now) > SCAN_TIMEOUT_SECONDS then
		debugLine("scan timeout", activeScan.itemLink or ("item:" .. tostring(activeScan.itemID)), "clearing lock")
		clearActiveScan()
		return
	end

	if (activeScan.nextAttemptAt or 0) > now then
		return
	end
	activeScan.nextAttemptAt = now + ITEM_KEY_RETRY_SECONDS

	if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
		if not activeScan.throttleWaitLogged then
			debugLine("waiting", "auction house throttle")
			activeScan.throttleWaitLogged = true
		end
		ahSellingFrame:SetScript("OnUpdate", attemptActiveScanSearch)
		return
	end

	if C_AuctionHouse.GetItemKeyInfo and not C_AuctionHouse.GetItemKeyInfo(activeScan.itemKey) then
		if not activeScan.itemKeyWaitLogged then
			debugLine("waiting", "item key info", formatItemKey(activeScan.itemKey))
			activeScan.itemKeyWaitLogged = true
		end
		ahSellingFrame:SetScript("OnUpdate", attemptActiveScanSearch)
		return
	end

	stopScanUpdate()
	local sort = getSortForScan(activeScan.isCommodity)
	local ok, err
	if activeScan.isCommodity then
		ok, err = pcall(C_AuctionHouse.SendSearchQuery, activeScan.itemKey, { sort }, true)
	else
		ok, err = pcall(C_AuctionHouse.SendSellSearchQuery, activeScan.itemKey, { sort }, true)
		if not ok then
			line("SendSellSearchQuery failed; trying SendSearchQuery", tostring(err))
			ok, err = pcall(C_AuctionHouse.SendSearchQuery, activeScan.itemKey, { sort }, true)
		end
	end

	if ok then
		activeScan.searchSent = true
	else
		line("search failed", tostring(err))
		clearActiveScan()
	end
end

function SmartRez:GetAHSellingConfig()
	return ensureAHSellingConfig()
end

function SmartRez:GetAHSellingWhitelist()
	return ensureAHSellingConfig().whitelist
end

function SmartRez:GetAHSellingOrderedItemIDs()
	return ensureAHSellingConfig().order
end

function SmartRez:GetAHSellingItemConfig(itemID)
	return ensureItemConfig(itemID)
end

function SmartRez:AddAHSellingWhitelistItem(itemID, skipRefresh)
	if not itemID then
		return
	end

	local config = ensureAHSellingConfig()
	config.whitelist[itemID] = true
	addOrderedAHSellingItem(config, itemID)
	local itemConfig = ensureItemConfig(itemID)
	if itemConfig.minPriceExpression == DEFAULT_MIN_PRICE_TEXT then
		itemConfig.minPriceExpression = getDefaultMinPriceExpression(nil, itemID)
	end
	if not skipRefresh then
		refreshViews()
	end
end

function SmartRez:RemoveAHSellingWhitelistItem(itemID, skipRefresh)
	local config = ensureAHSellingConfig()
	config.whitelist[itemID] = nil
	config.items[itemID] = nil
	removeOrderedAHSellingItem(config, itemID)
	if not skipRefresh then
		refreshViews()
	end
end

function SmartRez:SetAHSellingItemConfigValue(itemID, key, value, skipRefresh)
	local itemConfig = ensureItemConfig(itemID)

	if key == "stackSize" then
		itemConfig[key] = math.max(1, math.floor(tonumber(value) or itemConfig[key] or 1))
	elseif key == "minPriceExpression" then
		itemConfig.minPriceExpression = normalizeMinPriceExpression(value)
	end

	if not skipRefresh then
		refreshViews()
	end
end

function SmartRez:IsAHSellingItemAuctionable(location)
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

function SmartRez:BuildAHSellingSnapshot()
	local config = ensureAHSellingConfig()
	local whitelist = config.whitelist
	local snapshot = {
		isTSMAvailable = _G.TSM_API ~= nil,
		hasSelection = next(whitelist) ~= nil,
		availableItemIDs = {},
		itemsByID = {},
		totalAvailableQuantity = 0,
		availableItemTypes = 0,
		selectedItemTypes = 0,
	}
	local seenItemIDs = {}

	self:ForEachPlayerBagSlot(function(bag, slot)
		local itemInfo = C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
		local itemID = itemInfo and itemInfo.itemID
		if not itemID then
			return
		end

		local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
		if not self:IsAHSellingItemAuctionable(location) then
			return
		end

		local entry = snapshot.itemsByID[itemID]
		if not entry then
			entry = {
				itemID = itemID,
				itemLink = getItemLinkFromLocation(location, itemID),
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

	for itemID, entry in pairs(snapshot.itemsByID) do
		snapshot.availableItemTypes = snapshot.availableItemTypes + 1
		if whitelist[itemID] and entry.count > 0 then
			snapshot.selectedItemTypes = snapshot.selectedItemTypes + 1
		end
	end

	return snapshot
end

function SmartRez:GetAHSellingItemMinPrice(itemID, itemLink)
	local itemConfig = ensureItemConfig(itemID)
	local expression = itemConfig.minPriceExpression
	local fixedPrice = parseMoneyText(expression)
	if fixedPrice then
		return fixedPrice
	end
	return getTSMPrice(expression, itemLink, itemID)
end

function SmartRez:GetAHSellingMinPriceDisplayText(expression)
	expression = normalizeMinPriceExpression(expression)
	if not parseMoneyText(expression) then
		return expression
	end

	return SmartRez.UI.ColorizeMoneySuffixes(expression)
end

function SmartRez:GetAHSellingLatestScanDisplayText(itemID)
	local scan = latestScanByItemID[itemID]
	if not scan or type(scan.lowestPrice) ~= "number" then
		return ""
	end

	return formatMoneyColored(scan.lowestPrice, scan.blockedByMin and "FF7B72" or "7EE787")
end

function SmartRez:PrintAHSellingNextAction()
	local snapshot = self:BuildAHSellingSnapshot()
	local orderedItemIDs = self:GetAHSellingOrderedItemIDs()

	if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
		print("AH Sell: open the Auction House before posting.")
		return
	end

	if C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
		print("AH Sell: auction house throttle is not ready yet.")
		return
	end

	for _, itemID in ipairs(orderedItemIDs) do
		local entry = snapshot.itemsByID[itemID]
		if entry and entry.count > 0 then
			local itemConfig = ensureItemConfig(itemID)
			local minPrice, priceError = self:GetAHSellingItemMinPrice(itemID, entry.itemLink)
			print(string.format(
				"AH Sell: next configured item %s, bag %d slot %d, stack %d, min %s.",
				entry.itemLink or ("item:" .. tostring(itemID)),
				entry.firstBag or 0,
				entry.firstSlot or 0,
				itemConfig.stackSize or 1,
				minPrice and formatMoneyColored(minPrice) or "unresolved"
			))
			if not minPrice and priceError then
				print("AH Sell: min price error: " .. tostring(priceError))
			end
			return
		end
	end

	print("AH Sell: no configured auctionable item found in player bags.")
end

function SmartRez:GetNextAHSellingCandidate()
	local snapshot = self:BuildAHSellingSnapshot()
	local config = ensureAHSellingConfig()
	local orderedItemIDs = config.order
	local itemCount = #orderedItemIDs
	if itemCount == 0 then
		return nil
	end

	local startIndex = math.min(math.max(1, config.scanCursor or 1), itemCount)
	for offset = 0, itemCount - 1 do
		local index = ((startIndex + offset - 1) % itemCount) + 1
		local itemID = orderedItemIDs[index]
		local entry = snapshot.itemsByID[itemID]
		if entry and entry.count > 0 then
			local location = ItemLocation:CreateFromBagAndSlot(entry.firstBag, entry.firstSlot)
			local itemConfig = ensureItemConfig(itemID)
			local minPrice, priceError = self:GetAHSellingItemMinPrice(itemID, entry.itemLink)
			local itemKey = getItemKey(location, itemID)
			local ok, commodityStatus = pcall(C_AuctionHouse.GetItemCommodityStatus, location)
			return {
				itemID = itemID,
				itemLink = entry.itemLink,
				location = location,
				bag = entry.firstBag,
				slot = entry.firstSlot,
				itemKey = itemKey,
				stackSize = itemConfig.stackSize or 1,
				availableCount = entry.count or 0,
				minPrice = minPrice,
				priceError = priceError,
				isCommodity = ok and commodityStatus == Enum.ItemCommodityStatus.Commodity,
				scanIndex = index,
			}
		end
	end
end

function SmartRez:ScanAHSellingNextItem(allowPreparedPost)
	if allowPreparedPost and executePreparedPost() then
		return
	end
	if preparedPost then
		line("blocked", "post is prepared; click AH Sell again")
		return
	end

	if hasActiveScanLock() then
		debugLine("blocked", "scan already in progress")
		return
	end

	local ready, reason = getAuctionHouseReady()
	if not ready then
		debugLine("blocked", reason)
		return
	end

	local candidate = self:GetNextAHSellingCandidate()
	if not candidate then
		line("blocked", "no configured auctionable item found in player bags")
		return
	end
	if not candidate.itemKey then
		line("blocked", "could not build item key for", candidate.itemLink or ("item:" .. tostring(candidate.itemID)))
		advanceScanCursorFrom(candidate.scanIndex or 1)
		return
	end
	if not candidate.minPrice then
		line("blocked", "min price error", tostring(candidate.priceError))
		advanceScanCursorFrom(candidate.scanIndex or 1)
		return
	end

	ensureScanEvents()
	activeScan = candidate
	activeScan.startedAt = GetTime and GetTime() or 0
	advanceScanCursorFrom(candidate.scanIndex or 1)
	debugLine("scan start", candidate.itemLink or ("item:" .. tostring(candidate.itemID)), "key", formatItemKey(candidate.itemKey), "commodity", tostring(candidate.isCommodity), "min", SmartRez.UI.FormatMoney(candidate.minPrice), "stack", tostring(candidate.stackSize))

	attemptActiveScanSearch()
end

local function isActiveClickPhase(down)
	local useKeyDown = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
	if useKeyDown then
		return down == true
	end
	return down ~= true
end

local sellButton = CreateFrame("Button", BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
sellButton:RegisterForClicks("AnyUp", "AnyDown")
sellButton:SetScript("OnClick", function(_, _, down)
	if preparedPost then
		if down == true then
			return
		end
		SmartRez:ScanAHSellingNextItem(true)
		return
	end

	if not isActiveClickPhase(down) then
		return
	end

	SmartRez:ScanAHSellingNextItem(false)
end)

ahSellingFrame:SetScript("OnEvent", function(_, eventName, ...)
	if eventName == "COMMODITY_SEARCH_RESULTS_UPDATED" then
		processCommodityScan(...)
	elseif eventName == "ITEM_SEARCH_RESULTS_UPDATED" then
		processItemScan(...)
	elseif eventName == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
		debugLine("throttle ready")
	elseif eventName == "AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED" then
		debugLine("throttle queued", tostring(select(1, ...)), tostring(select(2, ...)))
	elseif eventName == "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT" then
		debugLine("throttle sent", tostring(select(1, ...)), tostring(select(2, ...)))
	elseif eventName == "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED" then
		debugLine("throttle response", tostring(select(1, ...)), tostring(select(2, ...)))
	elseif (eventName == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" or eventName == "AUCTION_HOUSE_BROWSE_FAILURE") and activeScan then
		line("search failed", eventName)
		clearActiveScan()
	elseif eventName == "AUCTION_HOUSE_AUCTION_CREATED" and pendingPost then
		line(
			pendingPost.itemLink or ("item:" .. tostring(pendingPost.itemID)),
			colorText("x" .. tostring(pendingPost.quantity), "7EE787"),
			colorText("posted at", "7EE787"),
			formatMoneyColored(pendingPost.unitPrice or 0, "7EE787")
		)
		pendingPost = nil
	elseif eventName == "AUCTION_MULTISELL_UPDATE" and pendingPost then
		debugLine("multisell update", pendingPost.itemLink or ("item:" .. tostring(pendingPost.itemID)), tostring(select(1, ...)), tostring(select(2, ...)))
	elseif (eventName == "AUCTION_HOUSE_POST_ERROR" or eventName == "AUCTION_MULTISELL_FAILURE") and pendingPost then
		line(pendingPost.itemLink or ("item:" .. tostring(pendingPost.itemID)), "post failed", eventName)
		pendingPost = nil
	elseif eventName == "UI_ERROR_MESSAGE" and pendingPost then
		line(pendingPost.itemLink or ("item:" .. tostring(pendingPost.itemID)), "post error", tostring(select(2, ...)))
		pendingPost = nil
	elseif eventName == "UI_ERROR_MESSAGE" then
		debugLine("ui error", tostring(select(1, ...)), tostring(select(2, ...)))
	end
end)

SmartRez:RegisterBindableAction({
	key = "ahsell",
	label = "AH Sell",
	buttonName = BUTTON_NAME,
	order = 590,
})
