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

-- The NPC being talked to, or nil when the client hides it (secret values); saved by NoteVisit only for an NPC with a recipe.
local function CurrentNPC()
	local guid = UnitGUID("npc")
	if issecretvalue(guid) or not guid then
		return nil
	end
	local unitType, _, _, _, _, npcID = strsplit("-", guid)
	if unitType ~= "Creature" then
		return nil
	end
	npcID = tonumber(npcID)
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
	local observation
	for _, existing in ipairs(observations) do
		-- A drop is one creature in one place: the same creature elsewhere is a separate sighting.
		if existing.kind == kind and existing[npc.field] == npc.value and (kind ~= "drop" or ns.SamePlace(existing, details)) then
			observation = existing
			break
		end
	end
	local isNew = observation == nil
	if isNew then
		observation = { kind = kind, [npc.field] = npc.value }
		table.insert(observations, observation)
	end
	details.faction = npc.faction
	local changed = isNew
	if kind == "drop" then
		observation.count = (observation.count or 0) + 1 -- each loot window is one more time seen
		changed = true
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
		local intake = ns.voice.intake
		ns.Say(intake.noise, (count == 1 and intake.reportOne or intake.report):format(count, name or UNKNOWN))
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
-- All three filters are on for the read; the player's choice is put back after.
local TRAINER_SERVICE_TYPES = { "available", "unavailable", "used" }

-- Runs read with every trainer service shown, then restores the player's filter, also when read fails; read is given the old filter.
function ns.WithAllTrainerServices(read)
	local shown = {}
	for _, serviceType in ipairs(TRAINER_SERVICE_TYPES) do
		shown[serviceType] = not not GetTrainerServiceTypeFilter(serviceType)
		if not shown[serviceType] then
			SetTrainerServiceTypeFilter(serviceType, true)
		end
	end
	local ok, first, second, third, fourth = pcall(read, shown)
	for serviceType, wasShown in pairs(shown) do
		if not wasShown then
			SetTrainerServiceTypeFilter(serviceType, false)
		end
	end
	if not ok then
		error(first, 0)
	end
	return first, second, third, fourth
end

local ReadTrainerServices

local function RecordTrainer()
	if not ns.db.selfFound then
		return 0
	end
	local professionTrainer = IsTradeskillTrainer()
	local npc = CurrentNPC()
	if not npc then
		return 0
	end
	return ns.WithAllTrainerServices(function()
		return ReadTrainerServices(npc, professionTrainer)
	end)
end

function ReadTrainerServices(npc, professionTrainer)
	local count, recipes = 0, 0
	local changed = false
	local services = GetNumTrainerServices()
	-- A recipe has a category; a profession rank has none.
	local stepIndex = GetTrainerServiceStepIndex()
	for index = 1, services do
		local name, serviceType, _, _, _, category = GetTrainerServiceInfo(index)
		if name and serviceType ~= "header" and index ~= stepIndex and category and category ~= "" then
			local _, skillRank = GetTrainerServiceSkillReq(index)
			local cost = GetTrainerServiceCost(index)
			-- Forever's TooltipUtil.GetDisplayedSpell checks the tooltip type before reading id.
			local tooltip = C_TooltipInfo.GetTrainerService(index)
			local spellID = tooltip and tooltip.type == Enum.TooltipDataType.Spell and tooltip.id
			-- No Spell tooltip means no recipe ID; skip it.
			if spellID and (professionTrainer or C_TradeSkillUI.GetTradeSkillLineForRecipe(spellID)) then
				local isNew, updated = Save("recipes", spellID, "trainer", npc, { skill = skillRank, cost = cost })
				recipes = recipes + 1
				changed = changed or updated
				if isNew then count = count + 1 end
			end
		end
	end
	-- The trainer's next rank for this character (Blizzard's trainer window shows it apart, as its skill step).
	if professionTrainer and ns.NoteTrainerRank(npc.npcID) then
		NoteVisit(npc)
	end
	if recipes > 0 then NoteVisit(npc) end
	return count, npc, services > 0, changed
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
local frame = CreateFrame("Frame")
local record, timer, visitNPC
local newSources = 0

local function FinishVisit()
	if timer then
		timer:Cancel()
		timer = nil
	end
	Announce(newSources, visitNPC and (ns.GetNPC(visitNPC.npcID) or {}).name)
	newSources, visitNPC, record = 0, nil, nil
	wipe(missingItems)
	frame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
end

local function Scan()
	timer = nil
	wipe(missingItems)
	--@debug@
	local perfStart, perfName = debugprofilestop(), record == RecordTrainer and "trainer scan" or "vendor scan"
	--@end-debug@
	local count, npc, ready, changed = record()
	--@debug@
	ns.Perf(perfName, perfStart)
	--@end-debug@
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
	return ready
