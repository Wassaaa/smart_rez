local SmartRez = _G.SmartRez

---@type AceGUILib
local AceGUI = LibStub("AceGUI-3.0")

local UI = SmartRez.UI

---@class SmartRezAHSellingWindow: AceGUIWindow
---@field scroll AceGUIScrollFrame
---@field scrollStatus table

---@type SmartRezAHSellingWindow?
local sellConfigFrame

local function captureSellScrollStatus()
	if not (sellConfigFrame and sellConfigFrame.scroll) then
		return
	end

	sellConfigFrame.scrollStatus = sellConfigFrame.scrollStatus or { scrollvalue = 0 }
	local scroll = sellConfigFrame.scroll
	local sourceStatus = scroll.status or scroll.localstatus
	if scroll.scrollbar and scroll.scrollbar.GetValue then
		sellConfigFrame.scrollStatus.scrollvalue = scroll.scrollbar:GetValue() or sellConfigFrame.scrollStatus.scrollvalue or 0
	else
		sellConfigFrame.scrollStatus.scrollvalue = sourceStatus and sourceStatus.scrollvalue or sellConfigFrame.scrollStatus.scrollvalue or 0
	end
	sellConfigFrame.scrollStatus.offset = sourceStatus and sourceStatus.offset or sellConfigFrame.scrollStatus.offset or 0
end

function SmartRez:CaptureAHSellingScrollStatus()
	captureSellScrollStatus()
end

local function getSellScrollSnapshot()
	local status = sellConfigFrame and sellConfigFrame.scrollStatus or nil
	return {
		scrollvalue = status and status.scrollvalue or 0,
		offset = status and status.offset or 0,
	}
end

local function restoreSellScrollStatus(snapshot)
	if not (sellConfigFrame and sellConfigFrame.scroll and sellConfigFrame.scroll.SetScroll) then
		return
	end

	local scroll = sellConfigFrame.scroll
	local status = sellConfigFrame.scrollStatus or { scrollvalue = 0 }
	local restoreStatus = snapshot or status
	local function apply()
		if sellConfigFrame and sellConfigFrame.scroll == scroll and scroll.SetScroll then
			status.scrollvalue = restoreStatus.scrollvalue or 0
			status.offset = restoreStatus.offset or status.offset or 0
			scroll:SetScroll(status.scrollvalue or 0)
		end
	end

	apply()
	if C_Timer and C_Timer.After then
		C_Timer.After(0, apply)
		C_Timer.After(0.05, apply)
		C_Timer.After(0.15, apply)
		C_Timer.After(0.3, apply)
	end
end

local function refreshSellConfigSurfaces(preserveCapturedScroll, sellScrollSnapshot)
	if C_Timer and C_Timer.After then
		C_Timer.After(0, function()
			if sellConfigFrame and sellConfigFrame.Refresh then
				sellConfigFrame:Refresh(preserveCapturedScroll and "preserve" or "config", sellScrollSnapshot)
			end
			if SmartRez.RefreshAutomationConfigTab then
				SmartRez:RefreshAutomationConfigTab("ahselling", preserveCapturedScroll == true)
			end
		end)
	else
		if sellConfigFrame and sellConfigFrame.Refresh then
			sellConfigFrame:Refresh(preserveCapturedScroll and "preserve" or "config", sellScrollSnapshot)
		end
		if SmartRez.RefreshAutomationConfigTab then
			SmartRez:RefreshAutomationConfigTab("ahselling", preserveCapturedScroll == true)
		end
	end
end

function SmartRez:RefreshAHSellingConfigSurfaces(preserveScroll)
	local sellScrollSnapshot
	if preserveScroll then
		captureSellScrollStatus()
		sellScrollSnapshot = getSellScrollSnapshot()
		if SmartRez.CaptureAutomationConfigScrollStatus then
			SmartRez:CaptureAutomationConfigScrollStatus()
		end
	end
	refreshSellConfigSurfaces(preserveScroll == true, sellScrollSnapshot)
end

local function mutateAHSellingConfig(callback)
	captureSellScrollStatus()
	local sellScrollSnapshot = getSellScrollSnapshot()
	if SmartRez.CaptureAutomationConfigScrollStatus then
		SmartRez:CaptureAutomationConfigScrollStatus()
	end
	callback()
	refreshSellConfigSurfaces(true, sellScrollSnapshot)
