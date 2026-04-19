local _, SnipeAuctionator = ...
local SmartRez = _G.SmartRez

local BUY_NOW_BUTTON_NAME = "SmartRezAuctionatorBuyNowBtn"
local BAIT_NOW_BUTTON_NAME = "SmartRezAuctionatorBaitNowBtn"

local function getAuctionatorBuyFrame()
  local frame = _G.AuctionatorBuyCommodityFrame
  if frame and frame.DetailsContainer and frame.DetailsContainer.BuyButton then
    return frame
  end
end

local function getAuctionatorBuyCommodityFrameTemplateMixin()
  return _G.AuctionatorBuyCommodityFrameTemplateMixin
end

local function getAuctionatorBuyButton()
  local frame = getAuctionatorBuyFrame()
  return frame and frame.DetailsContainer.BuyButton or nil
end

local function syncSnipeFrame(frame, itemID)
  local snipeFrame = frame and frame.SnipeFrame or nil
  if not snipeFrame or not itemID then
    return
  end

  snipeFrame.itemID = itemID
  snipeFrame.price:SetAmount(PriceMemory[itemID] or 0)
  snipeFrame.baitPrice:SetAmount(BaitMemory[itemID] or 0)
end

-- Initialize main frame and state variables
SnipeAuctionator.frame = CreateFrame("Frame")
SnipeAuctionator.isInitialized = false
SnipeAuctionator.hooksInitialized = false
SnipeAuctionator.purchaseLocked = false
SnipeAuctionator.purchaseConfirmed = false

local function setBuyButtonLocked(frame, locked)
  local buyButton = frame and frame.DetailsContainer and frame.DetailsContainer.BuyButton or nil
  if not buyButton then
    return
  end

  if locked then
    buyButton:SetText("Buying...")
    buyButton:Disable()
  else
    buyButton:SetText(AUCTIONATOR_L_BUY_NOW or "Buy Now")
    if frame and frame.results and frame.GetPrices then
      local _, totalPrice = frame:GetPrices()
      buyButton:SetEnabled(totalPrice <= GetMoney())
    else
      buyButton:Disable()
    end
  end
end

local function lockPurchase(frame)
  SnipeAuctionator.purchaseLocked = true
  SnipeAuctionator.purchaseConfirmed = false
  setBuyButtonLocked(frame, true)
end

local function markPurchaseConfirmed()
  SnipeAuctionator.purchaseConfirmed = true
end

local function unlockPurchase(frame)
  SnipeAuctionator.purchaseLocked = false
  SnipeAuctionator.purchaseConfirmed = false
  setBuyButtonLocked(frame or getAuctionatorBuyFrame(), false)
end

local function isPurchaseLocked(frame)
  if SnipeAuctionator.purchaseLocked then
    return true
  end

  if not frame then
    return false
  end

  if frame.waitingForPurchase then
    return true
  end

  if frame.FinalConfirmationDialog and frame.FinalConfirmationDialog:IsShown() then
    return true
  end

  if frame.QuantityCheckConfirmationDialog and frame.QuantityCheckConfirmationDialog:IsShown() then
    return true
  end

  return false
end

local function attachConfirmationHooks(frame)
  if not frame or frame.smartRezConfirmationHooksAttached then
    return
  end

  frame.smartRezConfirmationHooksAttached = true

  if frame.FinalConfirmationDialog then
    hooksecurefunc(frame.FinalConfirmationDialog, "SetDetails", function()
      lockPurchase(frame)
    end)
    hooksecurefunc(frame.FinalConfirmationDialog, "ConfirmPurchase", function()
      markPurchaseConfirmed()
    end)
    hooksecurefunc(frame.FinalConfirmationDialog, "OnHide", function()
      if not SnipeAuctionator.purchaseConfirmed then
        unlockPurchase(frame)
      end
    end)
  end

  if frame.QuantityCheckConfirmationDialog then
    hooksecurefunc(frame.QuantityCheckConfirmationDialog, "SetDetails", function()
      lockPurchase(frame)
    end)
    hooksecurefunc(frame.QuantityCheckConfirmationDialog, "ConfirmPurchase", function()
      markPurchaseConfirmed()
    end)
    hooksecurefunc(frame.QuantityCheckConfirmationDialog, "OnHide", function()
      if not SnipeAuctionator.purchaseConfirmed then
        unlockPurchase(frame)
      end
    end)
  end
