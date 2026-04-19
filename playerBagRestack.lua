local SmartRez = _G.SmartRez

local _C_GetContainerItemInfo = C_Container and C_Container.GetContainerItemInfo
local _C_PickupContainerItem = C_Container and C_Container.PickupContainerItem
local _C_GetItemMaxStackSizeByID = C_Item and C_Item.GetItemMaxStackSizeByID
local _C_Item_IsLocked = C_Item and C_Item.IsLocked
local _ClearCursor = ClearCursor

---@class SmartRezPlayerBagStack
---@field bag integer
---@field slot integer
---@field count integer
---@field itemID integer

---@class SmartRezPlayerBagRestackMove
---@field itemID integer
---@field action string
---@field source SmartRezPlayerBagStack
---@field target SmartRezPlayerBagStack
---@field maxStack integer

SmartRez.PlayerBagRestack = SmartRez.PlayerBagRestack or {}
local PlayerBagRestack = SmartRez.PlayerBagRestack

local function isHigherBagSlot(leftBag, leftSlot, rightBag, rightSlot)
	if leftBag ~= rightBag then
		return leftBag > rightBag
	end

	return leftSlot > rightSlot
end

local function compareAscendingCountThenBagSlot(left, right)
	if left.count ~= right.count then
		return left.count < right.count
	end

	if left.bag ~= right.bag then
		return left.bag < right.bag
	end

	return left.slot < right.slot
end

