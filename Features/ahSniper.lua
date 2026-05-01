local SmartRez = _G.SmartRez
local C_AuctionHouse = C_AuctionHouse

local BUTTON_NAME = "SmartRezAHSnipeButton"
local DEFAULT_PRICE_TEXT = "1g"
local DEFAULT_BUY_STACK_SIZE = 1
local DEFAULT_BAIT_STACK_SIZE = 0
local DEFAULT_BAIT_INTERVAL_SECONDS = 30
local DEFAULT_AUCTION_DURATION = 1
local SCAN_TIMEOUT_SECONDS = 10
local PREFIX = "Smart Rez AH Snipe:"

local ahSniperFrame = CreateFrame("Frame")
local pendingBuy
local pendingBait
local lastBaitByItemID = {}
local latestScanByItemID = {}

local SEARCH_EVENTS = {
	"COMMODITY_PRICE_UPDATED",
	"COMMODITY_PRICE_UNAVAILABLE",
	"COMMODITY_PURCHASE_SUCCEEDED",
	"COMMODITY_PURCHASE_FAILED",
	"AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
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
		startedAt = GetTime and GetTime() or 0,
	}
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
		return true
	end

	ensureEvents()
	pendingBuy = {
		itemID = buy.itemID,
		itemLink = buy.itemLink,
		quantity = buy.quantity,
		maxUnitPrice = buy.maxUnitPrice,
		maxTotal = buy.maxTotal,
		startedAt = GetTime and GetTime() or 0,
	}

	local ok, err = pcall(C_AuctionHouse.StartCommoditiesPurchase, buy.itemID, buy.quantity)
	if not ok then
		actionLine(buy.itemLink or ("item:" .. tostring(buy.itemID)), "FF7B72", "buy failed", tostring(err))
		pendingBuy = nil
		return true
	end

	debugLine("purchase quote requested", buy.itemLink or ("item:" .. tostring(buy.itemID)), source or "direct", "x" .. tostring(buy.quantity), "cap", SmartRez.UI.FormatMoney(buy.maxUnitPrice))
	return true
end

local function tryPostBait(candidate)
	ensureEvents()
	local baitStackSize = math.max(0, math.floor(tonumber(candidate.baitStackSize) or 0))
	if baitStackSize <= 0 then
		return false
	end

	local now = GetTime and GetTime() or 0
	local interval = math.max(1, math.floor(tonumber(candidate.baitIntervalSeconds) or DEFAULT_BAIT_INTERVAL_SECONDS))
	if (lastBaitByItemID[candidate.itemID] or 0) + interval > now then
		return false
	end

	local location = SmartRez:FindAHBagLocation(candidate.itemID)
	if not location then
		debugLine("bait skipped no bag item", candidate.itemLink or ("item:" .. tostring(candidate.itemID)))
		return false
	end

	local ok, err = pcall(C_AuctionHouse.PostCommodity, location, DEFAULT_AUCTION_DURATION, baitStackSize, candidate.baitPrice)
	if not ok then
		actionLine(candidate.itemLink or ("item:" .. tostring(candidate.itemID)), "FF7B72", "bait failed", tostring(err))
		return true
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
	return true
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

local function getCandidate()
	local config = ensureAHSniperConfig()
	local orderedItemIDs = config.order
	if #orderedItemIDs == 0 then
		return nil
	end

	local snapshot = SmartRez:BuildAHPlayerBagSnapshot()
	local startIndex = math.min(math.max(1, config.scanCursor or 1), #orderedItemIDs)
	for offset = 0, #orderedItemIDs - 1 do
		local index = ((startIndex + offset - 1) % #orderedItemIDs) + 1
		local itemID = orderedItemIDs[index]
		local itemConfig = ensureItemConfig(itemID)
		local itemData = snapshot.itemsByID[itemID] or {}
		local itemLink = itemData.itemLink or select(2, C_Item.GetItemInfo(itemID)) or ("item:" .. tostring(itemID))
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

function SmartRez:RunAHSniperNextAction()
	if hasPendingBuyLock() then
		debugLine("blocked purchase pending")
		return
	end
	if hasPendingBaitLock() then
		debugLine("blocked bait pending")
		return
	end

	local ready, reason = SmartRez:IsAHReady()
	if not ready then
		debugLine("blocked", reason)
		return
	end

	local candidate = getCandidate()
	if not candidate then
		actionLine("AH Sniper", "FF7B72", "no items configured")
		return
	end

	if candidate.baitPrice and tryPostBait(candidate) then
		return
	end

	if not candidate.buyPrice then
		debugLine("buy skipped price error", candidate.itemLink or ("item:" .. tostring(candidate.itemID)), tostring(candidate.buyPriceError))
		return
	end

	startBuyRequest(buildBuyRequest(candidate), "direct")
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
		end
		pendingBuy = nil
	elseif eventName == "COMMODITY_PURCHASE_SUCCEEDED" and pendingBuy then
		actionLine(
			pendingBuy.itemLink or ("item:" .. tostring(pendingBuy.itemID)),
			"7EE787",
			"bought",
			"x" .. tostring(pendingBuy.quantity),
			"at",
			money(pendingBuy.confirmedUnitPrice or pendingBuy.maxUnitPrice or 0, "7EE787")
		)
		pendingBuy = nil
	elseif eventName == "COMMODITY_PURCHASE_FAILED" and pendingBuy then
		actionLine(pendingBuy.itemLink or ("item:" .. tostring(pendingBuy.itemID)), "FF7B72", "buy failed")
		pendingBuy = nil
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
	end
end)

SmartRez:RegisterBindableAction({
	key = "ahsniper",
	label = "AH Sniper",
	buttonName = BUTTON_NAME,
	order = 591,
})
