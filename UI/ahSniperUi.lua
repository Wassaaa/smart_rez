local SmartRez = _G.SmartRez

---@type AceGUILib
local AceGUI = LibStub("AceGUI-3.0")

local UI = SmartRez.UI

---@class SmartRezAHSniperWindow: AceGUIWindow
---@field scroll AceGUIScrollFrame
---@field scrollStatus table

---@type SmartRezAHSniperWindow?
local sniperConfigFrame

local function captureSniperScrollStatus()
	if not (sniperConfigFrame and sniperConfigFrame.scroll) then
		return
	end

	sniperConfigFrame.scrollStatus = sniperConfigFrame.scrollStatus or { scrollvalue = 0 }
	local scroll = sniperConfigFrame.scroll
	local sourceStatus = scroll.status or scroll.localstatus
	if scroll.scrollbar and scroll.scrollbar.GetValue then
		sniperConfigFrame.scrollStatus.scrollvalue = scroll.scrollbar:GetValue() or sniperConfigFrame.scrollStatus.scrollvalue or 0
	else
		sniperConfigFrame.scrollStatus.scrollvalue = sourceStatus and sourceStatus.scrollvalue or sniperConfigFrame.scrollStatus.scrollvalue or 0
	end
	sniperConfigFrame.scrollStatus.offset = sourceStatus and sourceStatus.offset or sniperConfigFrame.scrollStatus.offset or 0
end

function SmartRez:CaptureAHSniperScrollStatus()
	captureSniperScrollStatus()
end

local function getSniperScrollSnapshot()
	local status = sniperConfigFrame and sniperConfigFrame.scrollStatus or nil
	return {
		scrollvalue = status and status.scrollvalue or 0,
		offset = status and status.offset or 0,
	}
end

local function restoreSniperScrollStatus(snapshot)
	if not (sniperConfigFrame and sniperConfigFrame.scroll and sniperConfigFrame.scroll.SetScroll) then
		return
	end

	local scroll = sniperConfigFrame.scroll
	local status = sniperConfigFrame.scrollStatus or { scrollvalue = 0 }
	local restoreStatus = snapshot or status
	local function apply()
		if sniperConfigFrame and sniperConfigFrame.scroll == scroll and scroll.SetScroll then
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

local function refreshSniperConfigSurfaces(preserveCapturedScroll, sniperScrollSnapshot)
	if C_Timer and C_Timer.After then
		C_Timer.After(0, function()
			if sniperConfigFrame and sniperConfigFrame.Refresh then
				sniperConfigFrame:Refresh(preserveCapturedScroll and "preserve" or "config", sniperScrollSnapshot)
			end
			if SmartRez.RefreshAutomationConfigTab then
				SmartRez:RefreshAutomationConfigTab("ahsniper", preserveCapturedScroll == true)
			end
		end)
	else
		if sniperConfigFrame and sniperConfigFrame.Refresh then
			sniperConfigFrame:Refresh(preserveCapturedScroll and "preserve" or "config", sniperScrollSnapshot)
		end
		if SmartRez.RefreshAutomationConfigTab then
			SmartRez:RefreshAutomationConfigTab("ahsniper", preserveCapturedScroll == true)
		end
	end
end

function SmartRez:RefreshAHSniperConfigSurfaces(preserveScroll)
	local sniperScrollSnapshot
	if preserveScroll then
		captureSniperScrollStatus()
		sniperScrollSnapshot = getSniperScrollSnapshot()
		if SmartRez.CaptureAutomationConfigScrollStatus then
			SmartRez:CaptureAutomationConfigScrollStatus()
		end
	end
	refreshSniperConfigSurfaces(preserveScroll == true, sniperScrollSnapshot)
end

