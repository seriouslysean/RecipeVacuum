-- Development commands and their log: the whole file exists only in a checkout build and is stripped from releases (docs/development.md, "Working build").
local _, ns = ...

--@debug@

local UseScan -- defined below
local mockedRanks = {} -- rank links the mockbooks command added, removed at logout
-- Lua errors shown and blocked actions reported, and timing, from the toolkit's working-build helpers.
local toolkit = LibStub("JigBoltgripToolkit-1.0")
toolkit:EnableWorkingBuild()

-- Timing is kept by the library per module; ns.device stands in for the module until settings load.
function ns.PerfMs(name, ms)
	toolkit:TimeMs(ns.device, name, ms)
end

function ns.Perf(name, started)
	toolkit:Time(ns.device, name, started)
end

local function PerfLines()
	return toolkit:TimingLines(ns.device)
end

-- Times the profession window's opening for the perf command.
local openStarted, openMs
local openTimer = CreateFrame("Frame")
openTimer:RegisterEvent("TRADE_SKILL_SHOW")
openTimer:RegisterEvent("TRADE_SKILL_CLOSE")
openTimer:SetScript("OnEvent", function(_, event)
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
			ns.PerfMs("profession window open", openMs)
		end
	end)
end)

-- The log, watch and log commands are the toolkit's working-build log (its docs/standards.md, "Working
-- build helpers"); the lines live in this addon's saved data (devLog, devLogRun, watch).
local function Append(line, dated)
	toolkit:Log(ns.device, line, dated)
end

-- Watch lines go to the log only, so chat stays clear.
local logOnly

-- A line from Voice.lua goes to chat through ns.Log and to the saved log with the same tag.
local LOG_TAG = ns.title .. ": "
local voice = ns.voice

local function Chat(line)
	ns.Log(line)
end

local function print(...)
	local line = strjoin(" ", tostringall(...))
	Append(line)
	if not logOnly then _G.print(line) end
end

-- Says one of the Vacuum's lines: logged, and shown in chat unless a watch callback is running.
-- A development line: logged, and shown as a plain line in chat.
local function Voiced(line)
	Append(LOG_TAG .. line)
	Chat(line)
end

-- A failure: the voiced line, then the error itself on a plain line so it stays exact.
local function Malfunction(where, problem)
	Voiced(voice.malfunction:format(where))
	Append(problem)
	Chat(problem)
end

local function Say(line, ...)
	line = select("#", ...) > 0 and line:format(...) or line
	Append(LOG_TAG .. line)
	if not logOnly then Chat(line) end
end

-- The one chat line a watch event may print: it found recipes (voice rules: docs/voice.md; Homing Robot OOX-17/TN is the model).
local function WatchFound(count)
	if count > 0 then
		Voiced(voice.detected:format(count, count == 1 and "recipe" or "recipes"))
	end
end

local IsRecipeItem = ns.IsRecipeItem

-- Wraps a watch callback so its lines skip chat; the flag is cleared even when it errors.
local function LogOnly(callback)
	return function(...)
		logOnly = true
		local ok, problem = pcall(callback, ...)
		logOnly = nil
		if not ok then Malfunction("the watch", tostring(problem)) end
	end
end


-- The watch logs loot windows, quest dialogs and spell targets, to learn what Forever reports for loot and quest givers and rewards.

-- tostring that never touches a secret value (Forever can hand addons secret GUIDs and names).
local function Describe(value)
	if issecretvalue(value) then
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

