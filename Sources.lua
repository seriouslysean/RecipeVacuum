local _, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale("RecipeVacuum")

-- Bumped on every change to the known sources, so cached results can tell they are stale.
ns.sourcesVersion = 0

function ns.SourcesChanged()
	ns.sourcesVersion = ns.sourcesVersion + 1
	ns.ClearUnlearnedCache()
	local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
	if page and page:IsVisible() and ns.db.showUnlearned and ns.CanShowUnlearned() then
		ns.RefreshList()
	end
end

ns.sourceOrder = { "trainer", "vendor", "quest", "drop" }

-- Labels reuse Blizzard's localized source names; marks are Blizzard art, size is the drawn height (docs/client-notes.md, "Requirements").
ns.sourceTypes = {
	trainer = { label = L["Trainer"],                     atlas = "Class", size = 14 },
	vendor  = { label = BATTLE_PET_SOURCE_3 or "Vendor", atlas = "Auctioneer", size = 14 },
	quest   = { label = BATTLE_PET_SOURCE_2 or "Quest",  texture = "Interface\\GossipFrame\\AvailableQuestIcon", size = 16 },
	drop    = { label = BATTLE_PET_SOURCE_1 or "Drop",   atlas = "lootroll-icon-need", size = 14 },
}

-- Self Found shows only the player's own finds (docs/data.md).
local function VisibleLayers()
	local db = ns.db
	if db.sourceLevel >= ns.LEVEL.FRIENDS then
		return db.found, db.shared, ns.included
	end
	return db.found
end

function ns.GetNPC(npcID)
	return npcID and (ns.db.npcs[npcID] or ns.included.npcs[npcID])
end

local function GetObject(objectID)
	return ns.db.objects[objectID] or ns.included.objects[objectID]
end

-- Name and positions ({ [mapID] = { x, y, seen } }) of an observation, plus a map ID when it has no position (instance drops).
-- Names come from the client where it can say them (items, quests, the Fishing spell), else the saved NPC and object tables.
-- A drop's own spot, where that creature was killed for this recipe; other sources use the NPC's.
local function OwnPosition(observation)
	if observation.kind == "drop" and observation.x and observation.map then
		return { [observation.map] = { x = observation.x, y = observation.y, seen = observation.seen } }
	end
end

function ns.SourceInfo(observation)
	if observation.quest then
		local giver = ns.GetNPC(observation.npc) or ns.GetNPC(observation.finisher)
		return C_QuestLog.GetTitleForQuestID(observation.quest) or ("%s %d"):format(QUEST or "Quest", observation.quest),
			giver and giver.positions, observation.map
	elseif observation.object then
		local object = GetObject(observation.object)
		local positions = OwnPosition(observation)
		if observation.kind ~= "drop" then positions = positions or object and object.positions end
		return object and object.name, positions, observation.map
	elseif observation.container then
		return C_Item.GetItemNameByID(observation.container), nil, nil
	elseif observation.fishing then
		local positions = observation.x and { [observation.fishing] = { x = observation.x, y = observation.y, seen = observation.seen } }
		return C_Spell.GetSpellName(ns.FISHING_SPELL_ID), positions, observation.fishing
	elseif observation.zone then
		-- A group-roll drop: the zone is known, what dropped it is not.
		return UNKNOWN, nil, observation.zone
	end
	local npc = ns.GetNPC(observation.npc)
	-- A drop is placed by its own spot only; without one it keeps its map and gets no pin .
	local positions = OwnPosition(observation)
	if observation.kind ~= "drop" then positions = positions or npc and npc.positions end
	return npc and npc.name, positions, observation.map
end

-- Drop scope from sightings; why these thresholds: docs/data.md, "Drops".
local ZONE_DROP_CREATURES = 2 -- creature types in one zone or dungeon for a zone drop
local WORLD_DROP_ZONES = 3    -- zones or dungeons for a world drop
local DROP_SCOPE_LABELS = {
	single = BATTLE_PET_SOURCE_1 or "Drop",
	zone = L["Zone Drop"],             -- no Blizzard string
	world = TRANSMOG_SOURCE_4 or "World Drop",
	mixed = BATTLE_PET_SOURCE_1 or "Drop",
}

