local SmartRez = _G.SmartRez

local dispatcher = CreateFrame("Button", "GoldPrinterBtn", nil, "SecureActionButtonTemplate")
local stateFrame = CreateFrame("Frame")

dispatcher:RegisterForClicks("AnyUp", "AnyDown")
dispatcher:SetAttribute("type", "click")

SmartRez.goldPrinterStepIndex = SmartRez.goldPrinterStepIndex or 1
SmartRez.goldPrinterDebugState = SmartRez.goldPrinterDebugState or {}

local function debugPrint(...)
	if not (SmartRez.GetDebugEnabled and SmartRez:GetDebugEnabled()) then
		return
	end

	print("SmartRez GP:", ...)
end

local function debugStateChanged(key, ...)
	if not (SmartRez.GetDebugEnabled and SmartRez:GetDebugEnabled()) then
		return
	end

	local parts = { ... }
	local state = table.concat(parts, "|")
	if SmartRez.goldPrinterDebugState[key] == state then
		return
	end

	SmartRez.goldPrinterDebugState[key] = state
	print("SmartRez GP:", ...)
end

local function buildClickMacro(buttonName, down)
	if not buttonName or buttonName == "" then
		return nil
	end

	return "/click " .. buttonName .. " LeftButton " .. (down and "1" or "0")
end

local function refreshViews()
	if SmartRez.RefreshViews then
		SmartRez:RefreshViews()
	end
end

local function getGoldPrinterStatusText()
	local phase = SmartRez:GetGoldPrinterPhase()
	if phase == "craft" or phase == "recipeCraft" then
		return SmartRez:Colorize("7EE787", SmartRez:GetGoldPrinterPhaseLabel())
	end
	if phase == "disenchant" then
		return SmartRez:Colorize("FFD866", SmartRez:GetGoldPrinterPhaseLabel())
	end
	if phase == "shatter" or phase == "craftSalvage" then
		return SmartRez:Colorize("7AA2F7", SmartRez:GetGoldPrinterPhaseLabel())
	end
	return SmartRez:Colorize("C0CAF5", SmartRez:GetGoldPrinterPhaseLabel())
end

local function getSelectedRoutine()
	return SmartRez:GetGoldPrinterRoutine()
end

local function getRoutineSteps()
	local routine = getSelectedRoutine()
	return routine and routine.steps or {}
end

local function clampStepIndex()
	local steps = getRoutineSteps()
	if #steps == 0 then
		SmartRez.goldPrinterStepIndex = 1
		return
	end

	if SmartRez.goldPrinterStepIndex < 1 then
		SmartRez.goldPrinterStepIndex = 1
	elseif SmartRez.goldPrinterStepIndex > #steps then
		SmartRez.goldPrinterStepIndex = 1
	end
end

local function resetStepIndex()
	if SmartRez.goldPrinterStepIndex ~= 1 then
		debugPrint("reset step", SmartRez.goldPrinterStepIndex, "->", 1)
		SmartRez.goldPrinterStepIndex = 1
		refreshViews()
	end
end

local function advanceStep()
	local steps = getRoutineSteps()
	if #steps == 0 then
		resetStepIndex()
		return
	end

	local previousStep = SmartRez.goldPrinterStepIndex
	SmartRez.goldPrinterStepIndex = SmartRez.goldPrinterStepIndex + 1
	if SmartRez.goldPrinterStepIndex > #steps then
		SmartRez.goldPrinterStepIndex = 1
	end

	debugPrint("advance step", previousStep, "->", SmartRez.goldPrinterStepIndex)
	refreshViews()
end

local function activateStepContexts(routineKey, stepIndex, step)
	local changed = SmartRez:ActivateGoldPrinterRoutineStepContexts(routineKey, stepIndex, step)
	if changed then
		SmartRez:MarkCraftSalvageCacheDirty()
		if SmartRez.RefreshDisenchantButton then
			SmartRez:RefreshDisenchantButton()
		end
	end
end

local function clearStepContexts()
	SmartRez:ClearActiveGoldPrinterStepContexts()
	SmartRez:MarkCraftRecipeCacheDirty()
	SmartRez:MarkCraftSalvageCacheDirty()
	if SmartRez.RefreshDisenchantButton then
		SmartRez:RefreshDisenchantButton()
	end
end

local function hasRecipeCraftWork()
	local actionKey = SmartRez:GetGoldPrinterRecipeActionKey()
	local actionConfig = SmartRez.craftRecipeActions[actionKey]
	if not actionConfig then
		debugStateChanged("recipeCraftMissing", "recipe craft missing", tostring(actionKey))
		return false, true
	end

	if SmartRez:IsCraftRecipeActionBlocked(actionKey) then
		debugStateChanged("recipeCraftBlocked", "recipe craft blocked", tostring(actionKey))
		return false, false
	end

	local hasTarget = SmartRez:GetCraftRecipeTarget(actionKey) ~= nil
	debugStateChanged("recipeCraft", "recipe craft", tostring(actionKey), "hasTarget", tostring(hasTarget))
	return hasTarget, true
end