local function mutateAHSniperConfig(callback)
	captureSniperScrollStatus()
	local sniperScrollSnapshot = getSniperScrollSnapshot()
	if SmartRez.CaptureAutomationConfigScrollStatus then
		SmartRez:CaptureAutomationConfigScrollStatus()
	end
	callback()
	refreshSniperConfigSurfaces(true, sniperScrollSnapshot)
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
	local itemConfig = SmartRez:GetAHSniperItemConfig(itemID)
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

	local latestScanText = SmartRez:GetAHSniperLatestScanDisplayText(itemID)
	if latestScanText and latestScanText ~= "" then
		local latestLabel = AceGUI:Create("Label")
		latestLabel:SetWidth(100)
		latestLabel:SetText(latestScanText)
		titleRow:AddChild(latestLabel)
	end

	local baitWarningText = SmartRez:GetAHSniperBaitWarningDisplayText(itemID)
	if baitWarningText and baitWarningText ~= "" then
		local baitWarningLabel = AceGUI:Create("Label")
		baitWarningLabel:SetWidth(190)
		baitWarningLabel:SetText(baitWarningText)
		titleRow:AddChild(baitWarningLabel)
	end

	local buyRow = AceGUI:Create("SimpleGroup")
	buyRow:SetFullWidth(true)
	buyRow:SetLayout("Flow")
	itemGroup:AddChild(buyRow)

	addTinyLabel(buyRow, "Buy", 44, "7EE787")
	addTinyLabel(buyRow, "Stack", 52)
	addCompactEdit(buyRow, 44, itemConfig.buyStackSize or 1, function(value)
		mutateAHSniperConfig(function()
			SmartRez:SetAHSniperItemConfigValue(itemID, "buyStackSize", value, true)
		end)
	end)
	buyRow:AddChild(UI.CreateHorizontalSpacer(8))
	addTinyLabel(buyRow, "Price", 48)
	addCompactEdit(buyRow, 120, SmartRez:GetAHPriceDisplayText(itemConfig.buyPriceExpression), function(value)
		mutateAHSniperConfig(function()
			SmartRez:SetAHSniperItemConfigValue(itemID, "buyPriceExpression", value, true)
		end)
	end)

	local baitRow = AceGUI:Create("SimpleGroup")
	baitRow:SetFullWidth(true)
	baitRow:SetLayout("Flow")
	itemGroup:AddChild(baitRow)

	addTinyLabel(baitRow, "Bait", 44, "79C0FF")
	addTinyLabel(baitRow, "Stack", 52)
	addCompactEdit(baitRow, 44, itemConfig.baitStackSize or 0, function(value)
		mutateAHSniperConfig(function()
			SmartRez:SetAHSniperItemConfigValue(itemID, "baitStackSize", value, true)
		end)
	end)
	baitRow:AddChild(UI.CreateHorizontalSpacer(8))
	addTinyLabel(baitRow, "Price", 48)
	addCompactEdit(baitRow, 120, SmartRez:GetAHPriceDisplayText(itemConfig.baitPriceExpression), function(value)
		mutateAHSniperConfig(function()
			SmartRez:SetAHSniperItemConfigValue(itemID, "baitPriceExpression", value, true)
		end)
	end)
	baitRow:AddChild(UI.CreateHorizontalSpacer(8))
	addTinyLabel(baitRow, "Sec", 36)
	addCompactEdit(baitRow, 44, itemConfig.baitIntervalSeconds or 30, function(value)
		mutateAHSniperConfig(function()
			SmartRez:SetAHSniperItemConfigValue(itemID, "baitIntervalSeconds", value, true)
		end)
	end)
	baitRow:AddChild(UI.CreateHorizontalSpacer(8))
	addTinyLabel(baitRow, "Keep", 44)
	addCompactEdit(baitRow, 44, itemConfig.baitKeepInBags or 0, function(value)
		mutateAHSniperConfig(function()
			SmartRez:SetAHSniperItemConfigValue(itemID, "baitKeepInBags", value, true)
		end)
	end)

	UI.AddSectionSpacer(itemGroup)
end

