local addonName, ns = ...

-- Self Found: records where recipes come from, for every profession, into the self-found layer (Core.lua),
-- with the player's faction and position. Trainers by recipe ID from tooltips (another addon Scanner.lua).
-- Only Enum.ItemClass.Recipe items are kept; anything else costs one item-class check.

local RECIPE_ITEM_CLASS = Enum.ItemClass.Recipe

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

local BUILD = tonumber((select(2, GetBuildInfo())))

-- The NPC being talked to, or nil when the client hides it (secret values). Name and position go into
-- the NPC table once per scan.
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
	ns.NoteNPC(ns.db.npcs, npcID, UnitName("npc"), mapID, x, y, seen)
	return { field = "npc", value = npcID, npcID = npcID, faction = (UnitFactionGroup("player")), seen = seen }
end

-- A source of another kind; field names the observation field that identifies it (object, container,
-- fishing, quest, or npc for a creature).
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
		local system = ChatTypeInfo.SYSTEM
		DEFAULT_CHAT_FRAME:AddMessage(("%s: %d new recipe %s from %s."):format(
			C_AddOns.GetAddOnMetadata(addonName, "Title"), count, count == 1 and "source" or "sources",
			name or UNKNOWN), system.r, system.g, system.b)
	end
end

-- Recipe items wait in pendingItems until Unlearned.lua links them to a recipe ID.
local function NotePendingItem(itemID, recipeName, spellID)
	if not ns.db.itemRecipe[itemID] then
		local pending = ns.db.pendingItems[itemID] or {}
		pending.name = recipeName or pending.name
		pending.spellID = spellID or pending.spellID
		ns.db.pendingItems[itemID] = pending
	end
end

local function IsRecipeItem(itemID)
	if not itemID then return false end
	local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
	return classID == RECIPE_ITEM_CLASS
end

-- IsTradeskillTrainer() is true for profession trainers. The window's filter hides known recipes, so
-- turn on all three service types for the scan, as its checkboxes do, and restore the player's choice
-- after.
local TRAINER_SERVICE_TYPES = { "available", "unavailable", "used" }

local function RecordTrainer()
	if not ns.db.selfFound or not IsTradeskillTrainer() then
		return 0
	end
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
	local count = 0
	local changed = false
	local services = GetNumTrainerServices()
	-- The profession rank ("Journeyman Tailoring") is a service too; the window shows it apart
	-- (GetTrainerServiceStepIndex). Read it with all filters on.
	local stepIndex = GetTrainerServiceStepIndex()
	for index = 1, services do
		local name, serviceType = GetTrainerServiceInfo(index)
		if name and serviceType ~= "header" and index ~= stepIndex then
			local _, skillRank = GetTrainerServiceSkillReq(index)
			local cost = GetTrainerServiceCost(index)
			-- Forever's TooltipUtil.GetDisplayedSpell checks the tooltip type before reading id.
			local tooltip = C_TooltipInfo.GetTrainerService(index)
			local spellID = tooltip and tooltip.type == Enum.TooltipDataType.Spell and tooltip.id
			-- No Spell tooltip means no recipe ID to list; skip it.
			if spellID then
				local isNew, updated = Save("recipes", spellID, "trainer", npc, { skill = skillRank, cost = cost })
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
	return count, npc, services > 0, changed
end

-- Vendor recipe items ("Pattern: Red Linen Bag" teaches "Red Linen Bag"). Names can arrive after the
-- window opens, so this also runs on MERCHANT_UPDATE.
local missingItems = {}
local function RecordVendor()
	if not ns.db.selfFound then
		return 0
	end
	local npc = CurrentNPC()
	if not npc then
		return 0
	end
	local count = 0
	local changed = false
	local items = GetMerchantNumItems()
	for index = 1, items do
		local itemID = GetMerchantItemID(index)
		if IsRecipeItem(itemID) then
			local info = C_MerchantFrame.GetItemInfo(index)
			local itemName = info and info.name
			if not itemName then
				missingItems[itemID] = true
			end
			-- Unlearned.lua links the item to its recipe when the profession opens.
			local recipeName = itemName and (itemName:match("^.-:%s*(.+)$") or itemName)
			if recipeName then
				NotePendingItem(itemID, recipeName:lower(), info.spellID)
			end
			if recipeName then
				local isNew, updated = Save("items", itemID, "vendor", npc, {
					spellID = info.spellID,
					price = info.price,
					limited = info.numAvailable >= 0,
				})
				changed = changed or updated
				if isNew then count = count + 1 end
			end
		end
	end
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
	local count, npc, ready, changed = record()
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

-- Loot windows. LOOT_READY can fire twice before LOOT_OPENED, so each window is read once (Rarity
-- Core/EventHandlers.lua). Sources from GetLootSourceInfo, as Wowhead Looter reads them: field 6 of a
-- Creature or GameObject GUID is its ID; a bag container is an Item GUID (C_Item.GetItemIDByGUID).
-- Fishing loot comes from the bobber, so it is kept by zone. Object names come from the spell cast to open them.
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

local function ReadLoot()
	if lootRead or not ns.db or not ns.db.selfFound then
		return
	end
	lootRead = true
	local count, changed, sourceName = 0, false, nil
	for slot = 1, GetNumLootItems() do
		local link = GetLootSlotType(slot) == Enum.LootSlotType.Item and GetLootSlotLink(slot)
		local itemID = link and C_Item.GetItemInfoInstant(link)
		if IsRecipeItem(itemID) then
			local sources = { GetLootSourceInfo(slot) }
			for index = 1, #sources, 2 do
				local source, details, name = LootSource(sources[index])
				if source then
					NotePendingItem(itemID)
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
	local details = {}
	local guid = UnitGUID("questnpc")
	if guid and not issecretvalue(guid) then
		local unitType, _, _, _, _, id = strsplit("-", guid)
		id = tonumber(id)
		if unitType == "Creature" and id then
			local mapID, x, y = GetPlayerLocation()
			ns.NoteNPC(ns.db.npcs, id, UnitName("questnpc"), mapID, x, y, GetServerTime())
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
		ReadLoot()
	else
		ReadQuest(event)
	end
end)
