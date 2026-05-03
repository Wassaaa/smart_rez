local SmartRez = _G.SmartRez
local C_AuctionHouse = C_AuctionHouse

local BUTTON_NAME = "SmartRezAHSnipeButton"
local DEFAULT_PRICE_TEXT = "1g"
local DEFAULT_BUY_STACK_SIZE = 1
local DEFAULT_BAIT_STACK_SIZE = 0
local DEFAULT_BAIT_INTERVAL_SECONDS = 30
local DEFAULT_AUCTION_DURATION = 1
local SCAN_TIMEOUT_SECONDS = 10
local BULK_SCAN_TIMEOUT_SECONDS = 5
local WARNING_REFRESH_TIMEOUT_SECONDS = 30
local ITEM_KEY_RETRY_SECONDS = 0.2
local PREFIX = "Smart Rez AH Snipe:"

local ahSniperFrame = CreateFrame("Frame")
local pendingBuy
local pendingBait
local bulkOpportunity
local bulkScan
local pendingBulkBuy
local warningRefresh
local lastBaitByItemID = {}
local latestScanByItemID = {}
local latestWarningByItemID = {}

local SEARCH_EVENTS = {
	"COMMODITY_PRICE_UPDATED",
	"COMMODITY_PRICE_UNAVAILABLE",
	"COMMODITY_SEARCH_RESULTS_UPDATED",
	"ITEM_SEARCH_RESULTS_UPDATED",
	"COMMODITY_PURCHASE_SUCCEEDED",
	"COMMODITY_PURCHASE_FAILED",
	"AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
	"AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
	"AUCTION_HOUSE_BROWSE_FAILURE",
	"AUCTION_HOUSE_AUCTION_CREATED",
	"AUCTION_HOUSE_POST_ERROR",
	"UI_ERROR_MESSAGE",
}

local function isDebugEnabled()
	return SmartRez.GetDebugEnabled and SmartRez:GetDebugEnabled()
end

local function line(...)
	print(...)
end

local function colorText(text, color)
	return SmartRez.UI.Colorize(color, text)
end

