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

local function getAuctionatorBuyButton()
  local frame = getAuctionatorBuyFrame()
  return frame and frame.DetailsContainer.BuyButton or nil
end

-- Initialize main frame and state variables
SnipeAuctionator.frame = CreateFrame("Frame")
SnipeAuctionator.isInitialized = false
SnipeAuctionator.hooksInitialized = false

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
  if not snipeFrame or not snipeFrame.itemID then
    DEFAULT_CHAT_FRAME:AddMessage("No Auctionator item selected", 1, 1, 0)
    return
  end

  local loc = findFromBag(snipeFrame.itemID)
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

  self:SetAttribute("clickbutton", getAuctionatorBuyButton())
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
    if currentSnipePrice ~= lastSnipePrice then
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
    if currentBaitPrice ~= lastBaitPrice then
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

local function preHookFunction(func, preHookAction)
  return function(...)
    if preHookAction then
      preHookAction(...)
    end
    return func(...)
  end
end

-- Hook into Auctionator's Buy Commodity Frame
function SnipeAuctionator:HookAuctionatorBuyCommodityFrame()
  if self.hooksInitialized then return true end

  local AucMix = AuctionatorBuyCommodityFrameTemplateMixin
  if not AucMix then
    print("SnipeAuctionator: AuctionatorBuyCommodityFrameTemplateMixin not found. Retrying...")
    return false
  end

  -- Prevent list update on purchase
  local originalOnEvent = AucMix.OnEvent
  AucMix.OnEvent = function(self, event, ...)
    if event == "COMMODITY_PURCHASE_SUCCEEDED" then
      return
    end
    originalOnEvent(self, event, ...)
  end
  local originalBuyClicked = AucMix.BuyClicked
  AucMix.BuyClicked = function(self, ...)
    if self.results == nil then
      return
    end
    print("SnipeAuctionator: BuyClicked pre hook called")
    originalBuyClicked(self, ...)
  end

  local originalUpdateView = AucMix.UpdateView
  AucMix.UpdateView = function(self, ...)
    if self.expectedItemID then
      -- Check if the item has a saved quantity in the table
      --local savedQuantity = SnipeAuctionator.itemSnipeQuantities[self.expectedItemID]
      local savedQuantity = QuantityMemory[self.expectedItemID]
      -- Only update selectedQuantity during initialization
      if SnipeAuctionator.isInitializing then
        self.selectedQuantity = savedQuantity or 1
      end
      -- If the user modifies the quantity and it's not 1, save it
      if self.selectedQuantity ~= 1 and self.selectedQuantity ~= savedQuantity then
        -- SnipeAuctionator.itemSnipeQuantities[self.expectedItemID] = self.selectedQuantity
        QuantityMemory[self.expectedItemID] = self.selectedQuantity
      end
    end
    -- Call the original function
    originalUpdateView(self, ...)
    -- Clear the initialization flag after the view is updated
    SnipeAuctionator.isInitializing = false
  end

  -- Hook into OnLoad and create the snipe UI
  hooksecurefunc(AucMix, "OnLoad", function(frame)
    print("SnipeAuctionator: Hooked into AuctionatorBuyCommodityFrameTemplateMixin.OnLoad")
    frame.SnipeFrame = self:CreateSnipeUI(frame.DetailsContainer)

    -- Hook into BuyClicked
    hooksecurefunc(frame, "BuyClicked", function()
      frame.DetailsContainer.BuyButton:SetText("Buying...")
      frame.DetailsContainer.BuyButton:Disable()
      if frame.WidePriceRangeWarningDialog then
        frame.WidePriceRangeWarningDialog:StartPurchase()
      end
    end)

    -- Hook into CheckPurchase
    hooksecurefunc(frame, "CheckPurchase", function(aucFrame, newUnitPrice, newTotalPrice)
      print("SnipeAuctionator: CheckPurchase called")
      local itemName, itemLink = C_Item.GetItemInfo(aucFrame.expectedItemID)
      local maxPrice = frame.SnipeFrame.price:GetAmount()

      -- Display item information
      DEFAULT_CHAT_FRAME:AddMessage(
        string.format("%s\nID: %d\nPrice: %s\nMax: %s",
          itemLink or "Unknown Item",
          aucFrame.expectedItemID,
          GetMoneyString(newUnitPrice),
          maxPrice and GetMoneyString(maxPrice) or "Not Set"
        ),
        1, 1, 0
      )

      -- Check if price is within range and confirm purchase
      if maxPrice and maxPrice > 0 then
        if newUnitPrice <= maxPrice then
          aucFrame.FinalConfirmationDialog:ConfirmPurchase()
          DEFAULT_CHAT_FRAME:AddMessage(string.format("Purchasing %s x%d\n", itemLink, aucFrame.selectedQuantity), 1, 1,
            0)
        else
          aucFrame.FinalConfirmationDialog:Hide()
          DEFAULT_CHAT_FRAME:AddMessage("Too rich, try again\n", 1, 1, 0)
        end
      end
    end)
  end)

  print("SnipeAuctionator: Successfully hooked into AuctionatorBuyCommodityFrameTemplateMixin")
  self.hooksInitialized = true
  return true
end

-- Register and handle events
function SnipeAuctionator:RegisterEvents()
  self.frame:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
  self.frame:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
  self.frame:RegisterEvent("AUCTION_HOUSE_SHOW")
  self.frame:SetScript("OnEvent", function(_, eventName, eventData)
    if eventName == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
      -- print("SnipeAuctionator: AUCTION_HOUSE_THROTTLED_SYSTEM_READY event received")
      local buyButton = AuctionatorBuyCommodityFrame.DetailsContainer.BuyButton
      if buyButton then
        buyButton:SetText(AUCTIONATOR_L_BUY_NOW)
        buyButton:Enable()
      end
    elseif eventName == "COMMODITY_SEARCH_RESULTS_UPDATED" then
      AuctionatorBuyCommodityFrame.SnipeFrame.itemID = eventData
      -- AuctionatorBuyCommodityFrame.SnipeFrame.price:SetAmount(self.itemMaxPrices[eventData] or 0)
      AuctionatorBuyCommodityFrame.SnipeFrame.price:SetAmount(PriceMemory[eventData] or 0)
      AuctionatorBuyCommodityFrame.SnipeFrame.baitPrice:SetAmount(BaitMemory[eventData] or 0)
      SnipeAuctionator.isInitializing = true
    elseif eventName == "AUCTION_HOUSE_SHOW" then
      SnipeAuctionator:HookAuctionatorBuyCommodityFrame()
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