local function hasCraftSalvageWork(professionKey)
	local profession = SmartRez:GetCraftSalvageProfession(professionKey)
	if not profession then
		debugStateChanged("craftSalvageMissing", "craft salvage missing", tostring(professionKey))
		return false, true
	end

	if SmartRez:IsCraftSalvageActionBlocked(professionKey) then
		debugStateChanged("craftSalvageBlocked", "craft salvage blocked", tostring(professionKey))
		return false, false
	end

	local hasTarget = SmartRez:GetCraftSalvageTarget(professionKey) ~= nil
	debugStateChanged("craftSalvage", "craft salvage", tostring(professionKey), "hasTarget", tostring(hasTarget))
	return hasTarget, true
end

local function hasDisenchantWork()
	local hasTarget = SmartRez:HasDisenchantTarget()
	debugStateChanged("disenchant", "disenchant", "locked", tostring(SmartRez:IsDisenchantLocked()), "hasTarget", tostring(hasTarget))
	return hasTarget
end

local function getStepAction(routineKey, stepIndex, step, down)
	activateStepContexts(routineKey, stepIndex, step)

	if step.type == "recipeCraft" then
		if not step.recipeConfig or not step.recipeConfig.recipeID then
			return nil, true
		end

		local canCraft, stepComplete = hasRecipeCraftWork()
		if canCraft then
			local actionConfig = SmartRez.craftRecipeActions[SmartRez:GetGoldPrinterRecipeActionKey()]
			return {
				actionType = "macro",
				macroText = buildClickMacro(actionConfig and actionConfig.buttonName or nil, down),
				targetName = actionConfig and actionConfig.buttonName or nil,
			}
		end
		return nil, stepComplete
	end

	if step.type == "craftSalvage" then
		local selection = step.selection
		local professionKey = selection and selection.professionKey or nil
		if not professionKey then
			return nil, true
		end

		local canCraftSalvage, stepComplete = hasCraftSalvageWork(professionKey)
		if canCraftSalvage then
			local profession = SmartRez:GetCraftSalvageProfession(professionKey)
			return {
				actionType = "macro",
				macroText = buildClickMacro(profession and profession.buttonName or nil, down),
				targetName = profession and profession.buttonName or nil,
			}
		end
		return nil, stepComplete
	end

	if step.type == "disenchant" then
		if SmartRez:IsDisenchantLocked() then
			return nil, false
		end

		if hasDisenchantWork() then
			local macroText = SmartRez:PrepareDisenchantMacro()
			if macroText then
				return {
					actionType = "macro",
					macroText = macroText,
				}
			end

			return nil, false
		end

		return nil, true
	end

	return nil, true
end

local function chooseAction(down)
	local routine = getSelectedRoutine()
	local steps = routine and routine.steps or {}
	if #steps == 0 then
		clearStepContexts()
		return nil
	end

	clampStepIndex()

	for _ = 1, #steps do
		local stepIndex = SmartRez.goldPrinterStepIndex
		local step = steps[stepIndex]
		local action, stepComplete = getStepAction(routine.key, stepIndex, step, down)
		if action then
			debugStateChanged("chooseAction", "choose action", tostring(stepIndex), SmartRez:GetGoldPrinterRoutineStepLabel(step))
			return action
		end

		if not stepComplete then
			debugStateChanged("chooseAction", "step incomplete", tostring(stepIndex), SmartRez:GetGoldPrinterRoutineStepLabel(step))
			return nil
		end

		advanceStep()
	end

	clearStepContexts()
	resetStepIndex()
	return nil
end

dispatcher:SetScript("PreClick", function(self, _, down)
	if not SmartRez:IsActiveCraftClickPhase(down) then
		return
	end

	if InCombatLockdown() then
		debugStateChanged("dispatch", "blocked in combat")
		return
	end

	local action = chooseAction(down)
	if not action then
		debugStateChanged("dispatch", "no action")
		self:SetAttribute("type", "macro")
		self:SetAttribute("macrotext", nil)
		return
	end

	debugStateChanged("dispatch", "dispatch macro", action.targetName or "custom")
	self:SetAttribute("type", "macro")
	self:SetAttribute("macrotext", action.macroText)
end)

dispatcher:SetScript("PostClick", function(self)
	if InCombatLockdown() then
		return
	end

	self:SetAttribute("type", "macro")
	self:SetAttribute("macrotext", nil)
end)

stateFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
stateFrame:SetScript("OnEvent", function(_, eventName)
	if eventName == "PLAYER_ENTERING_WORLD" then
		resetStepIndex()
		clearStepContexts()
	end
end)

SmartRez:RegisterBindableAction({
	key = "goldprinter",
	label = "Gold Printer",
	buttonName = "GoldPrinterBtn",
	order = 5,
})

function SmartRez:GetGoldPrinterPhase()
	local steps = getRoutineSteps()
	local step = steps[self.goldPrinterStepIndex or 1]
	return step and step.type or "idle"
end

function SmartRez:GetGoldPrinterPhaseLabel()
	local steps = getRoutineSteps()
	local step = steps[self.goldPrinterStepIndex or 1]
	return self:GetGoldPrinterRoutineStepLabel(step)
end

if SmartRez.RegisterOverridePopupStatusProvider then
	SmartRez:RegisterOverridePopupStatusProvider({
		key = "goldprinter",
		label = "Gold Printer",
		order = 10,
		getText = getGoldPrinterStatusText,
	})
end
