local SmartRez = _G.SmartRez

local _C_GetBaseProfessionInfo = C_TradeSkillUI.GetBaseProfessionInfo
local _C_OpenTradeSkill = C_TradeSkillUI.OpenTradeSkill
local _C_OpenRecipe = C_TradeSkillUI.OpenRecipe
local _GetCVar = GetCVar
local _GetTime = GetTime
local _UnitCastingInfo = UnitCastingInfo
local _UnitChannelInfo = UnitChannelInfo
local _format = string.format

local ACTIVITY_TIMEOUT_PADDING_SECONDS = 0.2
local ACTIVITY_TIMEOUT_RETRY_DELAY_SECONDS = 0.1
local ACTIVITY_TIMEOUT_RETRY_ATTEMPTS = 5

local INVENTORY_FULL_ERROR_MESSAGE = "Inventory is full"
local INTERRUPTED_ERROR_MESSAGE = "Interrupted"
local UI_INTERRUPTED_ERROR_MESSAGE = "UI Interrupted"

local function defaultDebugEnabled()
	return SmartRez.GetDebugEnabled and SmartRez:GetDebugEnabled() or false
end

local function buildDebugPrefix(options)
	return options.debugPrefix or options.label or options.key or "Craft"
end

local function debugPrint(options, ...)
	local debugEnabled = options.debugEnabled
	if type(debugEnabled) == "function" then
		if not debugEnabled() then
			return
		end
	elseif debugEnabled ~= true and not defaultDebugEnabled() then
		return
	end

	print(buildDebugPrefix(options) .. ":", ...)
end

function SmartRez:IsActiveCraftClickPhase(down)
	return (down == true) == (_GetCVar("ActionButtonUseKeyDown") == "1")
end

function SmartRez:GetActiveCraftTimeout(fallbackSeconds, paddingSeconds)
	local _, _, _, startTimeMS, endTimeMS = _UnitCastingInfo("player")
	if not startTimeMS or not endTimeMS then
		_, _, _, startTimeMS, endTimeMS = _UnitChannelInfo("player")
	end

	if startTimeMS and endTimeMS then
		local remainingSeconds = math.max(0, ((endTimeMS - (_GetTime() * 1000)) / 1000))
		return remainingSeconds + (paddingSeconds or ACTIVITY_TIMEOUT_PADDING_SECONDS), true
	end

	return fallbackSeconds, false
end

