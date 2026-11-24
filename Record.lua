local _, ns = ...

-- Self Found: records where recipes come from, for every profession, into the self-found layer (Core.lua),
-- with the player's faction and position. Trainers by recipe ID from tooltips (another addon Scanner.lua).
-- Only Enum.ItemClass.Recipe items are kept; anything else costs one item-class check.

-- Positions are rounded to three decimals of the 0..1 map coordinate.
local COORDINATE_PRECISION = 1000

local function Round(value)
	return math.floor(value * COORDINATE_PRECISION + 0.5) / COORDINATE_PRECISION
end

local function GetPlayerLocation()
	local mapID = C_Map.GetBestMapForUnit("player")
	local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if not position then
		return mapID
	end
	local x, y = position:GetXY()
	return mapID, Round(x), Round(y)
end

local BUILD = ns.BUILD

-- The NPC being talked to, or nil when the client hides it (secret values). Its name and position are
-- saved by NoteVisit, and only for an NPC that has a recipe: every trainer and vendor passes through here.
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

-- Called when a scan found at least one recipe, new or already saved, so a trainer whose recipes are
-- all known still gets its position refreshed.
local function NoteVisit(npc)
	ns.NoteNPC(ns.db.npcs, npc.npcID, npc.name, npc.mapID, npc.x, npc.y, npc.seen)
	ns.NoteNPCFaction(npc.npcID, npc.npcFaction)
end

-- A source of another kind; field names the observation field that identifies it (object, container,
-- fishing, zone, quest, or npc for a creature).
local function Source(field, value)
	return { field = field, value = value, faction = (UnitFactionGroup("player")), seen = GetServerTime() }
end

-- Details compared on every sighting. A missing field keeps its saved value. npc is a detail for quests
-- (the giver), the identity otherwise.
local DETAIL_FIELDS = { "faction", "skill", "cost", "price", "limited", "spellID", "choice", "npc",
	"finisher", "giverItem", "map", "x", "y" }

-- Adds or updates one self-found observation. Returns isNew and whether anything besides the seen time
-- changed (which bumps the revision).
local function Save(bucket, id, kind, npc, details)
	local observations = ns.db.found[bucket][id]
	if not observations then
		observations = {}
		ns.db.found[bucket][id] = observations
	end
	local observation
	for _, existing in ipairs(observations) do
		if existing.kind == kind and existing[npc.field] == npc.value then
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
		ns.Log(ns.voice.intake:format(count, count == 1 and "source" or "sources", name or UNKNOWN))
	end
end

-- Recipe items wait in pendingItems until Unlearned.lua links them to a recipe ID.
-- A recipe item waits here until its tooltip data has loaded and names the recipe it teaches
-- (ns.LinkPending).
local function NotePendingItem(itemID)
	if not ns.db.itemRecipe[itemID] and not ns.GetSeededRecipe(itemID) then
		ns.db.pendingItems[itemID] = ns.db.pendingItems[itemID] or {}
	end
end

local function IsRecipeItem(itemID)
	return itemID ~= nil and ns.IsRecipeItem(itemID) ~= nil
end

-- Some NPCs teach recipes without the profession trainer flag, so at other trainers a service counts
-- only when its spell belongs to a profession (docs/client-notes.md, "Trainers"). All three filters
-- are on for the read, and the player's choice is put back after.
local TRAINER_SERVICE_TYPES = { "available", "unavailable", "used" }

local function RecordTrainer()
	if not ns.db.selfFound then
		return 0
	end
	local professionTrainer = IsTradeskillTrainer()
	local npc = CurrentNPC()
	if not npc then
		return 0
	end
	local savedFilter = {}
	for _, serviceType in ipairs(TRAINER_SERVICE_TYPES) do
		savedFilter[serviceType] = not not GetTrainerServiceTypeFilter(serviceType)
		if not savedFilter[serviceType] then
			SetTrainerServiceTypeFilter(serviceType, true)
		end
	end
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
			-- No Spell tooltip means no recipe ID to list; skip it.
			if spellID and (professionTrainer or C_TradeSkillUI.GetTradeSkillLineForRecipe(spellID)) then
				local isNew, updated = Save("recipes", spellID, "trainer", npc, { skill = skillRank, cost = cost })
				recipes = recipes + 1
				changed = changed or updated
				if isNew then count = count + 1 end
			end
		end
	end
	for serviceType, wasShown in pairs(savedFilter) do
		if not wasShown then
			SetTrainerServiceTypeFilter(serviceType, false)
		end
	end
	if recipes > 0 then NoteVisit(npc) end
	return count, npc, services > 0, changed
