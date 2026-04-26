local SmartRez = _G.SmartRez

local dispatcher = CreateFrame("Button", "GoldPrinterBtn", nil, "SecureActionButtonTemplate")
local stateFrame = CreateFrame("Frame")

dispatcher:RegisterForClicks("AnyUp", "AnyDown")
dispatcher:SetAttribute("type", "click")

SmartRez.goldPrinterStepIndex = SmartRez.goldPrinterStepIndex or 1
SmartRez.goldPrinterDebugState = SmartRez.goldPrinterDebugState or {}
SmartRez.goldPrinterRuntime = SmartRez.goldPrinterRuntime or {}

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

local function getNow()
  if GetTimePreciseSec then
    return GetTimePreciseSec()
  end
  return GetTime()
end

local function getRuntime()
  local routine = getSelectedRoutine()
  local routineKey = routine and routine.key or "none"
  local runtime = SmartRez.goldPrinterRuntime

  if runtime.routineKey ~= routineKey then
    runtime.routineKey = routineKey
    runtime.unlockedTimedSteps = {}
    runtime.actionCounts = {}
    runtime.intervalBatchCounts = {}
    runtime.lastIntervalDispatch = runtime.lastIntervalDispatch or {}
  end

  runtime.unlockedTimedSteps = runtime.unlockedTimedSteps or {}
  runtime.actionCounts = runtime.actionCounts or {}
  runtime.intervalBatchCounts = runtime.intervalBatchCounts or {}
  runtime.lastIntervalDispatch = runtime.lastIntervalDispatch or {}
  return runtime
end

local function getStepRuntimeKey(routineKey, stepIndex)
  return tostring(routineKey) .. ":" .. tostring(stepIndex)
end

local function getStepCompletionMode(step)
  return step and step.completionMode or "untilNoTargets"
end

local function getStepActionCount(step)
  return math.max(1, math.floor(tonumber(step and step.actionCount) or 1))
end

local function getStepIntervalSeconds(step)
  return math.max(1, math.floor(tonumber(step and step.intervalSeconds) or 900))
end

local function isTimedPriorityStep(step)
  return getStepCompletionMode(step) == "interval"
end

local function resetCycleRuntime()
  local runtime = getRuntime()
  runtime.unlockedTimedSteps = {}
  runtime.actionCounts = {}
  runtime.intervalBatchCounts = {}
  runtime.lastIntervalDispatch = {}
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
    resetCycleRuntime()
  end

  debugPrint("advance step", previousStep, "->", SmartRez.goldPrinterStepIndex)
  refreshViews()
end

local function unlockTimedStep(routineKey, stepIndex, step)
  if not isTimedPriorityStep(step) then
    return
  end

  getRuntime().unlockedTimedSteps[getStepRuntimeKey(routineKey, stepIndex)] = true
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
  local lockState = SmartRez.GetDisenchantDebugStateText and SmartRez:GetDisenchantDebugStateText() or "no-state"
  debugStateChanged("disenchant", "disenchant", "locked", tostring(SmartRez:IsDisenchantLocked()), "hasTarget",
    tostring(hasTarget), lockState)
  return hasTarget
end

local function isIntervalStepEligible(routineKey, stepIndex, step)
  local runtime = getRuntime()
  local key = getStepRuntimeKey(routineKey, stepIndex)
  local targetCount = getStepActionCount(step)
  local batchCount = runtime.intervalBatchCounts[key] or 0

  if batchCount > 0 and batchCount < targetCount then
    return true
  end

  local lastDispatch = runtime.lastIntervalDispatch[key]
  if not lastDispatch then
    return true
  end

  if getNow() - lastDispatch >= getStepIntervalSeconds(step) then
    runtime.intervalBatchCounts[key] = 0
    return true
  end

  return false
end

local function isStepAlreadyComplete(routineKey, stepIndex, step)
  local mode = getStepCompletionMode(step)
  local key = getStepRuntimeKey(routineKey, stepIndex)
  local runtime = getRuntime()

  if mode == "once" then
    return (runtime.actionCounts[key] or 0) >= 1
  elseif mode == "count" then
    return (runtime.actionCounts[key] or 0) >= getStepActionCount(step)
  elseif mode == "interval" then
    return not isIntervalStepEligible(routineKey, stepIndex, step)
  end

  return false
end

local function getRemainingStepActionCount(routineKey, stepIndex, step)
  local mode = getStepCompletionMode(step)
  local key = getStepRuntimeKey(routineKey, stepIndex)
  local runtime = getRuntime()
  local targetCount = getStepActionCount(step)

  if mode == "interval" then
    return math.max(1, targetCount - (runtime.intervalBatchCounts[key] or 0))
  elseif mode == "count" then
    return math.max(1, targetCount - (runtime.actionCounts[key] or 0))
  elseif mode == "once" then
    return 1
  end

  return nil
end