-- The place a drop counts in: its dungeon, else its zone (a group roll knows only the zone).
local function DropZone(observation)
	if observation.instance then
		return "instance", observation.instance
	end
	local zone = observation.map or observation.zone
	return zone and "map", zone
end

-- Scope of a recipe's drops: single, zone, world or mixed, with the evidence behind it. Fishing and
-- container drops keep their own lines and do not count toward scope.
function ns.DropScope(entries)
	local creatures, places, times, placeCount, creatureCount = {}, {}, 0, 0, 0
	local onlyPlace
	for _, observation in ipairs(entries or {}) do
		if observation.kind == "drop" and not observation.fishing and not observation.container then
			local creature = observation.npc and ("npc" .. observation.npc) or observation.object and ("object" .. observation.object)
			if creature and not creatures[creature] then
				creatures[creature], creatureCount = true, creatureCount + 1
			end
			local kind, place = DropZone(observation)
			if place and not places[kind .. place] then
				places[kind .. place], placeCount = { kind = kind, id = place }, placeCount + 1
				onlyPlace = places[kind .. place]
			end
			times = times + (observation.count or 1)
		end
	end
	if times == 0 then
		return nil
	end
	local scope = "mixed"
	if placeCount >= WORLD_DROP_ZONES then
		scope = "world"
	elseif creatureCount >= ZONE_DROP_CREATURES and placeCount == 1 then
		scope = "zone"
	elseif creatureCount == 1 then
		scope = "single"
	end
	return { scope = scope, times = times, creatures = creatureCount, places = placeCount, place = placeCount == 1 and onlyPlace or nil }
end

function ns.DropPlaceName(kind, id)
	if kind == "instance" then
		return GetRealZoneText(id)
	end
	local mapInfo = C_Map.GetMapInfo(id)
	return mapInfo and mapInfo.name or UNKNOWN
end

function ns.NewestPosition(positions)
	local newestMap, newest
	for mapID, position in pairs(positions or {}) do
		if not newest or (position.seen or 0) > (newest.seen or 0) then
			newestMap, newest = mapID, position
		end
	end
	return newestMap, newest
end

-- The fields that identify a source (Core.lua); for a quest the NPC is a detail.
-- Two drops are in the same place when map, subzone and dungeon all match.
function ns.SamePlace(a, b)
	return a.map == b.map and a.area == b.area and a.instance == b.instance
end

local function SameSource(a, b)
	if a.kind ~= b.kind then return false end
	if a.quest or b.quest then return a.quest == b.quest end
	return a.npc == b.npc and a.object == b.object and a.container == b.container and a.fishing == b.fishing
		and a.zone == b.zone and (a.kind ~= "drop" or ns.SamePlace(a, b))
end

-- A source found by the player and a peer is in two layers; the first layer read wins.
local function AppendOnce(list, observation)
	for _, listed in ipairs(list) do
		if SameSource(listed, observation) then return end
	end
	table.insert(list, observation)
end

local function AppendLayer(list, layer, recipeInfo, itemIDs)
	if not layer then return end
	for _, observation in ipairs(layer.recipes[recipeInfo.recipeID] or {}) do
		AppendOnce(list, observation)
	end
	for _, itemID in ipairs(itemIDs or {}) do
		for _, observation in ipairs(layer.items[itemID] or {}) do
			AppendOnce(list, observation)
		end
	end
end

function ns.GetSources(recipeInfo)
	if not ns.db then
		return nil
	end
	local list = {}
	local itemIDs = ns.GetRecipeItems(recipeInfo.recipeID)
	local found, shared, included = VisibleLayers()
	AppendLayer(list, found, recipeInfo, itemIDs)
	AppendLayer(list, shared, recipeInfo, itemIDs)
	AppendLayer(list, included, recipeInfo, itemIDs)
	return #list > 0 and list or nil
end