local function actionLine(itemLink, color, ...)
	local parts = {}
	for index = 1, select("#", ...) do
		local part = tostring(select(index, ...))
		if part:find("|c", 1, true) then
			parts[#parts + 1] = part
		else
			parts[#parts + 1] = colorText(part, color)
		end
	end
	line(itemLink or "item:?", table.concat(parts, colorText(" ", color)))
end

local function debugLine(...)
	if isDebugEnabled() then
		print(PREFIX, ...)
	end
end

local function money(value, color)
	return SmartRez.UI.FormatMoneyColored(value, color)
end

local function capText(value)
	return colorText("cap ", "7D8590") .. money(value, "FFD866")
end

local function refreshViews()
	if SmartRez.RefreshViews then
		SmartRez:RefreshViews()
	end
end

local function actionResult(status, consumedThrottle)
	return {
		status = status,
		consumedThrottle = consumedThrottle == true,
	}
end

local function ensureAHSniperConfig()
	SmartRez:EnsureConfig()
	if type(SmartRez.db.ahSniper) ~= "table" then
		SmartRez.db.ahSniper = {}
	end

	local config = SmartRez.db.ahSniper
	config.whitelist = type(config.whitelist) == "table" and config.whitelist or {}
	config.items = type(config.items) == "table" and config.items or {}
	config.order = type(config.order) == "table" and config.order or {}

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

local function ensureItemConfig(itemID)
	local config = ensureAHSniperConfig()
	if type(config.items[itemID]) ~= "table" then
		config.items[itemID] = {}
	end

	local itemConfig = config.items[itemID]
	itemConfig.buyStackSize = math.max(1, math.floor(tonumber(itemConfig.buyStackSize) or DEFAULT_BUY_STACK_SIZE))
	itemConfig.buyPriceExpression = SmartRez:NormalizeAHPriceExpression(itemConfig.buyPriceExpression, DEFAULT_PRICE_TEXT)
	itemConfig.baitStackSize = math.max(0, math.floor(tonumber(itemConfig.baitStackSize) or DEFAULT_BAIT_STACK_SIZE))
	itemConfig.baitPriceExpression = SmartRez:NormalizeAHPriceExpression(itemConfig.baitPriceExpression, DEFAULT_PRICE_TEXT)
	itemConfig.baitIntervalSeconds = math.max(1, math.floor(tonumber(itemConfig.baitIntervalSeconds) or DEFAULT_BAIT_INTERVAL_SECONDS))
	itemConfig.baitKeepInBags = math.max(0, math.floor(tonumber(itemConfig.baitKeepInBags) or 0))
	return itemConfig
end

local function advanceScanCursorFrom(index)
	local config = ensureAHSniperConfig()
	if #config.order == 0 then
		config.scanCursor = 1
		return
	end
	config.scanCursor = (index % #config.order) + 1
end

local function hasPendingBuyLock()
	if not pendingBuy then
		return false
	end

	local now = GetTime and GetTime() or 0
	if now - (pendingBuy.startedAt or now) <= SCAN_TIMEOUT_SECONDS then
		return true
	end

	debugLine("buy timeout", pendingBuy.itemLink or ("item:" .. tostring(pendingBuy.itemID)), "clearing lock")
	pcall(C_AuctionHouse.CancelCommoditiesPurchase)
	pendingBuy = nil
	return false
end

local function hasPendingBaitLock()
	if not pendingBait then
		return false
	end

	local now = GetTime and GetTime() or 0
	if now - (pendingBait.startedAt or now) <= SCAN_TIMEOUT_SECONDS then
		return true
	end

	debugLine("bait timeout", pendingBait.itemLink or ("item:" .. tostring(pendingBait.itemID)), "clearing lock")
	pendingBait = nil
	return false
end

local function hasBulkScanLock()
	if not bulkScan then
		return false
	end

	local now = GetTime and GetTime() or 0
	if now - (bulkScan.startedAt or now) <= BULK_SCAN_TIMEOUT_SECONDS then
		return true
	end

	debugLine("bulk scan timeout", bulkScan.itemLink or ("item:" .. tostring(bulkScan.itemID)), "clearing")
	bulkScan = nil
	return false
end

local function ensureEvents()
	for _, eventName in ipairs(SEARCH_EVENTS) do
		pcall(ahSniperFrame.RegisterEvent, ahSniperFrame, eventName)
	end
end

local function buildBuyRequest(candidate)
	return {
		itemID = candidate.itemID,
		itemLink = candidate.itemLink,
		quantity = candidate.buyStackSize,
		maxUnitPrice = candidate.buyPrice,
		maxTotal = candidate.buyPrice * candidate.buyStackSize,
		bulkMode = candidate.bulkMode == true,
		startedAt = GetTime and GetTime() or 0,
	}
end

local function getItemKey(itemID)
	if C_AuctionHouse and C_AuctionHouse.MakeItemKey then
		local ok, itemKey = pcall(C_AuctionHouse.MakeItemKey, itemID)
		if ok and type(itemKey) == "table" then
			return itemKey
		end
	end
end

local function clearBulkState()
	bulkOpportunity = nil
	bulkScan = nil
	pendingBulkBuy = nil
end

local function priceWarningThreshold(unitPrice)
	if _G.Auctionator
		and Auctionator.Utilities
		and Auctionator.Utilities.PriceWarningThreshold
	then
		local ok, threshold = pcall(Auctionator.Utilities.PriceWarningThreshold, unitPrice)
		if ok and type(threshold) == "number" then
			return threshold
		end
	end

	if unitPrice == 0 then
		return 0
	end

	local multiplier = 0.3 + 0.4 * math.min(1, 10000 / unitPrice)
	return unitPrice * multiplier
end

local function calculateCommodityWarningFromResults(itemID)
	local totalQuantity = C_AuctionHouse.GetCommoditySearchResultsQuantity
		and C_AuctionHouse.GetCommoditySearchResultsQuantity(itemID)
		or 0
	local targetQuantity = math.min(5000, math.floor(totalQuantity * 0.2))
	local runningQuantity = 0

	for index = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemID) do
		local result = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, index)
		if result then
			runningQuantity = runningQuantity + (result.quantity or 0)
			if runningQuantity >= targetQuantity then
				local referencePrice = tonumber(result.unitPrice)
				if referencePrice and referencePrice > 0 then
					return math.floor(priceWarningThreshold(referencePrice)), referencePrice, targetQuantity, totalQuantity
				end
			end
		end
	end
end

local function clearWarningRefresh()
	warningRefresh = nil
	ahSniperFrame:SetScript("OnUpdate", nil)
end

local function completeWarningRefresh()
	local completed = warningRefresh and warningRefresh.completed or 0
	clearWarningRefresh()
	line("Smart Rez AH Snipe:", colorText("bait warning refresh complete", "7EE787"), colorText(tostring(completed) .. " item(s)", "7D8590"))
	if SmartRez.RefreshAHSniperConfigSurfaces then
		SmartRez:RefreshAHSniperConfigSurfaces(true)
	end
end

local function failWarningRefresh(reason)
	local itemLink = warningRefresh and warningRefresh.activeItemLink or nil
	line("Smart Rez AH Snipe:", colorText("bait warning refresh stopped", "FF7B72"), itemLink or "", colorText(reason or "failed", "FF7B72"))
	clearWarningRefresh()
end

local function recordLatestScan(itemID, quote, maxPrice)
	if not itemID then
		return
	end

	latestScanByItemID[itemID] = {
		averageUnitPrice = quote and quote.averageUnitPrice or nil,
		maxPrice = maxPrice,
		quantity = quote and quote.quantity or nil,
		buyable = quote and type(maxPrice) == "number" and quote.averageUnitPrice <= maxPrice or false,
		scannedAt = GetTime and GetTime() or 0,
	}

	if SmartRez.RefreshAHSniperConfigSurfaces then
		SmartRez:RefreshAHSniperConfigSurfaces(true)
	end
end

local function startBuyRequest(buy, source)
	local ready, reason = SmartRez:IsAHReady()
	if not ready then
		debugLine("blocked buy", reason)
		return actionResult("blocked")
	end

	ensureEvents()
	pendingBuy = {
		itemID = buy.itemID,
		itemLink = buy.itemLink,
		quantity = buy.quantity,
		maxUnitPrice = buy.maxUnitPrice,
		maxTotal = buy.maxTotal,
		bulkMode = buy.bulkMode == true,
		startedAt = GetTime and GetTime() or 0,
	}

	local ok, err = pcall(C_AuctionHouse.StartCommoditiesPurchase, buy.itemID, buy.quantity)
	if not ok then
		actionLine(buy.itemLink or ("item:" .. tostring(buy.itemID)), "FF7B72", "buy failed", tostring(err))
		pendingBuy = nil
		return actionResult("failed")
	end

	debugLine("purchase quote requested", buy.itemLink or ("item:" .. tostring(buy.itemID)), source or "direct", "x" .. tostring(buy.quantity), "cap", SmartRez.UI.FormatMoney(buy.maxUnitPrice))
	return actionResult(buy.bulkMode and "startedBulkBuy" or "startedBuy", true)
end

local function startBulkScan()
	if not bulkOpportunity then
		return nil
	end

	local ready, reason = SmartRez:IsAHReady()
	if not ready then
		debugLine("blocked bulk scan", reason)
		return actionResult("blocked")
	end

	local itemKey = getItemKey(bulkOpportunity.itemID)
	if not itemKey then
		debugLine("bulk scan skipped no item key", bulkOpportunity.itemLink or ("item:" .. tostring(bulkOpportunity.itemID)))
		clearBulkState()
		return actionResult("failed")
	end

	ensureEvents()
	bulkScan = {
		itemID = bulkOpportunity.itemID,
		itemLink = bulkOpportunity.itemLink,
		itemKey = itemKey,
		maxUnitPrice = bulkOpportunity.maxUnitPrice,
		configuredStackSize = bulkOpportunity.configuredStackSize,
		startedAt = GetTime and GetTime() or 0,
	}

	local ok, err = pcall(C_AuctionHouse.SendSearchQuery, itemKey, { { sortOrder = 0, reverseSort = false } }, true)
	if not ok then
		debugLine("bulk scan failed", tostring(err))
		clearBulkState()
		return actionResult("failed")
	end

	debugLine("bulk scan sent", bulkScan.itemLink or ("item:" .. tostring(bulkScan.itemID)), "cap", SmartRez.UI.FormatMoney(bulkScan.maxUnitPrice))
	return actionResult("bulkScanStarted", true)
end

local function startPendingBulkBuy()
	if not pendingBulkBuy then
		return nil
	end

	local buy = pendingBulkBuy
	pendingBulkBuy = nil
	return startBuyRequest({
		itemID = buy.itemID,
		itemLink = buy.itemLink,
		quantity = buy.quantity,
		maxUnitPrice = buy.maxUnitPrice,
		maxTotal = buy.maxUnitPrice * buy.quantity,
		bulkMode = true,
	}, "bulk")
end

local function pumpWarningRefresh()
	if not warningRefresh then
		ahSniperFrame:SetScript("OnUpdate", nil)
		return
	end

	local now = GetTime and GetTime() or 0
	if now - (warningRefresh.startedAt or now) > WARNING_REFRESH_TIMEOUT_SECONDS then
		failWarningRefresh("timeout")
		return
	end

	if warningRefresh.activeItemID then
		return
	end

	if (warningRefresh.nextAttemptAt or 0) > now then
		return
	end
	warningRefresh.nextAttemptAt = now + ITEM_KEY_RETRY_SECONDS

	if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
		return
	end

	local itemID = warningRefresh.queue[warningRefresh.index]
	if not itemID then
		completeWarningRefresh()
		return
	end

	local itemKey = getItemKey(itemID)
	if C_AuctionHouse.GetItemKeyInfo and itemKey and not C_AuctionHouse.GetItemKeyInfo(itemKey) then
		return
	end

	if not itemKey then
		latestWarningByItemID[itemID] = {
			error = "no item key",
			scannedAt = now,
		}
		warningRefresh.index = warningRefresh.index + 1
		warningRefresh.nextAttemptAt = now
		return
	end

	warningRefresh.activeItemID = itemID
	warningRefresh.activeItemLink = select(2, C_Item.GetItemInfo(itemID)) or ("item:" .. tostring(itemID))
	local ok, err = pcall(C_AuctionHouse.SendSearchQuery, itemKey, { { sortOrder = 0, reverseSort = false } }, true)
	if not ok then
		latestWarningByItemID[itemID] = {
			error = tostring(err),
			scannedAt = now,
		}
		warningRefresh.activeItemID = nil
		warningRefresh.activeItemLink = nil
		warningRefresh.index = warningRefresh.index + 1
		warningRefresh.nextAttemptAt = now
		return
	end

	debugLine("bait warning scan sent", warningRefresh.activeItemLink, tostring(warningRefresh.index) .. "/" .. tostring(#warningRefresh.queue))
end

local function processWarningRefreshResults(itemID)
	if not warningRefresh or warningRefresh.activeItemID ~= itemID then
		return
	end

	local warningPrice, referencePrice, targetQuantity, totalQuantity = calculateCommodityWarningFromResults(itemID)
	latestWarningByItemID[itemID] = {
		warningPrice = warningPrice,
		referencePrice = referencePrice,
		targetQuantity = targetQuantity,
		totalQuantity = totalQuantity,
		scannedAt = GetTime and GetTime() or 0,
		error = warningPrice and nil or "no commodity results",
	}
	warningRefresh.completed = (warningRefresh.completed or 0) + (warningPrice and 1 or 0)

	debugLine(
		"bait warning result",
		warningRefresh.activeItemLink or ("item:" .. tostring(itemID)),
		"warn", warningPrice and SmartRez.UI.FormatMoney(warningPrice) or "nil",
		"ref", referencePrice and SmartRez.UI.FormatMoney(referencePrice) or "nil",
		"target", tostring(targetQuantity or "nil"),
		"total", tostring(totalQuantity or "nil")
	)

	warningRefresh.activeItemID = nil
	warningRefresh.activeItemLink = nil
	warningRefresh.index = warningRefresh.index + 1
	warningRefresh.nextAttemptAt = GetTime and GetTime() or 0

	if SmartRez.RefreshAHSniperConfigSurfaces then
		SmartRez:RefreshAHSniperConfigSurfaces(true)
	end

	pumpWarningRefresh()
end

local function processWarningRefreshItemResults(itemKey)
	if not warningRefresh or not warningRefresh.activeItemID then
		return
	end

	local itemID = warningRefresh.activeItemID
	if type(itemKey) == "table" and itemKey.itemID and itemKey.itemID ~= itemID then
		return
	end

	latestWarningByItemID[itemID] = {
		error = "not commodity",
		scannedAt = GetTime and GetTime() or 0,
	}
	debugLine("bait warning skipped non-commodity", warningRefresh.activeItemLink or ("item:" .. tostring(itemID)))

	warningRefresh.activeItemID = nil
	warningRefresh.activeItemLink = nil
	warningRefresh.index = warningRefresh.index + 1
	warningRefresh.nextAttemptAt = GetTime and GetTime() or 0

	if SmartRez.RefreshAHSniperConfigSurfaces then
		SmartRez:RefreshAHSniperConfigSurfaces(true)
	end

	pumpWarningRefresh()
end

local function tryPostBait(candidate)
	ensureEvents()
	local baitStackSize = math.max(0, math.floor(tonumber(candidate.baitStackSize) or 0))
	if baitStackSize <= 0 then
		return nil
	end

	local now = GetTime and GetTime() or 0
	local interval = math.max(1, math.floor(tonumber(candidate.baitIntervalSeconds) or DEFAULT_BAIT_INTERVAL_SECONDS))
	if (lastBaitByItemID[candidate.itemID] or 0) + interval > now then
		return nil
	end

	local location = SmartRez:FindAHBagLocation(candidate.itemID)
	if not location then
		debugLine("bait skipped no bag item", candidate.itemLink or ("item:" .. tostring(candidate.itemID)))
		return nil
	end

	local ok, err = pcall(C_AuctionHouse.PostCommodity, location, DEFAULT_AUCTION_DURATION, baitStackSize, candidate.baitPrice)
	if not ok then
		actionLine(candidate.itemLink or ("item:" .. tostring(candidate.itemID)), "FF7B72", "bait failed", tostring(err))
		return actionResult("failed")
	end

	pendingBait = {
		itemID = candidate.itemID,
		itemLink = candidate.itemLink,
		quantity = baitStackSize,
		unitPrice = candidate.baitPrice,
		startedAt = now,
	}
	lastBaitByItemID[candidate.itemID] = now
	debugLine("bait sent", candidate.itemLink or ("item:" .. tostring(candidate.itemID)), "x" .. tostring(baitStackSize), SmartRez.UI.FormatMoney(candidate.baitPrice))
	return actionResult("postedBait", true)
end

local function processBuyPriceUpdated(unitPrice, totalPrice)
	if not pendingBuy then
		return
	end

	local averageUnitPrice = type(totalPrice) == "number"
		and math.ceil(totalPrice / math.max(1, pendingBuy.quantity) / 100) * 100
		or unitPrice
	recordLatestScan(pendingBuy.itemID, {
		quantity = pendingBuy.quantity,
		total = totalPrice,
		averageUnitPrice = averageUnitPrice,
		highestUnitPrice = unitPrice,
	}, pendingBuy.maxUnitPrice)

	if type(totalPrice) == "number" and totalPrice <= pendingBuy.maxTotal then
		pendingBuy.confirmedUnitPrice = averageUnitPrice or unitPrice
		pendingBuy.confirmedTotalPrice = totalPrice
		local ok, err = pcall(C_AuctionHouse.ConfirmCommoditiesPurchase, pendingBuy.itemID, pendingBuy.quantity)
		if ok then
			debugLine("buy confirmed", pendingBuy.itemLink or ("item:" .. tostring(pendingBuy.itemID)), "x" .. tostring(pendingBuy.quantity), SmartRez.UI.FormatMoney(averageUnitPrice or unitPrice or 0))
		else
			actionLine(pendingBuy.itemLink or ("item:" .. tostring(pendingBuy.itemID)), "FF7B72", "buy failed", tostring(err))
			pendingBuy = nil
		end
	else
		pcall(C_AuctionHouse.CancelCommoditiesPurchase)
		line(
			pendingBuy.itemLink or ("item:" .. tostring(pendingBuy.itemID)),
			colorText("too high ", "FF7B72")
				.. money(averageUnitPrice or unitPrice or 0, "FF7B72")
				.. colorText("  >  ", "7D8590")
				.. capText(pendingBuy.maxUnitPrice)
		)
		pendingBuy = nil
	end
end

local function processBulkSearchResults(itemID)
	if not bulkScan or bulkScan.itemID ~= itemID then
		return
	end

	local scan = bulkScan
	bulkScan = nil
	local resultCount = C_AuctionHouse.GetNumCommoditySearchResults and C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0
	local first = resultCount > 0 and C_AuctionHouse.GetCommoditySearchResultInfo(itemID, 1) or nil
	local unitPrice = first and tonumber(first.unitPrice) or nil
	local quantity = first and math.max(0, math.floor(tonumber(first.quantity) or 0)) or 0
	if not unitPrice or unitPrice <= 0 or quantity <= 0 then
		debugLine("bulk scan empty", scan.itemLink or ("item:" .. tostring(itemID)))
		clearBulkState()
		return
	end

	if unitPrice > scan.maxUnitPrice then
		debugLine("bulk skipped", scan.itemLink or ("item:" .. tostring(itemID)), "unit", SmartRez.UI.FormatMoney(unitPrice), "cap", SmartRez.UI.FormatMoney(scan.maxUnitPrice))
		clearBulkState()
		return
	end

	if quantity <= math.max(1, math.floor(tonumber(scan.configuredStackSize) or 1)) then
		debugLine("bulk skipped small stack", scan.itemLink or ("item:" .. tostring(itemID)), "x" .. tostring(quantity))
		clearBulkState()
		return
	end

	local moneyAvailable = GetMoney and GetMoney() or 0
	local affordableQuantity = math.floor(moneyAvailable / unitPrice)
	local buyQuantity = math.min(quantity, affordableQuantity)
	if buyQuantity <= math.max(1, math.floor(tonumber(scan.configuredStackSize) or 1)) then
		debugLine("bulk skipped gold", scan.itemLink or ("item:" .. tostring(itemID)), "x" .. tostring(quantity), "unit", SmartRez.UI.FormatMoney(unitPrice))
		clearBulkState()
		return
	end

	pendingBulkBuy = {
		itemID = itemID,
		itemLink = scan.itemLink,
		quantity = buyQuantity,
		maxUnitPrice = scan.maxUnitPrice,
	}
	bulkOpportunity = nil
	debugLine("bulk ready", scan.itemLink or ("item:" .. tostring(itemID)), "x" .. tostring(buyQuantity), "unit", SmartRez.UI.FormatMoney(unitPrice), "cap", SmartRez.UI.FormatMoney(scan.maxUnitPrice))
end

local function getCandidate()
	local config = ensureAHSniperConfig()
	local orderedItemIDs = config.order
	if #orderedItemIDs == 0 then
		return nil
	end

	local startIndex = math.min(math.max(1, config.scanCursor or 1), #orderedItemIDs)
	for offset = 0, #orderedItemIDs - 1 do
		local index = ((startIndex + offset - 1) % #orderedItemIDs) + 1
		local itemID = orderedItemIDs[index]
		local itemConfig = ensureItemConfig(itemID)
		local itemLink = select(2, C_Item.GetItemInfo(itemID)) or ("item:" .. tostring(itemID))
		local buyPrice, buyPriceError = SmartRez:GetAHPriceExpressionValue(itemConfig.buyPriceExpression, itemLink, itemID)
		local baitPrice, baitPriceError = SmartRez:GetAHPriceExpressionValue(itemConfig.baitPriceExpression, itemLink, itemID)
		local candidate = {
			itemID = itemID,
			itemLink = itemLink,
			buyStackSize = itemConfig.buyStackSize,
			buyPrice = buyPrice,
			buyPriceError = buyPriceError,
			baitStackSize = itemConfig.baitStackSize,
			baitPrice = baitPrice,
			baitPriceError = baitPriceError,
			baitIntervalSeconds = itemConfig.baitIntervalSeconds,
			scanIndex = index,
		}
		advanceScanCursorFrom(index)
		return candidate
	end
end

function SmartRez:GetAHSniperConfig()
	return ensureAHSniperConfig()
end

function SmartRez:GetAHSniperWhitelist()
	return ensureAHSniperConfig().whitelist
end

function SmartRez:GetAHSniperOrderedItemIDs()
	return ensureAHSniperConfig().order
end

function SmartRez:GetAHSniperItemConfig(itemID)
	return ensureItemConfig(itemID)
end

function SmartRez:AddAHSniperWhitelistItem(itemID, skipRefresh)
	if not itemID then
		return
	end

	local config = ensureAHSniperConfig()
	config.whitelist[itemID] = true
	SmartRez:AddOrderedAHItem(config, itemID)
	local itemConfig = ensureItemConfig(itemID)
	if itemConfig.buyPriceExpression == DEFAULT_PRICE_TEXT then
		itemConfig.buyPriceExpression = SmartRez:GetAHDefaultPriceExpression(nil, itemID, DEFAULT_PRICE_TEXT)
	end
	if itemConfig.baitPriceExpression == DEFAULT_PRICE_TEXT then
		itemConfig.baitPriceExpression = SmartRez:GetAHDefaultPriceExpression(nil, itemID, DEFAULT_PRICE_TEXT)
	end
	if not skipRefresh then
		refreshViews()
	end
end

function SmartRez:RemoveAHSniperWhitelistItem(itemID, skipRefresh)
	local config = ensureAHSniperConfig()
	config.whitelist[itemID] = nil
	config.items[itemID] = nil
	SmartRez:RemoveOrderedAHItem(config, itemID)
	if not skipRefresh then
		refreshViews()
	end
end

function SmartRez:SetAHSniperItemConfigValue(itemID, key, value, skipRefresh)
	local itemConfig = ensureItemConfig(itemID)
	if key == "buyStackSize" then
		itemConfig.buyStackSize = math.max(1, math.floor(tonumber(value) or itemConfig.buyStackSize or 1))
	elseif key == "buyPriceExpression" then
		itemConfig.buyPriceExpression = SmartRez:NormalizeAHPriceExpression(value, DEFAULT_PRICE_TEXT)
	elseif key == "baitStackSize" then
		itemConfig.baitStackSize = math.max(0, math.floor(tonumber(value) or itemConfig.baitStackSize or 0))
	elseif key == "baitPriceExpression" then
		itemConfig.baitPriceExpression = SmartRez:NormalizeAHPriceExpression(value, DEFAULT_PRICE_TEXT)
	elseif key == "baitIntervalSeconds" then
		itemConfig.baitIntervalSeconds = math.max(1, math.floor(tonumber(value) or itemConfig.baitIntervalSeconds or DEFAULT_BAIT_INTERVAL_SECONDS))
	elseif key == "baitKeepInBags" then
		itemConfig.baitKeepInBags = math.max(0, math.floor(tonumber(value) or itemConfig.baitKeepInBags or 0))
		if SmartRez.MarkCraftRecipeCacheDirty then
			SmartRez:MarkCraftRecipeCacheDirty()
		end
		if SmartRez.MarkCraftSalvageCacheDirty then
			SmartRez:MarkCraftSalvageCacheDirty()
		end
		if SmartRez.RefreshDisenchantButton then
			SmartRez:RefreshDisenchantButton()
		end
	end
	if not skipRefresh then
		refreshViews()
	end
end

function SmartRez:GetAHSniperLatestScanDisplayText(itemID)
	local scan = latestScanByItemID[itemID]
	local itemConfig = ensureItemConfig(itemID)
	if not scan or type(scan.averageUnitPrice) ~= "number" or scan.quantity ~= itemConfig.buyStackSize then
		return ""
	end
	return money(scan.averageUnitPrice, scan.buyable and "7EE787" or "FF7B72")
end

function SmartRez:GetAHSniperBaitWarningDisplayText(itemID)
	local warning = latestWarningByItemID[itemID]
	if not warning then
		return ""
	end

	if type(warning.warningPrice) == "number" then
		return colorText("bait warn <= ", "7D8590") .. money(warning.warningPrice, "FFD866")
	end

	if warning.error then
		return colorText("bait warn: " .. tostring(warning.error), "FF7B72")
	end

	return ""
end

function SmartRez:RefreshAHSniperBaitWarningPrices()
	if warningRefresh then
		line("Smart Rez AH Snipe:", colorText("bait warning refresh already running", "FFD866"))
		return false
	end

	if hasPendingBuyLock() or hasPendingBaitLock() or hasBulkScanLock() then
		line("Smart Rez AH Snipe:", colorText("finish pending buy/bait/bulk work before refreshing bait warnings", "FF7B72"))
		return false
	end
	if (self.HasAHSellingActiveScan and self:HasAHSellingActiveScan())
		or (self.HasAHSellingPendingPost and self:HasAHSellingPendingPost())
	then
		line("Smart Rez AH Snipe:", colorText("finish pending AH selling work before refreshing bait warnings", "FF7B72"))
		return false
	end

	local ready, reason = self:IsAHReady()
	if not ready then
		line("Smart Rez AH Snipe:", colorText(reason, "FF7B72"))
		return false
	end

	local queue = {}
	for _, itemID in ipairs(ensureAHSniperConfig().order) do
		queue[#queue + 1] = itemID
	end

	if #queue == 0 then
		line("Smart Rez AH Snipe:", colorText("no AH sniper items configured", "FF7B72"))
		return false
	end

	ensureEvents()
	warningRefresh = {
		queue = queue,
		index = 1,
		completed = 0,
		startedAt = GetTime and GetTime() or 0,
		nextAttemptAt = 0,
	}

	line("Smart Rez AH Snipe:", colorText("refreshing bait warning prices", "79C0FF"), colorText(tostring(#queue) .. " item(s)", "7D8590"))
	ahSniperFrame:SetScript("OnUpdate", pumpWarningRefresh)
	pumpWarningRefresh()
	return true
end

function SmartRez:HasAHSniperPendingAction()
	return hasPendingBuyLock() or hasPendingBaitLock() or hasBulkScanLock() or warningRefresh ~= nil
end

function SmartRez:HasAHSniperConfiguredWork()
	return #ensureAHSniperConfig().order > 0
end

function SmartRez:HasAHSniperBulkOpportunity()
	return pendingBulkBuy ~= nil or bulkOpportunity ~= nil
end

function SmartRez:RunAHSniperNextAction()
	if hasPendingBuyLock() then
		debugLine("blocked purchase pending")
		return actionResult("pending")
	end
	if hasPendingBaitLock() then
		debugLine("blocked bait pending")
		return actionResult("pending")
	end
	if hasBulkScanLock() then
		debugLine("blocked bulk scan pending")
		return actionResult("pending")
	end
	if warningRefresh then
		debugLine("blocked bait warning refresh pending")
		return actionResult("pending")
	end

	local ready, reason = SmartRez:IsAHReady()
	if not ready then
		debugLine("blocked", reason)
		return actionResult("blocked")
	end

	local bulkBuyResult = startPendingBulkBuy()
	if bulkBuyResult then
		return bulkBuyResult
	end

	local bulkScanResult = startBulkScan()
	if bulkScanResult then
		return bulkScanResult
	end

	local candidate = getCandidate()
	if not candidate then
		actionLine("AH Sniper", "FF7B72", "no items configured")
		return actionResult("noWork")
	end

	local baitResult = candidate.baitPrice and tryPostBait(candidate) or nil
	if baitResult then
		return baitResult
	end

	if not candidate.buyPrice then
		debugLine("buy skipped price error", candidate.itemLink or ("item:" .. tostring(candidate.itemID)), tostring(candidate.buyPriceError))
		return actionResult("blocked")
	end

	return startBuyRequest(buildBuyRequest(candidate), "direct")
end

local function isActiveClickPhase(down)
	local useKeyDown = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
	if useKeyDown then
		return down == true
	end
	return down ~= true
end

local snipeButton = CreateFrame("Button", BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
snipeButton:RegisterForClicks("AnyUp", "AnyDown")
snipeButton:SetScript("OnClick", function(_, _, down)
	if not isActiveClickPhase(down) then
		return
	end
	SmartRez:RunAHSniperNextAction()
end)

ahSniperFrame:SetScript("OnEvent", function(_, eventName, ...)
	if eventName == "COMMODITY_PRICE_UPDATED" then
		processBuyPriceUpdated(...)
	elseif eventName == "COMMODITY_PRICE_UNAVAILABLE" then
		if pendingBuy then
			actionLine(pendingBuy.itemLink or ("item:" .. tostring(pendingBuy.itemID)), "FF7B72", "price unavailable")
			if pendingBuy.bulkMode then
				clearBulkState()
			end
		end
		pendingBuy = nil
	elseif eventName == "COMMODITY_SEARCH_RESULTS_UPDATED" then
		processBulkSearchResults(...)
		processWarningRefreshResults(...)
	elseif eventName == "ITEM_SEARCH_RESULTS_UPDATED" then
		processWarningRefreshItemResults(...)
	elseif eventName == "COMMODITY_PURCHASE_SUCCEEDED" and pendingBuy then
		actionLine(
			pendingBuy.itemLink or ("item:" .. tostring(pendingBuy.itemID)),
			"7EE787",
			"bought",
			"x" .. tostring(pendingBuy.quantity),
			"at",
			money(pendingBuy.confirmedUnitPrice or pendingBuy.maxUnitPrice or 0, "7EE787")
		)
		if pendingBuy.bulkMode then
			clearBulkState()
		else
			local itemConfig = ensureItemConfig(pendingBuy.itemID)
			local configuredCap = SmartRez:GetAHPriceExpressionValue(
				itemConfig.buyPriceExpression,
				pendingBuy.itemLink or ("item:" .. tostring(pendingBuy.itemID)),
				pendingBuy.itemID
			)
			local confirmedUnitPrice = pendingBuy.confirmedUnitPrice or pendingBuy.maxUnitPrice
			local maxUnitPrice = math.min(confirmedUnitPrice or pendingBuy.maxUnitPrice, configuredCap or pendingBuy.maxUnitPrice)
			if type(maxUnitPrice) == "number" and maxUnitPrice > 0 then
				bulkOpportunity = {
					itemID = pendingBuy.itemID,
					itemLink = pendingBuy.itemLink,
					maxUnitPrice = maxUnitPrice,
					configuredStackSize = pendingBuy.quantity,
				}
				debugLine("bulk opportunity", pendingBuy.itemLink or ("item:" .. tostring(pendingBuy.itemID)), "cap", SmartRez.UI.FormatMoney(maxUnitPrice))
			end
		end
		pendingBuy = nil
	elseif eventName == "COMMODITY_PURCHASE_FAILED" and pendingBuy then
		actionLine(pendingBuy.itemLink or ("item:" .. tostring(pendingBuy.itemID)), "FF7B72", "buy failed")
		if pendingBuy.bulkMode then
			clearBulkState()
		end
		pendingBuy = nil
	elseif (eventName == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" or eventName == "AUCTION_HOUSE_BROWSE_FAILURE") and bulkScan then
		debugLine("bulk scan failed", eventName)
		clearBulkState()
	elseif (eventName == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" or eventName == "AUCTION_HOUSE_BROWSE_FAILURE") and warningRefresh then
		failWarningRefresh(eventName)
	elseif eventName == "AUCTION_HOUSE_AUCTION_CREATED" and pendingBait then
		actionLine(
			pendingBait.itemLink or ("item:" .. tostring(pendingBait.itemID)),
			"79C0FF",
			"bait",
			"x" .. tostring(pendingBait.quantity),
			"at",
			money(pendingBait.unitPrice, "79C0FF")
		)
		pendingBait = nil
	elseif (eventName == "AUCTION_HOUSE_POST_ERROR" or eventName == "UI_ERROR_MESSAGE") and pendingBait then
		actionLine(pendingBait.itemLink or ("item:" .. tostring(pendingBait.itemID)), "FF7B72", "bait failed")
		pendingBait = nil
	elseif eventName == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
		debugLine("throttle ready")
		pumpWarningRefresh()
	end
end)

SmartRez:RegisterBindableAction({
	key = "ahsniper",
	label = "AH Sniper",
	buttonName = BUTTON_NAME,
	order = 591,
})
