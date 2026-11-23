local _, ns = ...

function ns.SourcesChanged()
	ns.ClearUnlearnedCache()
	local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
	if page and page:IsVisible() and ns.db.showUnlearned and ns.CanShowUnlearned() then
		ns.RefreshList()
	end
end

-- Source types in the order a row shows them: the easiest way to learn wins.
ns.sourceOrder = { "trainer", "vendor", "quest", "drop" }

-- Labels reuse Blizzard's localized source names where they exist.
ns.sourceTypes = {
	trainer = { label = "Trainer",                       texture = "Interface\\GossipFrame\\GossipGossipIcon" },
	vendor  = { label = BATTLE_PET_SOURCE_3 or "Vendor", atlas = "bags-junkcoin" },
	quest   = { label = BATTLE_PET_SOURCE_2 or "Quest",  texture = "Interface\\GossipFrame\\AvailableQuestIcon" },
	drop    = { label = BATTLE_PET_SOURCE_1 or "Drop",   texture = "Interface\\GossipFrame\\VendorGossipIcon" },
}

-- Lookups read the layers described in Core.lua. Recipes are keyed by recipe ID (trainer
-- services, read from the trainer tooltip's spell ID the way another addon's Scanner.lua
-- does); recipe items by item ID, linked to a recipe ID in RecipeVacuumDB.itemRecipe once
-- the item's profession is opened. Everything shows the included and shared layers too;
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
	return ns.db.npcs[npcID] or ns.included.npcs[npcID]
end

local function AppendLayer(list, layer, recipeInfo, itemIDs)
	if not layer then return end
	for _, observation in ipairs(layer.recipes[recipeInfo.recipeID] or {}) do
		table.insert(list, observation)
	end
	for _, itemID in ipairs(itemIDs or {}) do
		for _, observation in ipairs(layer.items[itemID] or {}) do
			table.insert(list, observation)
		end
	end
	-- Schema 1 trainer finds that are not linked to a recipe ID yet.
	for _, observation in ipairs(layer.trainerNames[ns.NameKey(recipeInfo.name)] or {}) do
		table.insert(list, observation)
	end
end

-- Every visible observation for a recipe, or nil when none is known.
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

-- Stores on a cached recipe what rows and the Sources filter need, so redraws and filtering
-- read fields instead of looking sources up: sourceTypes (set) and primarySource (the type
-- the row shows, the easiest way to learn), both nil when no source is known.
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

-- Whether the Sources filter lets this recipe through. Recipes with no known source pass
-- while "Unknown" is checked.
function ns.PassesSourceFilter(recipeInfo)
	local filter = ns.db.sourceFilter
	-- Unobtainable recipes (another faction's) only show when that filter is checked; it is
	-- off by default.
	if recipeInfo.unobtainable then
		return filter.unobtainable == true
	end
	-- Self Found shows only recipes the player has witnessed (seen at a trainer, vendor or
	-- quest); shared sources are already hidden in that mode.
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

-- Enum.Profession and Enum.ItemRecipeSubclass use different numbers for the same trades.
local recipeSubclass = {}
for name, profession in pairs(Enum.Profession) do
	recipeSubclass[profession] = Enum.ItemRecipeSubclass[name]
end

-- Picks the one candidate recipe the observations' factions allow (vendors and trainers only
-- offer their own faction's version); nil when that is not unique.
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

-- The recipe a pending item teaches, from its name ("Pattern: Red Linen Bag" teaches "Red
-- Linen Bag"), read from the client so received items need no name on the wire.
local function TaughtName(itemID, item)
	if item.name then return item.name end
	local itemName = C_Item.GetItemNameByID(itemID)
	if not itemName then
		C_Item.RequestLoadItemDataByID(itemID)
		return nil
	end
	return (itemName:match("^.-:%s*(.+)$") or itemName):lower()
end

-- Links recorded vendor items and schema 1 trainer names to recipe IDs for the open
-- profession. byName maps lowercase recipe names to recipe IDs; inProfession is the set of
-- recipe IDs in the profession.
function ns.LinkPending(byName, inProfession, profession)
	local db = ns.db
	for itemID, item in pairs(db.pendingItems) do
		local recipeID = item.spellID and inProfession[item.spellID] and item.spellID
		if not recipeID and recipeSubclass[profession] then
			local _, _, _, _, _, class, subclass = C_Item.GetItemInfoInstant(itemID)
			local name = class == Enum.ItemClass.Recipe and subclass == recipeSubclass[profession] and TaughtName(itemID, item)
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
	for _, layer in ipairs({ db.found, db.shared }) do
		for name, observations in pairs(layer.trainerNames) do
			local recipeID = byName[name] and MatchByFaction(byName[name], observations)
			if recipeID then
				layer.recipes[recipeID] = layer.recipes[recipeID] or {}
				for _, observation in ipairs(observations) do
					observation.name = nil
					table.insert(layer.recipes[recipeID], observation)
					if layer == db.found then
						ns.MarkFind(observation, "recipe", recipeID)
					end
				end
				layer.trainerNames[name] = nil
			end
		end
	end
end

ns.UNOBTAINABLE = "Unobtainable"
ns.SOURCE_NOT_FOUND = "Source not found yet"

-- Row marks that aren't source types: Blizzard's search glass for "not found yet" and its red
-- X for recipes this character can never learn.
ns.marks = {
	unknown = { atlas = "common-search-magnifyingglass" },
	unobtainable = { atlas = "common-icon-redx" },
}

function ns.SetSourceTexture(texture, sourceType)
	local info = ns.sourceTypes[sourceType] or ns.marks[sourceType]
	if info.atlas then
		texture:SetAtlas(info.atlas)
	else
		texture:SetTexture(info.texture)
	end
end

-- Tooltip lines for a recipe's sources: "Vendor: Kendor Kabonka, Stormwind City".
function ns.AddSourceLines(tooltip, recipeInfo)
	if recipeInfo.unobtainable then
		GameTooltip_AddErrorLine(tooltip, ns.UNOBTAINABLE)
		return
	end
	local entries = ns.GetSources(recipeInfo)
	if not entries then
		GameTooltip_AddDisabledLine(tooltip, ns.SOURCE_NOT_FOUND)
		return
	end
	for _, observation in ipairs(entries) do
		local npc = ns.GetNPC(observation.npc)
		local where = npc and npc.name or UNKNOWN
		local newest, newestMap
		for mapID, position in pairs(npc and npc.positions or {}) do
			if not newest or (position.seen or 0) > (newest.seen or 0) then
				newest, newestMap = position, mapID
			end
		end
		local mapInfo = newestMap and C_Map.GetMapInfo(newestMap)
		if mapInfo then
			where = where .. ", " .. mapInfo.name
		end
		GameTooltip_AddNormalLine(tooltip, ns.sourceTypes[observation.kind].label .. ": " .. HIGHLIGHT_FONT_COLOR:WrapTextInColorCode(where))
	end
end

-- Whether the player's faction can learn a recipe. Forever marks the other faction's
-- versions only in tooltip data: a UsageRequirement line of the Faction type ("Horde Only"),
-- the same line data Blizzard's Perks UI reads. Recipes don't change, so remember answers.
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
