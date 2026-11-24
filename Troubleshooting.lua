-- Troubleshooting commands. Shipped in every build and listed in the chat help, not on the settings page
-- (as other addons list theirs). Nothing runs until a command does, apart from the
-- profession-open timer below.
local _, ns = ...

-- Command output is also kept in RecipeVacuumDB.devLog and shown in a copyable popup.
local openStarted, openMs
local timing = CreateFrame("Frame")
timing:RegisterEvent("TRADE_SKILL_SHOW")
timing:RegisterEvent("TRADE_SKILL_CLOSE")
timing:SetScript("OnEvent", function(_, event)
	if event == "TRADE_SKILL_SHOW" then
		openStarted, openMs = debugprofilestop(), nil
	else
		openStarted = nil
	end
end)
EventUtil.ContinueOnAddOnLoaded("Blizzard_Professions", function()
	hooksecurefunc(ProfessionsFrame.CraftingPage, "Init", function()
		if openStarted and C_TradeSkillUI.IsTradeSkillReady() then
			openMs, openStarted = debugprofilestop() - openStarted, nil
		end
	end)
end)

-- Keeps the last LOG_LINES lines across commands, so a toggle such as watch keeps what it recorded.
local LOG_LINES = 2000
local toolkit = LibStub("JigBoltgripToolkit-1.0")

local function ShowLog()
	toolkit:ShowText("Recipe Vacuum: select all, then copy", table.concat(ns.db.devLog or {}, "\n"))
end

-- Lines are timestamped, so a long watch reads as a timeline.
local function Append(line)
	ns.db.devLog = ns.db.devLog or {}
	table.insert(ns.db.devLog, line ~= "" and date("%H:%M:%S ") .. line or line)
	while #ns.db.devLog > LOG_LINES do
		table.remove(ns.db.devLog, 1)
	end
end

local function print(...)
	local line = strjoin(" ", tostringall(...))
	Append(line)
	_G.print(line)
	if toolkit:IsTextShown() then
		ShowLog()
	end
end

