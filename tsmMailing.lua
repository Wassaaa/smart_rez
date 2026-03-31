local SmartRez = _G.SmartRez

local BUTTON_LABELS = {
	openAllMail = "Open All Mail",
	openMail = "Open Mail",
	allSold = "All Sold",
	allBought = "All Bought",
	allCancelled = "All Cancelled",
	allExpired = "All Expired",
	allOther = "All Other",
	sold = "Sold",
	bought = "Bought",
	cancelled = "Cancelled",
	expired = "Expired",
	other = "Other",
}

local function isMailVisible()
	if _G.TSM_API and _G.TSM_API.IsUIVisible then
		local ok, isVisible = pcall(_G.TSM_API.IsUIVisible, "MAILING")
		if ok and isVisible then
			return true
		end
	end

	return _G.MailFrame and _G.MailFrame:IsShown()
end

local function getButtonText(button)
	if not button then
		return nil
	end

	if type(button.GetText) == "function" then
		local text = button:GetText()
		if text and text ~= "" then
			return text
		end
	end

	local textRegion = button.text
	if textRegion and type(textRegion.GetText) == "function" then
		local text = textRegion:GetText()
		if text and text ~= "" then
			return text
		end
	end

	local regions = { button:GetRegions() }
	for _, region in ipairs(regions) do
		if region and region.GetObjectType and region:GetObjectType() == "FontString" then
			local text = region:GetText()
			if text and text ~= "" then
				return text
			end
		end
	end

	return nil
end

local function findVisibleButtonByLabel(...)
	local wanted = {}
	for i = 1, select("#", ...) do
		wanted[select(i, ...)] = true
	end

	local frame = EnumerateFrames()
	while frame do
		if frame.IsObjectType and frame:IsObjectType("Button") and frame.IsShown and frame:IsShown() and frame.IsEnabled and frame:IsEnabled() then
			local text = getButtonText(frame)
			if text and wanted[text] then
				return frame, text
			end
		end
		frame = EnumerateFrames(frame)
	end

	return nil
end

local function clickTSMButton(...)
	if not isMailVisible() then
		print("Smart Rez: open the TSM mailbox UI before using this macro.")
		return
	end

	local button = findVisibleButtonByLabel(...)
	if not button then
		print("Smart Rez: could not find the live TSM mail button.")
		return
	end

	button:Click()
end

local function createProxyButton(config)
	local button = CreateFrame("Button", config.buttonName, UIParent, "SecureActionButtonTemplate")
	button:RegisterForClicks("AnyUp", "AnyDown")
	button:SetScript("OnClick", function()
		clickTSMButton(unpack(config.labels))
	end)

	if config.key and config.label then
		SmartRez:RegisterBindableAction({
			key = config.key,
			label = config.label,
			buttonName = config.buttonName,
			order = config.order or 100,
		})
	end

	return button
end

createProxyButton({
	key = "tsm_open_all_mail",
	label = "TSM Open Mail",
	buttonName = "SmartRezTSMOpenAllMailBtn",
	order = 90,
	labels = {
		BUTTON_LABELS.openAllMail,
		BUTTON_LABELS.openMail,
	},
})

createProxyButton({
	buttonName = "SmartRezTSMOpenAllSalesBtn",
	labels = {
		BUTTON_LABELS.allSold,
		BUTTON_LABELS.sold,
	},
})

createProxyButton({
	buttonName = "SmartRezTSMOpenAllBuysBtn",
	labels = {
		BUTTON_LABELS.allBought,
		BUTTON_LABELS.bought,
	},
})

createProxyButton({
	buttonName = "SmartRezTSMOpenAllCancelsBtn",
	labels = {
		BUTTON_LABELS.allCancelled,
		BUTTON_LABELS.cancelled,
	},
})

createProxyButton({
	buttonName = "SmartRezTSMOpenAllExpiresBtn",
	labels = {
		BUTTON_LABELS.allExpired,
		BUTTON_LABELS.expired,
	},
})

createProxyButton({
	buttonName = "SmartRezTSMOpenAllOtherBtn",
	labels = {
		BUTTON_LABELS.allOther,
		BUTTON_LABELS.other,
	},
})
