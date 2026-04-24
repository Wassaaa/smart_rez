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
local automationConfigFrame

local WINDOW_WIDTH = 680
local WINDOW_HEIGHT = 600

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

local function captureAutomationScrollStatus(groupValue)
	if not automationConfigFrame or not automationConfigFrame.tabs or not groupValue then
		return
	end

	---@type AceGUIScrollFrame?
	local selectedChild = automationConfigFrame.tabs.children and automationConfigFrame.tabs.children[1] or nil
	if not selectedChild or not selectedChild.localstatus then
		return
	end

	automationConfigFrame.scrollStatuses = automationConfigFrame.scrollStatuses or {}
	automationConfigFrame.scrollStatuses[groupValue] = automationConfigFrame.scrollStatuses[groupValue] or {}
	automationConfigFrame.scrollStatuses[groupValue].scrollvalue = selectedChild.localstatus.scrollvalue or automationConfigFrame.scrollStatuses[groupValue].scrollvalue or 0
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
local function renderAutomationGroup(tabGroup, groupValue)
	captureAutomationScrollStatus(groupValue)
	tabGroup:ReleaseChildren()

	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetLayout("List")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	if automationConfigFrame then
		automationConfigFrame.scrollStatuses = automationConfigFrame.scrollStatuses or {}
		automationConfigFrame.scrollStatuses[groupValue] = automationConfigFrame.scrollStatuses[groupValue] or {}
		scroll:SetStatusTable(automationConfigFrame.scrollStatuses[groupValue])
	end
	tabGroup:AddChild(scroll)

	renderSelectedAutomationTab(scroll, groupValue)
	renderAutomationFooter(scroll)
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
		automationConfigFrame.selectedGroup = groupValue
		renderAutomationGroup(automationConfigFrame.tabs, groupValue)
	end)
	automationConfigFrame:AddChild(automationConfigFrame.tabs)

	function automationConfigFrame:Refresh()
		local tabs = buildAutomationTabs()
		self.tabs:SetTabs(tabs)

		local selectedGroup = self.selectedGroup
		if not selectedGroup or not isAutomationTabAvailable(selectedGroup) then
			selectedGroup = "goldprinter"
		end

		self.selectedGroup = selectedGroup
		if self.tabs.selected == selectedGroup then
			renderAutomationGroup(self.tabs, selectedGroup)
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
