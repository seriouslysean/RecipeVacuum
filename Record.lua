local _, ns = ...

-- Records where recipes come from, for every profession, into the self-found layer (Core.lua); trainers by recipe ID from tooltips (another addon Scanner.lua).
-- Only Enum.ItemClass.Recipe items are kept, so other loot costs one item-class check.

-- Positions are rounded to three decimals of the 0..1 map coordinate.
local COORDINATE_PRECISION = 1000

local function Round(value)
	return math.floor(value * COORDINATE_PRECISION + 0.5) / COORDINATE_PRECISION
end

function ns.GetPlayerLocation()
	local mapID = C_Map.GetBestMapForUnit("player")
	local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if not position then
		return mapID
	end
	local x, y = position:GetXY()
	return mapID, Round(x), Round(y)
end
local GetPlayerLocation = ns.GetPlayerLocation

local BUILD = ns.BUILD
local Readable, GUID = ns.toolkit.Readable, ns.toolkit.GUID

-- The NPC being talked to, or nil when the client hides it (secret values); saved by NoteVisit only for an NPC with a recipe.
local function CurrentNPC()
	local unitType, npcID = GUID(UnitGUID("npc"))
	if unitType ~= "Creature" then
		return nil
	end
	local seen = GetServerTime()
	local mapID, x, y = GetPlayerLocation()
	return { field = "npc", value = npcID, npcID = npcID, faction = (UnitFactionGroup("player")), seen = seen,
		name = UnitName("npc"), mapID = mapID, x = x, y = y, npcFaction = (UnitFactionGroup("npc")) }
end

-- Runs when a scan found at least one recipe, new or saved, so a trainer whose recipes are all known still refreshes its position.
local function NoteVisit(npc)
	ns.NoteNPC(ns.db.npcs, npc.npcID, npc.name, npc.mapID, npc.x, npc.y, npc.seen)
	ns.NoteNPCFaction(npc.npcID, npc.npcFaction)
end

-- A source of another kind; field is the observation field that identifies it (object, container, fishing, zone, quest, or npc).
local function Source(field, value)
	return { field = field, value = value, faction = (UnitFactionGroup("player")), seen = GetServerTime() }
end

-- Details compared on every sighting; a missing field keeps its saved value. npc is a detail for quests (the giver), the identity otherwise.
local DETAIL_FIELDS = { "faction", "skill", "cost", "price", "limited", "spellID", "choice", "npc",
	"finisher", "giverItem", "map", "x", "y", "area", "instance" }

-- Adds or updates one self-found observation; returns isNew and whether anything besides the seen time changed (which bumps the revision).
local function Save(bucket, id, kind, npc, details)
	local observations = ns.db.found[bucket][id]
	if not observations then
		observations = {}
		ns.db.found[bucket][id] = observations
	end
	local observation = ns.FindSource(observations, { kind = kind, [npc.field] = npc.value,
		map = details.map, area = details.area, instance = details.instance })
	local isNew = observation == nil
	if isNew then
		observation = { kind = kind, [npc.field] = npc.value }
		table.insert(observations, observation)
	end
	details.faction = npc.faction
	local changed = isNew
	if kind == "drop" then
		-- Each loot window is one more time seen. A repeat alone is not a new revision: farming would
		-- add one per kill, and every reply walks them; the count goes out with the next real change.
		observation.count = (observation.count or 0) + 1
	end
	for _, field in ipairs(DETAIL_FIELDS) do
		if details[field] ~= nil and observation[field] ~= details[field] then
			observation[field] = details[field]
			changed = true
		end
	end
	-- No deletion on absence: a visit only refreshes seen time and build.
	observation.seen, observation.build = npc.seen, BUILD
	if changed then
		ns.MarkFind(observation, bucket == "items" and "item" or "recipe", id)
	end
	return isNew, changed
end