end

local function addTinyLabel(group, text, width, color)
	local label = AceGUI:Create("Label")
	label:SetWidth(width or 48)
	label:SetText(UI.Colorize(color or "7D8590", text))
	group:AddChild(label)
	return label
end

local function addCompactEdit(group, width, value, onEnter)
	local editBox = AceGUI:Create("EditBox")
	editBox:SetWidth(width)
	editBox:SetText(tostring(value or ""))
	editBox:DisableButton(true)
	editBox:SetCallback("OnEnterPressed", function(_, _, enteredValue)
		onEnter(enteredValue)
	end)
	group:AddChild(editBox)
	return editBox
end

local function renderItemConfig(parent, snapshot, itemID)
	local itemData = snapshot.itemsByID[itemID] or {}
	local itemConfig = SmartRez:GetAHSellingItemConfig(itemID)
	local itemName = itemData.itemLink or UI.GetItemDisplay(itemID)

	local itemGroup = AceGUI:Create("SimpleGroup")
	itemGroup:SetFullWidth(true)
	itemGroup:SetLayout("List")
	parent:AddChild(itemGroup)

	local titleRow = AceGUI:Create("SimpleGroup")
	titleRow:SetFullWidth(true)
	titleRow:SetLayout("Flow")
	itemGroup:AddChild(titleRow)

	local itemLabel = AceGUI:Create("Label")
	itemLabel:SetWidth(270)
	itemLabel:SetText(string.format(
		"%s  %s",
		itemName,
		UI.Colorize("79C0FF", "x" .. tostring(itemData.count or 0))
	))
	titleRow:AddChild(itemLabel)

	local latestScanText = SmartRez:GetAHSellingLatestScanDisplayText(itemID)
	if latestScanText and latestScanText ~= "" then
		local latestLabel = AceGUI:Create("Label")
		latestLabel:SetWidth(100)
		latestLabel:SetText(latestScanText)
		titleRow:AddChild(latestLabel)
	end

	local configRow = AceGUI:Create("SimpleGroup")
	configRow:SetFullWidth(true)
	configRow:SetLayout("Flow")
	itemGroup:AddChild(configRow)

	addTinyLabel(configRow, "Stack", 52)
	addCompactEdit(configRow, 44, itemConfig.stackSize or 1, function(value)
		mutateAHSellingConfig(function()
			SmartRez:SetAHSellingItemConfigValue(itemID, "stackSize", value, true)
		end)
	end)

	configRow:AddChild(UI.CreateHorizontalSpacer(8))
	addTinyLabel(configRow, "Keep", 44)
	addCompactEdit(configRow, 44, itemConfig.keepInBags or 0, function(value)
		mutateAHSellingConfig(function()
			SmartRez:SetAHSellingItemConfigValue(itemID, "keepInBags", value, true)
		end)
	end)

	configRow:AddChild(UI.CreateHorizontalSpacer(8))
	addTinyLabel(configRow, "Min", 42)
	addCompactEdit(configRow, 120, SmartRez:GetAHSellingMinPriceDisplayText(itemConfig.minPriceExpression), function(value)
		mutateAHSellingConfig(function()
			SmartRez:SetAHSellingItemConfigValue(itemID, "minPriceExpression", value, true)
		end)
	end)

	UI.AddSectionSpacer(itemGroup)
end

