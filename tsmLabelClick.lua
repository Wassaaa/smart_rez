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
local UI_ORDER = { "CRAFTING", "AUCTION", "MAILING" }
local nextLabelClickTime = 0
local recentMacroErrors = {}
local rootFramesByUI = {
	AUCTION = {},
	CRAFTING = {},
	MAILING = {},
}
local buttonIndexByUI = {
	AUCTION = {},
	CRAFTING = {},
	MAILING = {},
}
local rootHooks = setmetatable({}, { __mode = "k" })
local buttonHooks = setmetatable({}, { __mode = "k" })
local refreshPendingByUI = {}
local registeredCraftingCallback = false
local MACRO_ERROR_THROTTLE = 1
local ROOT_FRAME_PREFIX = "TSM_FRAME:"

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

local function isButtonClickable(button)
	return button
		and button.IsObjectType
		and button:IsObjectType("Button")
		and button.IsShown
		and button:IsShown()
		and button.IsEnabled
		and button:IsEnabled()
end

local function validateIndexedButton(button, wantedLabels, frameValidator)
	if not isButtonClickable(button) then
		return nil
	end

	local text = getButtonText(button)
	local normalizedText = normalizeLabel(text)
	if not normalizedText or not wantedLabels[normalizedText] then
		return nil
	end

	if frameValidator and not frameValidator(button, text) then
		return nil
	end

	return button, text
end

local function buildWantedLabelSet(labels)
	local wanted = {}
	for _, label in ipairs(labels or {}) do
		wanted[label] = true
	end
	return wanted
end

local function clearUIButtonIndex(uiName)
	buttonIndexByUI[uiName] = {}
	rootFramesByUI[uiName] = {}
end

local function printLabelClickMessage(message)
	if SmartRez.GetTSMLabelClickShowMacroErrors and not SmartRez:GetTSMLabelClickShowMacroErrors() then
		return
	end

	local now = getNow()
	local nextAllowedTime = recentMacroErrors[message]
	if nextAllowedTime and now < nextAllowedTime then
		return
	end

	recentMacroErrors[message] = now + MACRO_ERROR_THROTTLE
	print(message)
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

