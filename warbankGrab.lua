local SmartRez = _G.SmartRez
local _C_OpenTradeSkill = C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill
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

local function buildWarbankGrabMacroText(target)
	if not target or target.bag == nil or target.slot == nil then
		return nil
	end

	return string.format("/use %d %d", target.bag, target.slot)
end

function SmartRez:GetHoveredWarbankItemID()
	return getHoveredItemID()
end

function SmartRez:GetWarbankGrabTarget(itemID)
	return findLargestWarbankStack(itemID or getHoveredItemID())
end

function SmartRez:HasWarbankGrabTarget()
	return self:GetWarbankGrabTarget() ~= nil
end

function SmartRez:PrepareWarbankGrabMacro()
	local proxyProfessionID = self.GetDefaultProfessionProxyProfessionID and self:GetDefaultProfessionProxyProfessionID() or nil
	if proxyProfessionID then
		local proxyReady = self.IsProfessionProxyReady and self:IsProfessionProxyReady(proxyProfessionID) or false
		if not proxyReady then
			if self.OpenProfessionProxy then
				self:OpenProfessionProxy(proxyProfessionID)
			elseif _C_OpenTradeSkill then
				_C_OpenTradeSkill(proxyProfessionID)
			end
			return nil
		end
	end

	local target = self:GetWarbankGrabTarget()
	if not target then
		return nil
	end

	return buildWarbankGrabMacroText(target)
end

button = CreateFrame("Button", "WarbankGrabBtn", nil, "SecureActionButtonTemplate")
button:RegisterForClicks("AnyDown")
button:SetAttribute("type", "macro")

button:SetScript("PreClick", function(self)
	if InCombatLockdown() then
		return
	end

	self:SetAttribute("macrotext", SmartRez:PrepareWarbankGrabMacro())
end)

button:SetScript("PostClick", function(self)
	self:SetAttribute("macrotext", nil)
end)

SmartRez:RegisterBindableAction({
	key = "warbankgrab",
	label = "Warbank Grab",
	buttonName = "WarbankGrabBtn",
	order = 11,
})