end

-- Initialize item data
local function InitializeItemData()
  if PriceMemory == nil then
    PriceMemory = {
      [210796] = 210000,       -- Mycobloom
      [224828] = 210000,       -- Weavercloth r1
    }
  end
  if BaitMemory == nil then
    BaitMemory = {
      [210796] = 120000,       -- Mycobloom
      [224828] = 120000,       -- Weavercloth r1
    }
  end
  if QuantityMemory == nil then
    QuantityMemory = {
      [210796] = 200,       -- Mycobloom
      [224828] = 200,       -- Weavercloth r1
    }
  end
end

-- Initialize the addon
function SnipeAuctionator:Initialize()
  if self.isInitialized then return end
  self.isInitialized = true

  print("SnipeAuctionator: Initializing...")
  InitializeItemData()
  print("SnipeAuctionator: Initialization complete. Ready to snipe!")
end

local function findFromBag(itemID)
  for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
      if itemInfo and itemInfo.itemID == itemID then
        return ItemLocation:CreateFromBagAndSlot(bag, slot)
      end
    end
  end
end

local function postBaitAuction()
  local frame = getAuctionatorBuyFrame()
  local snipeFrame = frame and frame.SnipeFrame or nil
  local itemID = frame and frame.expectedItemID or (snipeFrame and snipeFrame.itemID) or nil
  if not itemID then
    DEFAULT_CHAT_FRAME:AddMessage("No Auctionator item selected", 1, 1, 0)
    return
  end

  local loc = findFromBag(itemID)
  local quantity = 1
  local price = snipeFrame.baitPrice and snipeFrame.baitPrice:GetAmount() or 1
  if loc then
    C_AuctionHouse.PostCommodity(loc, 1, quantity, price)
  else
    DEFAULT_CHAT_FRAME:AddMessage("No item in bag", 1, 1, 0)
  end
end

