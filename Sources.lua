local _, ns = ...

-- Counts changes to the known sources, so anything computed from them can tell when it is stale.
ns.sourcesVersion = 0

function ns.SourcesChanged()
	ns.sourcesVersion = ns.sourcesVersion + 1
	ns.ClearUnlearnedCache()
	local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
	if page and page:IsVisible() and ns.db.showUnlearned and ns.CanShowUnlearned() then
		ns.RefreshList()
	end
end

-- Source types in row order: easiest way to learn first.
ns.sourceOrder = { "trainer", "vendor", "quest", "drop" }

-- Labels reuse Blizzard's localized source names where they exist.
-- Art (owner's pick, 2026-11-24): the book and coin stack are Blizzard's Class and Auctioneer atlases,
-- the dice its loot roll Need icon (LootHistory.lua), the quest mark its gossip icon. size is the drawn height.
ns.sourceTypes = {
	trainer = { label = "Trainer",                       atlas = "Class", size = 14 },
	vendor  = { label = BATTLE_PET_SOURCE_3 or "Vendor", atlas = "Auctioneer", size = 14 },
	quest   = { label = BATTLE_PET_SOURCE_2 or "Quest",  texture = "Interface\\GossipFrame\\AvailableQuestIcon", size = 16 },
	drop    = { label = BATTLE_PET_SOURCE_1 or "Drop",   atlas = "lootroll-icon-need", size = 14 },
}

-- Lookups read the data layers (docs/data.md). Self Found shows only the player's own finds.
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

-- Name and positions ({ [mapID] = { x, y, seen } }) of any observation, plus a map ID to name when
-- there is no position (instance drops). Names come from the client where it can say them (items,
-- quests, the Fishing spell), else the saved NPC and object tables.
function ns.SourceInfo(observation)
	if observation.quest then
		local giver = ns.GetNPC(observation.npc) or ns.GetNPC(observation.finisher)
		return C_QuestLog.GetTitleForQuestID(observation.quest) or ("%s %d"):format(QUEST or "Quest", observation.quest),
			giver and giver.positions, observation.map
	elseif observation.object then
		local object = GetObject(observation.object)
		return object and object.name, object and object.positions, observation.map
	elseif observation.container then
		return C_Item.GetItemNameByID(observation.container), nil, nil
	elseif observation.fishing then
		local positions = observation.x and { [observation.fishing] = { x = observation.x, y = observation.y, seen = observation.seen } }
		return C_Spell.GetSpellName(ns.FISHING_SPELL_ID), positions, observation.fishing
	elseif observation.zone then
		-- A drop seen only as a group roll: the zone is known, what dropped it is not.
		return UNKNOWN, nil, observation.zone
	end
	local npc = ns.GetNPC(observation.npc)
	return npc and npc.name, npc and npc.positions, observation.map
end

-- Newest position: mapID, position.
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
local function SameSource(a, b)
	if a.kind ~= b.kind then return false end
	if a.quest or b.quest then return a.quest == b.quest end
	return a.npc == b.npc and a.object == b.object and a.container == b.container and a.fishing == b.fishing
		and a.zone == b.zone
end

-- A source the player and a peer both found is in two layers; the first layer read wins.
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

-- Visible observations for a recipe, or nil when none known.
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

-- The item ID when an item (ID or link) is a recipe item, else nil. One instant lookup, no server.
function ns.IsRecipeItem(item)
	local itemID, _, _, _, _, classID = C_Item.GetItemInfoInstant(item)
	return classID == Enum.ItemClass.Recipe and itemID or nil
end

-- The nearest level a recipe, or an item that teaches it, has been come across at; nil if never.
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

-- Caches sourceTypes (a set, nil when no source is known) and met on a recipe, so redraws and
-- filtering read fields.
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

-- Whether the Sources filter passes this recipe. Recipes with no known source pass while Unknown is
-- checked.
-- The Sources filter. Recipes with a known source are shown unless their type is unticked. Recipes
-- with no known source are hidden unless Unknown is ticked: the list shows what the player or their
-- friends have come across, not everything the game's data holds.
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
		-- No known source: shown once come across within the chosen level, or with Unknown ticked.
		-- Unknown unticked by hand (as Uncheck All does) hides them all.
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

-- The recipe a recipe item teaches, by ID: the seed, a session scan, or the item's own tooltip data
-- (docs/data.md, "Recipe items").

-- From the seed or this session's scan; nil when neither knows the item.
function ns.GetSeededRecipe(itemID)
	local scanned = ns.scanned and ns.scanned[itemID]
	return scanned or (ns.seed and ns.seed.taught[itemID]) or nil
end

-- From the item's tooltip data: the recipe ID, false when the item teaches nothing, or nil while the
-- item's data loads.
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

-- Items asked for this session whose data has not arrived. Each is asked once: the list is built and
-- cached without it, and its arrival (ITEM_DATA_LOAD_RESULT) rebuilds the list. One that never answers
-- costs nothing more until the next session.
local awaitedItems = {}

local itemLoads = CreateFrame("Frame")
itemLoads:RegisterEvent("ITEM_DATA_LOAD_RESULT")
itemLoads:SetScript("OnEvent", function(_, _, itemID, success)
	if awaitedItems[itemID] and success then
		awaitedItems[itemID] = nil
		ns.SourcesChanged()
	end
end)

-- The recipe items that teach a recipe: the seed and this session's scan turned around once, then
-- the links saved in play for items they do not have.
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
	-- Both: an item the seed lacks was linked in play to a recipe the seed also knows. Rare, so the
	-- joined list is made once and dropped with the index.
	local joined = joinedItems[recipeID]
	if not joined or #joined ~= #seeded + #saved then
		joined = {}
		for _, itemID in ipairs(seeded) do joined[#joined + 1] = itemID end
		for _, itemID in ipairs(saved) do joined[#joined + 1] = itemID end
		joinedItems[recipeID] = joined
	end
	return joined
end

-- Links recorded recipe items (vendor, drop, quest) to the recipes they teach. An item the seed knows
-- needs no saved link. Returns false while an item's data is still loading, so the caller links again
-- on a later build.
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

-- The Fishing spell; the client localizes its name for fishing sources.
ns.FISHING_SPELL_ID = 7620

-- Tooltip lines under a source (quest NPC, Details specifics) are indented this many pixels.
local SUBLINE_INDENT = 10
local COORDINATE_SCALE = 100 -- map coordinates are 0..1; players read them as 0..100

-- Row and bottom-bar marks sit centered in square slots of this size, one pixel apart.
ns.MARK_SLOT_SIZE = 16
ns.MARK_SPACING = 1

-- "Source: Unknown" from Blizzard's strings (SOURCE, UNKNOWN), as journals label sources.
ns.SOURCE_LABEL = SOURCE or "Source:"

-- The row mark that isn't a source type: the search glass for "not found yet". Pixel sizes are set by
-- eye, since the Gossip files draw their art smaller than the atlases.
ns.marks = {
	unknown = { atlas = "common-search-magnifyingglass", size = 11 },
	-- Blizzard's padlock for a locked reagent slot (LockedIcon in
	-- Blizzard_ProfessionsRecipeReagentSlotBase.xml). The art has a clear edge, so 14 draws it as tall
	-- as the magnifier (docs/client-notes.md, "Requirements").
	locked = { atlas = "AdventureMapIcon-Lock", size = 14 },
}

-- Marks for a recipe in display order, filled into out; returns the count.
function ns.GetMarks(recipeInfo, out)
	wipe(out)
	-- The lock comes first, so it sits left of the source marks and they stay in line down the list.
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

-- Marks are drawn in full color at half strength, so they sit behind the recipe names, and at full
-- strength under the pointer.
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

-- Draws a mark on an icon frame that has a centered .Texture.
function ns.ApplyMark(icon, mark)
	local info = ns.sourceTypes[mark] or ns.marks[mark]
	-- size is the height; atlas art keeps its own shape (the padlock is not square).
	icon.Texture:SetSize(info.size * ns.GetMarkAspect(info), info.size)
	-- Compared by the art's own table, so a mark whose art is replaced redraws.
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

-- Details lists specifics under each source the way Blizzard labels them elsewhere: a gold label
-- (REQUIRES_LABEL, COSTS_LABEL, as the trainer and bank frames show them) and the value on the right,
-- A line's text led by its row mark, so the tooltip explains the marks: the same art, at text height.
local MARK_TEXT_HEIGHT = 14
-- Lines under a marked heading start where the heading's text does: past the mark and the space after
-- it (about 4 in the tooltip font), indented with Blizzard's own leftOffset.
local MARK_TEXT_INDENT = MARK_TEXT_HEIGHT + 4

local function MarkText(mark, text)
	local info = ns.sourceTypes[mark] or ns.marks[mark]
	local width = math.floor(MARK_TEXT_HEIGHT * ns.GetMarkAspect(info) + 0.5)
	local art = info.atlas and CreateAtlasMarkup(info.atlas, width, MARK_TEXT_HEIGHT)
		or ("|T%s:%d:%d|t"):format(info.texture, MARK_TEXT_HEIGHT, width)
	return art .. " " .. text
end

-- money drawn with GetMoneyString like item sell prices.
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

-- One source type's lines: a gold header when asked, one white "who | where" line per source (as the
-- Wardrobe sources tooltip, CollectionsUtil.lua), and indented lines under it. detailed adds
-- coordinates, skill and cost.
local function AddKindLines(tooltip, entries, kind, detailed, withHeader)
	for _, observation in ipairs(entries) do
		if observation.kind == kind then
			if withHeader then
				GameTooltip_AddNormalLine(tooltip, MarkText(kind, ns.sourceTypes[kind].label))
				withHeader = false
			end
			local name = ns.SourceInfo(observation)
			local mapID, x, y = ns.SourcePosition(observation)
			local mapInfo = mapID and C_Map.GetMapInfo(mapID)
			local where = mapInfo and mapInfo.name or ""
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
end


-- The whole source tooltip, for the recipe pane: the recipe as title, then every source type.
function ns.AddSourceLines(tooltip, recipeInfo, detailed)
	GameTooltip_SetTitle(tooltip, recipeInfo.name)
	-- The game's own requirement line, shown as Blizzard shows a row's disabled reason
	-- (Blizzard_ProfessionsRecipeList.lua, LockedIcon OnEnter).
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

-- Faction comes from the recipe's tooltip, a specialization from the tooltip of the item it makes
-- (docs/client-notes.md, "Requirements"). What is fixed for a game build is kept in recipeFacts.
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

-- A met requirement is drawn white and an unmet one red, a red of the tooltip's own, so the test is
-- on the channels: a red line has little green (docs/client-notes.md, "Requirements").
local UNMET_MAX_GREEN = 0.5

local function IsUnmet(color)
	return color ~= nil and color.g < UNMET_MAX_GREEN
end

-- Rows waiting for a made item's data redraw once, shortly after the answers arrive.
local LOCK_REFRESH_DELAY = 0.2
local loadingItems, refreshQueued = {}, false

local function QueueRowRefresh()
	if not refreshQueued then
		refreshQueued = true
		C_Timer.After(LOCK_REFRESH_DELAY, function()
			refreshQueued = false
			-- Hiding unavailable recipes changes which rows exist, so the list is built again.
			if ns.db.showUnavailable then
				ns.RefreshRows()
			else
				ns.RefreshList()
			end
		end)
	end
end

-- recipeSpecs: what a recipe's made item says this session: false for no specialization requirement,
-- MET, or the game's requirement text when unmet. specialized: professions where the character meets
-- at least one, which is how a picked specialization is told (docs/client-notes.md, "Requirements").
local MET = true
local specialized = {}

-- A recipe's profession never changes, and row redraws ask for it often, so it is looked up once.
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
-- The list build asks for every recipe of the profession, learned ones too, so one met requirement
-- anywhere is found. Recipes known to have none are skipped, so only a first open reads them all.
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

-- The game's requirement text when the character has picked a specialization other than the one the
-- recipe's made item needs; false when there is no lock, nil while the made item's data loads. Nothing
-- locks before a specialization is picked: every recipe is still open to the character.
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