-- One entry per loot window (LOOT_READY can fire twice, then LOOT_OPENED), with the last spell target, which names gathered and chest objects.
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
		local recipes = 0
		for slot = 1, GetNumLootItems() do
			local link = GetLootSlotLink(slot)
			if link and not issecretvalue(link) and IsRecipeItem(link) then
				recipes = recipes + 1
			end
			local source = GetLootSourceInfo(slot)
			-- Containers opened from bags report an Item GUID with no item ID in it.
			local container = type(source) == "string" and not issecretvalue(source)
				and source:find("^Item%-") and C_Item.GetItemIDByGUID and C_Item.GetItemIDByGUID(source)
			print(("  slot %d type %s %s | sources %s%s"):format(slot, Describe(GetLootSlotType(slot)),
				Describe(GetLootSlotLink(slot)), DescribeAll(GetLootSourceInfo(slot)),
				container and (" | container item " .. Describe(container)) or ""))
		end
		WatchFound(recipes)
	end,
	QUEST_DETAIL = function() end, -- filled below
}
handlers.LOOT_OPENED = handlers.LOOT_READY
local function Quest(event)
	print(("%s quest %s | questnpc %s %s | %s"):format(event, Describe(GetQuestID()),
		Describe(UnitName("questnpc")), Describe(UnitGUID("questnpc")), Where()))
	local recipes = 0
	for _, kind in ipairs({ "reward", "choice" }) do
		local count = kind == "reward" and GetNumQuestRewards() or GetNumQuestChoices()
		for index = 1, count do
			print(("  %s %d: %s"):format(kind, index, DescribeAll(GetQuestItemInfo(kind, index))))
			if IsRecipeItem((select(6, GetQuestItemInfo(kind, index)))) then recipes = recipes + 1 end
		end
	end
	WatchFound(recipes)
end
handlers.QUEST_DETAIL = function() Quest("QUEST_DETAIL") end
-- A group roll names the item but not what dropped it; the handle is logged in case it matches something later.
handlers.START_LOOT_ROLL = function(rollID, rollTime, lootHandle)
	local link = GetLootRollItemLink(rollID)
	print(("ROLL %s | item %s | handle %s | time %s | unit target %s | %s"):format(Describe(rollID), Describe(link),
		Describe(lootHandle), Describe(rollTime), Describe(UnitGUID("target")), Where()))
	local itemID = link and not issecretvalue(link) and C_Item.GetItemInfoInstant(link)
	WatchFound(IsRecipeItem(itemID) and 1 or 0)
end
-- Vendors and trainers are recorded on window open, so the watch logs the visit: who and how many items or services.
handlers.MERCHANT_SHOW = function()
	print(("VENDOR %s %s | faction %s | %d items | %s"):format(Describe(UnitName("npc")), Describe(UnitGUID("npc")),
		Describe((UnitFactionGroup("npc"))), GetMerchantNumItems(), Where()))
	-- Each item with its class, since only the Recipe class (9) is recorded; log only.
	local recipes = 0
	for index = 1, GetMerchantNumItems() do
		local itemID = GetMerchantItemID(index)
		if IsRecipeItem(itemID) then recipes = recipes + 1 end
		Append(("  item %d %s %s | class %s"):format(index, Describe(itemID), Describe(GetMerchantItemLink(index)),
			Describe(itemID and select(6, C_Item.GetItemInfoInstant(itemID)))))
	end
	WatchFound(recipes)
