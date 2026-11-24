local _, ns = ...

function ns.SourcesChanged()
	ns.ClearUnlearnedCache()
	local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
	if page and page:IsVisible() and ns.db.showUnlearned and ns.CanShowUnlearned() then
		ns.RefreshList()
	end
end

-- Source types in row order: easiest way to learn first.
ns.sourceOrder = { "trainer", "vendor", "quest", "drop" }

-- Labels reuse Blizzard's localized source names where they exist.
ns.sourceTypes = {
	trainer = { label = "Trainer",                       texture = "Interface\\GossipFrame\\GossipGossipIcon", size = 14 },
	vendor  = { label = BATTLE_PET_SOURCE_3 or "Vendor", atlas = "bags-junkcoin", size = 18 },
	quest   = { label = BATTLE_PET_SOURCE_2 or "Quest",  texture = "Interface\\GossipFrame\\AvailableQuestIcon", size = 16 },
	drop    = { label = BATTLE_PET_SOURCE_1 or "Drop",   texture = "Interface\\GossipFrame\\VendorGossipIcon", size = 16 },
}

-- Lookups read the layers in Core.lua. Recipes are keyed by recipe ID (trainer spell ID from the
-- tooltip, as another addon Scanner.lua does); recipe items by item ID, linked in
-- RecipeVacuumDB.itemRecipe once the profession opens. Everything shows included and shared layers;
-- Self Found shows only the player's own finds.
function ns.NameKey(recipeName)
	return recipeName:lower()
end

local function VisibleLayers()
	local db = ns.db
	if db.shareWithFriends then
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
	local itemIDs = ns.db.recipeItems[recipeInfo.recipeID]
	local found, shared, included = VisibleLayers()
	AppendLayer(list, found, recipeInfo, itemIDs)
	AppendLayer(list, shared, recipeInfo, itemIDs)
	AppendLayer(list, included, recipeInfo, itemIDs)
	return #list > 0 and list or nil
end

-- Caches sourceTypes (set) and primarySource (the type the row shows) on a recipe so redraws and
-- filtering read fields; both nil when no source is known.
function ns.SummarizeSources(recipeInfo)
	recipeInfo.sourceTypes, recipeInfo.primarySource = nil, nil
	local entries = ns.GetSources(recipeInfo)
	if not entries then
		return
	end
	local types = {}
	for _, entry in ipairs(entries) do
		types[entry.kind] = true
	end
	recipeInfo.sourceTypes = types
	for _, sourceType in ipairs(ns.sourceOrder) do
		if types[sourceType] then
			recipeInfo.primarySource = sourceType
			break
		end
	end
end

-- Whether the Sources filter passes this recipe. Recipes with no known source pass while Unknown is
-- checked.
function ns.PassesSourceFilter(recipeInfo)
	local filter = ns.db.sourceFilter
	-- Self Found shows only recipes the player witnessed (trainer, vendor or quest); shared sources are
	-- already hidden in that mode.
	if not ns.db.shareWithFriends and not recipeInfo.sourceTypes then
		return false
	end
	local types = recipeInfo.sourceTypes
	if not types then
		return filter.unknown ~= false
	end
	for sourceType in pairs(types) do
		if filter[sourceType] ~= false then
			return true
		end
	end
	return false
end

-- Enum.Profession and Enum.ItemRecipeSubclass number the same trades differently.
local recipeSubclass = {}
for name, profession in pairs(Enum.Profession) do
	recipeSubclass[profession] = Enum.ItemRecipeSubclass[name]
end

-- The one candidate recipe the observations' factions allow (vendors and trainers only offer their own
-- faction's version); nil if not unique.
local function MatchByFaction(candidates, observations)
	local match
	for _, candidate in ipairs(candidates or {}) do
		local faction = ns.GetRecipeFaction(candidate)
		if faction == nil then
			return nil -- a missing tooltip could still distinguish two variants
		end
		local eligible = not faction
		for _, observation in ipairs(observations) do
			if observation.faction == faction then
				eligible = true
				break
			end
		end
		if eligible then
			if match and match ~= candidate then
				return nil
			end
			match = candidate
		end
	end
	return match
