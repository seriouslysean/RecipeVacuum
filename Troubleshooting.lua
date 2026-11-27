-- Development commands and their log: the whole file exists only in a checkout build and is stripped from releases (docs/development.md, "Working build").
local addonName, ns = ...

--@debug@

local UseScan -- defined below
local toolkit = ns.toolkit
local LV = toolkit.LogValue -- a logfmt value (kit docs/standards.md, "Working build")

-- Timing is kept by the library per module.
function ns.PerfMs(name, ms)
	toolkit:TimeMs(ns.module, name, ms)
end

function ns.Perf(name, started)
	toolkit:Time(ns.module, name, started)
end

local function PerfLines()
	return toolkit:TimingLines(ns.module)
end

-- Times the profession window's opening for the perf command.
local openStarted, openMs
toolkit:EventFrame(ns.module, {
	TRADE_SKILL_SHOW = function()
		openStarted, openMs = debugprofilestop(), nil
	end,
	TRADE_SKILL_CLOSE = function()
		openStarted = nil
	end,
})
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
-- A troubleshooting answer in the log, as text; facts go through toolkit:Trace with their own keys.
local function Append(text)
	toolkit:Trace(ns.module, "command output", "text", text)
end

-- Watch lines go to the log only, so chat stays clear.
local logOnly

-- A line from Voice.lua goes to chat and to the saved log with the same tag.
local LOG_TAG = ns.module.title .. ": "
local voice = ns.voice

-- Says one of the Vacuum's lines: logged, and shown in chat unless a watch callback is running.
local function Say(line, ...)
	line = select("#", ...) > 0 and line:format(...) or line
	Append(LOG_TAG .. line)
	if not logOnly then toolkit:Debug(line) end
end

-- What a watch event found, in the log only: the working build always watches, so a chat line here would repeat on every
-- window; the player's own line is the release one for new finds (docs/voice.md).
local function WatchFound(count)
	if count > 0 then
		toolkit:Trace(ns.module, "watch found", "recipes", count)
	end
end

local IsRecipeItem = ns.IsRecipeItem

-- The watch logs loot windows, quest dialogs and spell targets, to learn what Forever reports for loot and quest givers and rewards.

local Describe, Readable = toolkit.Describe, toolkit.Readable

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
	return "map", mapID, "pos", position and ("%.3f,%.3f"):format(position:GetXY()) or nil, "instance", (IsInInstance())
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
		toolkit:Trace(ns.module, "loot", "args", DescribeAll(...), "cast_target", Describe(castTarget), "fishing", IsFishingLoot(),
			"target", Describe(UnitGUID("target")), Where())
		local recipes = 0
		for slot = 1, GetNumLootItems() do
			local link = GetLootSlotLink(slot)
			if link and Readable(link) and IsRecipeItem(link) then
				recipes = recipes + 1
			end
			local source = GetLootSourceInfo(slot)
			-- Containers opened from bags report an Item GUID with no item ID in it.
			local container = type(source) == "string" and Readable(source)
				and source:find("^Item%-") and C_Item.GetItemIDByGUID and C_Item.GetItemIDByGUID(source)
			toolkit:Trace(ns.module, "loot slot", "n", slot, "type", Describe(GetLootSlotType(slot)),
				"link", Describe(GetLootSlotLink(slot)), "sources", DescribeAll(GetLootSourceInfo(slot)),
				"container_item", container or nil)
		end
		WatchFound(recipes)
	end,
	QUEST_DETAIL = function() end, -- filled below
}
handlers.LOOT_OPENED = handlers.LOOT_READY
local function Quest(event)
	toolkit:Trace(ns.module, "quest", "event", event, "id", GetQuestID(), "npc", Describe(UnitName("questnpc")),
		"guid", Describe(UnitGUID("questnpc")), Where())
	local recipes = 0
	for _, kind in ipairs({ "reward", "choice" }) do
		local count = kind == "reward" and GetNumQuestRewards() or GetNumQuestChoices()
		for index = 1, count do
			toolkit:Trace(ns.module, "quest item", "kind", kind, "n", index, "info", DescribeAll(GetQuestItemInfo(kind, index)))
			if IsRecipeItem((select(6, GetQuestItemInfo(kind, index)))) then recipes = recipes + 1 end
		end
	end
	WatchFound(recipes)