local function recordStepDispatch(routineKey, stepIndex, step, amount)
  local mode = getStepCompletionMode(step)
  if mode == "untilNoTargets" then
    return false
  end

  amount = math.max(1, math.floor(tonumber(amount) or 1))

  local key = getStepRuntimeKey(routineKey, stepIndex)
  local runtime = getRuntime()
  local targetCount = getStepActionCount(step)

  if mode == "interval" then
    local count = (runtime.intervalBatchCounts[key] or 0) + amount
    runtime.intervalBatchCounts[key] = count

    if count >= targetCount then
      runtime.lastIntervalDispatch[key] = getNow()
      runtime.intervalBatchCounts[key] = 0
      debugPrint("interval step satisfied", stepIndex, "count", count, "interval", getStepIntervalSeconds(step))
      return true
    end

    return false
  end

  local count = (runtime.actionCounts[key] or 0) + amount
  runtime.actionCounts[key] = count
  debugPrint("count step progress", stepIndex, count .. "/" .. targetCount)
  return count >= targetCount
end

local function getStepAction(routineKey, stepIndex, step, down)
  activateStepContexts(routineKey, stepIndex, step)
  unlockTimedStep(routineKey, stepIndex, step)

  if isStepAlreadyComplete(routineKey, stepIndex, step) then
    return nil, true
  end

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
      local castLimit = getRemainingStepActionCount(routineKey, stepIndex, step)

      return {
        actionType = "macro",
        macroText = buildClickMacro(profession and profession.buttonName or nil, down),
        targetName = profession and profession.buttonName or nil,
        professionKey = professionKey,
        castLimit = castLimit,
        dispatchAmount = castLimit or 1,
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

    for priorityIndex = 1, stepIndex - 1 do
      local priorityStep = steps[priorityIndex]
      local priorityKey = getStepRuntimeKey(routine.key, priorityIndex)
      if isTimedPriorityStep(priorityStep) and getRuntime().unlockedTimedSteps[priorityKey] and isIntervalStepEligible(routine.key, priorityIndex, priorityStep) then
        local priorityAction, priorityComplete = getStepAction(routine.key, priorityIndex, priorityStep, down)
        if priorityAction then
          debugStateChanged("chooseAction", "choose timed priority", tostring(priorityIndex),
            SmartRez:GetGoldPrinterRoutineStepLabel(priorityStep))
          if priorityAction.professionKey and priorityAction.castLimit then
            SmartRez:SetGoldPrinterCraftSalvageCastLimit(priorityAction.professionKey, priorityAction.castLimit)
          end

          if recordStepDispatch(routine.key, priorityIndex, priorityStep, priorityAction.dispatchAmount) then
            refreshViews()
          end
          return priorityAction
        elseif not priorityComplete then
          debugStateChanged("chooseAction", "timed priority incomplete", tostring(priorityIndex),
            SmartRez:GetGoldPrinterRoutineStepLabel(priorityStep))
          return nil
        end
      end
    end

    local action, stepComplete = getStepAction(routine.key, stepIndex, step, down)
    if action then
      debugStateChanged("chooseAction", "choose action", tostring(stepIndex),
        SmartRez:GetGoldPrinterRoutineStepLabel(step))

      if action.professionKey and action.castLimit then
        SmartRez:SetGoldPrinterCraftSalvageCastLimit(action.professionKey, action.castLimit)
      end

      -- Important:
      -- Do not advance the routine step before the macro runs.
      -- The craft/salvage buttons read the currently active Gold Printer step context,
      -- so advancing here would make the macro execute using the next step's selection.
      if recordStepDispatch(routine.key, stepIndex, step, action.dispatchAmount) then
        action.advanceStepAfterClick = true
      end

      return action
    end

    if not stepComplete then
      debugStateChanged("chooseAction", "step incomplete", tostring(stepIndex),
        SmartRez:GetGoldPrinterRoutineStepLabel(step))
      return nil
    end

    advanceStep()
  end

  clearStepContexts()
  resetStepIndex()
  return nil
end

local pendingPostClickAdvance = false

dispatcher:SetScript("PreClick", function(self, _, down)
  pendingPostClickAdvance = false

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

  pendingPostClickAdvance = action.advanceStepAfterClick == true

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

  if pendingPostClickAdvance then
    pendingPostClickAdvance = false
    advanceStep()
  end
end)

stateFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
stateFrame:SetScript("OnEvent", function(_, eventName)
  if eventName == "PLAYER_ENTERING_WORLD" then
    resetStepIndex()
    resetCycleRuntime()
    clearStepContexts()
  end
end)

SmartRez:RegisterBindableAction({
  key = "goldprinter",
  label = "Gold Printer",
  buttonName = "GoldPrinterBtn",
  order = 5,
})

function SmartRez:SetGoldPrinterCraftSalvageCastLimit(professionKey, maxCasts)
  if not professionKey then
    return
  end

  self.goldPrinterCraftSalvageCastLimits = self.goldPrinterCraftSalvageCastLimits or {}
  self.goldPrinterCraftSalvageCastLimits[professionKey] = math.max(1, math.floor(tonumber(maxCasts) or 1))
end

function SmartRez:GetGoldPrinterCraftSalvageCastLimit(professionKey)
  local limits = self.goldPrinterCraftSalvageCastLimits
  local limit = limits and limits[professionKey] or nil
  if not limit then
    return nil
  end

  return math.max(1, math.floor(tonumber(limit) or 1))
end

function SmartRez:ClearGoldPrinterCraftSalvageCastLimit(professionKey)
  if self.goldPrinterCraftSalvageCastLimits then
    self.goldPrinterCraftSalvageCastLimits[professionKey] = nil
  end
end

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