---@param parent AceGUIContainer
function UI.RenderAHSniperTab(parent)
	local snapshot = SmartRez:BuildAHPlayerBagSnapshot()
	local currentSnapshot = snapshot

	if SmartRez.RegisterAutomationConfigInventoryRefresher then
		SmartRez:RegisterAutomationConfigInventoryRefresher(function()
			currentSnapshot = SmartRez:BuildAHPlayerBagSnapshot()
		end)
	end

	local summary = UI.CreateCard(parent, "AH Sniper")
	UI.AddLabel(summary, "Configure buy caps and optional timed bait posts. The AH must be open; this first pass handles commodity items.", "A5D6FF")

	local warningRow = AceGUI:Create("SimpleGroup")
	warningRow:SetFullWidth(true)
	warningRow:SetLayout("Flow")
	summary:AddChild(warningRow)

	local refreshWarningsButton = AceGUI:Create("Button")
	refreshWarningsButton:SetText("Refresh bait warnings")
	refreshWarningsButton:SetWidth(180)
	refreshWarningsButton:SetCallback("OnClick", function()
		SmartRez:RefreshAHSniperBaitWarningPrices()
	end)
	warningRow:AddChild(refreshWarningsButton)

	addTinyLabel(warningRow, "/sr buywarn", 92, "7D8590")

	UI.RenderIconMultiPicker(parent, {
		title = "Sniper Items",
		helpText = "Auctionable items from player bags. Click icons to include or exclude them from the AH sniper list.",
		availableItemIDs = snapshot.availableItemIDs,
		getSelectedSet = function()
			return SmartRez:GetAHSniperWhitelist()
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
			tooltip:AddLine(isSelected and "Included in AH sniper" or "Not included in AH sniper", 0.49, isSelected and 0.91 or 0.52, isSelected and 0.53 or 0.56)
		end,
		addItemFunc = function(itemID)
			mutateAHSniperConfig(function()
				SmartRez:AddAHSniperWhitelistItem(itemID, true)
				currentSnapshot = SmartRez:BuildAHPlayerBagSnapshot()
			end)
		end,
		removeItemFunc = function(itemID)
			mutateAHSniperConfig(function()
				SmartRez:RemoveAHSniperWhitelistItem(itemID, true)
				currentSnapshot = SmartRez:BuildAHPlayerBagSnapshot()
			end)
		end,
		controlHintText = "Click icons to choose which item types the AH sniper button will consider.",
		emptyText = "No auctionable player-bag items are visible right now.",
	})

	for _, itemID in ipairs(SmartRez:GetAHSniperOrderedItemIDs()) do
		if SmartRez:GetAHSniperWhitelist()[itemID] then
			renderItemConfig(parent, currentSnapshot, itemID)
		end
	end
end

local function createSniperConfigWindow()
	if sniperConfigFrame then
		return sniperConfigFrame
	end

	---@type SmartRezAHSniperWindow
	sniperConfigFrame = AceGUI:Create("Window")
	sniperConfigFrame:SetStatusTable(UI.GetWindowStatus("ahSniper", {
		width = 680,
		height = 600,
	}))
	sniperConfigFrame:SetTitle("Smart Rez AH Sniper")
	sniperConfigFrame:SetStatusText("")
	sniperConfigFrame:EnableResize(false)
	sniperConfigFrame:SetLayout("Fill")
	sniperConfigFrame.frame:SetFrameStrata("DIALOG")
	sniperConfigFrame:SetCallback("OnClose", function(widget)
		widget:Hide()
	end)

	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetLayout("List")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	sniperConfigFrame.scrollStatus = sniperConfigFrame.scrollStatus or { scrollvalue = 0 }
	scroll:SetStatusTable(sniperConfigFrame.scrollStatus)
	sniperConfigFrame:AddChild(scroll)
	sniperConfigFrame.scroll = scroll

	function sniperConfigFrame:Refresh(reason, scrollSnapshot)
		if reason ~= "preserve" then
			captureSniperScrollStatus()
			scrollSnapshot = getSniperScrollSnapshot()
		end
		self.scroll:ReleaseChildren()
		UI.RenderAHSniperTab(self.scroll)
		if self.scroll.DoLayout then
			self.scroll:DoLayout()
		end
		restoreSniperScrollStatus(scrollSnapshot)
	end

	SmartRez:RegisterManagedFrame(sniperConfigFrame)
	return sniperConfigFrame
end

function SmartRez:ShowAHSniperWindow()
	local window = createSniperConfigWindow()
	window:Refresh()
	window:Show()
end