local function frameNameHasPrefix(frame, prefix)
	if not frame or not frame.GetName then
		return false
	end

	local name = frame:GetName()
	return type(name) == "string" and name:sub(1, #prefix) == prefix
end

local function hasTSMFrameAncestor(frame)
	local parent = frame and frame.GetParent and frame:GetParent() or nil
	while parent do
		if frameNameHasPrefix(parent, ROOT_FRAME_PREFIX) then
			return true
		end
		parent = parent.GetParent and parent:GetParent() or nil
	end
	return false
end

local function discoverVisibleTSMRoots()
	local roots = {}
	local frame = _G.EnumerateFrames()
	while frame do
		if frame.IsObjectType and frame:IsObjectType("Frame") and frame.IsShown and frame:IsShown() and frameNameHasPrefix(frame, ROOT_FRAME_PREFIX) and not hasTSMFrameAncestor(frame) then
			roots[#roots + 1] = frame
		end
		frame = _G.EnumerateFrames(frame)
	end
	return roots
end

local warmUIButtonIndex

local function scheduleUIButtonRefresh(uiName, explicitRoot)
	if refreshPendingByUI[uiName] then
		return
	end

	refreshPendingByUI[uiName] = true
	_G.C_Timer.After(0, function()
		refreshPendingByUI[uiName] = nil
		if not isUIVisible(uiName) then
			clearUIButtonIndex(uiName)
			return
		end

		local roots = {}
		if explicitRoot then
			roots[1] = explicitRoot
		else
			roots = discoverVisibleTSMRoots()
		end

		rootFramesByUI[uiName] = roots
		local index = {}
		local visited = {}

		local function hookRootFrame(rootFrame)
			if not rootFrame or rootHooks[rootFrame] then
				return
			end
			rootHooks[rootFrame] = true
			rootFrame:HookScript("OnShow", function()
				scheduleUIButtonRefresh(uiName, rootFrame)
			end)
			rootFrame:HookScript("OnHide", function()
				if not isUIVisible(uiName) then
					clearUIButtonIndex(uiName)
				else
					scheduleUIButtonRefresh(uiName)
				end
			end)
		end

		local function hookButtonFrame(buttonFrame)
			if not buttonFrame or buttonHooks[buttonFrame] then
				return
			end
			buttonHooks[buttonFrame] = true
			buttonFrame:HookScript("OnClick", function()
				if not buttonFrame:IsMouseMotionFocus() then
					return
				end
				warmUIButtonIndex(uiName)
			end)
		end

		local function walk(frame)
			if not frame or visited[frame] then
				return
			end
			visited[frame] = true

			if frame.IsObjectType and frame:IsObjectType("Button") then
				hookButtonFrame(frame)
			end

			if isButtonClickable(frame) then
				local text = getButtonText(frame)
				local normalizedText = normalizeLabel(text)
				if normalizedText and not index[normalizedText] then
					index[normalizedText] = frame
				end
			end

			local children = { frame:GetChildren() }
			for _, child in ipairs(children) do
				walk(child)
			end
		end

		for _, rootFrame in ipairs(roots) do
			hookRootFrame(rootFrame)
			walk(rootFrame)
		end

		buttonIndexByUI[uiName] = index
	end)
end

warmUIButtonIndex = function(uiName, explicitRoot)
	scheduleUIButtonRefresh(uiName, explicitRoot)
	_G.C_Timer.After(0.1, function()
		if isUIVisible(uiName) then
			scheduleUIButtonRefresh(uiName, explicitRoot)
		end
	end)
end

local function refreshUIButtonIndexNow(uiName, explicitRoot)
	if refreshPendingByUI[uiName] then
		return
	end

	scheduleUIButtonRefresh(uiName, explicitRoot)
	if refreshPendingByUI[uiName] and not _G.InCombatLockdown() then
		-- The zero-delay timer will still run this frame; callers retry on the next press.
	end
end

local function registerCraftingUICallback()
	if registeredCraftingCallback or not (_G.TSM_API and _G.TSM_API.RegisterUICallback) then
		return
	end

	local ok = pcall(_G.TSM_API.RegisterUICallback, "CRAFTING", "SmartRez:TSMLabelClick", function(visible, frame)
		if visible and frame then
			warmUIButtonIndex("CRAFTING", frame)
		else
			clearUIButtonIndex("CRAFTING")
		end
	end)
	if ok then
		registeredCraftingCallback = true
	end
end

local function getIndexedButton(uiName, labels, frameValidator)
	local index = buttonIndexByUI[uiName]
	local wanted = buildWantedLabelSet(labels)

	for _, label in ipairs(labels) do
		local button = index and index[label] or nil
		local matchedButton, matchedText = validateIndexedButton(button, wanted, frameValidator)
		if matchedButton then
			return matchedButton, matchedText
		end
	end

	return nil
end

local function findVisibleButtonByLabel(labels, config)
	local frameValidator = config and config.frameValidator
	local uiName = config and config.uiName or nil

	if uiName then
		local button, text = getIndexedButton(uiName, labels, frameValidator)
		if button then
			return button, text
		end

		refreshUIButtonIndexNow(uiName)
		return nil
	end

	for _, activeUIName in ipairs(UI_ORDER) do
		if isUIVisible(activeUIName) then
			local button, text = getIndexedButton(activeUIName, labels, frameValidator)
			if button then
				return button, text
			end
		end
	end

	for _, activeUIName in ipairs(UI_ORDER) do
		if isUIVisible(activeUIName) then
			refreshUIButtonIndexNow(activeUIName)
		end
	end

	return nil
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

	local button = findVisibleButtonByLabel(labels, config)
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

local watcherFrame = CreateFrame("Frame")
watcherFrame:RegisterEvent("ADDON_LOADED")
watcherFrame:RegisterEvent("MAIL_SHOW")
watcherFrame:RegisterEvent("MAIL_CLOSED")
watcherFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
watcherFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")
watcherFrame:RegisterEvent("TRADE_SKILL_SHOW")
watcherFrame:RegisterEvent("TRADE_SKILL_CLOSE")
watcherFrame:SetScript("OnEvent", function(_, eventName, arg1)
	if eventName == "ADDON_LOADED" and arg1 == "TradeSkillMaster" then
		registerCraftingUICallback()
	elseif eventName == "MAIL_SHOW" then
		warmUIButtonIndex("MAILING")
	elseif eventName == "MAIL_CLOSED" then
		clearUIButtonIndex("MAILING")
	elseif eventName == "AUCTION_HOUSE_SHOW" then
		warmUIButtonIndex("AUCTION")
	elseif eventName == "AUCTION_HOUSE_CLOSED" then
		clearUIButtonIndex("AUCTION")
	elseif eventName == "TRADE_SKILL_SHOW" then
		registerCraftingUICallback()
		warmUIButtonIndex("CRAFTING")
	elseif eventName == "TRADE_SKILL_CLOSE" then
		clearUIButtonIndex("CRAFTING")
	end
end)

registerCraftingUICallback()
