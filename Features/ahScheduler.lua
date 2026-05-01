local SmartRez = _G.SmartRez

local BUTTON_NAME = "SmartRezAHBuySellButton"
local PREFIX = "Smart Rez AH:"

local buyActionsSinceSell = 0

local function isDebugEnabled()
  return SmartRez.GetDebugEnabled and SmartRez:GetDebugEnabled()
end

local function debugLine(...)
  if isDebugEnabled() then
    print(PREFIX, ...)
  end
end

local function isActiveClickPhase(down)
  local useKeyDown = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
  if useKeyDown then
    return down == true
  end

  return down ~= true
end

local function getBuyActionsPerSell()
  if SmartRez.GetAHSellingBuyActionsPerSell then
    return math.max(1, math.floor(tonumber(SmartRez:GetAHSellingBuyActionsPerSell()) or 5))
  end

  return 5
end

local function hasPendingAHOperation()
  return (SmartRez.HasAHSniperPendingAction and SmartRez:HasAHSniperPendingAction())
      or (SmartRez.HasAHSellingActiveScan and SmartRez:HasAHSellingActiveScan())
      or (SmartRez.HasAHSellingPendingPost and SmartRez:HasAHSellingPendingPost())
end

local function hasSniperWork()
  return SmartRez.HasAHSniperConfiguredWork and SmartRez:HasAHSniperConfiguredWork()
end

local function hasSniperBulkOpportunity()
  return SmartRez.HasAHSniperBulkOpportunity and SmartRez:HasAHSniperBulkOpportunity()
end

local function hasSellingWork()
  return SmartRez.HasAHSellingConfiguredWork and SmartRez:HasAHSellingConfiguredWork()
end

local function runSell(allowPreparedPost)
  if not SmartRez.ScanAHSellingNextItem then
    return nil
  end

  return SmartRez:ScanAHSellingNextItem(allowPreparedPost == true)
end

local function runSniper()
  if not SmartRez.RunAHSniperNextAction then
    return nil
  end

  return SmartRez:RunAHSniperNextAction()
end

local function recordSniperResult(result)
  if result and result.consumedThrottle and (result.status == "startedBuy" or result.status == "postedBait") then
    buyActionsSinceSell = buyActionsSinceSell + 1
  end
end

local function recordSellResult(result)
  if not result then
    return
  end

  if result.status == "scanStarted" or result.status == "posted" or result.status == "noWork" then
    buyActionsSinceSell = 0
  end
end

function SmartRez:RunAHBuySellNextAction()
  if hasPendingAHOperation() then
    debugLine("blocked", "AH operation pending")
    return
  end

  if hasSniperBulkOpportunity() then
    local sniperResult = runSniper()
    recordSniperResult(sniperResult)
    return sniperResult
  end

  if self.HasAHSellingPreparedPost and self:HasAHSellingPreparedPost() then
    local result = runSell(true)
    recordSellResult(result)
    return result
  end

  local sniperHasWork = hasSniperWork()
  local sellingHasWork = hasSellingWork()
  if not sniperHasWork and not sellingHasWork then
    debugLine("blocked", "no AH work configured")
    return
  end

  local sellOwed = buyActionsSinceSell >= getBuyActionsPerSell()
  if sellingHasWork and (sellOwed or not sniperHasWork) then
    local sellResult = runSell(false)
    recordSellResult(sellResult)

    if sellResult and sellResult.status ~= "noWork" and sellResult.status ~= "blocked" then
      return sellResult
    end
    if not sniperHasWork then
      return sellResult
    end
  end

  if sniperHasWork then
    local sniperResult = runSniper()
    recordSniperResult(sniperResult)
    if sniperResult and sniperResult.status ~= "noWork" then
      return sniperResult
    end
  end

  if sellingHasWork then
    local sellResult = runSell(false)
    recordSellResult(sellResult)
    return sellResult
  end
end

local ahButton = CreateFrame("Button", BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
ahButton:RegisterForClicks("AnyUp", "AnyDown")
ahButton:SetScript("OnClick", function(_, _, down)
  if not isActiveClickPhase(down) then
    return
  end

  SmartRez:RunAHBuySellNextAction()
end)

SmartRez:RegisterBindableAction({
  key = "ahbuysell",
  label = "AH Buy/Sell",
  buttonName = BUTTON_NAME,
  order = 589,
})
