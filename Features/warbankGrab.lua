local SmartRez = _G.SmartRez
local _C_OpenTradeSkill = C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill
local _C_UseContainerItem = C_Container and C_Container.UseContainerItem
local button

local function getHoveredItemID()
	if not GameTooltip or not GameTooltip:IsShown() or not GameTooltip.GetItem then
		return nil
	end

	local _, itemLink = GameTooltip:GetItem()
	if not itemLink then
		return nil
	end

	return C_Item.GetItemInfoInstant(itemLink)
end

local function findLargestWarbankStack(itemID)
	if not itemID then
		return nil
	end

	local bestTarget

	SmartRez:ForEachContainerSlot(SmartRez:GetWarbankContainerIDs(), function(bag, slot)
		local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
		if not itemInfo or itemInfo.itemID ~= itemID then
			return false
		end

		local stackCount = itemInfo.stackCount or 0
		if not bestTarget or stackCount > bestTarget.stackCount then
			bestTarget = {
				itemID = itemID,
				bag = bag,
				slot = slot,
				stackCount = stackCount,
			}
		end

		return false
	end)

	return bestTarget
end

local function findSmallestWarbankStackUnderCount(itemID, maxStackCount)
	if not itemID or not maxStackCount or maxStackCount <= 0 then
		return nil
	end

	local bestTarget

	SmartRez:ForEachContainerSlot(SmartRez:GetWarbankContainerIDs(), function(bag, slot)
		local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
		if not itemInfo or itemInfo.itemID ~= itemID then
			return false
		end

		local stackCount = itemInfo.stackCount or 0
		if stackCount <= 0 or stackCount >= maxStackCount then
			return false
		end

		if not bestTarget or stackCount < bestTarget.stackCount then
			bestTarget = {
				itemID = itemID,
				bag = bag,
				slot = slot,
				stackCount = stackCount,
			}
		end

		return false
	end)

	return bestTarget
end

function SmartRez:GetHoveredWarbankItemID()
	return getHoveredItemID()
end

function SmartRez:GetWarbankGrabTarget(itemID)
	return findLargestWarbankStack(itemID or getHoveredItemID())
end

function SmartRez:GetWarbankPartialStackTarget(itemID, maxStackCount)
	return findSmallestWarbankStackUnderCount(itemID, maxStackCount)
end

function SmartRez:HasWarbankGrabTarget()
	return self:GetWarbankGrabTarget() ~= nil
end

function SmartRez:TryGrabWarbankTarget(target)
	if not target or target.bag == nil or target.slot == nil or not _C_UseContainerItem then
		return false
	end

	_C_UseContainerItem(target.bag, target.slot)
	return true
end

function SmartRez:TryGrabHoveredWarbankItem()
	local proxyProfessionID = self.GetDefaultProfessionProxyProfessionID and self:GetDefaultProfessionProxyProfessionID() or nil
	if proxyProfessionID then
		local proxyReady = self.IsProfessionProxyReady and self:IsProfessionProxyReady(proxyProfessionID) or false
		if not proxyReady then
			if self.OpenProfessionProxy then
				self:OpenProfessionProxy(proxyProfessionID)
			elseif _C_OpenTradeSkill then
				_C_OpenTradeSkill(proxyProfessionID)
			end
			return false
		end
	end

	local target = self:GetWarbankGrabTarget()
	if not target then
		return false
	end

	return self:TryGrabWarbankTarget(target)
end

button = CreateFrame("Button", "WarbankGrabBtn", nil, "SecureActionButtonTemplate")
button:RegisterForClicks("AnyDown")
button:SetScript("OnClick", function()
	if InCombatLockdown() then
		return
	end

	SmartRez:TryGrabHoveredWarbankItem()
end)

SmartRez:RegisterBindableAction({
	key = "warbankgrab",
	label = "Warbank Grab",
	buttonName = "WarbankGrabBtn",
	order = 11,
})