local function getStackSummary(stacks, maxStack)
	local total = 0
	local fullStacks = 0
	local partials = {}
	local highestStack = nil

	for _, stack in ipairs(stacks) do
		total = total + stack.count

		if stack.count == maxStack then
			fullStacks = fullStacks + 1
		else
			partials[#partials + 1] = stack
		end

		if not highestStack or isHigherBagSlot(stack.bag, stack.slot, highestStack.bag, highestStack.slot) then
			highestStack = stack
		end
	end

	return {
		total = total,
		fullStacks = fullStacks,
		targetFullStacks = math.floor(total / maxStack),
		targetStacks = math.ceil(total / maxStack),
		partials = partials,
		highestStack = highestStack,
	}
end

function PlayerBagRestack:GetStacks(itemID)
	local stacks = {}

	if not itemID then
		return stacks
	end

	SmartRez:ForEachPlayerBagSlot(function(bag, slot)
		local itemInfo = _C_GetContainerItemInfo and _C_GetContainerItemInfo(bag, slot) or nil
		if itemInfo and itemInfo.itemID == itemID and (itemInfo.stackCount or 0) > 0 then
			stacks[#stacks + 1] = {
				bag = bag,
				slot = slot,
				count = itemInfo.stackCount or 0,
				itemID = itemID,
			}
		end
	end)

	return stacks
end

function PlayerBagRestack:GetNextMove(itemID)
	if not itemID or not _C_GetItemMaxStackSizeByID or not _C_PickupContainerItem or not _ClearCursor or not _C_Item_IsLocked then
		return nil, "unsupported"
	end

	local maxStack = _C_GetItemMaxStackSizeByID(itemID) or 1
	if maxStack <= 1 then
		return nil, "not stackable"
	end

	local stacks = self:GetStacks(itemID)
	if #stacks <= 1 then
		return nil, "single stack"
	end

	local summary = getStackSummary(stacks, maxStack)
	local partials = summary.partials
	if #partials == 0 then
		return nil, "all full"
	end

	local combineWorkNeeded = #stacks > summary.targetStacks or summary.fullStacks ~= summary.targetFullStacks
	if combineWorkNeeded and #partials >= 2 then
		table.sort(partials, compareAscendingCountThenBagSlot)

		local source = partials[1]
		local target = partials[#partials]
		local sourceLocation = ItemLocation:CreateFromBagAndSlot(source.bag, source.slot)
		local targetLocation = ItemLocation:CreateFromBagAndSlot(target.bag, target.slot)
		if _C_Item_IsLocked(sourceLocation) or _C_Item_IsLocked(targetLocation) then
			return nil, "locked"
		end

		return {
			itemID = itemID,
			action = "merge",
			source = source,
			target = target,
			maxStack = maxStack,
		}
	end

	local partial = partials[1]
	local highestStack = summary.highestStack
	if not highestStack or (partial.bag == highestStack.bag and partial.slot == highestStack.slot) then
		return nil, combineWorkNeeded and "waiting for combine" or "partial already highest slot"
	end

	local sourceLocation = ItemLocation:CreateFromBagAndSlot(partial.bag, partial.slot)
	local targetLocation = ItemLocation:CreateFromBagAndSlot(highestStack.bag, highestStack.slot)
	if _C_Item_IsLocked(sourceLocation) or _C_Item_IsLocked(targetLocation) then
		return nil, "locked"
	end

	return {
		itemID = itemID,
		action = "move_partial_to_highest_slot",
		source = partial,
		target = highestStack,
		maxStack = maxStack,
	}
end

function PlayerBagRestack:PerformMove(itemID)
	local move, reason = self:GetNextMove(itemID)
	if not move then
		return false, reason
	end

	_ClearCursor()
	_C_PickupContainerItem(move.source.bag, move.source.slot)
	_C_PickupContainerItem(move.target.bag, move.target.slot)
	_ClearCursor()
	return true, move.action
end

function PlayerBagRestack:GetRunner()
	if self.runner then
		return self.runner
	end

	local runner = CreateFrame("Frame")
	runner.active = false
	runner.waiting = false
	runner.itemID = nil

	local function finish(reason)
		runner.active = false
		runner.waiting = false
		runner.itemID = nil
		runner:UnregisterAllEvents()

		if SmartRez:GetDebugEnabled() then
			print("SmartRez PB:", "restack complete", reason or "done")
		end
	end

	local function tryNextMove()
		if not runner.active or not runner.itemID then
			return
		end

		local moved, reason = PlayerBagRestack:PerformMove(runner.itemID)
		if not moved then
			finish(reason)
			return
		end

		runner.waiting = true
		runner:RegisterEvent("BAG_UPDATE_DELAYED")
	end

	runner:SetScript("OnEvent", function(_, eventName)
		if eventName ~= "BAG_UPDATE_DELAYED" or not runner.active or not runner.waiting then
			return
		end

		runner.waiting = false
		runner:UnregisterEvent("BAG_UPDATE_DELAYED")
		C_Timer.After(0.05, tryNextMove)
	end)

	runner.TryNextMove = tryNextMove
	runner.Finish = finish
	self.runner = runner
	return runner
end

function PlayerBagRestack:Start(itemID)
	local runner = self:GetRunner()
	if runner.active then
		if runner.itemID == itemID then
			return true
		end

		return false
	end

	runner.itemID = itemID
	runner.active = true
	runner.waiting = false
	runner:TryNextMove()
	return runner.active
end

function PlayerBagRestack:IsActive(itemID)
	local runner = self.runner
	if not runner or not runner.active then
		return false
	end

	if itemID and runner.itemID ~= itemID then
		return false
	end

	return true
end

function SmartRez:GetPlayerBagItemStacks(itemID)
	return PlayerBagRestack:GetStacks(itemID)
end

function SmartRez:GetPlayerBagItemRestackMove(itemID)
	return PlayerBagRestack:GetNextMove(itemID)
end

function SmartRez:PerformPlayerBagItemRestackMove(itemID)
	return PlayerBagRestack:PerformMove(itemID)
end

function SmartRez:StartPlayerBagItemRestack(itemID)
	return PlayerBagRestack:Start(itemID)
end

function SmartRez:IsPlayerBagItemRestackActive(itemID)
	return PlayerBagRestack:IsActive(itemID)
end
