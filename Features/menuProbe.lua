local SmartRez = _G.SmartRez

local menuProbeEnabled = false
local menuProbeInitialized = false
local menuProbeFrame = CreateFrame("Frame")
local hookedFrames = {}

local function trim(value)
	return (value or ""):match("^%s*(.-)%s*$")
end

local function formatProbeValue(value)
	local valueType = type(value)
	if valueType == "string" then
		return value == "" and '""' or value
	end

	if valueType == "number" or valueType == "boolean" or valueType == "nil" then
		return tostring(value)
	end

	if valueType == "table" and value.GetName then
		local frameName = value:GetName()
		if frameName and frameName ~= "" then
			return frameName
		end
	end

	return valueType
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

local function buildProbeState()
	local state = {
		"menu=" .. tostring(GameMenuFrame and GameMenuFrame:IsShown() or false),
		"professions=" .. tostring(ProfessionsFrame and ProfessionsFrame:IsShown() or false),
		"professionID=" .. tostring(getCurrentProfessionID() or "nil"),
	}

	if SmartRez.IsProfessionProxyReady then
		state[#state + 1] = "proxyReady=" .. tostring(SmartRez:IsProfessionProxyReady())
	end

	return table.concat(state, " ")
end

local function logProbe(tag, ...)
	if not menuProbeEnabled then
		return
	end

	local parts = { "SmartRez Probe:", tag }
	local count = select("#", ...)
	for index = 1, count do
		parts[#parts + 1] = formatProbeValue(select(index, ...))
	end
	parts[#parts + 1] = "[" .. buildProbeState() .. "]"
	print(table.concat(parts, " "))
end

local function hookFrameScript(frame, scriptName, label)
	if not frame then
		return
	end

	local frameHooks = hookedFrames[frame]
	if not frameHooks then
		frameHooks = {}
		hookedFrames[frame] = frameHooks
	end

	if frameHooks[scriptName] then
		return
	end

	frame:HookScript(scriptName, function()
		logProbe(label)
	end)
	frameHooks[scriptName] = true
end

local function ensureFrameHooks()
	hookFrameScript(GameMenuFrame, "OnShow", "GameMenuFrame OnShow")
	hookFrameScript(GameMenuFrame, "OnHide", "GameMenuFrame OnHide")
	hookFrameScript(ProfessionsFrame, "OnShow", "ProfessionsFrame OnShow")
	hookFrameScript(ProfessionsFrame, "OnHide", "ProfessionsFrame OnHide")
end

local function hookGlobalFunction(functionName)
	local target = _G[functionName]
	if type(target) ~= "function" then
		return
	end

	hooksecurefunc(functionName, function(...)
		ensureFrameHooks()
		logProbe(functionName, ...)
	end)
end

function SmartRez:InitializeMenuProbe()
	if menuProbeInitialized then
		return
	end

	hookGlobalFunction("ToggleGameMenu")
	hookGlobalFunction("ShowUIPanel")
	hookGlobalFunction("HideUIPanel")
	hookGlobalFunction("CloseWindows")
	hookGlobalFunction("CloseSpecialWindows")
	hookGlobalFunction("CloseMenus")
	hookGlobalFunction("CloseAllWindows")

	menuProbeFrame:RegisterEvent("TRADE_SKILL_SHOW")
	menuProbeFrame:RegisterEvent("TRADE_SKILL_CLOSE")
	menuProbeFrame:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED")
	menuProbeFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
	menuProbeFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
	menuProbeFrame:SetScript("OnEvent", function(_, eventName, ...)
		ensureFrameHooks()
		logProbe("EVENT " .. eventName, ...)
	end)

	ensureFrameHooks()
	menuProbeInitialized = true
end

function SmartRez:IsMenuProbeEnabled()
	return menuProbeEnabled
end

function SmartRez:SetMenuProbeEnabled(enabled)
	self:InitializeMenuProbe()
	menuProbeEnabled = enabled == true
	print("Smart Rez: menu probe " .. (menuProbeEnabled and "enabled." or "disabled."))
	if menuProbeEnabled then
		ensureFrameHooks()
		logProbe("manual state")
	end
end

function SmartRez:ToggleMenuProbe()
	self:SetMenuProbeEnabled(not menuProbeEnabled)
end

function SmartRez:PrintMenuProbeState(label)
	self:InitializeMenuProbe()
	local prefix = trim(label)
	if prefix ~= "" then
		print("Smart Rez: " .. prefix .. " [" .. buildProbeState() .. "]")
	else
		print("Smart Rez: [" .. buildProbeState() .. "]")
	end
end