local function Dump()
	if not (ProfessionsFrame and ProfessionsFrame:IsShown()) then
		print("Recipe Vacuum: open a profession first.")
		return
	end

	local recipeID
	for _, id in ipairs(C_TradeSkillUI.GetAllRecipeIDs()) do
		local info = C_TradeSkillUI.GetRecipeInfo(id)
		if info and not info.learned then
			recipeID = id
			break
		end
	end
	if not recipeID then
		print("Recipe Vacuum: no unlearned recipes in this profession.")
		return
	end

	local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
	print(("Recipe Vacuum: %d %s"):format(recipeID, info.name or "?"))
	local keys = {}
	for key in pairs(info) do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		if type(info[key]) ~= "table" then
			print("  " .. key .. " = " .. tostring(info[key]))
		end
	end
	-- Parenthesized: on Forever the call returns no value, which tostring rejects.
	print("  sourceText = " .. tostring((C_TradeSkillUI.GetRecipeSourceText(recipeID))))

	-- Unlearned recipes per sourceType.
	local professionID = Professions.GetProfessionInfo().professionID
	local counts, total = {}, 0
	for _, id in ipairs(C_TradeSkillUI.GetAllRecipeIDs()) do
		local recipe = C_TradeSkillUI.GetRecipeInfo(id)
		if recipe and not recipe.learned and C_TradeSkillUI.IsRecipeInSkillLine(id, professionID) then
			local key = recipe.sourceType and ((_G["BATTLE_PET_SOURCE_" .. recipe.sourceType] or "?") .. " (" .. recipe.sourceType .. ")") or "none"
			counts[key] = (counts[key] or 0) + 1
			total = total + 1
		end
	end
	local parts = {}
	for key, count in pairs(counts) do
		table.insert(parts, key .. ": " .. count)
	end
	table.sort(parts)
	print(("  sourceType across %d unlearned: %s"):format(total, table.concat(parts, ", ")))

	local fromSources = {}
	for index = 1, C_PetJournal.GetNumPetSources() do
		if C_TradeSkillUI.IsAnyRecipeFromSource(index) then
			table.insert(fromSources, (_G["BATTLE_PET_SOURCE_" .. index] or "?") .. " (" .. index .. ")")
		end
	end
	print("  sources with recipes: " .. (#fromSources > 0 and table.concat(fromSources, ", ") or "none"))
end




-- Requirement lines on the open profession's unlearned recipes, grouped by type, to see how Forever
-- marks recipes a character can never learn.
local function Requirements()
	if not (ProfessionsFrame and ProfessionsFrame:IsShown()) then
		print("Recipe Vacuum: open a profession first.")
		return
	end
	local professionID = Professions.GetProfessionInfo().professionID
	local seen, count = {}, 0
	for _, id in ipairs(C_TradeSkillUI.GetAllRecipeIDs()) do
		local info = C_TradeSkillUI.GetRecipeInfo(id)
		if info and not info.learned and C_TradeSkillUI.IsRecipeInSkillLine(id, professionID) then
			local tooltip = C_TooltipInfo.GetSpellByID(id)
			for _, line in ipairs(tooltip and tooltip.lines or {}) do
				if line.type == Enum.TooltipDataLineType.UsageRequirement and line.leftText then
					local color = line.leftColor and line.leftColor:GenerateHexColor() or "?"
					local key = tostring(line.requirementType) .. "|" .. line.leftText:gsub("%d+", "#") .. "|" .. color
					if not seen[key] then
						seen[key] = true
						count = count + 1
						print(("  requirementType %s | color %s | %s | e.g. %d %s"):format(
							tostring(line.requirementType), color, line.leftText, id, info.name))
					end
				end
			end
		end
	end
	print(("Recipe Vacuum: %d distinct requirement lines."):format(count))
end

-- Size of the account's finds as one export, to decide whether sharing needs paging (another addon sends
-- one compressed message).
local function ExportSize()
	local rows = ns.FindsSince(0, math.huge)
	local json = C_EncodingUtil.SerializeJSON(rows)
	local cbor = C_EncodingUtil.SerializeCBOR(rows)
	local deflated = C_EncodingUtil.CompressString(cbor, Enum.CompressionMethod.Deflate)
	local encoded = C_EncodingUtil.EncodeBase64(deflated)
	print(("Recipe Vacuum: %d shareable finds | JSON %d bytes | CBOR %d | Deflate %d | Base64 %d | ~%d addon messages of 255 bytes"):format(
		#rows, #json, #cbor, #deflated, #encoded, math.ceil(#encoded / 250)))
end

-- One-shot checks: saved data after the upgrade, Blizzard atlases we use, and which APIs Forever
-- exposes.
local function Checks()
	local db = ns.db
	print(("schema %s | revision %s | pending items %d"):format(
		tostring(db.schema), tostring(db.exchange and db.exchange.revision), CountTable(db.pendingItems)))
	for _, atlas in ipairs({ "bags-junkcoin", "common-search-magnifyingglass" }) do
		print(("atlas %s: %s"):format(atlas, C_Texture.GetAtlasInfo(atlas) and "present" or "MISSING"))
	end
	for _, name in ipairs({ "GetLootSourceInfo", "IsFishingLoot", "GetQuestItemInfo", "issecretvalue" }) do
		print(("%s: %s"):format(name, type(_G[name])))
	end
	print("C_Item.GetItemSpell:", type(C_Item.GetItemSpell), "| C_Map.OpenWorldMap:", type(C_Map.OpenWorldMap),
		"| C_SuperTrack.SetSuperTrackedUserWaypoint:", type(C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint))
	local mapID = C_Map.GetBestMapForUnit("player")
	print("map", tostring(mapID), "| CanSetUserWaypointOnMap:", tostring(mapID and C_Map.CanSetUserWaypointOnMap(mapID)),
		"| colorblindMode:", GetCVar("colorblindMode"))
	-- Locale-independent recipe item link: does the item expose its recipe?
	local itemID = next(db.itemRecipe) or next(db.pendingItems)
	if itemID then
		print(("recipe item %d (links to recipe %s):"):format(itemID, tostring(db.itemRecipe[itemID])))
		print("  C_Item.GetItemSpell:", C_Item.GetItemSpell and strjoin(" ", tostringall(C_Item.GetItemSpell(itemID))) or "n/a")
		local tooltip = C_TooltipInfo.GetItemByID(itemID)
		-- Every field of every line: a nested block may name the crafted item, linking recipe items
		-- without English names.
		for index, line in ipairs(tooltip and tooltip.lines or {}) do
			local fields = {}
			for key, value in pairs(line) do
				if type(value) ~= "table" and key ~= "leftText" then
					table.insert(fields, key .. "=" .. tostring(value))
				end
			end
			table.sort(fields)
			print(("  %d %s | %s"):format(index, tostring(line.leftText), table.concat(fields, " ")))
		end
	end
end

-- Logs loot windows, quest dialogs and spell targets, to learn what Forever reports for mob, object,
-- container and fishing loot and for quest givers and rewards.
local watcher

-- tostring that never touches a secret value (Forever can hand addons secret GUIDs and names).
local function Describe(value)
	if issecretvalue and issecretvalue(value) then
		return "<secret>"
	end
	return tostring(value)
end

local function DescribeAll(...)
	local parts = {}
	for index = 1, select("#", ...) do
		parts[index] = Describe((select(index, ...)))
	end
	return table.concat(parts, " ")
end

local function Where()
	local mapID = C_Map.GetBestMapForUnit("player")
	local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	return ("map %s pos %s | instance %s"):format(tostring(mapID),
		position and ("%.3f,%.3f"):format(position:GetXY()) or "nil", tostring((IsInInstance())))
end

-- One entry per loot window (LOOT_READY can fire twice, then LOOT_OPENED), with the last spell target,
-- which names gathered and chest objects.
local castTarget, lootLogged
local handlers = {
	UNIT_SPELLCAST_SENT = function(unit, target)
		if unit == "player" then castTarget = target end
	end,
	LOOT_CLOSED = function()
		lootLogged, castTarget = nil, nil
	end,
	LOOT_READY = function(...)
		if lootLogged then return end
		lootLogged = true
		print(("LOOT %s | cast target %s | fishing %s | unit target %s | %s"):format(DescribeAll(...),
			Describe(castTarget), Describe(IsFishingLoot()), Describe(UnitGUID("target")), Where()))
		for slot = 1, GetNumLootItems() do
			local source = GetLootSourceInfo(slot)
			-- Containers opened from bags report an Item GUID with no item ID in it.
			local container = type(source) == "string" and not (issecretvalue and issecretvalue(source))
				and source:find("^Item%-") and C_Item.GetItemIDByGUID and C_Item.GetItemIDByGUID(source)
			print(("  slot %d type %s %s | sources %s%s"):format(slot, Describe(GetLootSlotType(slot)),
				Describe(GetLootSlotLink(slot)), DescribeAll(GetLootSourceInfo(slot)),
				container and (" | container item " .. Describe(container)) or ""))
		end
	end,
	QUEST_DETAIL = function() end, -- filled below
}
handlers.LOOT_OPENED = handlers.LOOT_READY
local function Quest(event)
	print(("%s quest %s | questnpc %s %s | %s"):format(event, Describe(GetQuestID()),
		Describe(UnitName("questnpc")), Describe(UnitGUID("questnpc")), Where()))
	for _, kind in ipairs({ "reward", "choice" }) do
		local count = kind == "reward" and GetNumQuestRewards() or GetNumQuestChoices()
		for index = 1, count do
			print(("  %s %d: %s"):format(kind, index, DescribeAll(GetQuestItemInfo(kind, index))))
		end
	end
end
handlers.QUEST_DETAIL = function() Quest("QUEST_DETAIL") end
handlers.QUEST_COMPLETE = function() Quest("QUEST_COMPLETE") end

-- watch on | off (no word toggles). Saved, so it resumes after /reload; the log reaches disk on /reload
-- or logout.
local function StartWatch()
	watcher = CreateFrame("Frame")
	for event in pairs(handlers) do
		watcher:RegisterEvent(event)
	end
	watcher:SetScript("OnEvent", function(_, event, ...)
		-- Log errors: script errors may be hidden in the client.
		local ok, problem = pcall(handlers[event], ...)
		if not ok then
			print(("watch error in %s: %s"):format(event, Describe(problem)))
		end
	end)
end

local function Watch(word)
	word = (word or ""):lower()
	local on = word == "on" or (word == "" and not watcher)
	if on and not watcher then
		StartWatch()
	elseif not on and watcher then
		watcher:UnregisterAllEvents()
		watcher = nil
	end
	ns.db.watch = on or nil
	print(on and "Recipe Vacuum: watching loot and quests (/recipevacuum watch off to stop). Saved to disk on /reload or logout."
		or "Recipe Vacuum: watch off.")
end

-- Called by Core once saved data is loaded (an ADDON_LOADED callback here could run before it).
function ns.ResumeWatch()
	if ns.db.watch and not watcher then
		StartWatch()
		Append("watch resumed after reload")
	end
end


-- Each command logs a header (time, client build, character, open profession), runs, then shows the log
-- in the copy window; "log" only shows it.
local function Logged(run)
	return function(arguments)
		local version, build = GetBuildInfo()
		local _, faction = UnitFactionGroup("player")
		local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
		local profession = page and page:IsVisible() and Professions.GetProfessionInfo()
		for _, line in ipairs({
			"",
			date("%Y-%m-%d %H:%M:%S") .. " /recipevacuum " .. (arguments.action or ""),
			("client %s (%s) | addon %s | %s, %s, level %d"):format(version, build,
				tostring(C_AddOns.GetAddOnMetadata("RecipeVacuum", "Version")),
				UnitName("player"), tostring(faction), UnitLevel("player")),
			profession and ("profession %s (id %d) skill %d/%d"):format(profession.professionName or "?",
				profession.professionID or 0, profession.skillLevel or 0, profession.maxSkillLevel or 0)
				or "no open crafting page",
		}) do
			Append(line)
		end
		run(arguments.text)
		ShowLog()
	end
end



local troubleshooting = {
	{ "checks", "Check saved data, icons and the game functions Recipe Vacuum uses", Checks },
	{ "watch", "Log where loot and quest rewards come from: watch on, watch off", Watch, quiet = true },
	{ "dump", "Show what the game reports for one unlearned recipe of the open profession", Dump },
	{ "requirements", "List the requirement lines on the open profession's unlearned recipes", Requirements },
	{ "perf", "Show how long the profession window took to open", function()
		print("Recipe Vacuum: trade skill show to first ready crafting Init:",
			openMs and ("%.1f ms"):format(openMs) or "no sample")
		print(("Last list with unlearned recipes: %s, %d such builds since reload."):format(
			ns.lastUnlearnedMs and ("%.1f ms"):format(ns.lastUnlearnedMs) or "no sample", ns.unlearnedBuilds or 0))
	end },
	{ "exportsize", "Show how large your finds are when shared", ExportSize },
}

ns.commands = ns.commands or {}
for _, command in ipairs(troubleshooting) do
	local action, description, run = command[1], command[2], command[3]
	-- Quiet commands print to chat only, so the profession window stays in view.
	local logged = not command.quiet and Logged(run)
	table.insert(ns.commands, { action = action, description = description, troubleshooting = true,
		run = function(text)
			if logged then logged({ action = action, text = text }) else run(text) end
		end })
end
table.insert(ns.commands, { action = "log", description = "Show the troubleshooting log; log clear empties it", troubleshooting = true,
	run = function(word)
		if (word or ""):lower() == "clear" then
			ns.db.devLog = {}
			_G.print("Recipe Vacuum: troubleshooting log cleared.")
		else
			ShowLog()
		end
	end })