---@param parent AceGUIContainer
function UI.RenderAHSellingTab(parent)
	local snapshot = SmartRez:BuildAHSellingSnapshot()
	local currentSnapshot = snapshot

	if SmartRez.RegisterAutomationConfigInventoryRefresher then
		SmartRez:RegisterAutomationConfigInventoryRefresher(function()
			currentSnapshot = SmartRez:BuildAHSellingSnapshot()
		end)
	end

	local summary = UI.CreateCard(parent, "AH Selling")
	UI.AddLabel(summary, "Configure auctionable player-bag items here. Posting still requires the Auction House to be open; this window is only the setup surface.", "A5D6FF")

	UI.RenderIconMultiPicker(parent, {
		title = "Selling Items",
		helpText = "Auctionable items from player bags. Click icons to include or exclude them from the Smart Rez AH selling list.",
		availableItemIDs = snapshot.availableItemIDs,
		getSelectedSet = function()
			return SmartRez:GetAHSellingWhitelist()
		end,
		getItemCount = function(itemID)
			local itemData = currentSnapshot.itemsByID[itemID]
			return itemData and itemData.count or 0
		end,
		getIconLabel = function(itemID)
			local itemData = currentSnapshot.itemsByID[itemID]
			local itemCount = itemData and itemData.count or 0
			return UI.Colorize(itemCount > 0 and "79C0FF" or "7D8590", tostring(itemCount))
		end,
		addTooltipLines = function(tooltip, itemID, _, isSelected)
			local itemData = currentSnapshot.itemsByID[itemID]
			tooltip:AddLine(" ")
			tooltip:AddLine("Player bags: " .. tostring(itemData and itemData.count or 0), 0.48, 0.75, 1)
			tooltip:AddLine(isSelected and "Included in AH selling" or "Not included in AH selling", 0.49, isSelected and 0.91 or 0.52, isSelected and 0.53 or 0.56)
		end,
		addItemFunc = function(itemID)
			mutateAHSellingConfig(function()
				SmartRez:AddAHSellingWhitelistItem(itemID, true)
				currentSnapshot = SmartRez:BuildAHSellingSnapshot()
			end)
		end,
		removeItemFunc = function(itemID)
			mutateAHSellingConfig(function()
				SmartRez:RemoveAHSellingWhitelistItem(itemID, true)
				currentSnapshot = SmartRez:BuildAHSellingSnapshot()
			end)
		end,
		emptySelectionText = "No AH selling items selected yet.",
		selectedStatusTextPrefix = "Configured ",
		selectedStatusTextSuffix = " item(s). Click highlighted icons to remove them.",
		controlHintText = "Click icons to choose which item types the AH sell button will consider.",
		emptyText = "No auctionable player-bag items are visible right now.",
	})

	for _, itemID in ipairs(SmartRez:GetAHSellingOrderedItemIDs()) do
		if SmartRez:GetAHSellingWhitelist()[itemID] then
			renderItemConfig(parent, currentSnapshot, itemID)
		end
	end
end

local function createSellConfigWindow()
	if sellConfigFrame then
		return sellConfigFrame
	end

	---@type SmartRezAHSellingWindow
	sellConfigFrame = AceGUI:Create("Window")
	sellConfigFrame:SetStatusTable(UI.GetWindowStatus("ahSelling", {
		width = 680,
		height = 600,
	}))
	sellConfigFrame:SetTitle("Smart Rez AH Selling")
	sellConfigFrame:SetStatusText("")
	sellConfigFrame:EnableResize(false)
	sellConfigFrame:SetLayout("Fill")
	sellConfigFrame.frame:SetFrameStrata("DIALOG")
	sellConfigFrame:SetCallback("OnClose", function(widget)
		widget:Hide()
	end)

	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetLayout("List")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	sellConfigFrame.scrollStatus = sellConfigFrame.scrollStatus or { scrollvalue = 0 }
	scroll:SetStatusTable(sellConfigFrame.scrollStatus)
	sellConfigFrame:AddChild(scroll)
	sellConfigFrame.scroll = scroll

	function sellConfigFrame:Refresh(reason, scrollSnapshot)
		if reason ~= "preserve" then
			captureSellScrollStatus()
			scrollSnapshot = getSellScrollSnapshot()
		end
		if reason == "inventory" and self:IsShown() then
			self.scroll:ReleaseChildren()
			UI.RenderAHSellingTab(self.scroll)
			if self.scroll.DoLayout then
				self.scroll:DoLayout()
			end
			restoreSellScrollStatus(scrollSnapshot)
			return
		end

		self.scroll:ReleaseChildren()
		UI.RenderAHSellingTab(self.scroll)
		if self.scroll.DoLayout then
			self.scroll:DoLayout()
		end
		restoreSellScrollStatus(scrollSnapshot)
	end

	SmartRez:RegisterManagedFrame(sellConfigFrame)
	return sellConfigFrame
end

function SmartRez:ShowAHSellingWindow()
	local window = createSellConfigWindow()
	window:Refresh()
	window:Show()
end