local function Announce(count, name)
	if count > 0 and ns.db.announceNewFinds then
		ns.toolkit:Say(ns.module, ns.voice.intake, count, name or UNKNOWN)
	end
end

-- A recipe item waits here until its tooltip data loads and names its recipe (ns.LinkPending).
local function NotePendingItem(itemID)
	if not ns.db.itemRecipe[itemID] and not ns.GetSeededRecipe(itemID) then
		ns.db.pendingItems[itemID] = ns.db.pendingItems[itemID] or {}
	end
end

local function IsRecipeItem(itemID)
	return itemID ~= nil and ns.IsRecipeItem(itemID) ~= nil
end

-- Some NPCs teach recipes without the profession trainer flag, so a service counts only when its spell belongs to a profession (docs/client-notes.md, "Trainers").
-- The scan reads what the window shows under the player's own filters and never sets one: a filter change makes Blizzard's trainer list
-- rebuild (TRAINER_UPDATE), which showed as a flicker (docs/client-notes.md, "Trainers").
local TRAINER_SERVICE_TYPES = { "available", "unavailable", "used" }

local trainerSpells = {} -- "npcID:service name" = spell, for this session
local trainerMisses = {} -- same key = tooltip reads that gave no spell; capped like an item that never answers
local trainerJob -- the scan in progress: { npc, professionTrainer, index, services, skipped, ... }

-- The first read of a trainer is a tooltip per service (about 1.5 ms each on the Deck, 23 to 33 ms in all), so it runs in steps of
-- TRAINER_STEP_MS, one frame apart; a trainer already read this session costs no tooltips. A step ends before a tooltip would pass the
-- 5 ms frame bar, so the budget is the bar less one tooltip (docs/client-notes.md, "Trainers").
local TRAINER_STEP_MS = 3
local TRAINER_MAX_RESTARTS = 5 -- the list changed under a scan this many times (filters, a purchase): stop and let the next update ask again
local FinishScan -- defined below, after Scan's pieces

local function EndTrainerJob(job)
	if trainerJob == job then trainerJob = nil end
end

local function Skip(job, reason)
	job.skipped[reason] = (job.skipped[reason] or 0) + 1
end

