local addonName, ns = ...

-- Self Found: when a trainer or vendor window opens, save the recipes it teaches or sells,
-- for every profession, with the NPC, the player's faction and where the player stands.
-- Keys follow another addon's scanner (see Sources.lua): recipe IDs from trainer service
-- tooltips, item IDs for recipe items sold by vendors.

local RECIPE_ITEM_CLASS = Enum.ItemClass.Recipe

local function GetPlayerLocation()
	local mapID = C_Map.GetBestMapForUnit("player")
	local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if not position then
		return mapID
	end
	local x, y = position:GetXY()
	return mapID, math.floor(x * 1000 + 0.5) / 1000, math.floor(y * 1000 + 0.5) / 1000
end

-- The NPC the player is talking to, or nil when the client keeps it hidden (secret values).
local function GetNPC()
	local guid = UnitGUID("npc")
	if issecretvalue(guid) or not guid then
		return nil
	end
	local unitType, _, _, _, _, npcID = strsplit("-", guid)
	if unitType ~= "Creature" then
		return nil
	end
	local mapID, x, y = GetPlayerLocation()
	return {
		npcID = tonumber(npcID), npcName = UnitName("npc"), faction = (UnitFactionGroup("player")),
		mapID = mapID, x = x, y = y, seen = time(),
	}
end

-- Adds or updates one source; returns true when it is new. npc carries the NPC and where
-- the player stood, looked up once per scan.
local function Save(key, sourceType, npc, details)
	local entries = ns.db.sources[key]
	if not entries then
		entries = {}
		ns.db.sources[key] = entries
	end
	local entry
	for _, existing in ipairs(entries) do
		if existing.type == sourceType and existing.npcID == npc.npcID then
			entry = existing
			break
		end
	end
	local isNew = entry == nil
	if isNew then
		entry = {}
		table.insert(entries, entry)
	end
	local firsthand = entry.origin ~= "self"
	if firsthand then
		wipe(entry)
		entry.type, entry.origin, entry.npcID = sourceType, "self", npc.npcID
	end
	local betterID = details.spellID and details.spellID ~= entry.spellID
	entry.npcName = npc.npcName
	entry.mapID, entry.x, entry.y = npc.mapID, npc.x, npc.y
	entry.faction = npc.faction
	entry.seen = npc.seen
	for field, value in pairs(details) do
		entry[field] = value
	end
	if firsthand or betterID then
		ns.MarkFind(key, entry)
	end
	return isNew, firsthand or betterID
end

local function Announce(count, npc)
	if count > 0 and npc and ns.db.announceNewFinds then
		local system = ChatTypeInfo.SYSTEM
		DEFAULT_CHAT_FRAME:AddMessage(("%s: %d new recipe %s from %s."):format(
			C_AddOns.GetAddOnMetadata(addonName, "Title"), count, count == 1 and "source" or "sources",
			npc.npcName or UNKNOWN), system.r, system.g, system.b)
	end
end

-- Trainer windows list what the trainer teaches; IsTradeskillTrainer() is true for
-- profession trainers. The list follows the trainer window's own filter, which hides
-- recipes the player already knows by default, so turn on all three service types for the
-- scan (as the window's own checkboxes do) and put the player's choice back after.
local TRAINER_SERVICE_TYPES = { "available", "unavailable", "used" }

local function RemoveTrainerFallback(key, npcID, skill)
	local entries = ns.db.sources[key]
	if entries then
		for index, entry in ipairs(entries) do
			if entry.type == "trainer" and entry.npcID == npcID and entry.skill == skill then
				ns.ForgetFind(entry)
				table.remove(entries, index)
				if #entries == 0 then
					ns.db.sources[key] = nil
				end
				return true
			end
		end
	end
end

local function RecordTrainer()
	if not ns.db.selfFound or not IsTradeskillTrainer() then
		return 0
	end
	local npc = GetNPC()
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
	-- The profession rank ("Journeyman Tailoring") is a service too; Blizzard's trainer
	-- window shows it apart, by GetTrainerServiceStepIndex(). Read it with all filters on.
	local stepIndex = GetTrainerServiceStepIndex()
	for index = 1, services do
		local name, serviceType = GetTrainerServiceInfo(index)
		if name and serviceType ~= "header" and index ~= stepIndex then
			local _, skillRank = GetTrainerServiceSkillReq(index)
			local cost = GetTrainerServiceCost(index)
			-- Forever's TooltipUtil.GetDisplayedSpell checks the tooltip type before reading id.
			local tooltip = C_TooltipInfo.GetTrainerService(index)
			local spellID = tooltip and tooltip.type == Enum.TooltipDataType.Spell and tooltip.id
			local nameKey = ns.NameKey(name)
			local isNew, updated = Save(spellID or nameKey, "trainer", npc, { skill = skillRank, cost = cost, name = name })
			changed = changed or updated
			if spellID and RemoveTrainerFallback(nameKey, npc.npcID, skillRank) then
				changed = true
			elseif isNew then
				count = count + 1
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

-- Vendor windows: every recipe item for sale ("Pattern: Red Linen Bag" teaches "Red Linen
-- Bag"). Item names can arrive after the window opens, so this also runs on MERCHANT_UPDATE.
local missingItems = {}
local function RecordVendor()
	if not ns.db.selfFound then
		return 0
	end
	local npc = GetNPC()
	if not npc then
		return 0
	end
	local count = 0
	local changed = false
	local items = GetMerchantNumItems()
	for index = 1, items do
		local itemID = GetMerchantItemID(index)
		local classID = itemID and select(6, C_Item.GetItemInfoInstant(itemID))
		if classID == RECIPE_ITEM_CLASS then
			local info = C_MerchantFrame.GetItemInfo(index)
			local itemName = info and info.name
			if not itemName then
				missingItems[itemID] = true
			end
			-- "Pattern: Red Linen Bag" teaches "Red Linen Bag"; Unlearned.lua links the item to
			-- its recipe ID when the profession is opened.
			local recipeName = itemName and (itemName:match("^.-:%s*(.+)$") or itemName)
			if recipeName and not ns.db.itemRecipe[itemID] then
				ns.db.pendingItems[itemID] = { name = recipeName:lower(), spellID = info.spellID }
			end
			if recipeName then
				local isNew, updated = Save(ns.ItemKey(itemID), "vendor", npc, {
					itemID = itemID,
					itemName = itemName,
					recipeName = recipeName,
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

-- Coalesce late names within the visit. Trainer filter changes fire TRAINER_UPDATE, so
-- listen specifically for service names. Report the total once the visit finishes.
local SCAN_DELAY = 0.2
local frame = CreateFrame("Frame")
local record, timer, visitNPC
local newSources = 0

local function FinishVisit()
	if timer then
		timer:Cancel()
		timer = nil
	end
	Announce(newSources, visitNPC)
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
