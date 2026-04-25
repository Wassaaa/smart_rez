---@meta

---@class AceGUIWidget
local AceGUIWidget = {}

---@param width number
function AceGUIWidget:SetWidth(width) end

---@param height number
function AceGUIWidget:SetHeight(height) end

---@param isFull boolean
function AceGUIWidget:SetFullWidth(isFull) end

---@param isFull boolean
function AceGUIWidget:SetFullHeight(isFull) end

---@param name string
---@param func fun(widget: AceGUIWidget, event: string, ...: any)
function AceGUIWidget:SetCallback(name, func) end

function AceGUIWidget:Hide() end

function AceGUIWidget:Show() end

---@return boolean
function AceGUIWidget:IsShown() end

---@class AceGUIContainer: AceGUIWidget
---@field children? AceGUIWidget[]
local AceGUIContainer = {}

---@param child AceGUIWidget
function AceGUIContainer:AddChild(child) end

function AceGUIContainer:ReleaseChildren() end

---@param layout string
function AceGUIContainer:SetLayout(layout) end

---@class AceGUILabel: AceGUIWidget
local AceGUILabel = {}

---@param text string?
function AceGUILabel:SetText(text) end

---@class AceGUIInteractiveLabel: AceGUILabel
local AceGUIInteractiveLabel = {}

---@class AceGUIButton: AceGUIWidget
local AceGUIButton = {}

---@param text string?
function AceGUIButton:SetText(text) end

---@class AceGUIEditBox: AceGUIWidget
local AceGUIEditBox = {}

---@param text string?
function AceGUIEditBox:SetText(text) end

---@return string
function AceGUIEditBox:GetText() end

---@param text string?
function AceGUIEditBox:SetLabel(text) end

---@param disabled boolean
function AceGUIEditBox:DisableButton(disabled) end

---@class AceGUIIcon: AceGUIWidget
---@field frame table
---@field image table
---@field qualityBadge? table
---@field selectionGlow? table

---@param text string?
function AceGUIIcon:SetLabel(text) end

---@param path any
function AceGUIIcon:SetImage(path, ...) end

---@param width number
---@param height number
function AceGUIIcon:SetImageSize(width, height) end

---@param disabled boolean
function AceGUIIcon:SetDisabled(disabled) end

---@class AceGUICheckBox: AceGUIWidget
local AceGUICheckBox = {}

---@param text string?
function AceGUICheckBox:SetLabel(text) end

---@param value boolean
function AceGUICheckBox:SetValue(value) end

---@class AceGUISlider: AceGUIWidget
local AceGUISlider = {}

---@param text string?
function AceGUISlider:SetLabel(text) end

---@param min number
---@param max number
---@param step number
function AceGUISlider:SetSliderValues(min, max, step) end

---@param value number
function AceGUISlider:SetValue(value) end

---@class AceGUIDropdown: AceGUIWidget
local AceGUIDropdown = {}

---@param text string?
function AceGUIDropdown:SetLabel(text) end

---@param list table
function AceGUIDropdown:SetList(list) end

---@param value string|number?
function AceGUIDropdown:SetValue(value) end

---@class AceGUISimpleGroup: AceGUIContainer
local AceGUISimpleGroup = {}

---@class AceGUIInlineGroup: AceGUIContainer
local AceGUIInlineGroup = {}

---@param text string?
function AceGUIInlineGroup:SetTitle(text) end

---@class AceGUIScrollFrame: AceGUIContainer
---@field localstatus? table
---@field status? table
local AceGUIScrollFrame = {}

---@param status table
function AceGUIScrollFrame:SetStatusTable(status) end

---@param value number
function AceGUIScrollFrame:SetScroll(value) end

---@class AceGUIWindow: AceGUIContainer
---@field frame table
local AceGUIWindow = {}

---@param text string?
function AceGUIWindow:SetTitle(text) end

---@param text string?
function AceGUIWindow:SetStatusText(text) end

---@param enabled boolean
function AceGUIWindow:EnableResize(enabled) end

---@class AceGUITabDefinition
---@field text string
---@field value string
---@field disabled? boolean

---@class AceGUITabGroup: AceGUIContainer
---@field selected? string
local AceGUITabGroup = {}

---@param text string?
function AceGUITabGroup:SetTitle(text) end

---@param tabs AceGUITabDefinition[]
function AceGUITabGroup:SetTabs(tabs) end

---@param value string
function AceGUITabGroup:SelectTab(value) end

---@class AceGUILib
local AceGUILib = {}

---@overload fun(self: AceGUILib, widgetType: "Label"): AceGUILabel
---@overload fun(self: AceGUILib, widgetType: "InteractiveLabel"): AceGUIInteractiveLabel
---@overload fun(self: AceGUILib, widgetType: "Button"): AceGUIButton
---@overload fun(self: AceGUILib, widgetType: "EditBox"): AceGUIEditBox
---@overload fun(self: AceGUILib, widgetType: "Icon"): AceGUIIcon
---@overload fun(self: AceGUILib, widgetType: "CheckBox"): AceGUICheckBox
---@overload fun(self: AceGUILib, widgetType: "Slider"): AceGUISlider
---@overload fun(self: AceGUILib, widgetType: "Dropdown"): AceGUIDropdown
---@overload fun(self: AceGUILib, widgetType: "SimpleGroup"): AceGUISimpleGroup
---@overload fun(self: AceGUILib, widgetType: "InlineGroup"): AceGUIInlineGroup
---@overload fun(self: AceGUILib, widgetType: "ScrollFrame"): AceGUIScrollFrame
---@overload fun(self: AceGUILib, widgetType: "Window"): AceGUIWindow
---@overload fun(self: AceGUILib, widgetType: "TabGroup"): AceGUITabGroup
---@param widgetType string
---@return AceGUIWidget
function AceGUILib:Create(widgetType) end
