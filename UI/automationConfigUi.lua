local SmartRez = _G.SmartRez
local APP_NAME = SmartRez.appName

---@type AceGUILib
local AceGUI = LibStub("AceGUI-3.0")

local UI = SmartRez.UI

SmartRez.managedFrames = SmartRez.managedFrames or {}

---@class SmartRezAutomationWindow: AceGUIWindow
---@field frame table
---@field tabs AceGUITabGroup
---@field selectedGroup string?
---@field scrollStatuses table<string, table>
---@field activeScroll AceGUIScrollFrame?
local automationConfigFrame

local WINDOW_WIDTH = 680
local WINDOW_HEIGHT = 600

local function debugPrint(...)
	if not (SmartRez.GetDebugEnabled and SmartRez:GetDebugEnabled()) then
		return
	end

	print("SmartRez UI:", ...)
end

local function getAutomationTabValue(professionKey)
	return "salvage:" .. tostring(professionKey)
end

local function getAutomationTabProfession(groupValue)
	local professionKey = type(groupValue) == "string" and groupValue:match("^salvage:(.+)$")
	if professionKey then
		return SmartRez:GetCraftSalvageProfession(professionKey)
	end
end

local function buildAutomationTabs()
	local tabs = {
		{ text = "Gold Printer", value = "goldprinter" },
		{ text = "Bag Value", value = "bagvalue" },
	}

	for _, profession in ipairs(SmartRez:GetCraftSalvageProfessions(true)) do
		tabs[#tabs + 1] = {
			text = profession.label,
			value = getAutomationTabValue(profession.key),
		}
	end

	return tabs
end

local function isAutomationTabAvailable(groupValue)
	if groupValue == "goldprinter" or groupValue == "bagvalue" then
		return true
	end

	local profession = getAutomationTabProfession(groupValue)
	return profession ~= nil and SmartRez:HasProfession(profession.professionID)
end

---@param parent AceGUIContainer
local function renderAutomationFooter(parent)
	local footerGroup = AceGUI:Create("SimpleGroup")
	footerGroup:SetFullWidth(true)
	footerGroup:SetLayout("Flow")
	parent:AddChild(footerGroup)

	local closeButton = AceGUI:Create("Button")
	closeButton:SetText(CLOSE)
	closeButton:SetWidth(100)
	closeButton:SetCallback("OnClick", function()
		automationConfigFrame:Hide()
	end)
	footerGroup:AddChild(closeButton)
end

local function getAutomationScrollStatus(groupValue)
	automationConfigFrame.scrollStatuses = automationConfigFrame.scrollStatuses or {}
	automationConfigFrame.scrollStatuses[groupValue] = automationConfigFrame.scrollStatuses[groupValue] or { scrollvalue = 0 }
	return automationConfigFrame.scrollStatuses[groupValue]
end

local function getSelectedAutomationTab()
	local tabs = automationConfigFrame and automationConfigFrame.tabs or nil
	local status = tabs and (tabs.status or tabs.localstatus) or nil
	return status and status.selected or nil
end

local function captureAutomationScrollStatus(groupValue)
	if not automationConfigFrame or not automationConfigFrame.tabs or not groupValue then
		return
	end

	---@type AceGUIScrollFrame?
	local selectedChild = automationConfigFrame.activeScroll or (automationConfigFrame.tabs.children and automationConfigFrame.tabs.children[1]) or nil
	if not selectedChild then
		return
	end

	local status = getAutomationScrollStatus(groupValue)
	local sourceStatus = selectedChild.status or selectedChild.localstatus
	if selectedChild.scrollbar and selectedChild.scrollbar.GetValue then
		status.scrollvalue = selectedChild.scrollbar:GetValue() or status.scrollvalue or 0
	else
		status.scrollvalue = sourceStatus and sourceStatus.scrollvalue or status.scrollvalue or 0
	end
	status.offset = sourceStatus and sourceStatus.offset or status.offset or 0
	debugPrint("capture scroll", tostring(groupValue), "value", string.format("%.2f", status.scrollvalue or 0), "offset", tostring(status.offset or 0))
end

function SmartRez:CaptureAutomationConfigScrollStatus()
	if automationConfigFrame then
		captureAutomationScrollStatus(automationConfigFrame.selectedGroup)
	end
end

local function getAutomationScrollSnapshot(groupValue)
	local status = getAutomationScrollStatus(groupValue)
	return {
		scrollvalue = status.scrollvalue or 0,
		offset = status.offset or 0,
	}
end