end
handlers.QUEST_DETAIL = function() Quest("QUEST_DETAIL") end
-- A group roll names the item but not what dropped it; the handle is logged in case it matches something later.
handlers.START_LOOT_ROLL = function(rollID, rollTime, lootHandle)
	local link = GetLootRollItemLink(rollID)
	toolkit:Trace(ns.module, "roll", "id", rollID, "item", Describe(link), "handle", Describe(lootHandle), "time", rollTime,
		"target", Describe(UnitGUID("target")), Where())
	local itemID = link and Readable(link) and C_Item.GetItemInfoInstant(link)
	WatchFound(IsRecipeItem(itemID) and 1 or 0)
end
-- Vendors and trainers are recorded on window open, so the watch logs the visit: who and how many items or services.
handlers.MERCHANT_SHOW = function()
	toolkit:Trace(ns.module, "vendor", "name", Describe(UnitName("npc")), "guid", Describe(UnitGUID("npc")),
		"faction", (UnitFactionGroup("npc")), "items", GetMerchantNumItems(), Where())
	-- Each item with its class, since only the Recipe class (9) is recorded; log only.
	local recipes = 0
	for index = 1, GetMerchantNumItems() do
		local itemID = GetMerchantItemID(index)
		if IsRecipeItem(itemID) then recipes = recipes + 1 end
		toolkit:Trace(ns.module, "vendor item", "n", index, "id", itemID, "link", Describe(GetMerchantItemLink(index)),
			"class", itemID and select(6, C_Item.GetItemInfoInstant(itemID)))
	end
	WatchFound(recipes)
