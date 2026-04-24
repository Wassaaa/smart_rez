---@meta

---@class TSMApi
local TSMApi = {}

---@param uiName string
---@return boolean
function TSMApi.IsUIVisible(uiName) end

---@param customPriceStr string
---@return boolean
---@return string?
function TSMApi.IsCustomPriceValid(customPriceStr) end

---@param customPriceStr string
---@param itemString string
---@return number?
---@return string?
function TSMApi.GetCustomPriceValue(customPriceStr, itemString) end

---@param value number
---@return string
function TSMApi.FormatMoneyString(value) end

---@param item string
---@return string?
function TSMApi.ToItemString(item) end

---@param uiName string
---@param callbackId string
---@param callback fun(visible: boolean, frame: table?)
function TSMApi.RegisterUICallback(uiName, callbackId, callback) end

---@class _G
---@field TSM_API TSMApi?
---@field AuctionatorBuyCommodityFrame table?
---@field AuctionatorBuyCommodityFrameTemplateMixin table?
---@field AUCTIONATOR_L_BUY_NOW string?