---@param scroll AceGUIScrollFrame
local function restoreAutomationScrollStatus(scroll, groupValue, snapshot)
	local status = getAutomationScrollStatus(groupValue)
	local restoreStatus = snapshot or status
	local function apply()
		if automationConfigFrame and automationConfigFrame.activeScroll == scroll and scroll.SetScroll then
			status.scrollvalue = restoreStatus.scrollvalue or 0
			status.offset = restoreStatus.offset or status.offset or 0
			scroll:SetScroll(status.scrollvalue or 0)
		end
	end

	if scroll.SetScroll then
		debugPrint("restore scroll", tostring(groupValue), "value", string.format("%.2f", restoreStatus.scrollvalue or 0), "offset", tostring(restoreStatus.offset or 0))
		apply()
		C_Timer.After(0, apply)
		C_Timer.After(0.05, apply)
		C_Timer.After(0.15, function()
			if automationConfigFrame and automationConfigFrame.activeScroll == scroll and scroll.SetScroll then
				scroll:SetScroll(status.scrollvalue or 0)
			end
		end)
	end
end

---@param scroll AceGUIContainer
local function renderSelectedAutomationTab(scroll, groupValue)
	if groupValue == "goldprinter" then
		UI.RenderGoldPrinterTab(scroll)
	elseif groupValue == "bagvalue" then
		UI.RenderBagValueTab(scroll)
	else
		local profession = getAutomationTabProfession(groupValue)
		if profession then
			UI.RenderCraftSalvageTab(scroll, profession)
		end
	end
end

---@param tabGroup AceGUITabGroup
---@param preserveScroll boolean?
local function renderAutomationGroup(tabGroup, groupValue, preserveScroll)
	debugPrint("render group", tostring(groupValue), "preserve", tostring(preserveScroll), "aceSelected", tostring(getSelectedAutomationTab()))
	if preserveScroll and automationConfigFrame and automationConfigFrame.activeScroll then
		local scroll = automationConfigFrame.activeScroll
		captureAutomationScrollStatus(groupValue)
		local scrollSnapshot = getAutomationScrollSnapshot(groupValue)
		scroll:ReleaseChildren()
		renderSelectedAutomationTab(scroll, groupValue)
		renderAutomationFooter(scroll)
		restoreAutomationScrollStatus(scroll, groupValue, scrollSnapshot)
		return
	end

	tabGroup:ReleaseChildren()

	---@type AceGUIScrollFrame
	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetLayout("List")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	if automationConfigFrame then
		automationConfigFrame.activeScroll = scroll
		scroll:SetStatusTable(getAutomationScrollStatus(groupValue))
	end
	tabGroup:AddChild(scroll)

	renderSelectedAutomationTab(scroll, groupValue)
	renderAutomationFooter(scroll)
	restoreAutomationScrollStatus(scroll, groupValue)
end

local function createAutomationConfigWindow()
	if automationConfigFrame then
		return automationConfigFrame
	end

	---@type SmartRezAutomationWindow
	automationConfigFrame = AceGUI:Create("Window")
	automationConfigFrame:SetTitle(APP_NAME .. " Setup")
	automationConfigFrame:SetStatusText("")
	automationConfigFrame:SetWidth(WINDOW_WIDTH)
	automationConfigFrame:SetHeight(WINDOW_HEIGHT)
	automationConfigFrame:EnableResize(false)
	automationConfigFrame:SetLayout("Fill")
	automationConfigFrame.frame:SetFrameStrata("DIALOG")
	automationConfigFrame:SetCallback("OnClose", function(widget)
		widget:Hide()
	end)
	automationConfigFrame.scrollStatuses = {}

	-- TabGroup works best with an outer Fill layout and an inner ScrollFrame per tab.
	automationConfigFrame.tabs = AceGUI:Create("TabGroup")
	automationConfigFrame.tabs:SetLayout("Fill")
	automationConfigFrame.tabs:SetCallback("OnGroupSelected", function(_, _, groupValue)
		debugPrint("tab selected", tostring(groupValue), "previous", tostring(automationConfigFrame.selectedGroup))
		captureAutomationScrollStatus(automationConfigFrame.selectedGroup)
		automationConfigFrame.selectedGroup = groupValue
		renderAutomationGroup(automationConfigFrame.tabs, groupValue, false)
	end)
	automationConfigFrame:AddChild(automationConfigFrame.tabs)

	function automationConfigFrame:Refresh()
		captureAutomationScrollStatus(self.selectedGroup)

		local tabs = buildAutomationTabs()
		self.tabs:SetTabs(tabs)

		local selectedGroup = self.selectedGroup
		if not selectedGroup or not isAutomationTabAvailable(selectedGroup) then
			selectedGroup = "goldprinter"
		end

		self.selectedGroup = selectedGroup
		local aceSelectedGroup = getSelectedAutomationTab()
		debugPrint("refresh", tostring(selectedGroup), "aceSelected", tostring(aceSelectedGroup))
		if aceSelectedGroup == selectedGroup then
			renderAutomationGroup(self.tabs, selectedGroup, true)
		else
			self.tabs:SelectTab(selectedGroup)
		end
	end

	table.insert(SmartRez.managedFrames, automationConfigFrame)
	return automationConfigFrame
end

function SmartRez:ShowAutomationConfigWindow()
	local configWindow = createAutomationConfigWindow()
	configWindow:Refresh()
	configWindow:Show()
end