local buyNowProxyButton = CreateFrame("Button", BUY_NOW_BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
buyNowProxyButton:RegisterForClicks("AnyUp", "AnyDown")
buyNowProxyButton:SetAttribute("type", "click")
buyNowProxyButton:SetScript("PreClick", function(self)
  if InCombatLockdown() then
    return
  end

  local frame = getAuctionatorBuyFrame()
  if isPurchaseLocked(frame) then
    self:SetAttribute("clickbutton", nil)
    return
  end

  self:SetAttribute("clickbutton", frame and frame.DetailsContainer.BuyButton or nil)
end)
buyNowProxyButton:SetScript("PostClick", function(self)
  if InCombatLockdown() then
    return
  end

  self:SetAttribute("clickbutton", nil)
end)

local baitNowProxyButton = CreateFrame("Button", BAIT_NOW_BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
baitNowProxyButton:RegisterForClicks("AnyUp", "AnyDown")
baitNowProxyButton:SetScript("OnClick", postBaitAuction)

SmartRez:RegisterBindableAction({
  key = "auctionatorbuynow",
  label = "Auctionator Buy Now",
  buttonName = BUY_NOW_BUTTON_NAME,
  order = 580,
})

SmartRez:RegisterBindableAction({
  key = "auctionatorbaitnow",
  label = "Auctionator Bait Now",
  buttonName = BAIT_NOW_BUTTON_NAME,
  order = 581,
})

-- Create the Snipe UI
function SnipeAuctionator:CreateSnipeUI(parent)
  print("SnipeAuctionator: Creating snipe UI")
  local snipeFrame = CreateFrame("Frame", nil, parent)
  snipeFrame:SetSize(200, 50)
  snipeFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 60, -200)

  -- Create label
  snipeFrame.label = snipeFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  snipeFrame.label:SetText("Snipe price")
  snipeFrame.label:SetPoint("TOPLEFT", snipeFrame, "TOPLEFT", -25, 0)

  -- Create price input
  snipeFrame.price = CreateFrame("Frame", nil, snipeFrame, "AuctionatorConfigurationMoneyInputAlternate")
  snipeFrame.price:SetPoint("TOPLEFT", snipeFrame, "TOPLEFT", -150, -20)
  local lastSnipePrice = 0
  snipeFrame.price:SetAmount(0)

  -- Update price on change
  snipeFrame.price:SetScript("OnUpdate", function()
    local currentSnipePrice = snipeFrame.price:GetAmount()
    if snipeFrame.itemID and currentSnipePrice ~= lastSnipePrice then
      lastSnipePrice = currentSnipePrice
      PriceMemory[snipeFrame.itemID] = currentSnipePrice
    end
  end)

  -- Create bait price input
  snipeFrame.baitPrice = CreateFrame("Frame", nil, snipeFrame, "AuctionatorConfigurationMoneyInputAlternate")
  snipeFrame.baitPrice:SetPoint("TOPLEFT", snipeFrame.price, "TOPLEFT", 0, -50)
  snipeFrame.baitPrice:SetAmount(0)

  -- Update bait price on change
  local lastBaitPrice = 0
  snipeFrame.baitPrice:SetScript("OnUpdate", function()
    local currentBaitPrice = snipeFrame.baitPrice:GetAmount()
    if snipeFrame.itemID and currentBaitPrice ~= lastBaitPrice then
      lastBaitPrice = currentBaitPrice
      BaitMemory[snipeFrame.itemID] = currentBaitPrice
    end
  end)

  snipeFrame.baitPrice.button = CreateFrame("Button", nil, parent, "UIPanelDynamicResizeButtonTemplate")
  snipeFrame.baitPrice.button:SetEnabled(true)
  snipeFrame.baitPrice.button:SetSize(100, 20)
  snipeFrame.baitPrice.button:SetPoint("BOTTOMLEFT", snipeFrame.baitPrice, "BOTTOMLEFT", 135, -50)
  snipeFrame.baitPrice.button:SetText("Bait Now")
  snipeFrame.baitPrice.button:SetScript("OnClick", postBaitAuction)

  return snipeFrame
end

-- Hook into Auctionator's Buy Commodity Frame
function SnipeAuctionator:HookAuctionatorBuyCommodityFrame()
  if self.hooksInitialized then return true end

  local AucMix = getAuctionatorBuyCommodityFrameTemplateMixin()
  if not AucMix then
    print("SnipeAuctionator: AuctionatorBuyCommodityFrameTemplateMixin not found. Retrying...")
    return false
  end

  -- Hook into OnLoad and create the snipe UI
  hooksecurefunc(AucMix, "OnLoad", function(frame)
    print("SnipeAuctionator: Hooked into AuctionatorBuyCommodityFrameTemplateMixin.OnLoad")
    if not frame.SnipeFrame then
      frame.SnipeFrame = self:CreateSnipeUI(frame.DetailsContainer)
    end
    attachConfirmationHooks(frame)
  end)

  hooksecurefunc(AucMix, "ReceiveEvent", function(frame, eventName, ...)
    if eventName ~= Auctionator.Buying.Events.ShowCommodityBuy then
      return
    end

    local itemID = frame.expectedItemID
    syncSnipeFrame(frame, itemID)

    local savedQuantity = itemID and QuantityMemory[itemID] or nil
    if savedQuantity and savedQuantity > 0 and frame.selectedQuantity ~= savedQuantity then
      frame.selectedQuantity = savedQuantity
      frame:UpdateView()
    end
  end)

  hooksecurefunc(AucMix, "UpdateView", function(frame)
    local itemID = frame.expectedItemID
    if itemID then
      syncSnipeFrame(frame, itemID)
      if frame.selectedQuantity and frame.selectedQuantity > 0 then
        QuantityMemory[itemID] = frame.selectedQuantity
      end
    end

    if not isPurchaseLocked(frame) then
      setBuyButtonLocked(frame, false)
    end
  end)

  hooksecurefunc(AucMix, "ForceStartPurchase", function(frame)
    lockPurchase(frame)
  end)

  hooksecurefunc(AucMix, "BuyClicked", function(frame)
    if frame.WidePriceRangeWarningDialog and frame.WidePriceRangeWarningDialog:IsShown() then
      frame.WidePriceRangeWarningDialog:StartPurchase()
    end
  end)

  hooksecurefunc(AucMix, "CheckPurchase", function(frame, newUnitPrice)
    print("SnipeAuctionator: CheckPurchase called")

    local itemID = frame.expectedItemID
    local _, itemLink = C_Item.GetItemInfo(itemID)
    local maxPrice = frame.SnipeFrame and frame.SnipeFrame.price:GetAmount() or 0

    DEFAULT_CHAT_FRAME:AddMessage(
      string.format("%s\nID: %d\nPrice: %s\nMax: %s",
        itemLink or "Unknown Item",
        itemID or 0,
        GetMoneyString(newUnitPrice),
        maxPrice > 0 and GetMoneyString(maxPrice) or "Not Set"
      ),
      1, 1, 0
    )

    if maxPrice <= 0 then
      return
    end

    if newUnitPrice <= maxPrice then
      if frame.QuantityCheckConfirmationDialog and frame.QuantityCheckConfirmationDialog:IsShown() then
        if frame.QuantityCheckConfirmationDialog.QuantityInput then
          frame.QuantityCheckConfirmationDialog.QuantityInput:SetText(tostring(frame.selectedQuantity or 0))
        end
        frame.QuantityCheckConfirmationDialog:ConfirmPurchase()
      elseif frame.FinalConfirmationDialog and frame.FinalConfirmationDialog:IsShown() then
        frame.FinalConfirmationDialog:ConfirmPurchase()
      end

      DEFAULT_CHAT_FRAME:AddMessage(
        string.format("Purchasing %s x%d\n", itemLink or "Unknown Item", frame.selectedQuantity or 0),
        1,
        1,
        0
      )
    else
      if frame.QuantityCheckConfirmationDialog and frame.QuantityCheckConfirmationDialog:IsShown() then
        frame.QuantityCheckConfirmationDialog:Hide()
      elseif frame.FinalConfirmationDialog and frame.FinalConfirmationDialog:IsShown() then
        frame.FinalConfirmationDialog:Hide()
      end

      unlockPurchase(frame)
      DEFAULT_CHAT_FRAME:AddMessage("Too rich, try again\n", 1, 1, 0)
    end
  end)

  local liveFrame = getAuctionatorBuyFrame()
  if liveFrame then
    if not liveFrame.SnipeFrame then
      liveFrame.SnipeFrame = self:CreateSnipeUI(liveFrame.DetailsContainer)
    end
    attachConfirmationHooks(liveFrame)
  end

  print("SnipeAuctionator: Successfully hooked into AuctionatorBuyCommodityFrameTemplateMixin")
  self.hooksInitialized = true
  return true
end

-- Register and handle events
function SnipeAuctionator:RegisterEvents()
  self.frame:RegisterEvent("AUCTION_HOUSE_SHOW")
  self.frame:RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
  self.frame:RegisterEvent("COMMODITY_PURCHASE_FAILED")
  self.frame:RegisterEvent("COMMODITY_PRICE_UNAVAILABLE")
  self.frame:SetScript("OnEvent", function(_, eventName, eventData)
    if eventName == "AUCTION_HOUSE_SHOW" then
      SnipeAuctionator:HookAuctionatorBuyCommodityFrame()
    elseif eventName == "COMMODITY_PURCHASE_SUCCEEDED" or eventName == "COMMODITY_PURCHASE_FAILED" or eventName == "COMMODITY_PRICE_UNAVAILABLE" then
      unlockPurchase(getAuctionatorBuyFrame())
    end
  end)
end

-- Set up hooks
function SnipeAuctionator:SetupHooks()
  self:Initialize()
  self:RegisterEvents()
end

-- Set up hooks as soon as SnipeAuctionator loads
SnipeAuctionator:SetupHooks()

print("SnipeAuctionator: Addon loaded and attempting to hook into Auctionator...")
