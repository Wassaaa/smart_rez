local SmartRez = _G.SmartRez

local _C_GetBaseProfessionInfo = C_TradeSkillUI.GetBaseProfessionInfo
local _C_OpenTradeSkill = C_TradeSkillUI.OpenTradeSkill
local _C_OpenRecipe = C_TradeSkillUI.OpenRecipe
local _C_SortBags = C_Container.SortBags
local _GetCVar = GetCVar
local _GetTime = GetTime
local _UnitCastingInfo = UnitCastingInfo
local _UnitChannelInfo = UnitChannelInfo
local _format = string.format

local ACTIVITY_TIMEOUT_PADDING_SECONDS = 0.2
local ACTIVITY_TIMEOUT_RETRY_DELAY_SECONDS = 0.1
local ACTIVITY_TIMEOUT_RETRY_ATTEMPTS = 5

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
		isWaitingForBagSpace = false,
		isCraftInProgress = false,
		expectedSpellID = nil,
		timeoutExpiredReason = nil,
		bagSpaceRetrySeconds = 0,
		lastBagSortAttemptAt = 0,
		activityTimeoutRetryAttempts = 0,
		activityTimeoutRetryAt = 0,
	}

	function controller:Debug(...)
		debugPrint(self.options, ...)
	end

	function controller:IsBlocked()
		return self.isWaitingForBagSpace or self.unBlockButton > _GetTime()
	end

	function controller:GetLockState()
		return string.format(
			"blocked=%s remaining=%.2f waitingStart=%s waitingBag=%s inProgress=%s spell=%s timeout=%s",
			tostring(self:IsBlocked()),
			math.max(0, (self.unBlockButton or 0) - _GetTime()),
			tostring(self.isWaitingForCraftStart),
			tostring(self.isWaitingForBagSpace),
			tostring(self.isCraftInProgress),
			tostring(self.expectedSpellID or "nil"),
			tostring(self.timeoutExpiredReason or "nil")
		)
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
		self.isWaitingForBagSpace = false
		self.isCraftInProgress = false
		self.expectedSpellID = nil
		self.timeoutExpiredReason = nil
		self.bagSpaceRetrySeconds = 0
		self.lastBagSortAttemptAt = 0
		self.activityTimeoutRetryAttempts = 0
		self.activityTimeoutRetryAt = 0
		self.frame:UnregisterAllEvents()
		self.frame:SetScript("OnUpdate", nil)
	end

	function controller:Unlock(reason)
		self:Debug("unlock", reason or "unknown", self:GetLockState())
		self:ClearEventState()
		self:MarkDirty()
	end

	function controller:SetTimeout(seconds, reason)
		self.unBlockButton = _GetTime() + seconds
		self.pendingUnlockAt = self.unBlockButton
		self:Debug("lock", reason or "timeout", "timeout", seconds, self:GetLockState())
	end

	function controller:SetTimeoutSilently(seconds)
		self.unBlockButton = _GetTime() + seconds
		self.pendingUnlockAt = self.unBlockButton
	end

	function controller:EnsureOnUpdate()
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
					self:Debug("timeout reached", self.options.activityTimeoutReason or "activity timeout", self:GetLockState())
					self:Unlock(self.options.activityTimeoutReason or "activity timeout")
				else
					if self.isWaitingForCraftStart then
						self:Debug("lock", "pending craft timed out")
					end
					self:Debug("timeout reached", self.timeoutExpiredReason or self.options.startTimeoutReason or "timeout", self:GetLockState())
					self:Unlock(self.timeoutExpiredReason or self.options.startTimeoutReason or "timeout")
				end
			end
		end)
	end

	function controller:BeginPendingStart(expectedSpellID)
		self.isWaitingForCraftStart = true
		self.isWaitingForBagSpace = false
		self.isCraftInProgress = false
		self.expectedSpellID = expectedSpellID
		self.timeoutExpiredReason = self.options.startTimeoutReason or "craft start timeout"
		self:SetTimeout(self.options.startTimeoutSeconds or 1, "pending craft start")
		if type(self.options.registerEvents) == "function" then
			self.options.registerEvents(self)
		end
		self:EnsureOnUpdate()
	end

	function controller:BeginExternalWait(seconds, reason, timeoutReason)
		self.isWaitingForCraftStart = false
		self.isWaitingForBagSpace = false
		self.isCraftInProgress = false
		self.expectedSpellID = nil
		self.timeoutExpiredReason = timeoutReason or reason or "wait timeout"
		self.bagSpaceRetrySeconds = 0
		self.activityTimeoutRetryAttempts = 0
		self.activityTimeoutRetryAt = 0
		self:SetTimeout(seconds, reason or "wait")
		self:EnsureOnUpdate()
	end

	function controller:BeginBagSpaceWait(seconds, reason)
		self.isWaitingForCraftStart = false
		self.isWaitingForBagSpace = true
		self.isCraftInProgress = false
		self.expectedSpellID = nil
		self.timeoutExpiredReason = reason or "waiting for bag space"
		self.bagSpaceRetrySeconds = 0
		self.activityTimeoutRetryAttempts = 0
		self.activityTimeoutRetryAt = 0
		self.unBlockButton = 0
		self.pendingUnlockAt = 0
		self.frame:SetScript("OnUpdate", nil)
		self:Debug("lock", reason or "waiting for bag space")
	end

	function controller:TrySortPlayerBagsForSpace()
		if not _C_SortBags then
			return false
		end

		if (_GetTime() - self.lastBagSortAttemptAt) < 1 then
			return false
		end

		self.lastBagSortAttemptAt = _GetTime()
		self:Debug("sorting bags", "before bag space wait")
		_C_SortBags()
		if SmartRez.RebuildInventoryCounts then
			SmartRez:RebuildInventoryCounts()
		end
		self:MarkDirty()
		return true
	end

	function controller:RefreshActivityTimeout(seconds, reason)
		local wasCraftInProgress = self.isCraftInProgress
		self.isWaitingForCraftStart = false
		self.isWaitingForBagSpace = false
		self.isCraftInProgress = true
		self.timeoutExpiredReason = self.options.activityTimeoutReason or "activity timeout"
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

	function controller:HandleUnitSpellcastStart(unitToken, spellID, activityReason, activityTimeoutSeconds)
		if unitToken ~= "player" or not self:IsBlocked() or not self:MatchesExpectedSpell(spellID) then
			return false
		end

		self:Debug("spell event", "UNIT_SPELLCAST_START", unitToken, spellID or "nil")
		self:RefreshActivityTimeout(activityTimeoutSeconds, activityReason)
		return true
	end

	function controller:HandleUnitSpellcastComplete(unitToken, spellID, completionReason)
		if unitToken ~= "player" or not self:IsBlocked() or not self:MatchesExpectedSpell(spellID) then
			return false
		end

		self:Debug("spell event", completionReason or "spell complete", unitToken, spellID or "nil")
		return true
	end

	function controller:HandleTradeSkillCraftStopped(reason)
		if not self:IsBlocked() then
			return false
		end

		self:Debug("trade skill event", reason or "UPDATE_TRADESKILL_CAST_STOPPED")
		return true
	end

	function controller:HandleUnitSpellcastInterrupted(unitToken, spellID, reason)
		if unitToken ~= "player" or not self:IsBlocked() or not self:MatchesExpectedSpell(spellID) then
			return false
		end

		self:Debug("spell event", reason or "spell interrupted", unitToken, spellID or "nil")
		self:Unlock(reason or "spell interrupted")
		return true
	end

	function controller:HandleCraftEvent(eventName, ...)
		if eventName == "TRADE_SKILL_CRAFT_BEGIN" then
			return self:HandleTradeSkillCraftBegin(..., self.options.activityReason or "craft in progress", self.options.activityTimeoutSeconds)
		end

		if eventName == "UPDATE_TRADESKILL_CAST_STOPPED" then
			return self:HandleTradeSkillCraftStopped(eventName)
		end

		if eventName == "BAG_UPDATE_DELAYED" then
			return self:HandleBagUpdateWhileWaitingForSpace()
		end

		local unitToken, _, spellID = ...
		if eventName == "UNIT_SPELLCAST_START" then
			return self:HandleUnitSpellcastStart(unitToken, spellID, self.options.activityReason or "craft in progress")
		end

		if eventName == "UNIT_SPELLCAST_SUCCEEDED" or eventName == "UNIT_SPELLCAST_STOP" then
			return self:HandleUnitSpellcastComplete(unitToken, spellID, eventName)
		end

		if eventName == "UNIT_SPELLCAST_FAILED" or eventName == "UNIT_SPELLCAST_FAILED_QUIET" then
			return self:HandleUnitSpellcastFailed(unitToken, spellID, eventName)
		end

		if eventName == "UNIT_SPELLCAST_INTERRUPTED" then
			return self:HandleUnitSpellcastInterrupted(unitToken, spellID, eventName)
		end

		return false
	end

	function controller:HandleBlockedClick()
		if not self:IsBlocked() then
			return false
		end

		if SmartRez.goldPrinterAllowCraftInterrupt == true and self.isCraftInProgress then
			self:Debug("interrupting", "gold printer priority", self:GetLockState())
			self:Unlock("gold printer priority interrupt")
			return false
		end

		if self.isWaitingForBagSpace then
			self:Debug(
				"blocked",
				self:GetLockState(),
				"waitingForBagSpace", "true",
				"waitingForStart", tostring(self.isWaitingForCraftStart),
				"craftInProgress", tostring(self.isCraftInProgress),
				"spell", self.expectedSpellID or "nil"
			)
			return true
		end

		self:Debug(
			"blocked",
			self:GetLockState(),
			"remaining", _format("%.2f", self.unBlockButton - _GetTime()),
			"waitingForStart", tostring(self.isWaitingForCraftStart),
			"craftInProgress", tostring(self.isCraftInProgress),
			"spell", self.expectedSpellID or "nil"
		)
		return true
	end

	function controller:HandleBagUpdateWhileWaitingForSpace()
		if not self.isWaitingForBagSpace then
			return false
		end

		if SmartRez:GetFreeBagSlots() > 0 then
			self:Debug("bags updated", "space available")
			self:Unlock("bag space available")
		end

		return true
	end

	function controller:HandleUnitSpellcastFailed(unitToken, spellID, failureReason)
		if unitToken ~= "player" or not self:IsBlocked() or not self:MatchesExpectedSpell(spellID) then
			return false
		end

		self:Debug("spell event", failureReason or "spell failed", unitToken, spellID or "nil")
		if SmartRez:GetFreeBagSlots() <= 0 then
			self:TrySortPlayerBagsForSpace()
			if SmartRez:GetFreeBagSlots() > 0 then
				self:Unlock("bag space created by sort")
				return true
			end

			self:BeginBagSpaceWait(nil, "waiting for bag space")
			return true
		end

		self:Unlock(failureReason or "spell failed")
		return true
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