-- The recipe that makes an item: this session's scan first, then the seed (docs/data.md, "Come across").
function ns.GetMadeRecipe(itemID)
	local made = ns.scannedMade and ns.scannedMade[itemID]
	return made or (ns.seed and ns.seed.made and ns.seed.made[itemID]) or nil
end

-- Every source recorded for one item, across the visible layers.
function ns.GetItemSources(itemID)
	local list = {}
	local found, shared, included = VisibleLayers()
	local none = { recipeID = 0 }
	AppendLayer(list, found, none, { itemID })
	AppendLayer(list, shared, none, { itemID })
	AppendLayer(list, included, none, { itemID })
	return list
end

-- Instant client lookup, no server request.
function ns.IsRecipeItem(item)
	local itemID, _, _, _, _, classID = C_Item.GetItemInfoInstant(item)
	return classID == Enum.ItemClass.Recipe and itemID or nil
end

-- The nearest level at which a recipe, or an item that teaches it, was come across; nil if never.
function ns.MetLevel(recipeID)
	local met = ns.db.met
	local level = met.recipes[recipeID]
	for _, itemID in ipairs(ns.GetRecipeItems(recipeID) or {}) do
		local itemLevel = met.items[itemID]
		if itemLevel and (not level or itemLevel < level) then
			level = itemLevel
		end
	end
	return level
end

-- Caches sourceTypes (nil when no source is known) and met on the recipe, so redraws and filtering read fields.
function ns.SummarizeSources(recipeInfo)
	recipeInfo.sourceTypes = nil
	recipeInfo.met = ns.MetLevel(recipeInfo.recipeID)
	local entries = ns.GetSources(recipeInfo)
	if not entries then
		return
	end
	local types = {}
	for _, entry in ipairs(entries) do
		types[entry.kind] = true
	end
	recipeInfo.sourceTypes = types
end

-- Recipes with a known source show unless their type is unticked; those without show only when Unknown is ticked or they were come across.
ns.sourceFilterKeys = { "trainer", "vendor", "quest", "drop", "unknown" }

function ns.IsSourceShown(key)
	local shown = ns.db.sourceFilter[key]
	if shown == nil then
		return key ~= "unknown"
	end
	return shown
end

function ns.PassesSourceFilter(recipeInfo)
	local types = recipeInfo.sourceTypes
	if not types then
		-- No known source: shown once come across within the level, or with Unknown ticked; unticked by hand (as Uncheck All does) hides them all.
		local unknown = ns.db.sourceFilter.unknown
		return unknown or (unknown == nil and recipeInfo.met ~= nil and recipeInfo.met <= ns.db.sourceLevel)
	end
	for sourceType in pairs(types) do
		if ns.IsSourceShown(sourceType) then
			return true
		end
	end
	return false
end

-- The recipe an item teaches, by ID (docs/data.md, "Recipe items").

-- From the seed or this session's scan.
function ns.GetSeededRecipe(itemID)
	local scanned = ns.scanned and ns.scanned[itemID]
	return scanned or (ns.seed and ns.seed.taught[itemID]) or nil
end

-- From the item's tooltip data: the recipe ID, false when it teaches nothing, nil while its data loads.
function ns.GetTaughtRecipe(itemID)
	if not C_Item.IsItemDataCachedByID(itemID) then
		C_Item.RequestLoadItemDataByID(itemID)
		return nil
	end
	local tooltip = C_TooltipInfo.GetItemByID(itemID)
	if not (tooltip and tooltip.lines and tooltip.lines[1]) then
		return nil -- no tooltip data yet is not an answer
	end
	for _, line in ipairs(tooltip.lines) do
		if line.type == Enum.TooltipDataLineType.ItemSpellTriggerLearn and line.spellID then
			return line.spellID
		end
	end
	return false
end

-- Items awaiting data are asked once; ITEM_DATA_LOAD_RESULT rebuilds the list, and one that never answers costs nothing more.
local awaitedItems = {}

local itemLoads = CreateFrame("Frame")
itemLoads:RegisterEvent("ITEM_DATA_LOAD_RESULT")
itemLoads:SetScript("OnEvent", function(_, _, itemID, success)
	if awaitedItems[itemID] and success then
		awaitedItems[itemID] = nil
		ns.SourcesChanged()
	end
end)