end

local function ItemObservations(itemID)
	local list = {}
	for _, layer in ipairs({ ns.db.found, ns.db.shared }) do
		for _, observation in ipairs(layer.items[itemID] or {}) do
			table.insert(list, observation)
		end
	end
	return list
end

-- The recipe a pending item teaches, from its name, read from the client so received items need no name
-- on the wire.
local function TaughtName(itemID, item)
	if item.name then return item.name end
	local itemName = C_Item.GetItemNameByID(itemID)
	if not itemName then
		C_Item.RequestLoadItemDataByID(itemID)
		return nil
	end
	return (itemName:match("^.-:%s*(.+)$") or itemName):lower()
end

-- Links recorded recipe items (vendor, drop, quest) to recipe IDs for the open profession. byName maps
-- lowercase recipe names to IDs; inProfession is the set of recipe IDs. Returns false while an item's
-- name is still loading, so the caller links again on a later build.
function ns.LinkPending(byName, inProfession, profession)
	local db = ns.db
	local namesLoaded = true
	for itemID, item in pairs(db.pendingItems) do
		local recipeID = item.spellID and inProfession[item.spellID] and item.spellID
		if not recipeID and recipeSubclass[profession] then
			local _, _, _, _, _, class, subclass = C_Item.GetItemInfoInstant(itemID)
			local name = class == Enum.ItemClass.Recipe and subclass == recipeSubclass[profession] and TaughtName(itemID, item)
			if name == nil then namesLoaded = false end
			recipeID = name and MatchByFaction(byName[name], ItemObservations(itemID))
		end
		if recipeID then
			db.itemRecipe[itemID] = recipeID
			db.recipeItems[recipeID] = db.recipeItems[recipeID] or {}
			if not tContains(db.recipeItems[recipeID], itemID) then
				table.insert(db.recipeItems[recipeID], itemID)
			end
			db.pendingItems[itemID] = nil
		end
	end
	return namesLoaded
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
}

function ns.GetMarkSize(mark)
	return (ns.sourceTypes[mark] or ns.marks[mark]).size
end