end
-- A plain conversation, to tell an NPC that only talks from one that sells, trains or gives quests.
handlers.GOSSIP_SHOW = function()
	local options = {}
	for _, option in ipairs(C_GossipInfo.GetOptions()) do
		table.insert(options, Describe(option.name))
	end
	toolkit:Trace(ns.module, "gossip", "name", Describe(UnitName("npc")), "guid", Describe(UnitGUID("npc")),
		"quests", C_GossipInfo.GetNumAvailableQuests(), "options", #options > 0 and table.concat(options, "; ") or "none", Where())
end
handlers.TRAINER_SHOW = function()
	toolkit:Trace(ns.module, "trainer open", "name", Describe(UnitName("npc")), "guid", Describe(UnitGUID("npc")),
		"faction", (UnitFactionGroup("npc")), "profession_trainer", IsTradeskillTrainer() and true or false,
		"services", GetNumTrainerServices(), Where())
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
	local scan = ns.db.devScan
	if scan and scan.teaches and scan.build == select(2, GetBuildInfo()) then
		UseScan(scan)
	end
end

function ns.StartWorkingLog()
	UseKeptScan()
	toolkit:StartLog(ns.module, ns.db, WatchHandlers())
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
	toolkit:Trace(ns.module, "scan items", "recipe_items", #scan.items, "teach", known, "teach_none", none,
		"unanswered", #scan.items - known - none)
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
				table.insert(without, { recipeID, info.name or "?" })
			end
		end
	end
	toolkit:Trace(ns.module, "scan profession", "name", profession.professionName or "?", "unlearned", unlearned,
		"with_item", withItem, "without_item", #without)
	table.sort(without, function(a, b) return a[1] < b[1] end)
	for index = 1, math.min(#without, MISSING_LINES) do
		toolkit:Trace(ns.module, "scan no item", "id", without[index][1], "name", without[index][2])
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
		toolkit:Trace(ns.module, "scan load", "asked", #pending, "answered", answered, "seconds", timing.loadSeconds)
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
		toolkit:Trace(ns.module, "scan walk", "ids", id, "items", existing, "highest", lastItem, "recipe_items", #found,
			"work_ms", cpu, "seconds", GetTime() - started)
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
for name, label in pairs({ AddSourceLines = "source tooltip", MergeFinds = "merge shared finds", LinkPending = "link recipe items",
	GetUnlearnedRecipes = "unlearned recipes" }) do
	local inner = ns[name]
	ns[name] = function(...)
		local started = debugprofilestop()
		local first, second, third = inner(...)
		ns.Perf(label, started)
		return first, second, third
	end
end

toolkit:EventFrame(ns.module, {
	PLAYER_LOGOUT = function()
		-- Retired probes' data, so it does not stay in the saved file.
		if ns.db.devScan then ns.db.devScan.ranks = nil end -- the scan no longer reads rank books
		ns.db.devHover, ns.db.devHoverLog, ns.db.devSpecLines, ns.db.devChatColors = nil, nil, nil, nil
	end,
})

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
table.insert(troubleshooting, { "item", label = "Item Tooltip Data", button = "Save", "Save an item's tooltip data to the log", function(text)
	local itemID = tonumber(text)
	if not itemID then
		return ns.toolkit:Debug("item probe needs=item_id example=\"/recipevacuum item 16083\"")
	end
	if not C_Item.IsItemDataCachedByID(itemID) then
		C_Item.RequestLoadItemDataByID(itemID)
		return ns.toolkit:Debug("item probe requested=true next=run_again")
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
	ns.toolkit:Debug(("item probe saved_lines=%d id=%d next=reload"):format(#lines - 1, itemID))
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
table.insert(troubleshooting, { "mockranks", label = "Test Rank Sources", button = "Add", "Add test rank sources for this session", function()
	local now = GetServerTime()
	for _, row in ipairs(MOCK_BOOK_VENDORS) do
		local itemID, npcID, name, faction, mapID, x, y = unpack(row)
		ns.included.npcs[npcID] = { name = name, faction = faction, positions = { [mapID] = { x = x, y = y, seen = now } } }
		ns.included.items[itemID] = ns.included.items[itemID] or {}
		table.insert(ns.included.items[itemID], { kind = "vendor", npc = npcID, faction = faction, seen = now })
	end
	-- Rank links go in a session-only overlay, so a real rank learned meanwhile is never touched (Astra review).
	ns.rankOverlay = {}
	local function Add(skillLine, fromCap)
		ns.rankOverlay[skillLine] = ns.rankOverlay[skillLine] or {}
		local sources = ns.rankOverlay[skillLine][fromCap] or { npcs = {}, items = {}, quests = {} }
		ns.rankOverlay[skillLine][fromCap] = sources
		return sources
	end
	for itemID, rank in pairs(MOCK_BOOK_RANKS) do
		Add(rank[1], rank[2]).items[itemID] = now
	end
	local quest = MOCK_QUEST_RANK
	ns.included.npcs[quest.npc] = { name = quest.name, positions = { [quest.map] = { x = quest.x, y = quest.y, seen = now } } }
	Add(quest.skillLine, quest.fromCap).quests[quest.quest] = quest.npc
	ns.SourcesChanged()
	ns.toolkit:Debug("mock ranks added=expert_books,nat_pagle_quest scope=session next=reopen_window")
end, quiet = true })

-- Facts cache test: drops the cache, so the next unlearned-recipe build runs cold without it.
-- Compare that build's "unlearned recipes" timing with one after a plain reload (cache kept).
table.insert(troubleshooting, { "nofacts", label = "Recipe Facts Cache", button = "Drop", "Drop the recipe facts cache for a timing test", function()
	ns.db.recipeFacts = nil
	ns.ClearRecipeLocks()
	ns.SourcesChanged()
	ns.toolkit:Debug("facts cache dropped=true next=reload")
end, quiet = true })
table.insert(troubleshooting, { "perf", label = "Window Timings", button = "Show", "Show how long the window and its lookups took", function()
	local function Ms(value)
		return value and ("%.1f ms"):format(value) or voice.noSample
	end
	for _, line in ipairs(PerfLines()) do
		Append(line)
	end
	Say(voice.perfWindow, Ms(openMs))
	local timing = ns.db.devScan and ns.db.devScan.timing
	if timing and timing.totalSeconds then
		Say(voice.perfScan, timing.profession or UNKNOWN, timing.totalSeconds, timing.walkMs or 0,
			timing.walkSeconds or 0, timing.walkedIDs or 0)
		Say(voice.perfRequests, timing.asked or 0, timing.answered or 0, timing.loadSeconds or 0, timing.reportMs or 0)
	else
		Say(voice.perfNoScan)
	end
end })
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

local areaHandlers = {}
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
	areaHandlers[event] = function()
		if ns.db then
			CaptureArea(event)
		end
	end
end
toolkit:EventFrame(ns.module, areaHandlers)
-- Layout measuring: Blizzard's profession window and our panel, each element relative to its pane's own top-left in the pane's own
-- scale, read only (docs/development.md, "Working build"; tools/layout-diff.lua prints the differences).

local function Number(value)
	if type(value) == "number" and Readable(value) then return value end
end

-- A value read from a frame that may not have the method or may hold a secret.
local function Read(object, method, ...)
	if not (object and object[method]) then return end
	local ok, first, second, third = pcall(object[method], object, ...)
	if ok and Readable(first) then return first, second, third end
end

local function ScaleOf(region)
	return Number(Read(region, "GetEffectiveScale") or Read(Read(region, "GetParent"), "GetEffectiveScale"))
end

-- Walks a dotted path of keys; nil as soon as one is missing.
local function Path(root, path)
	local value = root
	for key in path:gmatch("[^.]+") do
		if type(value) ~= "table" then return end
		value = value[key]
	end
	return value
end

-- One region's geometry from the pane's top-left (y grows downward), in the pane's scale, plus text or art facts.
local function Measure(region, pane)
	if not (region and pane) then return { missing = true } end
	local scale, paneScale = ScaleOf(region), ScaleOf(pane)
	local left, top, width, height = Number(Read(region, "GetLeft")), Number(Read(region, "GetTop")),
		Number(Read(region, "GetWidth")), Number(Read(region, "GetHeight"))
	local paneLeft, paneTop = Number(Read(pane, "GetLeft")), Number(Read(pane, "GetTop"))
	if not (scale and paneScale and left and top and width and height and paneLeft and paneTop) then return { missing = true } end
	local result = { left = (left * scale - paneLeft * paneScale) / paneScale, top = (paneTop * paneScale - top * scale) / paneScale,
		width = width * scale / paneScale, height = height * scale / paneScale, shown = Read(region, "IsShown") and true or false }
	if Read(region, "IsObjectType", "FontString") then
		local object = Read(region, "GetFontObject")
		local _, size, flags = Read(region, "GetFont")
		result.fontObject = Read(object, "GetName") or "?"
		result.fontSize, result.fontFlags = Number(size), flags or ""
		local stringWidth, stringHeight = Number(Read(region, "GetStringWidth")), Number(Read(region, "GetStringHeight"))
		result.stringWidth = stringWidth and stringWidth * scale / paneScale
		result.stringHeight = stringHeight and stringHeight * scale / paneScale
		result.lines = Number(Read(region, "GetNumLines"))
		result.justifyH, result.justifyV = Read(region, "GetJustifyH"), Read(region, "GetJustifyV")
		result.wrapWidth = result.width
		result.wordWrap = Read(region, "CanWordWrap") and true or false
	elseif Read(region, "IsObjectType", "Texture") then
		result.atlas = Read(region, "GetAtlas")
		local texture = Read(region, "GetTexture")
		result.texture = result.atlas == nil and (type(texture) == "string" or type(texture) == "number") and texture or nil
	end
	return result
end

local function ByTop(a, b)
	return (Number(Read(a, "GetTop")) or 0) > (Number(Read(b, "GetTop")) or 0)
end

local function ShownFrames(list)
	local found = {}
	for _, frame in ipairs(list) do
		if Read(frame, "IsShown") then found[#found + 1] = frame end
	end
	table.sort(found, ByTop)
	return found
end

-- The first two recipe rows with no heading between them, so their pitch is the row spacing alone.
local function AdjacentRows(rowList, headingList)
	for index = 1, #rowList - 1 do
		local upper, lower = Number(Read(rowList[index], "GetTop")), Number(Read(rowList[index + 1], "GetTop"))
		local between = false
		for _, heading in ipairs(headingList) do
			local top = Number(Read(heading, "GetTop"))
			between = between or (top and upper and lower and top < upper and top > lower)
		end
		if not between then return rowList[index], rowList[index + 1] end
	end
	return rowList[1]
end

-- Blizzard's recipe frames, split into headings and rows by the keys their templates declare (Blizzard_ProfessionsRecipeList.xml).
local function BlizzardListFrames(scrollBox)
	local headings, rows = {}, {}
	if scrollBox and scrollBox.ForEachFrame then
		pcall(scrollBox.ForEachFrame, scrollBox, function(frame)
			if frame.SkillUps then rows[#rows + 1] = frame elseif frame.RankBar and frame.Label then headings[#headings + 1] = frame end
		end)
	end
	return ShownFrames(headings), ShownFrames(rows)
end

local function LayoutRecord(parts)
	local page = ProfessionsFrame.CraftingPage
	local form, list, window = page.SchematicForm, page.RecipeList, ProfessionsFrame
	local record = { pairs = {} }
	local function Pair(pane, measure, blizzard, ours)
		record.pairs[#record.pairs + 1] = { pane = pane, measure = measure, blizzard = blizzard, ours = ours }
		for side, values in pairs({ blizzard = blizzard, ours = ours }) do
			if values.missing then toolkit:Trace(ns.module, "layout missing", "measure", measure, "side", side, "pane", pane) end
		end
	end
	-- Both sides of one measure, each from its own pane.
	local function Both(pane, measure, blizzardPane, blizzardRegion, oursPane, oursRegion)
		Pair(pane, measure, Measure(blizzardRegion, blizzardPane), Measure(oursRegion, oursPane))
	end

	-- The recipe pane: output icon and its ring, name, requirement, Reagents label, slots, bottom margin, action button.
	local detail = parts.detail
	local function Detail(measure, blizzardRegion, oursRegion)
		Both("detail", measure, form, blizzardRegion, detail, oursRegion)
	end
	Detail("pane", form, detail)
	Detail("icon", form.OutputIcon, detail.Output)
	Detail("icon art", Path(form, "OutputIcon.Icon"), Path(detail, "Output.Icon"))
	Detail("icon border", Path(form, "OutputIcon.IconBorder"), Path(detail, "Output.IconBorder"))
	Detail("name", form.OutputText, detail.Name)
	Detail("requirement", form.OutputSubText, detail.Sub)
	Detail("Reagents label", Path(form, "Reagents.Label"), detail.ReagentsLabel)
	local slots = Read(form, "GetSlotsByReagentType", Enum.CraftingReagentType.Basic) or Read(form, "GetSlots") or {}
	local buttons = {}
	for _, slot in ipairs(ShownFrames(slots)) do buttons[#buttons + 1] = slot end
	local mine = ShownFrames(parts.reagentRows)
	local last
	for index = 1, math.max(#buttons, #mine) do
		local slot, button = buttons[index], mine[index]
		Detail(("reagent %d icon"):format(index), slot and slot.Button, button)
		Detail(("reagent %d name"):format(index), slot and slot.Name, button and button.Text)
		last = index
	end
	-- Gaps and the bottom margin come from the same measured edges, so both sides use one rule.
	local function Edges(regions, pane)
		local edges = {}
		for index, region in ipairs(regions) do
			local box = Measure(region, pane)
			edges[index] = not box.missing and box or nil
		end
		return edges
	end
	local function Gaps(blizzardEdges, oursEdges, name)
		local function Value(edges, index)
			local first, second = edges[index], edges[index + 1]
			if first and second then return { height = second.top - (first.top + first.height) } end
			return { missing = true }
		end
		for index = 1, math.max(#blizzardEdges, #oursEdges, 2) - 1 do
			Pair("detail", name:format(index), Value(blizzardEdges, index), Value(oursEdges, index))
		end
	end
	local blizzardIcons, oursIcons = {}, {}
	for index = 1, last or 0 do
		blizzardIcons[index] = buttons[index] and buttons[index].Button
		oursIcons[index] = mine[index]
	end
	local blizzardEdges, oursEdges = Edges(blizzardIcons, form), Edges(oursIcons, detail)
	Gaps(blizzardEdges, oursEdges, "gap below reagent %d icon")
	local function Margin(edges, pane)
		local lowest = edges[last or 0]
		local paneBox = Measure(pane, pane)
		if not (lowest and not paneBox.missing) then return { missing = true } end
		return { height = paneBox.height - (lowest.top + lowest.height) }
	end
	Pair("detail", "bottom content margin", Margin(blizzardEdges, form), Margin(oursEdges, detail))
	local action = parts.mapMore and parts.mapMore:IsShown() and parts.mapMore or parts.mapButton
	Both("detail", "action button", form, page.CreateButton, detail, action)

	-- The recipe list: headings, rows, their text insets, the row pitch and the scroll bar.
	local area = parts.listArea
	local function List(measure, blizzardRegion, oursRegion)
		Both("list", measure, list, blizzardRegion, area, oursRegion)
	end
	List("pane", list, area)
	List("scroll area", list.ScrollBox, parts.scroll)
	List("scroll bar", list.ScrollBar, parts.scroll.ScrollBar)
	local blizzardHeadings, blizzardRows = BlizzardListFrames(list.ScrollBox)
	local oursHeadings, oursRows = ShownFrames(parts.headings), ShownFrames(parts.rows)
	List("heading", blizzardHeadings[1], oursHeadings[1])
	List("heading text", blizzardHeadings[1] and blizzardHeadings[1].Label, oursHeadings[1] and oursHeadings[1].Label)
	List("first row", blizzardRows[1], oursRows[1])
	List("row text", blizzardRows[1] and blizzardRows[1].Label, oursRows[1] and oursRows[1].Label)
	local function Inset(frame)
		local box, text = Measure(frame, list), Measure(frame and frame.Label, list)
		if box.missing or text.missing then return { missing = true } end
		return { left = text.left - box.left, top = text.top - box.top }
	end
	local function InsetOurs(frame)
		local box, text = Measure(frame, area), Measure(frame and frame.Label, area)
		if box.missing or text.missing then return { missing = true } end
		return { left = text.left - box.left, top = text.top - box.top }
	end
	Pair("list", "heading text inset", Inset(blizzardHeadings[1]), InsetOurs(oursHeadings[1]))
	Pair("list", "row text inset", Inset(blizzardRows[1]), InsetOurs(oursRows[1]))
	local function Pitch(rowList, headingList, pane)
		local upper, lower = AdjacentRows(rowList, headingList)
		local first, second = Measure(upper, pane), Measure(lower, pane)
		if first.missing or second.missing then return { missing = true } end
		return { height = second.top - first.top }
	end
	Pair("list", "row-to-row pitch", Pitch(blizzardRows, blizzardHeadings, list), Pitch(oursRows, oursHeadings, area))

	-- The skill bar in its window, and the portrait; the details' icon is the pane's own portrait, so it pairs with the window's.
	local rank = page.RankBar
	local function Rank(measure, blizzardRegion, oursRegion)
		Both("rank bar", measure, window, blizzardRegion, parts.panel, oursRegion)
	end
	Rank("bar", rank, parts.rankBar)
	Rank("bar art", rank.Background, parts.rankBar.Background)
	Rank("bar border", rank.Border, parts.rankBar.Border)
	Rank("bar fill", rank.Fill, parts.rankBar.Fill)
	Rank("bar text", Path(rank, "Rank.Text"), Path(parts.rankBar, "text"))
	Both("portrait", "portrait", window, Path(window, "PortraitContainer.portrait"), parts.panel, Path(parts.panel, "PortraitContainer.portrait"))
	Both("portrait", "portrait box", window, Path(window, "PortraitContainer"), parts.panel, Path(parts.panel, "PortraitContainer"))
	Pair("portrait", "details icon against the window's portrait", Measure(Path(window, "PortraitContainer.portrait"), window),
		Measure(detail.Output, detail))
	return record
end

-- One record of the window and our panel beside it; nil with the reason when the two are not both on screen with a recipe selected.
local function RecordLayout()
	local parts = ns.DevPanelParts()
	local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
	-- The details are measured only while a recipe is selected in ours; the rest is measured either way.
	-- The overview tab: its section edges, so our list and details can split where its bottom row starts.
	local book = ProfessionsFrame and ProfessionsFrame.BookPage
	if book and book:IsVisible() then
		-- The sections sit in the page's content frame (Camelot/Blizzard_ProfessionsBookTemplates.xml, ProfessionsContentFrame).
		local content = book.ProfessionsContentFrame or book
		local found = 0
		for _, key in ipairs({ "PrimaryProfession1", "PrimaryProfession2", "SecondaryProfession1" }) do
			local region = content[key]
			if region then found = found + 1 end
			local scale = region and region:GetEffectiveScale()
			local top, bottom = region and region:GetTop(), region and region:GetBottom()
			toolkit:Trace(ns.module, "layout edge", "name", "blizzard overview " .. key, "top", top and top * scale,
				"bottom", bottom and bottom * scale)
		end
		local scale = ProfessionsFrame:GetEffectiveScale()
		toolkit:Trace(ns.module, "layout edge", "name", "blizzard window", "top", ProfessionsFrame:GetTop() * scale,
			"bottom", ProfessionsFrame:GetBottom() * scale)
		return { pairs = {}, profession = "overview", overview = found }
	end
	if not (page and page:IsVisible() and parts.panel and parts.panel:IsShown()) then
		return nil, "Open a profession, then run it again."
	end
	local profession = Professions.GetProfessionInfo()
	local ok, record = pcall(LayoutRecord, parts)
	if not ok then
		return nil, "Layout failed: " .. tostring(record)
	end
	record.profession, record.professionID, record.time = profession.professionName or "?", profession.professionID, GetServerTime()
	record.build = select(2, GetBuildInfo())
	record.version = C_AddOns.GetAddOnMetadata(addonName, "Version")
	record.windowScale, record.panelScale = ProfessionsFrame:GetEffectiveScale(), parts.panel:GetEffectiveScale()
	-- Section edges on screen, in pixels from the bottom, so ours can be lined up with the crafting page's own sections by a
	-- script (kit standards, "Side panels": measure, then draw). Each is top and bottom, or nil when not shown.
	local function Edge(name, region)
		local scale = region and region:GetEffectiveScale()
		local top, bottom = region and region:IsVisible() and region:GetTop(), region and region:IsVisible() and region:GetBottom()
		record.edges[#record.edges + 1] = { name = name, top = top and top * scale, bottom = bottom and bottom * scale }
		toolkit:Trace(ns.module, "layout edge", "name", name, "top", top and top * scale, "bottom", bottom and bottom * scale)
	end
	record.edges = {}
	local form = page.SchematicForm
	Edge("blizzard window", ProfessionsFrame)
	Edge("blizzard recipe list", page.RecipeList)
	Edge("blizzard recipe list rows", page.RecipeList and page.RecipeList.ScrollBox)
	Edge("blizzard schematic", form)
	Edge("blizzard reagents label", form and form.Reagents and form.Reagents.Label)
	Edge("blizzard create button", page.CreateButton)
	Edge("ours panel", parts.panel)
	Edge("ours rank bar", parts.rankBar)
	Edge("ours list", parts.listArea)
	Edge("ours list rows", parts.scroll)
	Edge("ours details", parts.detail)
	Edge("ours reagents label", parts.detail and parts.detail.ReagentsLabel)
	Edge("ours map pin", parts.mapButton and parts.mapButton:IsShown() and parts.mapButton or parts.mapMore)
	ns.db.devLayout = ns.db.devLayout or {}
	-- Every record is kept, by view and time, so each view and each build of it stays to be read: debugging data, nothing is
	-- dropped (owner, 2026-11-26).
	record.recipe = parts.detail.recipeID and parts.detail.Name:GetText() or "no recipe selected"
	record.when = date("%Y-%m-%d %H:%M:%S")
	ns.db.devLayout[record.profession .. " / " .. record.recipe .. " @ " .. record.when] = record
	toolkit:Trace(ns.module, "layout recorded", "measures", #record.pairs, "profession", record.profession)
	return record
end

table.insert(troubleshooting, { "layout", label = "Window Layout", button = "Record", "Record Blizzard's profession window and our panel layout", function()
	local record, reason = RecordLayout()
	if not record then return ns.toolkit:Debug("layout not_recorded reason=" .. LV(reason)) end
	if record.overview then
		return ns.toolkit:Debug(("layout overview recorded sections=%d next=logout"):format(record.overview))
	end
	ns.toolkit:Debug(("layout recorded measures=%d profession=%s next=reload"):format(#record.pairs, LV(record.profession)))
end, quiet = true })

-- The layout is recorded only from its Window Layout [Record] row: a development tool logs only when its button is
-- pressed (kit docs/standards.md, "Working build").
-- Sharing self-test for one account: the toolkit's share builds, checks and whispers every reply (its docs/sharing.md,
-- "Working build"); the merge goes into a scratch copy of the data and the line counts what arrived.
local function CountFinds(layer)
	local count = 0
	for _, bucket in pairs({ layer.recipes, layer.items }) do
		for _, observations in pairs(bucket) do
			count = count + #observations
		end
	end
	return count
end

table.insert(troubleshooting, { "sharetest", label = "Sharing", button = "Test", "Test sharing without a second player", function()
	ns.db.devShareTest = { date("%Y-%m-%d %H:%M:%S") }
	local real = ns.db
	local scratch = { npcs = {}, objects = {}, shared = ns.NewLayer(), itemRecipe = {}, pendingItems = {} }
	ns.share:SelfTest(function(line)
		table.insert(real.devShareTest, line)
		ns.toolkit:Debug(line)
	end, function(rows)
		ns.db = scratch
		local ok, changed, skipped = pcall(ns.share.Merge, ns.share, rows)
		ns.db = real
		if not ok then error(changed) end
		return changed, skipped
	end, function()
		local own, arrived = CountFinds(real.found), CountFinds(scratch.shared)
		return ("%d of this character's %d finds arrive%s"):format(arrived, own, arrived == own and "" or " (MISMATCH)")
	end)
end, quiet = true })
-- Seeding test; remove with the scan code once seeding is decided.
-- Forces one read of the open trainer's learned services, to see on the Deck whether "used" rows appear at all (docs/client-notes.md, "Trainers").
table.insert(troubleshooting, { "learned", label = "Learned Services", button = "Read", "Read the open trainer's learned services once", function()
	ns.ReadLearnedNow()
end })
-- Whether opening the world map from addon code taints (kit decision 0068): pins the last Map Pin place again and opens the
-- map at it; a block that follows is logged with its tainted fields.
table.insert(troubleshooting, { "mapopen", label = "Map Pin and Open", button = "Test", "Pin the last Map Pin place and open the map at it", function()
	local target = ns.lastPin
	if not target then
		ns.toolkit:Trace(ns.module, "map open test", "result", "skipped", "reason", "no_map_pin_yet")
		return ns.toolkit:Debug("Press Map Pin on a recipe first, then this.")
	end
	ns.ShowOnMap(target)
	OpenWorldMap(target.mapID)
	ns.toolkit:Trace(ns.module, "map open test", "map", target.mapID, "shown", WorldMapFrame and WorldMapFrame:IsShown())
end })
table.insert(troubleshooting, { "scan", label = "Recipe Items", button = "Find", "Find the recipe items for the open profession's recipes", Scan, quiet = true })

ns.commands = ns.commands or {}
for _, command in ipairs(troubleshooting) do
	local action, description, run = command[1], command[2], command[3]
	-- Quiet commands print to chat only, so the profession window stays in view.
	table.insert(ns.commands, { action = action, usage = command.usage, description = description, troubleshooting = true,
		label = command.label, button = command.button,
		run = command.quiet and run or toolkit:LoggedCommand(ns.module, action, run, ProfessionLine) })
end

-- Saved variables load time: the client reads them after the addon's last file (this one) and before
-- ADDON_LOADED, so the gap between the two is that read (plus any other addon's files in between).
local filesDone = debugprofilestop()
EventUtil.ContinueOnAddOnLoaded(addonName, function()
	ns.PerfMs("saved variables load", debugprofilestop() - filesDone)
end)
--@end-debug@