-- "used 1, no spell 2" for the trace.
local function SkippedText(skipped)
	local parts = {}
	for reason, n in pairs(skipped) do
		parts[#parts + 1] = reason .. " " .. n
	end
	table.sort(parts)
	return #parts > 0 and table.concat(parts, ", ") or "none"
end

-- Which of the player's filters hide a type of service, for the trace; they are only read.
local function HiddenTypes()
	local hidden = {}
	for _, serviceType in ipairs(TRAINER_SERVICE_TYPES) do
		if not GetTrainerServiceTypeFilter(serviceType) then
			hidden[#hidden + 1] = serviceType
		end
	end
	return #hidden > 0 and table.concat(hidden, ", ") or "none"
end

local function ReadTrainerService(job, index)
	local npc = job.npc
	local name, serviceType, _, _, _, category = GetTrainerServiceInfo(index)
	if not name then
		Skip(job, "no name yet")
	elseif serviceType == "header" then
		Skip(job, "header")
	elseif index == job.stepIndex then
		Skip(job, "rank step")
	elseif not category or category == "" then
		Skip(job, "no category")
	else
		local _, skillRank = GetTrainerServiceSkillReq(index)
		local cost = GetTrainerServiceCost(index)
		-- Forever's TooltipUtil.GetDisplayedSpell checks the tooltip type before reading id. One trainer's service of a name teaches the same
		-- spell, so it is read once per trainer and name a session; one that gave no spell is asked again only up to MAX_ITEM_ATTEMPTS.
		local key = npc.npcID .. ":" .. name
		local spellID = trainerSpells[key]
		if spellID == nil and (trainerMisses[key] or 0) < ns.MAX_ITEM_ATTEMPTS then
			--@debug@
			local tooltipStart = debugprofilestop()
			--@end-debug@
			local tooltip = C_TooltipInfo.GetTrainerService(index)
			--@debug@
			job.tooltipMs = job.tooltipMs + (debugprofilestop() - tooltipStart)
			--@end-debug@
			spellID = tooltip and tooltip.type == Enum.TooltipDataType.Spell and tooltip.id
			if spellID then
				trainerSpells[key] = spellID
			else
				trainerMisses[key] = (trainerMisses[key] or 0) + 1
				if trainerMisses[key] >= ns.MAX_ITEM_ATTEMPTS then
					ns.toolkit:Trace(ns.module, "TRAINER service %s of npc %d gave no spell %d times, not asked again this session", name, npc.npcID, trainerMisses[key])
				end
			end
		end
		-- No Spell tooltip means no recipe ID; skip it.
		if not spellID then
			Skip(job, "no spell")
		elseif job.professionTrainer or C_TradeSkillUI.GetTradeSkillLineForRecipe(spellID) then
			local isNew, updated = Save("recipes", spellID, "trainer", npc, { skill = skillRank, cost = cost })
			job.recipes = job.recipes + 1
			job.changed = job.changed or updated
			if isNew then job.count = job.count + 1 end
		else
			Skip(job, "not a profession")
		end
	end
end

local function TrainerStep(job)
	if trainerJob ~= job then return end -- the window closed or another trainer opened
	local started = debugprofilestop()
	-- The player changed a filter (or a purchase moved the list): the indices read so far are stale, so read again from the top. Services
	-- already asked for cost no tooltip (trainerSpells), so a restart is cheap.
	if job.stale then
		job.stale = nil
		job.restarts = job.restarts + 1
		if job.restarts > TRAINER_MAX_RESTARTS then
			ns.toolkit:Trace(ns.module, "TRAINER scan stopped after %d restarts: the list kept changing", TRAINER_MAX_RESTARTS)
			EndTrainerJob(job)
			return
		end
		ns.toolkit:Trace(ns.module, "TRAINER list changed at service %d of %d, read again from the top (restart %d)", job.index, job.services, job.restarts)
		job.services, job.stepIndex = GetNumTrainerServices(), GetTrainerServiceStepIndex()
		job.index, job.first, job.recipes, job.tooltipMs = 1, 1, 0, 0
		wipe(job.skipped)
	end
	job.steps = job.steps + 1
	while job.index <= job.services and (job.index == job.first or debugprofilestop() - started < TRAINER_STEP_MS) do
		ReadTrainerService(job, job.index)
		job.index = job.index + 1
	end
	local stepMs = debugprofilestop() - started
	job.ms = job.ms + stepMs
	job.worstMs = math.max(job.worstMs, stepMs)
	--@debug@
	ns.PerfMs("trainer scan step", debugprofilestop() - started)
	--@end-debug@
	if job.index <= job.services then
		job.first = job.index
		RunNextFrame(function() TrainerStep(job) end)
		return
	end
	-- The closing work is one step a frame (the rank read is a tooltip, the finish saves and redraws), each timed (docs/client-notes.md, "Trainers").
	local function Closing(name, work, after)
		RunNextFrame(function()
			if trainerJob ~= job then return end
			if job.stale then return TrainerStep(job) end
			local closeStart = debugprofilestop()
			work()
			local ms = debugprofilestop() - closeStart
			job.closingMs = job.closingMs + ms
			--@debug@
			ns.PerfMs("trainer scan " .. name, ms)
			--@end-debug@
			if after then after() end
		end)
	end
	Closing("rank", function()
		-- The trainer's next rank for this character (Blizzard's trainer window shows it apart, as its skill step).
		if job.professionTrainer and ns.NoteTrainerRank(job.npc.npcID) then
			job.rankNoted = true
		end
	end, function()
		Closing("visit", function()
			if job.rankNoted or job.recipes > 0 then NoteVisit(job.npc) end
		end, function()
			-- The job is over; the last step runs unguarded.
			EndTrainerJob(job)
			RunNextFrame(function()
				local finishStart = debugprofilestop()
				FinishScan(job.count, job.npc, job.changed)
				local ms = debugprofilestop() - finishStart
				--@debug@
				ns.PerfMs("trainer scan finish", ms)
				ns.PerfMs("trainer scan tooltips", job.tooltipMs)
				--@end-debug@
				ns.toolkit:Trace(ns.module, "TRAINER scan of %d services read in %d steps, %.1f ms (%.1f ms of tooltips, worst step %.1f ms), closed in %.1f ms and finished in %.1f ms; %d recipes, %d new; skipped: %s; filters off: %s; restarts %d",
					job.services, job.steps, job.ms, job.tooltipMs or 0, job.worstMs, job.closingMs, ms, job.recipes, job.count, SkippedText(job.skipped), HiddenTypes(), job.restarts)
			end)
		end)
	end)
end

-- Starts the scan; true when the services are there, false when the window has none yet (the caller asks again on the next update).
local function RecordTrainer()
	if not ns.db.selfFound then
		return true
	end
	local professionTrainer = IsTradeskillTrainer()
	local npc = CurrentNPC()
	if not npc then
		return true
	end
	if trainerJob then
		ns.toolkit:Trace(ns.module, "TRAINER scan already running, not started again")
		return true
	end
	local services = GetNumTrainerServices()
	if services == 0 then
		return false
	end
	local job = { npc = npc, professionTrainer = professionTrainer, index = 1, first = 1, services = services,
		-- A recipe has a category; a profession rank has none.
		stepIndex = GetTrainerServiceStepIndex(), count = 0, recipes = 0, changed = false, steps = 0, ms = 0, worstMs = 0, tooltipMs = 0, closingMs = 0, restarts = 0, skipped = {} }
	trainerJob = job
	local hidden = HiddenTypes()
	if hidden ~= "none" then
		-- Services of a hidden type are not in the list, so they are not seen and their count is not known without changing the filter.
		ns.toolkit:Trace(ns.module, "TRAINER filters off: %s; their services are not read this visit", hidden)
	end
	TrainerStep(job)
	return true
end

-- Vendor recipe items; also runs on MERCHANT_UPDATE, since a row's details can arrive after the window opens.
local missingItems = {}
local function RecordVendor()
	if not ns.db.selfFound then
		return 0
	end
	local npc = CurrentNPC()
	if not npc then
		return 0
	end
	local count, recipes = 0, 0
	local changed = false
	local items = GetMerchantNumItems()
	for index = 1, items do
		local itemID = GetMerchantItemID(index)
		if IsRecipeItem(itemID) then
			local info = C_MerchantFrame.GetItemInfo(index)
			-- The row can arrive after the window opens; MERCHANT_UPDATE reads it again.
			if not info then
				missingItems[itemID] = true
			end
			if info then
				NotePendingItem(itemID)
				local isNew, updated = Save("items", itemID, "vendor", npc, {
					spellID = info.spellID,
					price = info.price,
					limited = info.numAvailable >= 0,
				})
				recipes = recipes + 1
				changed = changed or updated
				if isNew then count = count + 1 end
			end
		end
	end
	if recipes > 0 then NoteVisit(npc) end
	return count, npc, items > 0, changed
end

-- Coalesce late names within the visit and report the total once; filter changes also fire TRAINER_UPDATE, so wait for service names.
local SCAN_DELAY = 0.2
local frame -- made below, once its handlers exist
local record, timer, visitNPC
local newSources = 0

local function FinishVisit()
	if timer then
		timer:Cancel()
		timer = nil
	end
	if trainerJob then
		ns.toolkit:Trace(ns.module, "TRAINER scan stopped at service %d of %d: the visit ended", trainerJob.index, trainerJob.services)
		EndTrainerJob(trainerJob)
	end
	Announce(newSources, visitNPC and (ns.GetNPC(visitNPC.npcID) or {}).name)
	newSources, visitNPC, record = 0, nil, nil
	wipe(missingItems)
	frame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
end

-- What follows a scan, whether it ran at once (a vendor) or in steps (a trainer).
function FinishScan(count, npc, changed)
	if next(missingItems) then
		frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	else
		frame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
	end
	if count > 0 then
		newSources, visitNPC = newSources + count, npc
	end
	if count > 0 or changed then
		ns.SourcesChanged()
	end
end

local function Scan()
	timer = nil
	wipe(missingItems)
	if record == RecordTrainer then
		return RecordTrainer()
	end
	--@debug@
	local perfStart = debugprofilestop()
	--@end-debug@
	local count, npc, ready, changed = record()
	--@debug@
	ns.Perf("vendor scan", perfStart)
	--@end-debug@
	FinishScan(count, npc, changed)
	return ready
end

local function OnVisitEvent(event, itemID)
	if event == "TRAINER_SHOW" or event == "MERCHANT_SHOW" then
		FinishVisit()
		record = event == "TRAINER_SHOW" and RecordTrainer or RecordVendor
		if not ns.db.selfFound or Scan() then
			return
		end
	elseif (event == "TRAINER_CLOSED" and record == RecordTrainer)
		or (event == "MERCHANT_CLOSED" and record == RecordVendor) then
		FinishVisit()
	elseif event == "TRAINER_UPDATE" and trainerJob then
		-- Filters and purchases fire it; a scan in progress reads again from the top.
		trainerJob.stale = true
		return
	elseif not ((record == RecordTrainer and (event == "TRAINER_SERVICE_INFO_NAME_UPDATE" or event == "TRAINER_UPDATE"))
		or (record == RecordVendor and (event == "MERCHANT_UPDATE" or missingItems[itemID]))) then
		return
	end
	if record and not timer then
		timer = C_Timer.NewTimer(SCAN_DELAY, Scan)
	end
end

local visitHandlers = {}
for _, event in ipairs({ "TRAINER_SHOW", "TRAINER_SERVICE_INFO_NAME_UPDATE", "TRAINER_UPDATE", "TRAINER_CLOSED", "MERCHANT_SHOW",
	"MERCHANT_UPDATE", "MERCHANT_CLOSED", "GET_ITEM_INFO_RECEIVED" }) do
	visitHandlers[event] = function(...)
		if ns.db then OnVisitEvent(event, ...) end
	end
end
-- The item event is asked for only while a scan waits on item data.
frame = ns.toolkit:EventFrame(ns.module, visitHandlers, { later = { GET_ITEM_INFO_RECEIVED = true } })

-- Loot windows, read once each; sources come from GetLootSourceInfo and fishing is kept by zone (docs/client-notes.md, "Loot, quests and vendors").
local castTarget, castAt, lootRead
-- An object's name is the target of the cast that opened it. Opening, mining and herb casts run at most
-- about five seconds, so an older cast was at something else and its target is not this object's name.
local OPEN_CAST_SECONDS = 6

-- Where a drop happened, by ID: the dungeon or raid when inside one, else the subzone at the spot
-- (docs/data.md, "Drops").
local function DropPlace(mapID, x, y)
	local inInstance, instanceType = IsInInstance()
	if inInstance and (instanceType == "party" or instanceType == "raid") then
		return nil, select(8, GetInstanceInfo())
	end
	local areas = mapID and x and C_MapExplorationInfo.GetExploredAreaIDsAtPosition(mapID, CreateVector2D(x, y))
	return areas and areas[1], nil
end

local function LootSource(guid)
	if not Readable(guid) then
		return nil
	end
	if IsFishingLoot() then
		local mapID, x, y = GetPlayerLocation()
		return mapID and Source("fishing", mapID), { map = mapID, x = x, y = y }, C_Spell.GetSpellName(ns.FISHING_SPELL_ID)
	end
	local unitType, id = GUID(guid)
	local mapID, x, y = GetPlayerLocation()
	if (unitType == "Creature" or unitType == "Vehicle") and id then
		-- The target's GUID and name can be secret (unit identity restricted); comparing one errors.
		local targetGUID = UnitGUID("target")
		local name = Readable(targetGUID) and targetGUID == guid and UnitName("target") or nil
		if not Readable(name) then name = nil end
		ns.NoteNPC(ns.db.npcs, id, name, mapID, x, y, GetServerTime())
		local area, instance = DropPlace(mapID, x, y)
		return Source("npc", id), { map = mapID, x = x, y = y, area = area, instance = instance }, (ns.GetNPC(id) or {}).name
	elseif unitType == "GameObject" and id then
		local name = castAt and GetTime() - castAt <= OPEN_CAST_SECONDS and castTarget or nil
		ns.NoteNPC(ns.db.objects, id, name, mapID, x, y, GetServerTime())
		local area, instance = DropPlace(mapID, x, y)
		return Source("object", id), { map = mapID, x = x, y = y, area = area, instance = instance },
			name or (ns.db.objects[id] or {}).name
	elseif unitType == "Item" then
		local itemID = C_Item.GetItemIDByGUID(guid)
		return itemID and Source("container", itemID), {}, itemID and C_Item.GetItemNameByID(itemID)
	end
end

-- Recipe items in the player's own loot window, by time, so a roll on the same item adds nothing.
local lootedAt = {}

local function ReadLoot()
	if lootRead or not ns.db or not ns.db.selfFound then
		return
	end
	lootRead = true
	-- One loot window is one sighting per recipe item and source, however many slots hold it.
	local counted, newItems, names, changed = {}, {}, {}, false
	for slot = 1, GetNumLootItems() do
		local link = GetLootSlotType(slot) == Enum.LootSlotType.Item and GetLootSlotLink(slot)
		local itemID = link and ns.IsRecipeItem(link)
		if itemID then
			local sources = { GetLootSourceInfo(slot) }
			for index = 1, #sources, 2 do
				local source, details, name = LootSource(sources[index])
				local key = source and ("%d %s %s"):format(itemID, source.field, tostring(source.value))
				if key and not counted[key] then
					counted[key] = true
					NotePendingItem(itemID)
					lootedAt[itemID] = GetTime()
					local isNew, updated = Save("items", itemID, "drop", source, details)
					changed = changed or updated
					if isNew then
						newItems[itemID] = true
						names[name or UNKNOWN] = true
					end
				end
			end
		end
	end
	-- The line names the source only when every new recipe came from it; otherwise the zone.
	local count, onlyName = 0, nil
	for _ in pairs(newItems) do count = count + 1 end
	for name in pairs(names) do onlyName = onlyName == nil and name or false end
	local mapID = C_Map.GetBestMapForUnit("player")
	local mapInfo = mapID and C_Map.GetMapInfo(mapID)
	Announce(count, onlyName or (mapInfo and mapInfo.name))
	if changed then
		ns.SourcesChanged()
	end
end

-- QUEST_DETAIL has the giver, QUEST_COMPLETE the finisher; both list rewards, and an item-started quest reports an Item GUID as giver.
local function ReadQuest(event)
	if not (ns.db and ns.db.selfFound) then
		return
	end
	local questID = GetQuestID()
	if not questID or questID == 0 then
		return
	end
	-- The quest NPC is saved only when the quest rewards a recipe (NoteQuestNPC).
	local details, questNPC = {}, nil
	local guid = UnitGUID("questnpc")
	local unitType, id = GUID(guid)
	if unitType then
		if unitType == "Creature" and id then
			local mapID, x, y = GetPlayerLocation()
			questNPC = { id, UnitName("questnpc"), mapID, x, y, GetServerTime(), faction = (UnitFactionGroup("questnpc")) }
			details[event == "QUEST_COMPLETE" and "finisher" or "npc"] = id
			-- A quest's place is where it is given; the turn-in may be elsewhere.
			if event == "QUEST_DETAIL" then details.map = mapID end
		elseif unitType == "Item" and event == "QUEST_DETAIL" then
			details.giverItem = C_Item.GetItemIDByGUID(guid)
		end
	end
	local count, changed = 0, false
	for _, kind in ipairs({ "reward", "choice" }) do
		local total = kind == "reward" and GetNumQuestRewards() or GetNumQuestChoices()
		for index = 1, total do
			local _, _, _, _, _, itemID = GetQuestItemInfo(kind, index)
			if IsRecipeItem(itemID) then
				NotePendingItem(itemID)
				if questNPC then
					ns.NoteNPC(ns.db.npcs, unpack(questNPC))
					ns.NoteNPCFaction(questNPC[1], questNPC.faction)
					questNPC = nil
				end
				local rowDetails = CopyTable(details)
				rowDetails.choice = kind == "choice"
				local isNew, updated = Save("items", itemID, "quest", Source("quest", questID), rowDetails)
				changed = changed or updated
				if isNew then count = count + 1 end
			end
		end
	end
	Announce(count, C_QuestLog.GetTitleForQuestID(questID))
	if changed then
		ns.SourcesChanged()
	end
end

-- A group roll names no source, so the find is kept by zone, read a moment later so the player's own loot window counts first.
local ROLL_SETTLE = 1 -- seconds before a roll is read
local ROLL_AFTER_LOOT = 120 -- a roll this soon after looting the same item is that drop

local function ReadRoll(rollID)
	if not (ns.db and ns.db.selfFound) then
		return
	end
	local link = GetLootRollItemLink(rollID)
	if not Readable(link) then
		return
	end
	local itemID = ns.IsRecipeItem(link)
	local looted = itemID and lootedAt[itemID]
	if not itemID or (looted and GetTime() - looted < ROLL_AFTER_LOOT) then
		return
	end
	local mapID = GetPlayerLocation()
	if not mapID then
		return
	end
	NotePendingItem(itemID)
	local isNew, updated = Save("items", itemID, "drop", Source("zone", mapID), { map = mapID })
	local mapInfo = C_Map.GetMapInfo(mapID)
	Announce(isNew and 1 or 0, mapInfo and mapInfo.name)
	if updated then
		ns.SourcesChanged()
	end
end

local function ReadLootWindow()
	--@debug@
	local perfStart = debugprofilestop()
	--@end-debug@
	ReadLoot()
	--@debug@
	ns.Perf("loot window", perfStart)
	--@end-debug@
end

local function ReadQuestWindow(event)
	--@debug@
	local perfStart = debugprofilestop()
	--@end-debug@
	ReadQuest(event)
	--@debug@
	ns.Perf("quest window", perfStart)
	--@end-debug@
end

ns.toolkit:EventFrame(ns.module, {
	START_LOOT_ROLL = function(rollID)
		C_Timer.After(ROLL_SETTLE, function() ReadRoll(rollID) end)
	end,
	UNIT_SPELLCAST_SENT = function(unit, target)
		if unit == "player" and ns.toolkit.Readable(target) then
			castTarget, castAt = target ~= "" and target or nil, GetTime()
		end
	end,
	LOOT_READY = ReadLootWindow,
	LOOT_OPENED = ReadLootWindow,
	LOOT_CLOSED = function()
		lootRead, castTarget, castAt = nil, nil, nil
	end,
	QUEST_DETAIL = function() ReadQuestWindow("QUEST_DETAIL") end,
	QUEST_COMPLETE = function() ReadQuestWindow("QUEST_COMPLETE") end,
})
