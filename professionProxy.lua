local SmartRez = _G.SmartRez

local professionProxyFrame
local professionProxyWatcher = CreateFrame("Frame")
local professionProxyTicker
local professionProxyHooksReady = false
local professionProxyInitialized = false
local professionProxyState = {
	enabled = false,
	professionID = nil,
	pendingUntil = 0,
}

local PROFESSION_PROXY_IDS = {
	alchemy = SmartRez.Profession.Alchemy,
	blacksmithing = SmartRez.Profession.Blacksmithing,
	cooking = SmartRez.Profession.Cooking,
	enchanting = SmartRez.Profession.Enchanting,
	engineering = SmartRez.Profession.Engineering,
	inscription = SmartRez.Profession.Inscription,
	jewelcrafting = SmartRez.Profession.Jewelcrafting,
	tailoring = SmartRez.Profession.Tailoring,
}

local PROFESSION_PROXY_ORDER = {
	SmartRez.Profession.Enchanting,
	SmartRez.Profession.Engineering,
	SmartRez.Profession.Inscription,
	SmartRez.Profession.Jewelcrafting,
	SmartRez.Profession.Alchemy,
	SmartRez.Profession.Tailoring,
	SmartRez.Profession.Blacksmithing,
	SmartRez.Profession.Cooking,
}

local applyProfessionProxyToFrames
local disableProfessionProxyForClosedBackend
local _C_IsTradeSkillReady = C_TradeSkillUI and C_TradeSkillUI.IsTradeSkillReady

local function getCurrentProfessionID()
	if not C_TradeSkillUI or not C_TradeSkillUI.GetBaseProfessionInfo then
		return nil
	end

	local professionInfo = C_TradeSkillUI.GetBaseProfessionInfo()
	return professionInfo and professionInfo.professionID or nil
end

local function isProfessionProxyBackendOpen()
	local currentProfessionID = getCurrentProfessionID()
	if not currentProfessionID then
		return false
	end

	if _C_IsTradeSkillReady and not _C_IsTradeSkillReady() then
		return false
	end

	if professionProxyState.professionID and currentProfessionID ~= professionProxyState.professionID then
		return false
	end

	return true
end

local function isProfessionProxyPendingOpen()
	return professionProxyState.enabled
		and type(professionProxyState.pendingUntil) == "number"
		and professionProxyState.pendingUntil > GetTime()
end

local function createProfessionProxyFrame()
	if professionProxyFrame then
		return professionProxyFrame
	end

	professionProxyFrame = CreateFrame("Frame", "SmartRezProfessionProxyFrame", UIParent, "BackdropTemplate")
	professionProxyFrame:SetSize(240, 72)
	professionProxyFrame:SetPoint("TOP", UIParent, "TOP", 0, -140)
	professionProxyFrame:SetFrameStrata("DIALOG")
	professionProxyFrame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	professionProxyFrame:Hide()

	professionProxyFrame.title = professionProxyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	professionProxyFrame.title:SetPoint("TOP", professionProxyFrame, "TOP", 0, -12)
	professionProxyFrame.title:SetText("Smart Rez Profession")

	professionProxyFrame.text = professionProxyFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	professionProxyFrame.text:SetPoint("TOP", professionProxyFrame.title, "BOTTOM", 0, -10)
	professionProxyFrame.text:SetText("Waiting for profession UI")

	return professionProxyFrame
end

local function updateProfessionProxyFrameText()
	if not professionProxyFrame then
		return
	end

	local backendProfessionID = getCurrentProfessionID() or professionProxyState.professionID
	local statusText = "Proxy active for "
	if isProfessionProxyPendingOpen() and not isProfessionProxyBackendOpen() then
		statusText = "Opening proxy for "
	end

	professionProxyFrame.text:SetText(statusText .. SmartRez:GetProfessionProxyLabel(backendProfessionID))
end

local function hideProfessionProxyFrame()
	if professionProxyFrame then
		professionProxyFrame:Hide()
	end
end

local function restoreProfessionFrames()
	if not ProfessionsFrame then
		return
	end

	ProfessionsFrame:SetAlpha(1)
	ProfessionsFrame:EnableMouse(true)
end

local function suppressProfessionFrames()
	if not ProfessionsFrame or not ProfessionsFrame:IsShown() then
		return
	end

	ProfessionsFrame:SetAlpha(0)
	ProfessionsFrame:EnableMouse(false)
end

