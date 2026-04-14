---@meta

---@class TSMApi
local TSMApi = {}

---@param uiName string
---@return boolean
function TSMApi.IsUIVisible(uiName) end

---@param uiName string
---@param callbackId string
---@param callback fun(visible: boolean, frame: table?)
function TSMApi.RegisterUICallback(uiName, callbackId, callback) end

---@class _G
---@field TSM_API TSMApi?
---@field AuctionatorBuyCommodityFrame table?
---@field AuctionatorBuyCommodityFrameTemplateMixin table?
---@field AUCTIONATOR_L_BUY_NOW string?