-- The recipe items per recipe: the seed and this session's scan inverted once, then the links saved in play.
local seededItems
local joinedItems = {}

function ns.ResetRecipeItems()
	seededItems = nil
	wipe(joinedItems)
end

function ns.GetRecipeItems(recipeID)
	if not seededItems then
		seededItems = {}
		for _, source in ipairs({ ns.seed and ns.seed.taught or {}, ns.scanned or {} }) do
			for itemID, taughtID in pairs(source) do
				seededItems[taughtID] = seededItems[taughtID] or {}
				if not tContains(seededItems[taughtID], itemID) then
					table.insert(seededItems[taughtID], itemID)
				end
			end
		end
		for _, items in pairs(seededItems) do
			table.sort(items)
		end
	end
	local seeded, saved = seededItems[recipeID], ns.db.recipeItems[recipeID]
	if not (seeded and saved) then
		return seeded or saved
	end
	-- Both layers: the joined list is made once and dropped with the index.
	local joined = joinedItems[recipeID]
	if not joined or #joined ~= #seeded + #saved then
		joined = {}
		for _, itemID in ipairs(seeded) do joined[#joined + 1] = itemID end
		for _, itemID in ipairs(saved) do joined[#joined + 1] = itemID end
		joinedItems[recipeID] = joined
	end
	return joined
end

-- Links recorded recipe items to the recipes they teach; false while an item's data loads, so the caller retries on a later build.
function ns.LinkPending()
	local db = ns.db
	local loaded = true
	for itemID, item in pairs(db.pendingItems) do
		if ns.GetSeededRecipe(itemID) then
			db.pendingItems[itemID] = nil
		elseif not item.none and not awaitedItems[itemID] then
			local recipeID = ns.GetTaughtRecipe(itemID)
			if recipeID == nil then
				awaitedItems[itemID] = true
				loaded = false
			elseif recipeID then
				--@debug@
				-- What the game says about the taught spell, to tell a profession rank from a recipe.
				local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
				db.devTaught = db.devTaught or {}
				db.devTaught[itemID] = ("spell %d | line %s | recipeInfo %s category %s learned %s | known %s"):format(recipeID,
					strjoin(",", tostringall(C_TradeSkillUI.GetTradeSkillLineForRecipe(recipeID))), tostring(info ~= nil),
					tostring(info and info.categoryID), tostring(info and info.learned), tostring(C_SpellBook.IsSpellKnown(recipeID)))
				--@end-debug@
				db.itemRecipe[itemID] = recipeID
				db.recipeItems[recipeID] = db.recipeItems[recipeID] or {}
				if not tContains(db.recipeItems[recipeID], itemID) then
					table.insert(db.recipeItems[recipeID], itemID)
				end
				db.pendingItems[itemID] = nil
			else
				item.none = true -- teaches nothing; not asked again
			end
		end
	end
	return loaded
end

-- The client localizes the Fishing spell's name for fishing sources.
ns.FISHING_SPELL_ID = 7620

-- Indent in pixels for tooltip lines under a source.
local SUBLINE_INDENT = 10
local COORDINATE_SCALE = 100 -- map coordinates are 0..1, shown as 0..100

-- Marks sit centered in square slots of this size, one pixel apart.
ns.MARK_SLOT_SIZE = 16
ns.MARK_SPACING = 1

-- From Blizzard's strings (SOURCE, UNKNOWN), as journals label sources.
ns.SOURCE_LABEL = SOURCE or "Source:"

-- The mark for "not found yet"; pixel sizes are set by eye, since the Gossip files draw smaller than the atlases.
ns.marks = {
	unknown = { atlas = "common-search-magnifyingglass", size = 11 },
	-- Blizzard's padlock for a locked reagent slot (Blizzard_ProfessionsRecipeReagentSlotBase.xml, LockedIcon).
	-- Its art has a clear edge, so 14 draws as tall as the magnifier (docs/client-notes.md, "Requirements").
	locked = { atlas = "AdventureMapIcon-Lock", size = 14 },
}

-- Marks for a recipe in display order, filled into out; returns the count.
function ns.GetMarks(recipeInfo, out)
	wipe(out)
	-- The lock comes first so the source marks stay in line down the list.
	if recipeInfo.lockReason then
		out[1] = "locked"
	end
	if recipeInfo.sourceTypes then
		for _, sourceType in ipairs(ns.sourceOrder) do
			if recipeInfo.sourceTypes[sourceType] then
				out[#out + 1] = sourceType
			end
		end
	else
		out[#out + 1] = "unknown"
	end
	return #out
end

-- Marks are drawn in color at half strength, so they sit behind the recipe names, and at full strength under the pointer.
local MARK_ALPHA = 0.5

local function SetArt(texture, info)
	if info.atlas then
		texture:SetAtlas(info.atlas)
	else
		texture:SetTexture(info.texture)
	end
end

function ns.GetMarkAspect(info)
	if not info.aspect then
		local atlas = info.atlas and C_Texture.GetAtlasInfo(info.atlas)
		info.aspect = atlas and atlas.width / atlas.height or 1
	end
	return info.aspect
end

-- Draws a mark on an icon frame with a centered .Texture.
function ns.ApplyMark(icon, mark)
	local info = ns.sourceTypes[mark] or ns.marks[mark]
	-- size is the height; atlas art keeps its own shape (the padlock is not square).
	icon.Texture:SetSize(info.size * ns.GetMarkAspect(info), info.size)
	-- Compared by the art's own table, so replaced art redraws.
	if icon.markInfo ~= info then
		SetArt(icon.Texture, info)
		icon.markInfo = info
	end
end

function ns.SetMarkStrength(icon, full)
	icon.Texture:SetAlpha(full and 1 or MARK_ALPHA)
end

function ns.SourcePosition(observation)
	local _, positions, fallbackMap = ns.SourceInfo(observation)
	local here = C_Map.GetBestMapForUnit("player")
	if here and positions and positions[here] then
		return here, positions[here].x, positions[here].y
	end
	local mapID, newest = ns.NewestPosition(positions)
	if newest then
		return mapID, newest.x, newest.y
	end
	return fallbackMap
end

-- Detail lines use Blizzard's gold labels (REQUIRES_LABEL, COSTS_LABEL) as the trainer and bank frames do.
-- Tooltip text is led by its row mark at text height.
local MARK_TEXT_HEIGHT = 14
-- Lines under a marked heading align with its text: the mark plus the space after it (about 4 in the tooltip font).
local MARK_TEXT_GAP = 4
local MARK_TEXT_INDENT = MARK_TEXT_HEIGHT + MARK_TEXT_GAP

local function MarkText(mark, text)
	local info = ns.sourceTypes[mark] or ns.marks[mark]
	local width = math.floor(MARK_TEXT_HEIGHT * ns.GetMarkAspect(info) + 0.5)
	local art = info.atlas and CreateAtlasMarkup(info.atlas, width, MARK_TEXT_HEIGHT)
		or ("|T%s:%d:%d|t"):format(info.texture, MARK_TEXT_HEIGHT, width)
	return art .. " " .. text
end

-- Money is drawn with GetMoneyString like item sell prices.
local function AddDetailLines(tooltip, observation)
	if observation.skill and observation.skill > 0 then
		local profession = Professions.GetProfessionInfo().professionName
		GameTooltip_AddColoredDoubleLine(tooltip, REQUIRES_LABEL, ("%s (%d)"):format(profession, observation.skill),
			NORMAL_FONT_COLOR, HIGHLIGHT_FONT_COLOR, false, MARK_TEXT_INDENT + SUBLINE_INDENT)
	end
	local money = observation.cost or observation.price
	if money and money > 0 then
		GameTooltip_AddColoredDoubleLine(tooltip, COSTS_LABEL, GetMoneyString(money, true),
			NORMAL_FONT_COLOR, HIGHLIGHT_FONT_COLOR, false, MARK_TEXT_INDENT + SUBLINE_INDENT)
	end
end

-- One source type's lines: an optional gold header, one "who | where" line per source (as the Wardrobe sources tooltip, CollectionsUtil.lua), and indented lines under it.
-- A drop's place as precisely as it was recorded: the dungeon, or "subzone, zone"; else the zone.
function ns.PlaceName(observation, mapInfo)
	if observation.instance then
		return GetRealZoneText(observation.instance)
	end
	local zone = mapInfo and mapInfo.name
	local subzone = observation.area and C_Map.GetAreaInfo(observation.area)
	if subzone and subzone ~= "" and subzone ~= zone then
		return zone and ("%s, %s"):format(subzone, zone) or subzone
	end
	return zone or UNKNOWN
end

-- One string per count form, so a translation can word each (singular and plural keys in Locales/enUS.lua).
local function Plural(count, one, many)
	return (count == 1 and one or many):format(count)
end

-- "Seen 3 times from 2 creatures in 1 zone": how much a drop label rests on.
local function DropEvidence(scope)
	return ("%s %s %s"):format(Plural(scope.times, L["Seen %d time"], L["Seen %d times"]),
		Plural(scope.creatures, L["from %d creature"], L["from %d creatures"]), Plural(scope.places, L["in %d zone"], L["in %d zones"]))
end

local DROP_LINES = 6 -- sightings listed under a drop header before "and N more"

local AddKindLines

-- Drops: the header names the scope ("Drop", "Zone Drop: Duskwood", "World Drop"), then the
-- sightings (a world drop lists its zones instead), then the evidence line.
local function AddDropLines(tooltip, entries, detailed, withHeader)
	local scope = ns.DropScope(entries)
	if not scope then
		return AddKindLines(tooltip, entries, "drop", detailed, withHeader, true)
	end
	local header = DROP_SCOPE_LABELS[scope.scope]
	if scope.scope == "zone" and scope.place then
		header = ("%s: %s"):format(header, ns.DropPlaceName(scope.place.kind, scope.place.id))
	end
	if withHeader then
		GameTooltip_AddNormalLine(tooltip, MarkText("drop", header))
	end
	if scope.scope == "world" then
		-- Creature zones are summarized; fishing and containers keep their own lines.
		local seen, names, own = {}, {}, {}
		for _, observation in ipairs(entries) do
			local kind, place = DropZone(observation)
			if observation.kind == "drop" and (observation.fishing or observation.container) then
				own[#own + 1] = observation
			elseif observation.kind == "drop" and place and not seen[kind .. place] then
				seen[kind .. place] = true
				names[#names + 1] = ns.DropPlaceName(kind, place)
			end
		end
		table.sort(names, function(a, b) return strcmputf8i(a, b) < 0 end)
		for index = 1, math.min(#names, DROP_LINES) do
			GameTooltip_AddColoredLine(tooltip, names[index], HIGHLIGHT_FONT_COLOR, false, MARK_TEXT_INDENT)
		end
		if #names > DROP_LINES then
			GameTooltip_AddColoredLine(tooltip, L["and %d more"]:format(#names - DROP_LINES), GRAY_FONT_COLOR, false, MARK_TEXT_INDENT)
		end
		AddKindLines(tooltip, own, "drop", detailed, false, true)
	else
		AddKindLines(tooltip, entries, "drop", detailed, false, true)
	end
	GameTooltip_AddColoredLine(tooltip, DropEvidence(scope), GRAY_FONT_COLOR, false, MARK_TEXT_INDENT)
end

function AddKindLines(tooltip, entries, kind, detailed, withHeader, plain)
	if kind == "drop" and not plain then
		return AddDropLines(tooltip, entries, detailed, withHeader)
	end
	local listed = 0
	for _, observation in ipairs(entries) do
		if observation.kind == kind then
			if withHeader then
				GameTooltip_AddNormalLine(tooltip, MarkText(kind, ns.sourceTypes[kind].label))
				withHeader = false
			end
			listed = listed + 1
			if kind == "drop" and listed > DROP_LINES then
				break
			end
			local name = ns.SourceInfo(observation)
			local mapID, x, y = ns.SourcePosition(observation)
			local mapInfo = mapID and C_Map.GetMapInfo(mapID)
			local where = ns.PlaceName(observation, mapInfo)
			if detailed and mapInfo and x then
				where = ("%s %.1f, %.1f"):format(where, x * COORDINATE_SCALE, y * COORDINATE_SCALE)
			end
			GameTooltip_AddColoredDoubleLine(tooltip, name or UNKNOWN, where, HIGHLIGHT_FONT_COLOR, GRAY_FONT_COLOR,
				false, MARK_TEXT_INDENT)
			local questNPC = observation.quest and (ns.GetNPC(observation.npc) or ns.GetNPC(observation.finisher))
			if questNPC and questNPC.name then
				GameTooltip_AddColoredLine(tooltip, questNPC.name, GRAY_FONT_COLOR, false, MARK_TEXT_INDENT + SUBLINE_INDENT)
			end
			if detailed then
				AddDetailLines(tooltip, observation)
			end
		end
	end
	if kind == "drop" and listed > DROP_LINES then
		local total = 0
		for _, observation in ipairs(entries) do
			if observation.kind == "drop" then total = total + 1 end
		end
		GameTooltip_AddColoredLine(tooltip, L["and %d more"]:format(total - DROP_LINES), GRAY_FONT_COLOR, false, MARK_TEXT_INDENT)
	end
end


-- The source tooltip for the recipe pane: the recipe as title, then every source type.
-- Source lines for a list of entries, without a title (the rank tooltip names its own rows).
function ns.AddEntryLines(tooltip, entries, detailed)
	for _, kind in ipairs(ns.sourceOrder) do
		AddKindLines(tooltip, entries, kind, detailed, true)
	end
end

function ns.AddSourceLines(tooltip, recipeInfo, detailed)
	GameTooltip_SetTitle(tooltip, recipeInfo.name)
	-- Blizzard's row disabled reason (Blizzard_ProfessionsRecipeList.lua, LockedIcon OnEnter).
	if recipeInfo.lockReason then
		GameTooltip_AddDisabledLine(tooltip, MarkText("locked", recipeInfo.lockReason))
	end
	local entries = ns.GetSources(recipeInfo)
	if not entries then
		GameTooltip_AddNormalLine(tooltip, MarkText("unknown", ns.SOURCE_LABEL .. " " .. HIGHLIGHT_FONT_COLOR:WrapTextInColorCode(UNKNOWN)))
		return
	end
	for _, kind in ipairs(ns.sourceOrder) do
		AddKindLines(tooltip, entries, kind, detailed, true)
	end
end

-- Faction comes from the recipe's tooltip, a specialization from the made item's (docs/client-notes.md, "Requirements").
-- recipeFacts keeps what is fixed for a game build.
local recipeFactions, recipeSpecs = {}, {}

local function Facts()
	local build = ns.BUILD
	local facts = ns.db.recipeFacts
	if not facts or facts.build ~= build then
		facts = { build = build, faction = {}, spec = {} }
		ns.db.recipeFacts = facts
	end
	return facts
end

function ns.GetRecipeFaction(recipeID)
	local faction = recipeFactions[recipeID]
	if faction ~= nil then
		return faction
	end
	local facts = Facts()
	faction = facts.faction[recipeID]
	if faction == nil then
		local tooltip = C_TooltipInfo.GetSpellByID(recipeID)
		if not (tooltip and tooltip.lines and tooltip.lines[1]) then
			return nil
		end
		faction = false
		for _, line in ipairs(tooltip.lines) do
			if line.type == Enum.TooltipDataLineType.UsageRequirement and line.leftText
				and line.requirementType == Enum.TooltipDataUsageRequirementType.Faction then
				faction = nil -- unreadable until a label matches
				for name, label in pairs(FACTION_LABELS_FROM_STRING) do
					if line.leftText:find(label, 1, true) then
						faction = name
						break
					end
				end
			end
		end
		if faction == nil then
			return nil
		end
		facts.faction[recipeID] = faction
	end
	recipeFactions[recipeID] = faction
	return faction
end

-- Met requirements draw white and unmet ones red; that red is the tooltip's own, so the test is low green (docs/client-notes.md, "Requirements").
local UNMET_MAX_GREEN = 0.5

local function IsUnmet(color)
	return color ~= nil and color.g < UNMET_MAX_GREEN
end

-- Rows waiting for a made item's data redraw once after the answers arrive.
local LOCK_REFRESH_DELAY = 0.2
local loadingItems, refreshQueued = {}, false

local function QueueRowRefresh()
	if not refreshQueued then
		refreshQueued = true
		C_Timer.After(LOCK_REFRESH_DELAY, function()
			refreshQueued = false
			-- Hiding unavailable recipes changes which rows exist, so rebuild the list.
			if ns.db.showUnavailable then
				ns.RefreshRows()
			else
				ns.RefreshList()
			end
		end)
	end
end

-- recipeSpecs: false for no specialization requirement, MET, or the requirement text when unmet.
-- specialized: professions where the character meets one, which is how a picked specialization is told (docs/client-notes.md, "Requirements").
local MET = true
local specialized = {}

-- Cached: row redraws ask often and it never changes.
local professions = {}

local function Profession(recipeID)
	local profession = professions[recipeID]
	if profession == nil then
		local line, _, parent = C_TradeSkillUI.GetTradeSkillLineForRecipe(recipeID)
		profession = parent or line or false
		professions[recipeID] = profession
	end
	return profession
end

-- Reads the specialization requirement of what a recipe makes; nil while that item's data loads.
-- Learned recipes are read too, so one met requirement anywhere is found; recipes known to have none are skipped.
function ns.ReadSpecialization(recipeID)
	local state = recipeSpecs[recipeID]
	if state ~= nil then
		return state
	end
	local facts = Facts()
	if facts.spec[recipeID] == false then
		recipeSpecs[recipeID] = false
		return false
	end
	local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
	local itemID = schematic and schematic.outputItemID
	if not itemID then
		facts.spec[recipeID], recipeSpecs[recipeID] = false, false
		return false
	end
	if not C_Item.IsItemDataCachedByID(itemID) then
		local waiting = loadingItems[itemID]
		if not waiting then
			waiting = {}
			loadingItems[itemID] = waiting
			Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
				loadingItems[itemID] = nil
				for waitingRecipeID in pairs(waiting) do
					ns.ReadSpecialization(waitingRecipeID)
				end
				QueueRowRefresh()
			end)
		end
		waiting[recipeID] = true
		return nil
	end
	local tooltip = C_TooltipInfo.GetItemByID(itemID)
	if not (tooltip and tooltip.lines and tooltip.lines[1]) then
		return nil -- no tooltip data yet is not an answer
	end
	local hasLine
	state = false
	for _, line in ipairs(tooltip.lines) do
		if line.type == Enum.TooltipDataLineType.UsageRequirement and line.leftText
			and line.requirementType == Enum.TooltipDataUsageRequirementType.Skill
			and not line.leftText:find("%d") then
			hasLine = true
			-- The line's own flag when it has one, else its color; with neither it says nothing.
			if line.usable == false or IsUnmet(line.leftColor) then
				state = line.leftText
			elseif line.usable or line.leftColor then
				state = MET
			end
		end
	end
	local profession = Profession(recipeID)
	if state == MET and profession then
		specialized[profession] = true
	end
	facts.spec[recipeID], recipeSpecs[recipeID] = hasLine or false, state
	return state
end

-- The requirement text when a specialization other than the made item's is picked; false for no lock, nil while data loads.
-- Nothing locks before a specialization is picked.
function ns.GetRecipeLock(recipeID)
	local state = ns.ReadSpecialization(recipeID)
	if state == nil then
		return nil
	end
	local profession = Profession(recipeID)
	return state ~= MET and state and profession and specialized[profession] and state or false
end

-- Choosing or dropping a specialization changes which requirements are met.
function ns.ClearRecipeLocks()
	wipe(recipeSpecs)
	wipe(specialized)
end