local function startProfessionProxyTicker()
	if professionProxyTicker then
		return
	end

	professionProxyTicker = C_Timer.NewTicker(0.1, function()
		if not professionProxyState.enabled then
			return
		end

		if isProfessionProxyBackendOpen() then
			professionProxyState.pendingUntil = 0
		end

		if not isProfessionProxyBackendOpen() and not isProfessionProxyPendingOpen() then
			disableProfessionProxyForClosedBackend()
			return
		end

		suppressProfessionFrames()
		if professionProxyFrame then
			updateProfessionProxyFrameText()
			professionProxyFrame:Show()
		end
	end)
end

local function stopProfessionProxyTicker()
	if not professionProxyTicker then
		return
	end

	professionProxyTicker:Cancel()
	professionProxyTicker = nil
end

local function applyProfessionProxyToFrames()
	if professionProxyState.enabled then
		createProfessionProxyFrame()
		updateProfessionProxyFrameText()
		professionProxyFrame:Show()
		suppressProfessionFrames()
		startProfessionProxyTicker()
	else
		stopProfessionProxyTicker()
		restoreProfessionFrames()
		hideProfessionProxyFrame()
	end
end

function disableProfessionProxyForClosedBackend()
	professionProxyState.enabled = false
	professionProxyState.pendingUntil = 0
	applyProfessionProxyToFrames()
end

local function ensureProfessionProxyHooks()
	if professionProxyHooksReady or not ProfessionsFrame then
		return
	end

	ProfessionsFrame:HookScript("OnShow", function()
		applyProfessionProxyToFrames()
	end)
	ProfessionsFrame:HookScript("OnHide", function()
		if professionProxyState.enabled and not isProfessionProxyBackendOpen() and not isProfessionProxyPendingOpen() then
			disableProfessionProxyForClosedBackend()
			return
		end

		restoreProfessionFrames()
		if not professionProxyState.enabled then
			hideProfessionProxyFrame()
		end
	end)
	professionProxyHooksReady = true
end

function SmartRez:GetProfessionProxyLabel(professionID)
	for label, id in pairs(PROFESSION_PROXY_IDS) do
		if id == professionID then
			return label
		end
	end

	return professionID and tostring(professionID) or "unknown"
end

function SmartRez:GetProfessionProxyProfessionID(value)
	local trimmed = (value or ""):match("^%s*(.-)%s*$"):lower()
	if trimmed == "" then
		return nil
	end

	local professionID = tonumber(trimmed)
	if professionID then
		return professionID
	end

	return PROFESSION_PROXY_IDS[trimmed]
end

function SmartRez:GetDefaultProfessionProxyProfessionID()
	local currentProfessionID = getCurrentProfessionID()
	if currentProfessionID then
		return currentProfessionID
	end

	for _, professionID in ipairs(PROFESSION_PROXY_ORDER) do
		if self:HasProfession(professionID) then
			return professionID
		end
	end

	return nil
end

function SmartRez:IsProfessionProxyReady(professionID)
	if not isProfessionProxyBackendOpen() then
		return false
	end

	if professionID and getCurrentProfessionID() ~= professionID then
		return false
	end

	return true
end

function SmartRez:SetProfessionProxyEnabled(enabled, professionID)
	professionProxyState.enabled = enabled == true
	if professionID then
		professionProxyState.professionID = professionID
	end
	if not professionProxyState.enabled then
		professionProxyState.pendingUntil = 0
	end

	applyProfessionProxyToFrames()
end

function SmartRez:OpenProfessionProxy(professionID)
	if not professionID then
		print("Smart Rez: unknown profession for proxy mode.")
		return
	end

	self:SetProfessionProxyEnabled(true, professionID)
	professionProxyState.pendingUntil = GetTime() + 1.5
	if C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill then
		C_TradeSkillUI.OpenTradeSkill(professionID)
	end
end

function SmartRez:InitializeProfessionProxy()
	if professionProxyInitialized then
		return
	end

	professionProxyWatcher:RegisterEvent("TRADE_SKILL_SHOW")
	professionProxyWatcher:RegisterEvent("TRADE_SKILL_CLOSE")
	professionProxyWatcher:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED")
	professionProxyWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
	professionProxyWatcher:SetScript("OnEvent", function(_, eventName)
		if eventName == "TRADE_SKILL_SHOW" then
			ensureProfessionProxyHooks()
			if professionProxyState.enabled then
				applyProfessionProxyToFrames()
			end
		elseif eventName == "TRADE_SKILL_CLOSE" then
			if professionProxyState.enabled and not isProfessionProxyPendingOpen() then
				disableProfessionProxyForClosedBackend()
			end
		elseif professionProxyState.enabled and not isProfessionProxyBackendOpen() and not isProfessionProxyPendingOpen() then
			disableProfessionProxyForClosedBackend()
		end
	end)

	professionProxyInitialized = true
end
