local ITEM_ID = 245807

local function printLine(...)
	print("SmartRez Sort Probe:", ...)
end

local function dumpStacks(itemID)
	itemID = itemID or ITEM_ID
	printLine("stack dump start", itemID)

	for bag = 1, 40 do
		local numSlots = C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag) or 0
		for slot = 1, numSlots do
			local info = C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot) or nil
			if info and info.itemID == itemID then
				printLine("bag", bag, "slot", slot, "count", info.stackCount or 0)
			end
		end
	end

	printLine("stack dump end", itemID)
end

local function probeSortAPIs()
	printLine("SortBags", C_Container and C_Container.SortBags ~= nil)
	printLine("SortBankBags", C_Container and C_Container.SortBankBags ~= nil)
	printLine("SortAccountBankBags", C_Container and C_Container.SortAccountBankBags ~= nil)
	printLine("CanViewBank", C_Bank and C_Bank.CanViewBank and C_Bank.CanViewBank() or false)
end

local function runSortBags()
	if C_Container and C_Container.SortBags then
		printLine("running", "SortBags")
		C_Container.SortBags()
		return
	end

	printLine("missing", "SortBags")
end

local function runSortBankBags()
	if C_Container and C_Container.SortBankBags then
		printLine("running", "SortBankBags")
		C_Container.SortBankBags()
		return
	end

	printLine("missing", "SortBankBags")
end

local function runSortAccountBankBags()
	if C_Container and C_Container.SortAccountBankBags then
		printLine("running", "SortAccountBankBags")
		C_Container.SortAccountBankBags()
		return
	end

	printLine("missing", "SortAccountBankBags")
end

local function dumpEverything(itemID)
	probeSortAPIs()
	dumpStacks(itemID)
end

_G.SmartRezSortProbe = {
	ITEM_ID = ITEM_ID,
	probe = probeSortAPIs,
	dumpStacks = dumpStacks,
	dumpEverything = dumpEverything,
	sortBags = runSortBags,
	sortBankBags = runSortBankBags,
	sortAccountBankBags = runSortAccountBankBags,
}

printLine("loaded", "use SmartRezSortProbe.probe()", "SmartRezSortProbe.dumpStacks()", "SmartRezSortProbe.sortBags()")
