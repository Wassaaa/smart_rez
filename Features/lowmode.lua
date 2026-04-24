local SmartRez = _G.SmartRez

local LOW_MODE_SETTINGS = {
	useMaxFPS = "1",
	maxfps = "8",
	useMaxFPSBk = "1",
	maxfpsbk = "8",
	RenderScale = "0.009",
	ResampleQuality = "0",
	textureFilteringMode = "0",
	graphicsTextureResolution = "1",
	gxMaximize = "0",
}

local TRACKED_CVARS = {
	"useMaxFPS",
	"maxfps",
	"useMaxFPSBk",
	"maxfpsbk",
	"RenderScale",
	"ResampleQuality",
	"textureFilteringMode",
	"graphicsTextureResolution",
	"gxMaximize",
}

SmartRezLowModeDB = SmartRezLowModeDB or {}

local function getLowModeDB()
	SmartRezLowModeDB = SmartRezLowModeDB or {}
	return SmartRezLowModeDB
end

local function refreshViews()
	if SmartRez.RefreshViews then
		SmartRez:RefreshViews()
	end
end

local function isLowModeEnabled()
	return tostring(GetCVar("gxMaximize") or "1") == "0"
end

local function captureCurrentState()
	local snapshot = {}
	for _, cvarName in ipairs(TRACKED_CVARS) do
		snapshot[cvarName] = GetCVar(cvarName)
	end
	snapshot.uiParentShown = UIParent:IsShown() and 1 or 0
	snapshot.isLowModeBaseline = false
	return snapshot
end

local function applySettings(settings)
	for _, cvarName in ipairs(TRACKED_CVARS) do
		local value = settings[cvarName]
		if value ~= nil then
			C_CVar.SetCVar(cvarName, tostring(value))
		end
	end
end

local function restartGraphics()
	ConsoleExec("gxrestart")
end

local function snapshotMatchesLowMode(snapshot)
	if type(snapshot) ~= "table" then
		return false
	end

	for _, cvarName in ipairs(TRACKED_CVARS) do
		if tostring(snapshot[cvarName] or "") ~= tostring(LOW_MODE_SETTINGS[cvarName] or "") then
			return false
		end
	end

	return snapshot.uiParentShown == 0
end

local function currentStateMatchesLowMode()
	for _, cvarName in ipairs(TRACKED_CVARS) do
		if tostring(GetCVar(cvarName) or "") ~= tostring(LOW_MODE_SETTINGS[cvarName] or "") then
			return false
		end
	end

	return not UIParent:IsShown()
end

function SmartRez:HasLowModeSnapshot()
	local snapshot = getLowModeDB().previousSettings
	return type(snapshot) == "table" and next(snapshot) ~= nil
end

function SmartRez:IsLowModeEnabled()
	return isLowModeEnabled()
end

function SmartRez:CaptureLowModeSnapshot(force)
	local db = getLowModeDB()
	if force ~= true and self:HasLowModeSnapshot() then
		return false, "Snapshot already saved."
	end

	db.previousSettings = captureCurrentState()
	db.previousSettings.isLowModeBaseline = false
	refreshViews()
	return true, "Saved current graphics/UI settings as the low mode restore snapshot."
end

function SmartRez:GetLowModeSnapshotSummary()
	local db = getLowModeDB()
	if not self:HasLowModeSnapshot() then
		return "No restore snapshot saved yet."
	end

	if snapshotMatchesLowMode(db.previousSettings) then
		return "Snapshot currently matches low mode settings."
	end

	return "Restore snapshot saved."
end

local function ensureRestoreSnapshot()
	local db = getLowModeDB()
	if type(db.previousSettings) == "table" and next(db.previousSettings) ~= nil and not snapshotMatchesLowMode(db.previousSettings) then
		return true
	end

	if currentStateMatchesLowMode() then
		return false
	end

	db.previousSettings = captureCurrentState()
	db.previousSettings.isLowModeBaseline = false
	return true
end

local function enableLowMode()
	if not ensureRestoreSnapshot() then
		print("SmartRez: low mode enabled, but no safe normal-settings snapshot was captured. Use the setup snapshot button after restoring your preferred settings.")
		refreshViews()
		return
	end

	applySettings(LOW_MODE_SETTINGS)
	UIParent:Hide()
	print("SmartRez: low mode enabled.")
	refreshViews()
	restartGraphics()
end

local function disableLowMode()
	local snapshot = getLowModeDB().previousSettings
	if not snapshotMatchesLowMode(snapshot) and type(snapshot) == "table" and next(snapshot) ~= nil then
		applySettings(snapshot)
		if snapshot.uiParentShown == 1 then
			UIParent:Show()
		else
			UIParent:Hide()
		end

		print("SmartRez: low mode disabled.")
		refreshViews()
		restartGraphics()
		return
	end

	print("SmartRez: low mode disabled, but restore data is missing or invalid.")
	refreshViews()
end

local function toggleLowMode()
	if isLowModeEnabled() then
		disableLowMode()
	else
		enableLowMode()
	end
end

local button = CreateFrame("Button", "LowModeToggleBtn", UIParent)
button:RegisterForClicks("LeftButtonUp")
button:SetScript("OnClick", function()
	toggleLowMode()
end)

SmartRez:RegisterBindableAction({
	key = "lowmode",
	label = "Toggle Low Mode",
	buttonName = "LowModeToggleBtn",
	order = 590,
})
