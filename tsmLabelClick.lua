local SmartRez = _G.SmartRez
local RESTRICTIONS = {
	mail = {
		uiName = "MAILING",
		requireMail = true,
		missingUIMessage = "Smart Rez: open the TSM mailbox UI before using this macro.",
	},
	ah = {
		uiName = "AUCTION",
		missingUIMessage = "Smart Rez: open the TSM auction UI before using this macro.",
	},
	auction = {
		uiName = "AUCTION",
		missingUIMessage = "Smart Rez: open the TSM auction UI before using this macro.",
	},
	prof = {
		uiName = "CRAFTING",
		missingUIMessage = "Smart Rez: open the TSM profession UI before using this macro.",
	},
	profession = {
		uiName = "CRAFTING",
		missingUIMessage = "Smart Rez: open the TSM profession UI before using this macro.",
	},
	crafting = {
		uiName = "CRAFTING",
		missingUIMessage = "Smart Rez: open the TSM profession UI before using this macro.",
	},
}
local nextLabelClickTime = 0

local function getNow()
	if _G.GetTimePreciseSec then
		return _G.GetTimePreciseSec()
	end
	return _G.GetTime()
end

local function isUIVisible(uiName)
	if _G.TSM_API and _G.TSM_API.IsUIVisible and uiName then
		local ok, isVisible = pcall(_G.TSM_API.IsUIVisible, uiName)
		if ok and isVisible then
			return true
		end
	end

	return false
end

local function isMailVisible()
	return isUIVisible("MAILING") or (_G.MailFrame and _G.MailFrame:IsShown())
end

local function getButtonText(button)
	if not button then
		return nil
	end

	if type(button.GetText) == "function" then
		local text = button:GetText()
		if text and text ~= "" then
			return text
		end
	end

	local textRegion = button.text
	if textRegion and type(textRegion.GetText) == "function" then
		local text = textRegion:GetText()
		if text and text ~= "" then
			return text
		end
	end

	local regions = { button:GetRegions() }
	for _, region in ipairs(regions) do
		if region and region.GetObjectType and region:GetObjectType() == "FontString" then
			local text = region:GetText()
			if text and text ~= "" then
				return text
			end
		end
	end

	return nil
end

local function normalizeLabel(label)
	if type(label) ~= "string" then
		return nil
	end

	label = label:match("^%s*(.-)%s*$")
	if label == "" then
		return nil
	end

	return label:lower()
end

local function normalizeRestrictionName(name)
	return normalizeLabel(name)
end

local function normalizeLabels(labels)
	local result = {}
	for _, label in ipairs(labels or {}) do
		label = normalizeLabel(label)
		if label then
			result[#result + 1] = label
		end
	end
	return result
end

local function findVisibleButtonByLabel(labels, frameValidator)
	local wanted = {}
	for _, label in ipairs(labels) do
		wanted[label] = true
	end

	local frame = EnumerateFrames()
	while frame do
		if frame.IsObjectType and frame:IsObjectType("Button") and frame.IsShown and frame:IsShown() and frame.IsEnabled and frame:IsEnabled() then
			local text = getButtonText(frame)
			local normalizedText = normalizeLabel(text)
			if normalizedText and wanted[normalizedText] and (not frameValidator or frameValidator(frame, text)) then
				return frame, text
			end
		end
		frame = EnumerateFrames(frame)
	end

	return nil
end

local function defaultClickError(config)
	if config and config.requireMail then
		return "Smart Rez: open the TSM mailbox UI before using this macro."
	end

	return "Smart Rez: required TSM UI is not open."
end

local function isOnLabelClickCooldown()
	return getNow() < nextLabelClickTime
end

local function startLabelClickCooldown()
	nextLabelClickTime = getNow() + (SmartRez.GetTSMLabelClickCooldown and SmartRez:GetTSMLabelClickCooldown() or 0.25)
end

local function printLabelClickMessage(message)
	if SmartRez.GetTSMLabelClickShowMacroErrors and not SmartRez:GetTSMLabelClickShowMacroErrors() then
		return
	end

	print(message)
end

function SmartRez:ClickVisibleButtonByLabel(config)
	config = config or {}
	local labels = normalizeLabels(config.labels)
	if #labels == 0 then
		printLabelClickMessage("Smart Rez: no labels were configured for this proxy button.")
		return
	end

	if isOnLabelClickCooldown() then
		return
	end

	if config.uiName and not isUIVisible(config.uiName) then
		printLabelClickMessage(config.missingUIMessage or defaultClickError(config))
		return
	end

	if config.requireMail and not isMailVisible() then
		printLabelClickMessage(config.missingUIMessage or defaultClickError(config))
		return
	end

	local button = findVisibleButtonByLabel(labels, config.frameValidator)
	if not button then
		printLabelClickMessage(config.missingButtonMessage or "Smart Rez: could not find a visible TSM button with a matching label.")
		return
	end

	startLabelClickCooldown()
	button:Click()
end

function SmartRez:GetTSMLabelClickRestriction(name)
	name = normalizeRestrictionName(name)
	return name and RESTRICTIONS[name] or nil
end

function SmartRez:ClickVisibleTSMButton(label, restrictionName)
	local displayLabel = type(label) == "string" and label:match("^%s*(.-)%s*$") or ""
	if displayLabel == "" then
		printLabelClickMessage("Smart Rez: provide a TSM button label to click.")
		return
	end

	local restriction = nil
	if restrictionName ~= nil then
		restriction = self:GetTSMLabelClickRestriction(restrictionName)
		if not restriction then
			printLabelClickMessage("Smart Rez: unknown TSM restriction '" .. tostring(restrictionName) .. "'. Use mail, ah, or prof.")
			return
		end
	end

	self:ClickVisibleButtonByLabel({
		uiName = restriction and restriction.uiName or nil,
		requireMail = restriction and restriction.requireMail or false,
		labels = { displayLabel },
		missingUIMessage = restriction and restriction.missingUIMessage or "Smart Rez: required TSM UI is not open.",
		missingButtonMessage = "Smart Rez: could not find a visible TSM button labeled '" .. displayLabel .. "'.",
	})
end

function SmartRez:RegisterLabelClickProxy(config)
	assert(type(config) == "table")
	assert(type(config.buttonName) == "string" and config.buttonName ~= "")

	local button = CreateFrame("Button", config.buttonName, UIParent, "SecureActionButtonTemplate")
	button:RegisterForClicks("AnyUp", "AnyDown")
	button:SetScript("OnClick", function()
		SmartRez:ClickVisibleButtonByLabel(config)
	end)

	if config.key and config.label then
		SmartRez:RegisterBindableAction({
			key = config.key,
			label = config.label,
			buttonName = config.buttonName,
			order = config.order or 100,
		})
	end

	return button
end