end

frame:RegisterEvent("TRAINER_SHOW")
frame:RegisterEvent("TRAINER_SERVICE_INFO_NAME_UPDATE")
frame:RegisterEvent("TRAINER_CLOSED")
frame:RegisterEvent("MERCHANT_SHOW")
frame:RegisterEvent("MERCHANT_UPDATE")
frame:RegisterEvent("MERCHANT_CLOSED")
frame:SetScript("OnEvent", function(_, event, itemID)
	if not ns.db then
		return
	end
	if event == "TRAINER_SHOW" or event == "MERCHANT_SHOW" then
		FinishVisit()
		record = event == "TRAINER_SHOW" and RecordTrainer or RecordVendor
		if not ns.db.selfFound or Scan() then
			return
		end
	elseif (event == "TRAINER_CLOSED" and record == RecordTrainer)
		or (event == "MERCHANT_CLOSED" and record == RecordVendor) then
		FinishVisit()
	elseif not ((record == RecordTrainer and event == "TRAINER_SERVICE_INFO_NAME_UPDATE")
		or (record == RecordVendor and (event == "MERCHANT_UPDATE" or missingItems[itemID]))) then
		return
	end
	if record and not timer then
		timer = C_Timer.NewTimer(SCAN_DELAY, Scan)
	end
end)

-- Loot windows, read once each; sources come from GetLootSourceInfo and fishing is kept by zone (docs/client-notes.md, "Loot, quests and vendors").
local castTarget, lootRead
local loot = CreateFrame("Frame")

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
	if not guid or issecretvalue(guid) then
		return nil
	end
	if IsFishingLoot() then
		local mapID, x, y = GetPlayerLocation()
		return mapID and Source("fishing", mapID), { map = mapID, x = x, y = y }, C_Spell.GetSpellName(ns.FISHING_SPELL_ID)
	end
	local unitType, _, _, _, _, id = strsplit("-", guid)
	local mapID, x, y = GetPlayerLocation()
	id = tonumber(id)
	if (unitType == "Creature" or unitType == "Vehicle") and id then
		-- The target's GUID and name can be secret (unit identity restricted); comparing one errors.
		local targetGUID = UnitGUID("target")
		local name = not issecretvalue(targetGUID) and targetGUID == guid and UnitName("target") or nil
		if issecretvalue(name) then name = nil end
		ns.NoteNPC(ns.db.npcs, id, name, mapID, x, y, GetServerTime())
		local area, instance = DropPlace(mapID, x, y)
		return Source("npc", id), { map = mapID, x = x, y = y, area = area, instance = instance }, (ns.GetNPC(id) or {}).name
	elseif unitType == "GameObject" and id then
		ns.NoteNPC(ns.db.objects, id, castTarget, mapID, x, y, GetServerTime())
		local area, instance = DropPlace(mapID, x, y)
		return Source("object", id), { map = mapID, x = x, y = y, area = area, instance = instance }, castTarget
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
	if guid and not issecretvalue(guid) then
		local unitType, _, _, _, _, id = strsplit("-", guid)
		id = tonumber(id)
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
	if not link or issecretvalue(link) then
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

loot:RegisterEvent("START_LOOT_ROLL")
loot:RegisterEvent("UNIT_SPELLCAST_SENT")
loot:RegisterEvent("LOOT_READY")
loot:RegisterEvent("LOOT_OPENED")
loot:RegisterEvent("LOOT_CLOSED")
loot:RegisterEvent("QUEST_DETAIL")
loot:RegisterEvent("QUEST_COMPLETE")
loot:SetScript("OnEvent", function(_, event, unit, target)
	if event == "UNIT_SPELLCAST_SENT" then
		if unit == "player" and not issecretvalue(target) then
			castTarget = target ~= "" and target or nil
		end
	elseif event == "LOOT_CLOSED" then
		lootRead, castTarget = nil, nil
	elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
		--@debug@
		local perfStart = debugprofilestop()
		--@end-debug@
		ReadLoot()
		--@debug@
		ns.Perf("loot window", perfStart)
		--@end-debug@
	elseif event == "START_LOOT_ROLL" then
		local rollID = unit
		C_Timer.After(ROLL_SETTLE, function() ReadRoll(rollID) end)
	else
		--@debug@
		local perfStart = debugprofilestop()
		--@end-debug@
		ReadQuest(event)
		--@debug@
		ns.Perf("quest window", perfStart)
		--@end-debug@
	end
end)
