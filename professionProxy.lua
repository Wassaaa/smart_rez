local SmartRez = _G.SmartRez

local professionProxyFrame
local professionProxyWatcher = CreateFrame("Frame")
local professionProxyTicker
local professionProxyHooksReady = false
local professionProxyInitialized = false
local professionProxyDisabledMouseFrames = {}
local professionProxyState = {
	enabled = false,
	professionID = nil,
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

local function getProfessionProxyConfig()
	SmartRez:EnsureConfig()
	local config = SmartRez.db.professionProxy
	if type(config) ~= "table" then
		config = {}
		SmartRez.db.professionProxy = config
	end

	if type(config.point) ~= "table" then
		config.point = {}
	end

	if config.visible == nil then
		config.visible = true
	end

	config.point.anchor = config.point.anchor or "TOP"
	config.point.relativePoint = config.point.relativePoint or config.point.anchor
	config.point.x = tonumber(config.point.x) or 0
	config.point.y = tonumber(config.point.y) or -80

	return config
end

local function isProfessionProxyFrameVisible()
	return getProfessionProxyConfig().visible ~= false
end

local function saveProfessionProxyFramePoint(frame)
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	local config = getProfessionProxyConfig()
	config.point.anchor = point or "TOP"
	config.point.relativePoint = relativePoint or config.point.anchor
	config.point.x = x or 0
	config.point.y = y or -80
end

local function applyProfessionProxyFramePoint(frame)
	local config = getProfessionProxyConfig()
	frame:ClearAllPoints()
	frame:SetPoint(config.point.anchor, UIParent, config.point.relativePoint, config.point.x, config.point.y)
end

local function getCurrentProfessionID()
	if not C_TradeSkillUI or not C_TradeSkillUI.GetBaseProfessionInfo then
		return nil
	end

	local professionInfo = C_TradeSkillUI.GetBaseProfessionInfo()
	local professionID = professionInfo and professionInfo.professionID or nil
	if type(professionID) ~= "number" or professionID <= 0 then
		return nil
	end

	return professionID
end

local function isProfessionProxyBackendOpen()
	local currentProfessionID = getCurrentProfessionID()
	if not currentProfessionID then
		return false
	end

	if professionProxyState.professionID and currentProfessionID ~= professionProxyState.professionID then
		return false
	end

	return true
end

local function createProfessionProxyFrame()
	if professionProxyFrame then
		return professionProxyFrame
	end

	professionProxyFrame = CreateFrame("Frame", "SmartRezProfessionProxyFrame", UIParent, "BackdropTemplate")
	professionProxyFrame:SetSize(88, 20)
	professionProxyFrame:SetFrameStrata("DIALOG")
	professionProxyFrame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 10,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	professionProxyFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
	professionProxyFrame:SetBackdropBorderColor(0.8, 0.66, 0.2, 0.9)
	professionProxyFrame:SetClampedToScreen(true)
	professionProxyFrame:SetMovable(true)
	professionProxyFrame:EnableMouse(true)
	professionProxyFrame:RegisterForDrag("LeftButton")
	professionProxyFrame:SetScript("OnDragStart", function(self)
		if InCombatLockdown() then
			return
		end

		self:StartMoving()
	end)
	professionProxyFrame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		saveProfessionProxyFramePoint(self)
	end)
	professionProxyFrame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
		GameTooltip:AddLine("rez_proxy")
		GameTooltip:AddLine("Left-drag to move", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("Current: " .. SmartRez:GetProfessionProxyLabel(getCurrentProfessionID() or professionProxyState.professionID), 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	professionProxyFrame:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	professionProxyFrame:Hide()
	applyProfessionProxyFramePoint(professionProxyFrame)

	professionProxyFrame.text = professionProxyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	professionProxyFrame.text:SetPoint("CENTER", professionProxyFrame, "CENTER", 0, 0)
	professionProxyFrame.text:SetText("rez_proxy")

	return professionProxyFrame
end

local function updateProfessionProxyFrameText()
	if not professionProxyFrame then
		return
	end

	professionProxyFrame.text:SetText("rez_proxy")
end

local function hideProfessionProxyFrame()
	if professionProxyFrame then
		GameTooltip:Hide()
		professionProxyFrame:Hide()
	end
end

local function restoreProfessionChildMouse()
	for frame in pairs(professionProxyDisabledMouseFrames) do
		if frame and frame.EnableMouse then
			frame:EnableMouse(true)
		end
	end

	professionProxyDisabledMouseFrames = {}
end

local function suppressProfessionChildMouse(frame)
	if not frame or not frame.GetChildren then
		return
	end

	for _, child in ipairs({ frame:GetChildren() }) do
		if child then
			if child.IsMouseEnabled and child:IsMouseEnabled() and child.EnableMouse then
				professionProxyDisabledMouseFrames[child] = true
				child:EnableMouse(false)
			end

			suppressProfessionChildMouse(child)
		end
	end
end

local function restoreProfessionFrames()
	if not ProfessionsFrame then
		restoreProfessionChildMouse()
		return
	end

	restoreProfessionChildMouse()
	ProfessionsFrame:SetAlpha(1)
	ProfessionsFrame:EnableMouse(true)
end

local function suppressProfessionFrames(includeChildren)
	if not ProfessionsFrame or not ProfessionsFrame:IsShown() then
		return
	end

	ProfessionsFrame:SetAlpha(0)
	ProfessionsFrame:EnableMouse(false)
	ProfessionsFrame:EnableMouseWheel(false)
	if includeChildren ~= false then
		suppressProfessionChildMouse(ProfessionsFrame)
	end
	GameTooltip:Hide()
	if ProfessionsFrame.SetMouseClickEnabled then
		ProfessionsFrame:SetMouseClickEnabled(false)
	end
	if ProfessionsFrame.SetMouseMotionEnabled then
		ProfessionsFrame:SetMouseMotionEnabled(false)
	end
end

local function startProfessionProxyTicker()
	if professionProxyTicker then
		return
	end

	professionProxyTicker = C_Timer.NewTicker(0.1, function()
		if not professionProxyState.enabled then
			return
		end

		if not isProfessionProxyBackendOpen() then
			disableProfessionProxyForClosedBackend()
			return
		end

		suppressProfessionFrames(false)
		if professionProxyFrame then
			updateProfessionProxyFrameText()
			if isProfessionProxyFrameVisible() then
				professionProxyFrame:Show()
			else
				professionProxyFrame:Hide()
			end
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
		if isProfessionProxyFrameVisible() then
			professionProxyFrame:Show()
		else
			professionProxyFrame:Hide()
		end
		suppressProfessionFrames(true)
		startProfessionProxyTicker()
	else
		stopProfessionProxyTicker()
		restoreProfessionFrames()
		hideProfessionProxyFrame()
	end
end

function disableProfessionProxyForClosedBackend()
	professionProxyState.enabled = false
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
		if professionProxyState.enabled and not isProfessionProxyBackendOpen() then
			disableProfessionProxyForClosedBackend()
			return
		end

		restoreProfessionFrames()
		hideProfessionProxyFrame()
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

function SmartRez:SetProfessionProxyFrameVisible(visible)
	getProfessionProxyConfig().visible = visible ~= false
	applyProfessionProxyToFrames()
end

function SmartRez:IsProfessionProxyFrameVisible()
	return isProfessionProxyFrameVisible()
end

function SmartRez:ResetProfessionProxyFramePosition()
	local config = getProfessionProxyConfig()
	config.point.anchor = "TOP"
	config.point.relativePoint = "TOP"
	config.point.x = 0
	config.point.y = -80
	if professionProxyFrame then
		applyProfessionProxyFramePoint(professionProxyFrame)
	end
end

function SmartRez:SetProfessionProxyEnabled(enabled, professionID)
	professionProxyState.enabled = enabled == true
	if professionID then
		professionProxyState.professionID = professionID
	end

	applyProfessionProxyToFrames()
end

function SmartRez:OpenProfessionProxy(professionID)
	if not professionID then
		print("Smart Rez: unknown profession for proxy mode.")
		return false
	end

	if self.HasProfession and not self:HasProfession(professionID) then
		print("Smart Rez: " .. self:GetProfessionProxyLabel(professionID) .. " is not learned on this character.")
		return false
	end

	self:SetProfessionProxyEnabled(true, professionID)
	if C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill then
		C_TradeSkillUI.OpenTradeSkill(professionID)
	end

	return true
end

function SmartRez:InitializeProfessionProxy()
	if professionProxyInitialized then
		return
	end

	if UIParent:IsEventRegistered("TRADE_SKILL_SHOW") then
		UIParent:UnregisterEvent("TRADE_SKILL_SHOW")
	end

	professionProxyWatcher:RegisterEvent("TRADE_SKILL_SHOW")
	professionProxyWatcher:RegisterEvent("TRADE_SKILL_CLOSE")
	professionProxyWatcher:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED")
	professionProxyWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
	professionProxyWatcher:SetScript("OnEvent", function(_, eventName)
		if eventName == "TRADE_SKILL_SHOW" then
			if not professionProxyState.enabled then
				UIParent_OnEvent(UIParent, "TRADE_SKILL_SHOW")
			end
			ensureProfessionProxyHooks()
			applyProfessionProxyToFrames()
		elseif eventName == "TRADE_SKILL_CLOSE" then
			disableProfessionProxyForClosedBackend()
		elseif professionProxyState.enabled and not isProfessionProxyBackendOpen() then
			disableProfessionProxyForClosedBackend()
		end
	end)

	professionProxyInitialized = true
end