function SmartRez:CreateCraftActionController(options)
	local controller = {
		options = options or {},
		frame = CreateFrame("Frame"),
		unBlockButton = 0,
		pendingUnlockAt = 0,
		isWaitingForCraftStart = false,
		isCraftInProgress = false,
		expectedSpellID = nil,
		activityTimeoutRetryAttempts = 0,
		activityTimeoutRetryAt = 0,
	}

	function controller:Debug(...)
		debugPrint(self.options, ...)
	end

	function controller:IsBlocked()
		return self.unBlockButton > _GetTime()
	end

	function controller:MarkDirty()
		local markDirty = self.options.markDirty
		if type(markDirty) == "function" then
			markDirty()
		end
	end

	function controller:ClearEventState()
		self.unBlockButton = 0
		self.pendingUnlockAt = 0
		self.isWaitingForCraftStart = false
		self.isCraftInProgress = false
		self.expectedSpellID = nil
		self.activityTimeoutRetryAttempts = 0
		self.activityTimeoutRetryAt = 0
		self.frame:UnregisterAllEvents()
		self.frame:SetScript("OnUpdate", nil)
	end

	function controller:Unlock(reason)
		self:Debug("unlock", reason or "unknown")
		self:ClearEventState()
		self:MarkDirty()
	end

	function controller:SetTimeout(seconds, reason)
		self.unBlockButton = _GetTime() + seconds
		self.pendingUnlockAt = self.unBlockButton
		self:Debug("lock", reason or "timeout", "timeout", seconds)
	end

	function controller:SetTimeoutSilently(seconds)
		self.unBlockButton = _GetTime() + seconds
		self.pendingUnlockAt = self.unBlockButton
	end

	function controller:BeginPendingStart(expectedSpellID)
		self.isWaitingForCraftStart = true
		self.isCraftInProgress = false
		self.expectedSpellID = expectedSpellID
		self:SetTimeout(self.options.startTimeoutSeconds or 1, "pending craft start")
		if type(self.options.registerEvents) == "function" then
			self.options.registerEvents(self)
		end
		self.frame:SetScript("OnUpdate", function()
			if self.isCraftInProgress and self.activityTimeoutRetryAttempts > 0 and _GetTime() >= self.activityTimeoutRetryAt then
				local timeoutSeconds, hasLiveCastInfo = SmartRez:GetActiveCraftTimeout(
					self.options.activityTimeoutSeconds or 2,
					self.options.activityTimeoutPaddingSeconds
				)
				if hasLiveCastInfo then
					self:SetTimeoutSilently(timeoutSeconds)
					self.activityTimeoutRetryAttempts = 0
					self.activityTimeoutRetryAt = 0
					self:Debug("lock", "activity timeout updated", "timeout", _format("%.2f", timeoutSeconds))
				else
					self.activityTimeoutRetryAttempts = self.activityTimeoutRetryAttempts - 1
					self.activityTimeoutRetryAt = _GetTime() + ACTIVITY_TIMEOUT_RETRY_DELAY_SECONDS
				end
			end

			if self.pendingUnlockAt > 0 and _GetTime() >= self.pendingUnlockAt then
				if self.isCraftInProgress then
					self:Unlock(self.options.activityTimeoutReason or "activity timeout")
				else
					self:Debug("lock", "pending craft timed out")
					self:Unlock(self.options.startTimeoutReason or "craft start timeout")
				end
			end
		end)
	end

	function controller:RefreshActivityTimeout(seconds, reason)
		local wasCraftInProgress = self.isCraftInProgress
		self.isWaitingForCraftStart = false
		self.isCraftInProgress = true
		local timeoutSeconds, hasLiveCastInfo = SmartRez:GetActiveCraftTimeout(
			seconds or self.options.activityTimeoutSeconds or 2,
			self.options.activityTimeoutPaddingSeconds
		)
		if hasLiveCastInfo then
			self.activityTimeoutRetryAttempts = 0
			self.activityTimeoutRetryAt = 0
		else
			self.activityTimeoutRetryAttempts = ACTIVITY_TIMEOUT_RETRY_ATTEMPTS
			self.activityTimeoutRetryAt = _GetTime() + ACTIVITY_TIMEOUT_RETRY_DELAY_SECONDS
		end

		if wasCraftInProgress then
			self:SetTimeoutSilently(timeoutSeconds)
			return
		end

		self:SetTimeout(timeoutSeconds, reason or self.options.activityTimeoutReason or "activity")
	end

	function controller:MatchesExpectedSpell(spellID)
		if not self.expectedSpellID or not spellID then
			return true
		end

		return spellID == self.expectedSpellID
	end

	function controller:HandleTradeSkillCraftBegin(spellID, activityReason, activityTimeoutSeconds)
		if not self:MatchesExpectedSpell(spellID) then
			self:Debug("trade skill event", "TRADE_SKILL_CRAFT_BEGIN", "ignored spell", spellID or "nil", "expected", self.expectedSpellID or "nil")
			return false
		end

		self:Debug("trade skill event", "TRADE_SKILL_CRAFT_BEGIN", spellID or "nil")
		self:RefreshActivityTimeout(activityTimeoutSeconds, activityReason)
		return true
	end

	function controller:HandleBlockedClick()
		if not self:IsBlocked() then
			return false
		end

		self:Debug(
			"blocked",
			"remaining", _format("%.2f", self.unBlockButton - _GetTime()),
			"waitingForStart", tostring(self.isWaitingForCraftStart),
			"craftInProgress", tostring(self.isCraftInProgress),
			"spell", self.expectedSpellID or "nil"
		)
		return true
	end

	function controller:HandleUIError(errorType, message, interruptedReason)
		if not self:IsBlocked() then
			return false
		end

		local normalizedMessage = type(message) == "string" and string.lower(message) or nil

		if message == ERR_INV_FULL or normalizedMessage == string.lower(INVENTORY_FULL_ERROR_MESSAGE) then
			self:Debug("ui error", errorType or "nil", message or "nil")
			self:Unlock("bags full")
			return true
		end

		if normalizedMessage == string.lower(INTERRUPTED_ERROR_MESSAGE) or normalizedMessage == string.lower(UI_INTERRUPTED_ERROR_MESSAGE) then
			self:Debug("ui error", errorType or "nil", message or "nil")
			self:Unlock(interruptedReason or "ui interrupted")
			return true
		end

		self:Debug("ui error ignored", errorType or "nil", message or "nil")
		return false
	end

	return controller
end

function SmartRez:CreateCraftActionButton(actionController, buttonName, onActionClick)
	local actionFrame = actionController.frame
	actionFrame.btn = CreateFrame("Button", buttonName, UIParent, "SecureActionButtonTemplate")
	actionFrame.btn:RegisterForClicks("AnyUp", "AnyDown")
	actionFrame.btn:SetScript("OnClick", function(_, _, down)
		if not self:IsActiveCraftClickPhase(down) then
			return
		end

		if actionController:HandleBlockedClick() then
			return
		end

		onActionClick(actionController)
	end)

	return actionFrame.btn
end

function SmartRez:EnsureCraftProfessionOpen(actionController, openTradeSkillID)
	if not openTradeSkillID then
		return true
	end

	local professionInfo = _C_GetBaseProfessionInfo and _C_GetBaseProfessionInfo()
	if professionInfo and professionInfo.professionID == openTradeSkillID then
		actionController:Debug("profession ready", professionInfo.professionID)
		return true
	end

	actionController:Debug("opening profession", openTradeSkillID, "current", professionInfo and professionInfo.professionID or "nil")
	if _C_OpenTradeSkill then
		_C_OpenTradeSkill(openTradeSkillID)
	end

	return false
end

function SmartRez:OpenCraftRecipeByID(actionController, recipeID)
	if not recipeID then
		return
	end

	actionController:Debug("opening recipe", recipeID)
	if _C_OpenRecipe then
		_C_OpenRecipe(recipeID)
	end
end