end

-- Vendor recipe items. A row's details can arrive after the window opens, so this also runs on
-- MERCHANT_UPDATE.
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
			-- The merchant's row can arrive after the window opens; MERCHANT_UPDATE reads it again.
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

-- Coalesce late names within the visit. Filter changes also fire TRAINER_UPDATE, so wait for service
-- names. Report the total once.
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

-- Loot windows, read once each. Sources come from GetLootSourceInfo; fishing is kept by zone
-- (docs/client-notes.md, "Loot, quests and vendors").
local castTarget, lootRead
local loot = CreateFrame("Frame")

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
		return Source("npc", id), { map = mapID }, (ns.GetNPC(id) or {}).name
	elseif unitType == "GameObject" and id then
		ns.NoteNPC(ns.db.objects, id, castTarget, mapID, x, y, GetServerTime())
		return Source("object", id), { map = mapID }, castTarget
	elseif unitType == "Item" then
		local itemID = C_Item.GetItemIDByGUID(guid)
		return itemID and Source("container", itemID), {}, itemID and C_Item.GetItemNameByID(itemID)
	end
end

-- Recipe items seen in the player's own loot window, by time, so a roll on the same item adds nothing.
local lootedAt = {}

local function ReadLoot()
	if lootRead or not ns.db or not ns.db.selfFound then
		return
	end
	lootRead = true
	local count, changed, sourceName = 0, false, nil
	for slot = 1, GetNumLootItems() do
		local link = GetLootSlotType(slot) == Enum.LootSlotType.Item and GetLootSlotLink(slot)
		local itemID = link and ns.IsRecipeItem(link)
		if itemID then
			local sources = { GetLootSourceInfo(slot) }
			for index = 1, #sources, 2 do
				local source, details, name = LootSource(sources[index])
				if source then
					NotePendingItem(itemID)
					lootedAt[itemID] = GetTime()
					local isNew, updated = Save("items", itemID, "drop", source, details)
					changed = changed or updated
					if isNew then
						count, sourceName = count + 1, name
					end
				end
			end
		end
	end
	Announce(count, sourceName)
	if changed then
		ns.SourcesChanged()
	end
end

-- QUEST_DETAIL has the giver, QUEST_COMPLETE the finisher; both list rewards (GetQuestItemInfo returns
-- the item ID before the name loads). Quests started from an item report an Item GUID as giver.
local function ReadQuest(event)
	if not (ns.db and ns.db.selfFound) then
		return
	end
	local questID = GetQuestID()
	if not questID or questID == 0 then
		return
	end
	-- The quest NPC is saved only when the quest rewards a recipe (NoteQuestNPC below).
	local details, questNPC = {}, nil
	local guid = UnitGUID("questnpc")
	if guid and not issecretvalue(guid) then
		local unitType, _, _, _, _, id = strsplit("-", guid)
		id = tonumber(id)
		if unitType == "Creature" and id then
			local mapID, x, y = GetPlayerLocation()
			questNPC = { id, UnitName("questnpc"), mapID, x, y, GetServerTime(), faction = (UnitFactionGroup("questnpc")) }
			details[event == "QUEST_COMPLETE" and "finisher" or "npc"] = id
			-- The quest's place is where it is given; the turn-in may be elsewhere.
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

-- A group roll on a recipe someone else looted: the roll names no source, so the find is kept by
-- zone. Read a moment later, so the player's own loot window is counted first.
local ROLL_SETTLE = 1        -- seconds before a roll is read
local ROLL_AFTER_LOOT = 120  -- a roll this soon after looting the same item is that same drop

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
