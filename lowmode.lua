local LOW_MODE_SETTINGS = {
  useMaxFPS = "1",
  maxfps = "8",
  useMaxFPSBk = "1",
  maxfpsbk = "8",
  RenderScale = "0.009",
  ResampleQuality = "0",
  textureFilteringMode = "0",
  graphicsTextureResolution = "1",
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
}

SmartRezLowModeDB = SmartRezLowModeDB or {}

local function isLowModeEnabled()
  return SmartRezLowModeDB.enabled == true
end

local function captureCurrentState()
  local snapshot = {}
  for _, cvarName in ipairs(TRACKED_CVARS) do
    snapshot[cvarName] = GetCVar(cvarName)
  end
  snapshot.uiParentShown = UIParent:IsShown() and 1 or 0
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

local function enableLowMode()
  SmartRezLowModeDB.previousSettings = captureCurrentState()
  applySettings(LOW_MODE_SETTINGS)
  UIParent:Hide()
  SmartRezLowModeDB.enabled = true
  print("SmartRez: low mode enabled.")
end

local function disableLowMode()
  local snapshot = SmartRezLowModeDB.previousSettings
  if not snapshot then
    SmartRezLowModeDB.enabled = false
    print("SmartRez: low mode restore data is missing.")
    return
  end

  applySettings(snapshot)
  if snapshot.uiParentShown == 1 then
    UIParent:Show()
  else
    UIParent:Hide()
  end

  SmartRezLowModeDB.enabled = false
  SmartRezLowModeDB.previousSettings = nil
  print("SmartRez: low mode disabled.")
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
