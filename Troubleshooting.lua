-- Troubleshooting commands. watch and log ship in every build; development commands sit between the
-- packager's debug markers (docs/development.md, "Working build").
local _, ns = ...

--@debug@
local UseScan -- defined with the scan code below
--@end-debug@

--@debug@
-- Performance record: each named piece keeps its run count, total and slowest run, written to the
-- saved log when the session ends.
local perfRecord, perfOrder = {}, {}

function ns.PerfMs(name, ms)
	local entry = perfRecord[name]
	if not entry then
		entry = { count = 0, total = 0, max = 0 }
		perfRecord[name] = entry
		perfOrder[#perfOrder + 1] = name
	end
	entry.count, entry.total = entry.count + 1, entry.total + ms
	if ms > entry.max then entry.max = ms end
end

function ns.Perf(name, started)
	ns.PerfMs(name, debugprofilestop() - started)
end

local function PerfLines()
	local lines = {}
	for _, name in ipairs(perfOrder) do
		local entry = perfRecord[name]
		lines[#lines + 1] = ("PERF %-24s runs %5d | average %7.2f ms | slowest %7.2f ms | total %8.1f ms"):format(
			name, entry.count, entry.total / entry.count, entry.max, entry.total)
	end
	return lines
end
--@end-debug@

--@debug@
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
--@end-debug@

-- Keeps the last LOG_LINES lines across commands and reloads. The copy window shows the current run:
-- the lines since the last command, or since watch was turned on (another addon shows the current session
-- the same way and keeps earlier ones). "log all" shows everything kept.
local LOG_LINES = 2000
local toolkit = LibStub("JigBoltgripToolkit-1.0")

-- A command's window shows that command's own lines (viewStart), even while a watch run is going;
-- "log" goes back to the run.
local viewStart

local function ShowLog(all)
	local log = ns.db.devLog or {}
	local first = all and 1 or math.min(viewStart or ns.db.devLogRun or 1, #log + 1)
	toolkit:ShowText(C_AddOns.GetAddOnMetadata("RecipeVacuum", "Title") .. ": " .. ns.voice.logTitle, table.concat(log, "\n", first))
end

-- Lines are timestamped, so a long watch reads as a timeline; a dated line is kept as it is.
local function Append(line, dated)
	ns.db.devLog = ns.db.devLog or {}
	table.insert(ns.db.devLog, (dated or line == "") and line or date("%H:%M:%S ") .. line)
	while #ns.db.devLog > LOG_LINES do
		table.remove(ns.db.devLog, 1)
		ns.db.devLogRun = math.max((ns.db.devLogRun or 1) - 1, 1)
		if viewStart then viewStart = math.max(viewStart - 1, 1) end
	end
end

-- The next line starts a new run. A running watch keeps its run, so other commands don't cut it short.
local function StartRun(force)
	if force or not ns.db.watch then
		ns.db.devLogRun = #(ns.db.devLog or {}) + 1
	end
end

-- Watch lines go to the log only: it runs while playing, and chat stays clear.
local logOnly

-- A line from Voice.lua goes to chat through ns.Log, which tags it, and to the saved log with the
-- same tag.
local LOG_TAG = "Recipe Vacuum: "
local voice = ns.voice

local function Chat(line)
	ns.Log(line)
end

local function print(...)
	local line = strjoin(" ", tostringall(...))
	Append(line)
	if not logOnly then _G.print(line) end
	if toolkit:IsTextShown() then
		ShowLog()
	end
end

-- Says one of the Vacuum's lines: logged, and shown in chat unless a watch callback is running.
local function Say(line, ...)
	line = select("#", ...) > 0 and line:format(...) or line
	Append(LOG_TAG .. line)
	if not logOnly then Chat(line) end
	if toolkit:IsTextShown() then
		ShowLog()
	end
end

-- The one chat line a watch event may print: it found recipes. Everything else stays in the log.
-- Chat lines speak like the game's gnomish machines, in the vacuum's own words: a state, then what it
-- is doing (Homing Robot OOX-17/TN: "Flight systems online! Engaging rockets for transport to Booty Bay!").
local function WatchFound(count)
	if count > 0 then
		local line = voice.detected:format(count, count == 1 and "recipe" or "recipes")
		Append(LOG_TAG .. line)
		Chat(line)
	end
end

local function IsRecipeItem(itemID)
	return itemID and select(6, C_Item.GetItemInfoInstant(itemID)) == Enum.ItemClass.Recipe
end

-- Wraps a watch callback so its lines skip chat; the flag is cleared even when the callback errors.
local function LogOnly(callback)
	return function(...)
		logOnly = true
		local ok, problem = pcall(callback, ...)
		logOnly = nil
		if not ok then Say(voice.malfunction, "the watch", tostring(problem)) end
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
		local recipes = 0
		for slot = 1, GetNumLootItems() do
			local link = GetLootSlotLink(slot)
			if link and not (issecretvalue and issecretvalue(link)) and IsRecipeItem(C_Item.GetItemInfoInstant(link)) then
				recipes = recipes + 1
			end
			local source = GetLootSourceInfo(slot)
			-- Containers opened from bags report an Item GUID with no item ID in it.
			local container = type(source) == "string" and not (issecretvalue and issecretvalue(source))
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
-- A group roll names the item but not what dropped it. The loot handle is logged in case it turns
-- out to match something that does (a corpse's GUID in a later loot line, for one).
handlers.START_LOOT_ROLL = function(rollID, rollTime, lootHandle)
	local link = GetLootRollItemLink(rollID)
	print(("ROLL %s | item %s | handle %s | time %s | unit target %s | %s"):format(Describe(rollID), Describe(link),
		Describe(lootHandle), Describe(rollTime), Describe(UnitGUID("target")), Where()))
	local itemID = link and not (issecretvalue and issecretvalue(link)) and C_Item.GetItemInfoInstant(link)
	WatchFound(IsRecipeItem(itemID) and 1 or 0)
end
-- Vendors and trainers are recorded when their window opens, not on a purchase, so the watch logs the
-- visit: who it is and how many items or services they list.
handlers.MERCHANT_SHOW = function()
	print(("VENDOR %s %s | faction %s | %d items | %s"):format(Describe(UnitName("npc")), Describe(UnitGUID("npc")),
		Describe((UnitFactionGroup("npc"))), GetMerchantNumItems(), Where()))
	-- Each item with its class, since only the Recipe class (9) is recorded. Log only, to keep chat clear.
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
-- Services can arrive after the window opens and the window's filter hides some, so list them a moment
-- later with every filter on, then put the player's filter back.
local TRAINER_LIST_DELAY = 0.5
local TRAINER_FILTERS = { "available", "unavailable", "used" }
handlers.TRAINER_SHOW = function()
	print(("TRAINER %s %s | faction %s | profession trainer %s | %d services shown | %s"):format(Describe(UnitName("npc")),
		Describe(UnitGUID("npc")), Describe((UnitFactionGroup("npc"))), Describe(IsTradeskillTrainer()), GetNumTrainerServices(), Where()))
	C_Timer.After(TRAINER_LIST_DELAY, LogOnly(function()
		local shown = {}
		for _, filter in ipairs(TRAINER_FILTERS) do
			shown[filter] = GetTrainerServiceTypeFilter(filter)
			SetTrainerServiceTypeFilter(filter, true)
		end
		print(("  with every filter on: %d services (filter was available %s, unavailable %s, used %s)"):format(
			GetNumTrainerServices(), Describe(shown.available), Describe(shown.unavailable), Describe(shown.used)))
		-- Recipes have a category and ranks have none, which is how the recorder tells them apart.
		-- Anything skipped is named, so a real recipe without a category would show up here.
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
				-- Does the game know the spell as a recipe? Ranks ("Journeyman Fishing") should not be.
				.. " | recipe info " .. Describe(tooltip and tooltip.id and C_TradeSkillUI.GetRecipeInfo(tooltip.id) ~= nil)
				.. " | step " .. Describe(GetTrainerServiceStepIndex()))
		end
		for _, filter in ipairs(TRAINER_FILTERS) do
			SetTrainerServiceTypeFilter(filter, shown[filter])
		end
		if #skipped > 0 then
			print("  skipped as ranks (no category): " .. table.concat(skipped, "; "))
		end
		WatchFound(recipes)
	end))
end
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
		logOnly = true
		local ok, problem = pcall(handlers[event], ...)
		logOnly = nil
		if not ok then
			Say(voice.malfunction, event, Describe(problem))
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
	if on and not ns.db.watch then
		StartRun(true)
		Append(date("%Y-%m-%d %H:%M:%S") .. " /recipevacuum watch on", true)
	end
	ns.db.watch = on or nil
	Say(on and voice.watchOn or voice.watchOff)
end

-- Called by Core once saved data is loaded (an ADDON_LOADED callback here could run before it).
--@debug@
-- A scan kept from this game build is used from the start of each session, ahead of the seed.
local function UseKeptScan()
	local scan = ns.db.devScan
	if scan and scan.teaches and scan.build == select(2, GetBuildInfo()) then
		UseScan(scan)
	end
end
--@end-debug@

function ns.ResumeWatch()
	--@debug@
	UseKeptScan()
	--@end-debug@
	if ns.db.watch and not watcher then
		StartWatch()
		Append("watch resumed after reload")
	end
end


--@debug@
-- Seeding scan: finds every recipe item and the recipe it teaches (docs/development.md, "Seeding").
local SCAN_FRAME_MS = 4        -- work per frame, so the game stays smooth
local SCAN_STEP = 500          -- IDs between clock checks
local SCAN_GAP = 50000         -- stop after this many IDs in a row with no item
local SCAN_CAP = 2000000
local LOAD_BATCH = 50          -- items requested per tick (500 a second)
local LOAD_INTERVAL = 0.1
local LOAD_TIMEOUT = 5         -- seconds to wait for the last answers
local NO_ANSWER = 0            -- saved for an item the game never answered, so it is not asked again
local ITEM_LIMIT = 10000       -- more recipe items than this means the walk went wrong; load nothing
local MISSING_LINES = 200      -- unlearned recipes without an item listed in the log

-- Makes a scan this session's layer over the seed (ns.scanned): only the items that teach a recipe.
-- Nothing is written to the seed or to the saved links.
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
-- When the running scan began, and its phases' timings (kept in devScan.timing for the perf command).
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
	-- What the scan learned is used at once, as this session's layer over the seed: the list redraws
	-- with the recipe items it found.
	UseScan(scan)
	ns.SourcesChanged()
	local timing = Timing(scan)
	timing.reportMs, timing.totalSeconds = debugprofilestop() - reportStart, GetTime() - scanStarted
	timing.profession = profession.professionName
	Say(voice.scanDone, withItem, unlearned, profession.professionName or UNKNOWN, timing.totalSeconds)
end

-- Loads each unanswered recipe item and reads the recipe it teaches. An item is asked once per build.
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
	-- Loads still waiting at the end are cancelled, so no callback stays registered, and remembered
	-- as unanswered.
	local waiting = {}
	local function Finish()
		if finished then return end
		finished = true
		for itemID, cancel in pairs(waiting) do
			cancel()
			-- An item already loaded answers at once, before its cancel handle is stored here.
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
				-- An answer that still carries no data counts as none, so the item is not asked again.
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
	-- One slice of the walk. Every pass of the outer loop ends on the clock or on done, and done is
	-- certain by SCAN_CAP, so the walk cannot run away.
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
		-- Loading costs a server request per item, so it only starts when the count is believable.
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

-- Runs only with a profession open. The item list and what each item teaches are kept per game
-- build, so a second profession reuses them and asks the server nothing.
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
		-- The item walk is reused, so this run's walk cost is nothing.
		Timing(scan).walkMs, Timing(scan).walkSeconds, Timing(scan).walkedIDs = 0, 0, 0
		ReadTaught(scan)
	else
		WalkItems()
	end
end

--@end-debug@

--@debug@
-- Shared functions timed from here, and the record written out when the session ends.
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
	local lines = PerfLines()
	if #lines > 0 then
		local version, build = GetBuildInfo()
		Append("")
		Append(("%s PERF session on %s (%s), %s level %d"):format(date("%Y-%m-%d %H:%M:%S"), version, build,
			UnitName("player") or UNKNOWN, UnitLevel("player") or 0), true)
		for _, line in ipairs(lines) do
			Append(line)
		end
	end
end)
--@end-debug@

-- Each command logs a header (time, client build, character, open profession), runs, then shows the log
-- in the copy window; "log" only shows it.
local function Logged(run)
	return function(arguments)
		local version, build = GetBuildInfo()
		local _, faction = UnitFactionGroup("player")
		local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
		local profession = page and page:IsVisible() and Professions.GetProfessionInfo()
		Append("")
		StartRun()
		viewStart = #ns.db.devLog + 1
		Append(date("%Y-%m-%d %H:%M:%S") .. " /recipevacuum " .. (arguments.action or ""), true)
		for _, line in ipairs({
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
	{ "watch", "Log loot, quest, vendor and trainer sources as you play: watch on, watch off", Watch, quiet = true },
}

--@debug@
-- Each goes once its question is answered.
-- Backs the performance claims; part of the release regression checks.
table.insert(troubleshooting, { "perf", "Show how long the profession window took to open", function()
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
-- Padlock comparison; remove once the owner has chosen. Each run puts the next candidate on the
-- locked rows: Blizzard's recipe row lock, its profession specialization lock, its reagent slot lock.
local LOCK_ART = {
	{ name = "recipe row lock", texture = "Interface\\LFGFrame\\UI-LFG-ICON-LOCK" },
	{ name = "specialization lock", atlas = "Professions_Specialization_Lock" },
	{ name = "reagent slot lock", atlas = "AdventureMapIcon-Lock" },
}
local lockArt = 1
table.insert(troubleshooting, { "locks", "Show the next padlock candidate on locked rows", function()
	lockArt = lockArt % #LOCK_ART + 1
	local art = LOCK_ART[lockArt]
	local exists = not art.atlas or C_Texture.GetAtlasInfo(art.atlas) ~= nil
	ns.marks.locked = { texture = art.texture, atlas = exists and art.atlas or nil, size = ns.marks.locked.size, plain = true }
	if not exists then
		ns.marks.locked.texture = LOCK_ART[1].texture
	end
	ns.RefreshRows()
	ns.Log(("Padlock %d of %d: %s%s"):format(lockArt, #LOCK_ART, art.name,
		exists and "" or " (this client lacks the art; showing the recipe row lock)"))
end, quiet = true })
-- Seeding test; remove with the scan code once seeding is decided.
table.insert(troubleshooting, { "scan", "Seeding test: find every recipe item in the game and match them to the open profession's recipes", Scan, quiet = true })
--@end-debug@

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
table.insert(ns.commands, { action = "log", description = "Show the last command's or watch's output; log all shows everything kept, log clear empties it", troubleshooting = true,
	run = function(word)
		word = (word or ""):lower()
		if word == "clear" then
			ns.db.devLog, ns.db.devLogRun = {}, nil
			Chat(voice.logPurged)
		else
			viewStart = nil
			ShowLog(word == "all")
		end
	end })