-- Marks for a recipe in display order, filled into out; returns the count.
function ns.GetMarks(recipeInfo, out)
	wipe(out)
	if recipeInfo.sourceTypes then
		for _, sourceType in ipairs(ns.sourceOrder) do
			if recipeInfo.sourceTypes[sourceType] then
				out[#out + 1] = sourceType
			end
		end
	else
		out[1] = "unknown"
	end
	return #out
end

-- Dimmed look for sources not yet had, after Blizzard_MountCollection.lua (Classic mount journal
-- disabled entries): half alpha, only mostly desaturated so each type keeps a hint of color. "Full
-- color source icons" turns it off.
local MARK_ALPHA = 0.5
local MARK_DESATURATION = 0.7

-- Draws a mark on an icon button that has a centered .Texture.
function ns.ApplyMark(icon, mark)
	local size = ns.GetMarkSize(mark)
	icon.Texture:SetSize(size, size)
	if icon.mark ~= mark then
		ns.SetSourceTexture(icon.Texture, mark)
		icon.mark = mark
	end
	local dimmed = not ns.db.fullColorIcons
	icon.Texture:SetDesaturation(dimmed and MARK_DESATURATION or 0)
	icon.Texture:SetAlpha(dimmed and MARK_ALPHA or 1)
end

function ns.SetSourceTexture(texture, sourceType)
	local info = ns.sourceTypes[sourceType] or ns.marks[sourceType]
	if info.atlas then
		texture:SetAtlas(info.atlas)
	else
		texture:SetTexture(info.texture)
	end
end

-- Tooltip lines for a recipe's sources, laid out like Blizzard's source tooltips: recipe name as title,
-- a gold line per source type, one white "who | where" double line per source (as the Wardrobe sources
-- tooltip, CollectionsUtil.lua).
-- A source's place to show: its position on the player's current map if seen there, else the newest.
-- Returns mapID, x, y; mapID alone for sources without a position (drops inside instances).
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
-- money drawn with GetMoneyString like item sell prices.
local function AddDetailLines(tooltip, observation)
	if observation.skill and observation.skill > 0 then
		local profession = Professions.GetProfessionInfo().professionName
		GameTooltip_AddColoredDoubleLine(tooltip, REQUIRES_LABEL, ("%s (%d)"):format(profession, observation.skill),
			NORMAL_FONT_COLOR, HIGHLIGHT_FONT_COLOR, false, SUBLINE_INDENT)
	end
	local money = observation.cost or observation.price
	if money and money > 0 then
		GameTooltip_AddColoredDoubleLine(tooltip, COSTS_LABEL, GetMoneyString(money, true),
			NORMAL_FONT_COLOR, HIGHLIGHT_FONT_COLOR, false, SUBLINE_INDENT)
	end
end

-- Source tooltip, shared by row marks and the Details button: the recipe as title, each source type
-- as a gold line, one white "who | where" line per source (as the Wardrobe sources tooltip,
-- CollectionsUtil.lua), and indented lines under it. detailed adds coordinates, skill and cost.
function ns.AddSourceLines(tooltip, recipeInfo, detailed)
	GameTooltip_SetTitle(tooltip, recipeInfo.name)
	local entries = ns.GetSources(recipeInfo)
	if not entries then
		GameTooltip_AddNormalLine(tooltip, ns.SOURCE_LABEL .. " " .. HIGHLIGHT_FONT_COLOR:WrapTextInColorCode(UNKNOWN))
		return
	end
	for _, kind in ipairs(ns.sourceOrder) do
		local header = false
		for _, observation in ipairs(entries) do
			if observation.kind == kind then
				if not header then
					GameTooltip_AddNormalLine(tooltip, ns.sourceTypes[kind].label)
					header = true
				end
				local name = ns.SourceInfo(observation)
				local mapID, x, y = ns.SourcePosition(observation)
				local mapInfo = mapID and C_Map.GetMapInfo(mapID)
				local where = mapInfo and mapInfo.name or ""
				if detailed and mapInfo and x then
					where = ("%s %.1f, %.1f"):format(where, x * COORDINATE_SCALE, y * COORDINATE_SCALE)
				end
				GameTooltip_AddColoredDoubleLine(tooltip, name or UNKNOWN, where, HIGHLIGHT_FONT_COLOR, GRAY_FONT_COLOR)
				local questNPC = observation.quest and (ns.GetNPC(observation.npc) or ns.GetNPC(observation.finisher))
				if questNPC and questNPC.name then
					GameTooltip_AddColoredLine(tooltip, questNPC.name, GRAY_FONT_COLOR, false, SUBLINE_INDENT)
				end
				if detailed then
					AddDetailLines(tooltip, observation)
				end
			end
		end
	end
end

-- Whether the player's faction can learn a recipe. Forever marks the other faction's versions only in
-- tooltip data, a UsageRequirement line of the Faction type ("Horde Only"), as Blizzard's Perks UI
-- reads it. Cached: recipes don't change.
local recipeFactions = {}

function ns.GetRecipeFaction(recipeID)
	if recipeFactions[recipeID] ~= nil then
		return recipeFactions[recipeID]
	end
	local tooltip = C_TooltipInfo.GetSpellByID(recipeID)
	if not (tooltip and tooltip.lines and tooltip.lines[1]) then
		return nil
	end
	for _, line in ipairs(tooltip.lines) do
		if line.type == Enum.TooltipDataLineType.UsageRequirement
			and line.requirementType == Enum.TooltipDataUsageRequirementType.Faction then
			for faction, label in pairs(FACTION_LABELS_FROM_STRING) do
				if line.leftText and line.leftText:find(label, 1, true) then
					recipeFactions[recipeID] = faction
					return faction
				end
			end
			return nil
		end
	end
	recipeFactions[recipeID] = false
	return false
end
