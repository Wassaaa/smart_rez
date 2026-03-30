_G.SmartRez = LibStub("AceAddon-3.0"):NewAddon("SmartRez", "AceConsole-3.0", "AceEvent-3.0")
_G.SmartRez.appName = "Smart Rez"
_G.SmartRez.bindableActions = {}
_G.SmartRez.craftSalvageActions = {}
_G.SmartRez.craftSalvageCache = {}
_G.SmartRez.craftSalvageCacheDirty = true
_G.SmartRez.craftRecipeActions = {}
_G.SmartRez.craftRecipeCache = {}
_G.SmartRez.craftRecipeCacheDirty = true
_G.SmartRez.knownProfessions = {}

_G.SmartRez.Profession = {
	Alchemy = 171,
	Blacksmithing = 164,
	Cooking = 185,
	Enchanting = 333,
	Engineering = 202,
	Fishing = 356,
	Herbalism = 182,
	Inscription = 773,
	Jewelcrafting = 755,
	Leatherworking = 165,
	Mining = 186,
	Skinning = 393,
	Tailoring = 197,
}

function _G.SmartRez:RegisterBindableAction(action)
	self.bindableActions[action.key] = action
end

function _G.SmartRez:RefreshKnownProfessions()
	local knownProfessions = {}
	local professionIndexes = { _G["GetProfessions"]() }

	for _, professionIndex in ipairs(professionIndexes) do
		if professionIndex then
			local _, _, _, _, _, _, professionID = _G["GetProfessionInfo"](professionIndex)
			if professionID then
				knownProfessions[professionID] = true
			end
		end
	end

	if _G["C_TradeSkillUI"] and _G["C_TradeSkillUI"]["GetChildProfessionInfos"] then
		for _, professionInfo in ipairs(_G["C_TradeSkillUI"]["GetChildProfessionInfos"]() or {}) do
			if professionInfo.professionID then
				knownProfessions[professionInfo.professionID] = true
			end
			if professionInfo.parentProfessionID then
				knownProfessions[professionInfo.parentProfessionID] = true
			end
		end
	end

	self.knownProfessions = knownProfessions
end

function _G.SmartRez:HasProfession(professionID)
	return self.knownProfessions[professionID] == true
end

function _G.SmartRez:GetBindableActions()
	local actions = {}
	for _, action in pairs(self.bindableActions) do
		if not action.requiredProfession or self:HasProfession(action.requiredProfession) then
			table.insert(actions, action)
		end
	end
	table.sort(actions, function(left, right)
		return left.order < right.order
	end)
	return actions
end

function _G.SmartRez:MarkCraftSalvageCacheDirty()
	self.craftSalvageCacheDirty = true
end

function _G.SmartRez:MarkCraftRecipeCacheDirty()
	self.craftRecipeCacheDirty = true
end

function _G.SmartRez:HandleInventoryChanged()
	self:MarkCraftSalvageCacheDirty()
	self:MarkCraftRecipeCacheDirty()

	if self.RebuildCraftSalvageCache then
		self:RebuildCraftSalvageCache()
	end

	if self.RebuildCraftRecipeCache then
		self:RebuildCraftRecipeCache()
	end
end

function _G.SmartRez:HandleProfessionsChanged()
	self:RefreshKnownProfessions()
	self:MarkCraftRecipeCacheDirty()

	if self.RefreshViews then
		self:RefreshViews()
	end
end

function _G.SmartRez:OnEnable()
	self:RegisterEvent("BAG_UPDATE_DELAYED", "HandleInventoryChanged")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "HandleInventoryChanged")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "HandleProfessionsChanged")
	self:RegisterEvent("SKILL_LINES_CHANGED", "HandleProfessionsChanged")
	self:HandleProfessionsChanged()
	self:HandleInventoryChanged()
end

_G["BINDING_HEADER_SMARTREZ"] = "Smart Rez"
_G["BINDING_NAME_CLICK SmartRezModeToggleBtn:LeftButton"] = "Toggle Smart Rez Mode"