end
-- A plain conversation, to tell an NPC that only talks from one that sells, trains or gives quests.
handlers.GOSSIP_SHOW = function()
	local options = {}
	for _, option in ipairs(C_GossipInfo.GetOptions()) do
		table.insert(options, Describe(option.name))
	end
	print(("GOSSIP %s %s | %d available quests | options: %s | %s"):format(Describe(UnitName("npc")),
		Describe(UnitGUID("npc")), C_GossipInfo.GetNumAvailableQuests(),
		#options > 0 and table.concat(options, "; ") or "none", Where()))
end
-- Services can arrive after the window opens and its filter hides some, so list them later with every filter on, then restore the player's filter.
local TRAINER_LIST_DELAY = 0.5
handlers.TRAINER_SHOW = function()
	print(("TRAINER %s %s | faction %s | profession trainer %s | %d services shown | %s"):format(Describe(UnitName("npc")),
		Describe(UnitGUID("npc")), Describe((UnitFactionGroup("npc"))), Describe(IsTradeskillTrainer()), GetNumTrainerServices(), Where()))
	C_Timer.After(TRAINER_LIST_DELAY, LogOnly(function() ns.WithAllTrainerServices(function(shown)
		print(("  with every filter on: %d services (filter was available %s, unavailable %s, used %s)"):format(
			GetNumTrainerServices(), Describe(shown.available), Describe(shown.unavailable), Describe(shown.used)))
		-- Recipes have a category and ranks none, which is how the recorder tells them apart; skipped ones are named.
		local recipes, skipped = 0, {}
		for index = 1, GetNumTrainerServices() do
			local tooltip = C_TooltipInfo.GetTrainerService(index)
			local name, _, _, _, _, category = GetTrainerServiceInfo(index)
			if tooltip and tooltip.id and C_TradeSkillUI.GetTradeSkillLineForRecipe(tooltip.id) then
				if category and category ~= "" then
					recipes = recipes + 1
				else
					table.insert(skipped, Describe(name))
				end
			end
			Append(("  service %d %s | spell %s | profession line %s"):format(index, DescribeAll(GetTrainerServiceInfo(index)),
				Describe(tooltip and tooltip.id),
				tooltip and tooltip.id and DescribeAll(C_TradeSkillUI.GetTradeSkillLineForRecipe(tooltip.id)) or "nil")
				-- Does the game know the spell as a recipe? Ranks ("Journeyman Fishing") do not count.
				.. " | recipe info " .. Describe(tooltip and tooltip.id and C_TradeSkillUI.GetRecipeInfo(tooltip.id) ~= nil)
				.. " | step " .. Describe(GetTrainerServiceStepIndex()))
		end
		if #skipped > 0 then
			print("  skipped as ranks (no category): " .. table.concat(skipped, "; "))
		end
		WatchFound(recipes)
	end) end))
end
handlers.QUEST_COMPLETE = function() Quest("QUEST_COMPLETE") end

-- The watch runs these handlers through the toolkit; their lines go to the log only, and an error is
-- reported by the toolkit as a malfunction.
local function WatchHandlers()
	local wrapped = {}
	for event, handler in pairs(handlers) do
		wrapped[event] = function(...)
			logOnly = true
			local ok, problem = pcall(handler, ...)
			logOnly = nil
			if not ok then error(Describe(problem), 0) end
		end
	end
	return wrapped
end

-- Called by Core once saved data is loaded (an ADDON_LOADED callback here could run before it).
-- A scan from this game build is used from the session start, ahead of the seed.
local function UseKeptScan()
	ns.scannedMade = ns.db.devMade -- from the `made` command
	local scan = ns.db.devScan
	if scan and scan.teaches and scan.build == select(2, GetBuildInfo()) then
		UseScan(scan)
	end
end

function ns.ResumeWatch()
	UseKeptScan()
	toolkit:StartLog(ns.device, ns.db, WatchHandlers())
end


-- Seeding scan: every recipe item and the recipe it teaches (docs/development.md, "Seeding").
local SCAN_FRAME_MS = 4 -- work per frame
local SCAN_STEP = 500 -- IDs between clock checks
local SCAN_GAP = 50000 -- stop after this many IDs in a row with no item
local SCAN_CAP = 2000000
local LOAD_BATCH = 50 -- items requested per tick
local LOAD_INTERVAL = 0.1
local LOAD_TIMEOUT = 5 -- seconds to wait for the last answers
local NO_ANSWER = 0 -- saved for an item the game never answered
local ITEM_LIMIT = 10000 -- more than this means the walk went wrong; load nothing
local MISSING_LINES = 200 -- unlearned recipes without an item listed in the log

-- Makes a scan this session's layer over the seed (ns.scanned): only items that teach a recipe; nothing is written to the seed or saved links.
function UseScan(scan)
	local scanned = {}
	for itemID, recipeID in pairs(scan.teaches) do
		if type(recipeID) == "number" and recipeID > 0 then
			scanned[itemID] = recipeID
		end
	end
	ns.scanned = scanned
	ns.ResetRecipeItems()
end

local scanning
-- When the running scan began, and its phase timings (kept in devScan.timing).
local scanStarted

local function Timing(scan)
	scan.timing = scan.timing or {}
	return scan.timing
end

-- The open profession's unlearned recipes against the table: how many have a recipe item.
local function Report(scan)
	scanning = nil
	local reportStart = debugprofilestop()
	local taught, known, none = {}, 0, 0
	for itemID, recipeID in pairs(scan.teaches) do
		if recipeID and recipeID ~= NO_ANSWER then
			taught[recipeID] = itemID
			known = known + 1
		elseif recipeID == false then
			none = none + 1
		end
	end
	Append(("SCAN %d recipe items: %d name the recipe they teach, %d teach nothing, %d unanswered"):format(
		#scan.items, known, none, #scan.items - known - none))
	if not (ProfessionsFrame and ProfessionsFrame:IsShown()) then
		Say(voice.scanNoWindow)
		return
	end
	local profession = Professions.GetProfessionInfo()
	local unlearned, withItem, without = 0, 0, {}
	for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs()) do
		local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
		if info and not info.learned and C_TradeSkillUI.IsRecipeInSkillLine(recipeID, profession.professionID) then
			unlearned = unlearned + 1
			if taught[recipeID] then
				withItem = withItem + 1
			else
				table.insert(without, ("%d %s"):format(recipeID, info.name or "?"))
			end
		end
	end
	Append(("  %s: %d unlearned | %d have a recipe item, %d do not (a trainer teaches those):"):format(
		profession.professionName or "?", unlearned, withItem, #without))
	table.sort(without)
	for index = 1, math.min(#without, MISSING_LINES) do
		Append("    " .. without[index])
	end
	-- The scan result is used at once as this session's layer, so the list redraws with the items it found.
	UseScan(scan)
	ns.SourcesChanged()
	local timing = Timing(scan)
	timing.reportMs, timing.totalSeconds = debugprofilestop() - reportStart, GetTime() - scanStarted
	timing.profession = profession.professionName
	Say(voice.scanDone, withItem, unlearned, profession.professionName or UNKNOWN, timing.totalSeconds)
end

-- Loads each unanswered recipe item and reads its recipe; an item is asked once per build.
local function ReadTaught(scan)
	local pending = {}
	for _, itemID in ipairs(scan.items) do
		if scan.teaches[itemID] == nil then
			pending[#pending + 1] = itemID
		end
	end
	local timing = Timing(scan)
	timing.asked, timing.answered, timing.loadSeconds = #pending, 0, 0
	if #pending == 0 then
		Report(scan)
		return
	end
	local requested, answered, finished, started = 0, 0, false, GetTime()
	-- Loads still waiting at the end are cancelled, so no callback stays registered, and remembered as unanswered.
	local waiting = {}
	local function Finish()
		if finished then return end
		finished = true
		for itemID, cancel in pairs(waiting) do
			cancel()
			-- An item already loaded answers at once, before its cancel handle is stored.
			if scan.teaches[itemID] == nil then scan.teaches[itemID] = NO_ANSWER end
		end
		timing.answered, timing.loadSeconds = answered, GetTime() - started
		Append(("SCAN asked for %d items, %d answered, in %.1f s"):format(#pending, answered, timing.loadSeconds))
		local ok, problem = pcall(Report, scan)
		if not ok then
			scanning = nil
			Say(voice.scanFailed, Describe(problem))
		end
	end
	local ticker
	ticker = C_Timer.NewTicker(LOAD_INTERVAL, function()
		for _ = 1, LOAD_BATCH do
			requested = requested + 1
			local itemID = pending[requested]
			if not itemID then
				ticker:Cancel()
				C_Timer.After(LOAD_TIMEOUT, Finish)
				return
			end
			local item = Item:CreateFromItemID(itemID)
			waiting[itemID] = item:ContinueWithCancelOnItemLoad(function()
				waiting[itemID] = nil
				-- An answer that still carries no data counts as none.
				local recipeID = ns.GetTaughtRecipe(itemID)
				scan.teaches[itemID] = recipeID == nil and NO_ANSWER or recipeID
				answered = answered + 1
				if answered == #pending then Finish() end
			end)
		end
	end)
end

local function WalkItems()
	local found = {}
	local id, lastItem, existing, cpu, started = 0, 0, 0, 0, GetTime()
	-- One slice of the walk; each pass ends on the clock or on done, and done is certain by SCAN_CAP.
	local function Walk()
		local frameStart = debugprofilestop()
		local done = false
		while not done and debugprofilestop() - frameStart < SCAN_FRAME_MS do
			for _ = 1, SCAN_STEP do
				id = id + 1
				local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(id)
				if classID then
					existing, lastItem = existing + 1, id
					if classID == Enum.ItemClass.Recipe then
						found[#found + 1] = id
					end
				end
			end
			done = id - lastItem > SCAN_GAP or id >= SCAN_CAP
		end
		cpu = cpu + (debugprofilestop() - frameStart)
		return done
	end
	local ticker
	ticker = C_Timer.NewTicker(0, function()
		-- An error must end the walk, not repeat every frame.
		local ok, done = pcall(Walk)
		if ok and not done then return end
		ticker:Cancel()
		if not ok then
			scanning = nil
			Say(voice.scanFailed, Describe(done))
			return
		end
		Append(("SCAN walked %d IDs | %d items exist | highest item %d | %d recipe items | %.0f ms of work over %.1f s"):format(
			id, existing, lastItem, #found, cpu, GetTime() - started))
		-- Loading costs a server request per item, so start only when the count is believable.
		if #found == 0 or #found > ITEM_LIMIT then
			scanning = nil
			Say(voice.scanBadCount)
			return
		end
		ns.db.devScan = { build = select(2, GetBuildInfo()), items = found, teaches = {},
			timing = { walkMs = cpu, walkSeconds = GetTime() - started, walkedIDs = id } }
		ReadTaught(ns.db.devScan)
	end)
end

-- Runs only with a profession open; the item list and what each item teaches are kept per game build, so a second profession asks the server nothing.
local function Scan()
	if scanning then
		Say(voice.scanBusy)
		return
	end
	if not (ProfessionsFrame and ProfessionsFrame:IsShown()) then
		Say(voice.scanNoWindow)
		return
	end
	Say(voice.scanStart, Professions.GetProfessionInfo().professionName or UNKNOWN)
	scanning, scanStarted = true, GetTime()
	local scan = ns.db.devScan
	if scan and scan.build == select(2, GetBuildInfo()) and scan.items and scan.teaches then
		-- The item walk is reused, so its cost here is nothing.
		Timing(scan).walkMs, Timing(scan).walkSeconds, Timing(scan).walkedIDs = 0, 0, 0
		ReadTaught(scan)
	else
		WalkItems()
	end
end


-- Shared functions timed from here; the record is written out at session end.
for name, label in pairs({ AddSourceLines = "source tooltip", MergeFinds = "merge shared finds", LinkPending = "link recipe items" }) do
	local inner = ns[name]
	ns[name] = function(...)
		local started = debugprofilestop()
		local first, second, third = inner(...)
		ns.Perf(label, started)
		return first, second, third
	end
end

local perfWriter = CreateFrame("Frame")
perfWriter:RegisterEvent("PLAYER_LOGOUT")
perfWriter:SetScript("OnEvent", function()
	-- Retired probes' data, so it does not stay in the saved file.
	for _, mocked in ipairs(mockedRanks) do
		mocked[1][mocked[2]][mocked[3]] = nil
	end
	-- Retired probes' data.
	ns.db.devHover, ns.db.devHoverLog, ns.db.devSpecLines, ns.db.devChatColors = nil, nil, nil, nil
end)

-- Each command logs the toolkit's header plus the open profession, runs, then shows its lines; "log" only shows them.
local function ProfessionLine()
	local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
	local profession = page and page:IsVisible() and Professions.GetProfessionInfo()
	return { profession and ("profession %s (id %d) skill %d/%d"):format(profession.professionName or "?",
		profession.professionID or 0, profession.skillLevel or 0, profession.maxSkillLevel or 0)
		or "no open crafting page" }
end


local troubleshooting = {}

-- Development commands, each removed once its question is answered; perf backs the performance claims (release regression checks).
-- Item probe: saves an item's tooltip lines with every plain field, to learn what the game says about
-- items the addon cannot place yet (profession rank books first). Remove once answered.
table.insert(troubleshooting, { "item", "Save an item's tooltip data to the log", function(text)
	local itemID = tonumber(text)
	if not itemID then
		return ns.Log("Give an item ID: /recipevacuum item 16083")
	end
	if not C_Item.IsItemDataCachedByID(itemID) then
		C_Item.RequestLoadItemDataByID(itemID)
		return ns.Log("Item data requested. Run the command again in a moment.")
	end
	local tooltip = C_TooltipInfo.GetItemByID(itemID)
	ns.db.devItems = ns.db.devItems or {}
	local lines = {}
	for index, line in ipairs(tooltip and tooltip.lines or {}) do
		local fields = {}
		for key, value in pairs(line) do
			if type(value) ~= "table" and type(value) ~= "function" then
				fields[#fields + 1] = key .. "=" .. tostring(value)
			end
		end
		table.sort(fields)
		lines[index] = table.concat(fields, " | ")
	end
	local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
	local spellName, spellID = C_Item.GetItemSpell(itemID)
	lines[#lines + 1] = ("class %s subclass %s | item spell %s %s"):format(tostring(classID), tostring(subclassID),
		tostring(spellID), tostring(spellName))
	ns.db.devItems[itemID] = lines
	ns.Log(("Saved %d tooltip lines for item %d. Reload to write them."):format(#lines - 1, itemID))
end, quiet = true })
-- Rank book test data, for this session only (not saved): the Expert book vendors from Wowhead's WoW Forever
-- pages (npc and item pages read 2026-11-25), so the rank mark can be checked without visiting them.
local MOCK_BOOK_VENDORS = {
	-- item, npc, name, faction, uiMapID, x, y
	{ 16072, 3955, "Shandrina", "Alliance", 1440, 0.494, 0.670 },
	{ 16072, 12033, "Wulan", "Horde", 1443, 0.262, 0.698 },
	{ 16084, 2805, "Deneb Walker", "Alliance", 1417, 0.270, 0.588 },
	{ 16084, 13476, "Balai Lok'Wein", "Horde", 1445, 0.364, 0.304 },
}
-- The rank each book raises, as a witnessed use would record it: skill line, cap it raises from.
local MOCK_BOOK_RANKS = { [16072] = { 185, 150 }, [16084] = { 129, 150 } } -- Cooking, First Aid
-- Artisan Fishing: quest 6607 "Nat Pagle, Angler Extreme" from Nat Pagle (npc 12919, both factions), rewards
-- spell 18248 (Wowhead WoW Forever quest and npc pages, read 2026-11-25). Fishing skill line 356, from 225.
local MOCK_QUEST_RANK = { quest = 6607, npc = 12919, name = "Nat Pagle", map = 1445, x = 0.584, y = 0.600,
	skillLine = 356, fromCap = 225 }
table.insert(troubleshooting, { "mockranks", "Add the Expert books and Nat Pagle's quest for this session, to test the rank mark", function()
	local now = GetServerTime()
	for _, row in ipairs(MOCK_BOOK_VENDORS) do
		local itemID, npcID, name, faction, mapID, x, y = unpack(row)
		ns.included.npcs[npcID] = { name = name, faction = faction, positions = { [mapID] = { x = x, y = y, seen = now } } }
		ns.included.items[itemID] = ns.included.items[itemID] or {}
		table.insert(ns.included.items[itemID], { kind = "vendor", npc = npcID, faction = faction, seen = now })
	end
	-- Rank links go in the saved table for the session and are taken out at logout (below).
	for itemID, rank in pairs(MOCK_BOOK_RANKS) do
		local skillLine, fromCap = unpack(rank)
		ns.db.ranks[skillLine] = ns.db.ranks[skillLine] or {}
		local sources = ns.db.ranks[skillLine][fromCap] or { npcs = {}, items = {}, quests = {} }
		ns.db.ranks[skillLine][fromCap] = sources
		if not sources.items[itemID] then
			sources.items[itemID] = now
			mockedRanks[#mockedRanks + 1] = { sources, "items", itemID }
		end
	end
	local quest = MOCK_QUEST_RANK
	ns.included.npcs[quest.npc] = { name = quest.name, positions = { [quest.map] = { x = quest.x, y = quest.y, seen = now } } }
	ns.db.ranks[quest.skillLine] = ns.db.ranks[quest.skillLine] or {}
	local questSources = ns.db.ranks[quest.skillLine][quest.fromCap] or { npcs = {}, items = {}, quests = {} }
	ns.db.ranks[quest.skillLine][quest.fromCap] = questSources
	if not questSources.quests[quest.quest] then
		questSources.quests[quest.quest] = quest.npc
		mockedRanks[#mockedRanks + 1] = { questSources, "quests", quest.quest }
	end
	ns.SourcesChanged()
	ns.Log("Expert books and Nat Pagle's quest added for this session. Reopen the profession window.")
end, quiet = true })

-- Facts cache test: drops the cache, so the next profession window builds its list cold without it.
-- Compare that build's "list build, cold" with one after a plain reload (cache kept).
table.insert(troubleshooting, { "nofacts", "Drop the recipe facts cache for a timing test", function()
	ns.db.recipeFacts = nil
	ns.ClearRecipeLocks()
	ns.SourcesChanged()
	ns.Log("Recipe facts cache dropped. Open a profession window, then reload.")
end, quiet = true })
table.insert(troubleshooting, { "perf", "Show how long the profession window and its list took", function()
	local function Ms(value)
		return value and ("%.1f ms"):format(value) or voice.noSample
	end
	for _, line in ipairs(PerfLines()) do
		Append(line)
	end
	Say(voice.perfWindow, Ms(openMs))
	Say(voice.perfList, Ms(ns.lastUnlearnedMs), Ms(ns.slowestUnlearnedMs), ns.unlearnedBuilds or 0)
	local phases = ns.coldBuildPhases
	if phases and phases.grouping then
		Say(voice.perfCold, phases.unlearned or 0, phases.recipes or 0, phases.sources or 0, phases.grouping)
	end
	local timing = ns.db.devScan and ns.db.devScan.timing
	if timing and timing.totalSeconds then
		Say(voice.perfScan, timing.profession or UNKNOWN, timing.totalSeconds, timing.walkMs or 0,
			timing.walkSeconds or 0, timing.walkedIDs or 0)
		Say(voice.perfRequests, timing.asked or 0, timing.answered or 0, timing.loadSeconds or 0, timing.reportMs or 0)
	else
		Say(voice.perfNoScan)
	end
end })
-- Made-item scan, for measuring the table before it ships: whenever a profession list is ready (the
-- player's own or one shown by another player), what each recipe makes is read once per game build.
local MADE_BATCH = 50 -- recipes read per frame
-- Format 3: format 2 could read the previous profession's list on a tab switch (the list is still the old one
-- when the new profession reports ready), so its counts came in pairs (Tailoring and Enchanting 471 each,
-- Engineering 18) and the profession switched to was never read.
local MADE_FORMAT, MADE_SAMPLES = 3, 8 -- a new format number makes every profession be read again
local madeScanning

local function ScanMade()
	if madeScanning or not C_TradeSkillUI.IsTradeSkillReady() then
		return
	end
	local profession = C_TradeSkillUI.GetBaseProfessionInfo()
	local professionID = profession and profession.professionID
	local done = ns.db.devMadeDone
	if not done or done.build ~= ns.BUILD or done.format ~= MADE_FORMAT then
		done = { build = ns.BUILD, format = MADE_FORMAT, missing = {} }
		ns.db.devMadeDone, ns.db.devMade = done, {}
	end
	if not professionID or (done[professionID] or 0) > 0 then
		return
	end
	local recipeIDs, made, index = C_TradeSkillUI.GetAllRecipeIDs(), ns.db.devMade, 0
	-- Not filled yet, or still the previous profession's list: read it on a later update.
	if #recipeIDs == 0 or not C_TradeSkillUI.IsRecipeInSkillLine(recipeIDs[1], professionID) then
		return
	end
	local noSchematic, noOutput, samples = 0, 0, {}
	madeScanning = true
	local function Batch()
		for _ = 1, MADE_BATCH do
			index = index + 1
			local recipeID = recipeIDs[index]
			if not recipeID then
				madeScanning, done[professionID], ns.scannedMade = nil, #recipeIDs, made
				done.missing[professionID] = ("%d recipes: %d without a schematic, %d without an output item; e.g. %s"):format(
					#recipeIDs, noSchematic, noOutput, table.concat(samples, "; "))
				return
			end
			local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
			local itemID = schematic and schematic.outputItemID
			if itemID then
				made[itemID] = math.min(made[itemID] or recipeID, recipeID) -- the lowest ID, to be stable
			else
				-- Why a recipe gave no made item, with a few examples, to explain a low count.
				noSchematic, noOutput = noSchematic + (schematic and 0 or 1), noOutput + (schematic and 1 or 0)
				if #samples < MADE_SAMPLES then
					local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
					samples[#samples + 1] = ("%d %s learned=%s skillLine=%s"):format(recipeID, info and info.name or "?",
						tostring(info and info.learned), tostring(C_TradeSkillUI.IsRecipeInSkillLine(recipeID, professionID)))
				end
			end
		end
		C_Timer.After(0, Batch)
	end
	Batch()
end

local madeFrame = CreateFrame("Frame")
madeFrame:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
madeFrame:SetScript("OnEvent", ScanMade)
-- Area capture; remove once it has answered: do several area IDs come back at one spot, and which is
-- the subzone; do unexplored areas return anything; what does a dungeon report. One entry per zone or
-- subzone change, to the saved file only.
local AREA_LOG_LIMIT = 400
local lastArea

local function CaptureArea(event)
	local mapID = C_Map.GetBestMapForUnit("player")
	local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	local areas = position and C_MapExplorationInfo.GetExploredAreaIDsAtPosition(mapID, position) or {}
	local named = {}
	for _, areaID in ipairs(areas) do
		named[#named + 1] = ("%d %s"):format(areaID, C_Map.GetAreaInfo(areaID) or "?")
	end
	local inInstance, instanceType = IsInInstance()
	local instance = ""
	if inInstance then
		local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
		instance = (" | instance %s %s %s"):format(instanceType, tostring(instanceID), name)
	end
	local entry = ("map %s %s | areas [%s] | zone %s | subzone %s | minimap %s%s"):format(tostring(mapID),
		position and ("%.3f,%.3f"):format(position:GetXY()) or "no position", table.concat(named, "; "),
		GetZoneText(), GetSubZoneText(), GetMinimapZoneText(), instance)
	if entry:gsub("^map %S+ %S+ ", "") == lastArea then
		return -- same place as the last entry, only moved
	end
	lastArea = entry:gsub("^map %S+ %S+ ", "")
	local log = ns.db.devAreas or {}
	ns.db.devAreas = log
	log[#log + 1] = date("%H:%M:%S ") .. event .. " | " .. entry
	if #log > AREA_LOG_LIMIT then
		table.remove(log, 1)
	end
end

local areaCapture = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
	areaCapture:RegisterEvent(event)
end
areaCapture:SetScript("OnEvent", function(_, event)
	if ns.db then
		CaptureArea(event)
	end
end)
-- Sharing self-test for one account (Sharing.lua).
table.insert(troubleshooting, { "sharetest", "Test sharing without a second player", function()
	ns.db.devShareTest = { date("%Y-%m-%d %H:%M:%S") }
	ns.ShareSelfTest(function(line)
		table.insert(ns.db.devShareTest, line)
		ns.Log(line)
	end)
end, quiet = true })
-- Seeding test; remove with the scan code once seeding is decided.
table.insert(troubleshooting, { "scan", "Find the recipe items for the open profession's recipes", Scan, quiet = true })

ns.commands = ns.commands or {}
for _, command in ipairs(troubleshooting) do
	local action, description, run = command[1], command[2], command[3]
	-- Quiet commands print to chat only, so the profession window stays in view.
	table.insert(ns.commands, { action = action, usage = command.usage, description = description, troubleshooting = true,
		run = command.quiet and run or toolkit:LoggedCommand(ns.device, action, run, ProfessionLine) })
end

-- Saved variables load time: the client reads them after the addon's last file (this one) and before
-- ADDON_LOADED, so the gap between the two is that read (plus any other addon's files in between).
local filesDone = debugprofilestop()
EventUtil.ContinueOnAddOnLoaded("RecipeVacuum", function()
	ns.PerfMs("saved variables load", debugprofilestop() - filesDone)
end)
--@end-debug@
