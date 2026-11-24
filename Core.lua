local addonName, ns = ...

-- Saved data layout and migrations: docs/data.md.
local SCHEMA = 8

-- How near to the player a piece of knowledge arrived, and how far the player chose to listen
-- (docs/data.md, "Levels"). Each level includes the ones before it.
ns.title = C_AddOns.GetAddOnMetadata(addonName, "Title")
ns.BUILD = tonumber((select(2, GetBuildInfo()))) -- the game build, as saved on finds and facts

-- IDs, revisions and times on the wire are below this (unsigned 32 bit); larger numbers are rejected.
ns.MAX_WIRE_NUMBER = 2^32

ns.LEVEL = { SELF = 1, FRIENDS = 2, PUBLIC = 3 }
ns.levelNames = { "Self Found", "Friends", "Public" }

function ns.NewLayer()
	return { recipes = {}, items = {} }
end

-- Option defaults live in Settings.lua.
local defaults = {
	showUnlearned = true, -- Blizzard default; Forever turns it off
	sourceLevel = ns.LEVEL.FRIENDS, -- how far the player listens; the options page and first-run question set it
	met = { recipes = {}, items = {} }, -- come across without a source: [recipeID or recipe itemID] = ns.LEVEL
	sourceFilter = {},     -- [sourceType or "unknown"] = true or false once set in the Sources filter (ns.IsSourceShown)
	showUnavailable = true, -- recipes locked by another specialization stay listed
	npcs = {},
	objects = {},
	-- Links made in play, only for recipe items the seed (Data/Seed.lua) does not have:
	itemRecipe = {},       -- [recipe itemID] = recipeID
	recipeItems = {},      -- [recipeID] = { recipe itemIDs }
	pendingItems = {},     -- [recipe itemID] = {} until its data loads and names the recipe it teaches
	-- recipeFacts: per-build facts read from recipe tooltips (Sources.lua), rebuilt on a new game build
}

-- Keeps the newest position per map.
-- The addon's chat lines are a log for the player: the addon's name, a colon, the text, all in the
-- color the game gives an NPC's speech (ChatTypeInfo.MONSTER_SAY), since the Vacuum is a machine
-- talking, as the game's gnomish machines do. One color throughout, as an NPC's line is. Only the
-- color is shared: no "says:", and no brackets, which Forever uses for player names.
function ns.Log(text)
	local color = ChatTypeInfo.MONSTER_SAY
	DEFAULT_CHAT_FRAME:AddMessage(("%s: %s"):format(ns.title, text),
		color.r, color.g, color.b)
end

function ns.NoteNPC(npcs, npcID, name, mapID, x, y, seen, fromPeer)
	local npc = npcs[npcID]
	if not npc then
		npc = { positions = {} }
		npcs[npcID] = npc
	end
	-- A peer only fills what is missing: a guildmate's client language never replaces our name for an
	-- NPC, and their report never moves a position the player may have seen for themselves.
	if name and not (fromPeer and npc.name) then npc.name = name end
	if mapID and x and y then
		local position = npc.positions[mapID]
		if not position or (not fromPeer and (seen or 0) >= (position.seen or 0)) then
			npc.positions[mapID] = { x = x, y = y, seen = seen }
		end
	end
end

-- The side an NPC belongs to, so the map never points a player at the other faction's trainer or
-- vendor (owner: sources stay listed, "no map pins cross faction"). Unknown stays nil.
function ns.NoteNPCFaction(npcID, faction)
	local npc = ns.db.npcs[npcID]
	if npc and faction then npc.faction = faction end
end

-- Ordered migrations, one per schema number, as other addons OnInitialize do.
-- Kept forever so old accounts still upgrade.
local migrations = {}

-- Schema 1 keyed vendors and trainers by lowercased recipe name.
migrations[2] = function(db)
	local sources, pending = {}, {}
	for name, entries in pairs(db.sources or {}) do
		for _, entry in ipairs(entries) do
			local key
			if entry.type == "vendor" and entry.itemID then
				key = "item:" .. entry.itemID
				entry.recipeName = entry.recipeName or name
				pending[entry.itemID] = { name = name:lower(), spellID = entry.spellID }
			else
				key = "name:" .. name:lower()
			end
			sources[key] = sources[key] or {}
			table.insert(sources[key], entry)
		end
	end
	db.sources, db.pendingItems = sources, pending
end

-- Schema 3 splits self-found and shared layers and keeps each NPC once. Renumbered revisions get a new
-- collection ID so peers resync from zero.
migrations[3] = function(db)
	local found, shared, npcs = ns.NewLayer(), ns.NewLayer(), db.npcs or {}
	for key, entries in pairs(db.sources or {}) do
		for _, entry in ipairs(entries) do
			local layer = entry.origin == "shared" and shared or found
			local observation = {
				kind = entry.type, npc = entry.npcID, faction = entry.faction, seen = entry.seen,
				skill = entry.skill, cost = entry.cost, price = entry.price, limited = entry.limited,
				spellID = entry.spellID,
			}
			if entry.npcID then
				ns.NoteNPC(npcs, entry.npcID, entry.npcName, entry.mapID, entry.x, entry.y, entry.seen)
			end
			local bucket, id
			if type(key) == "number" then
				bucket, id = layer.recipes, key
			elseif type(key) == "string" and key:match("^item:%d+$") then
				bucket, id = layer.items, tonumber(key:sub(6))
			end
			-- Schema 4 drops these name keys.
			if bucket and entry.type and entry.npcID then
				bucket[id] = bucket[id] or {}
				table.insert(bucket[id], observation)
			end
		end
	end
	db.found, db.shared, db.npcs = found, shared, npcs
	db.sources, db.exchange, db.probe = nil, nil, nil
end

-- Schema 4 drops schema 1 trainer finds keyed by name (rank lines, names both factions share).
-- Revisiting the trainer records them by recipe ID.
migrations[4] = function(db)
	for _, layer in ipairs({ db.found, db.shared }) do
		if layer then layer.trainerNames = nil end
	end
end

-- Schema 5 keeps only the NPCs and objects a saved source names. Earlier versions saved every vendor
-- opened and every quest giver spoken to.
migrations[5] = function(db)
	local used = { npcs = {}, objects = {} }
	for _, layer in ipairs({ db.found, db.shared }) do
		for _, bucket in ipairs({ layer.recipes, layer.items }) do
			for _, observations in pairs(bucket) do
				for _, observation in ipairs(observations) do
					if observation.npc then used.npcs[observation.npc] = true end
					if observation.finisher then used.npcs[observation.finisher] = true end
					if observation.object then used.objects[observation.object] = true end
				end
			end
		end
	end
	for kind, keep in pairs(used) do
		for id in pairs(db[kind] or {}) do
			if not keep[id] then db[kind][id] = nil end
		end
	end
end

-- Schema 6 links recipe items to recipes by the ID in the item's tooltip data. Earlier links came from
-- matching names, which paired a few items wrongly, so every link is made again.
migrations[6] = function(db)
	for itemID in pairs(db.itemRecipe or {}) do
		db.pendingItems[itemID] = {}
	end
	for _, pending in pairs(db.pendingItems) do
		pending.name, pending.spellID = nil, nil
	end
	db.itemRecipe, db.recipeItems = {}, {}
end

-- Schema 7 drops the Full Color Source Icons option: marks are always in color, brighter under the pointer.
migrations[7] = function(db)
	db.fullColorIcons = nil
end

-- Schema 8 replaces the two source modes with three levels; an earlier Self Found choice is kept.
migrations[8] = function(db)
	db.sourceLevel = db.shareWithFriends == false and ns.LEVEL.SELF or ns.LEVEL.FRIENDS
	db.shareWithFriends = nil
end

EventUtil.ContinueOnAddOnLoaded(addonName, function()
	local db = RecipeVacuumDB or {}
	local version = db.schema or (db.sources and 1) or SCHEMA
	if version > SCHEMA then
		-- Newer save: leave it alone and run on an empty session copy.
		db = {}
		version = SCHEMA
		ns.Log("saved data is from a newer version; it was left unchanged.")
	else
		RecipeVacuumDB = db
	end
	for step = version + 1, SCHEMA do
		migrations[step](db)
		db.schema = step
	end
	db.schema = SCHEMA
	for key, value in pairs(defaults) do
		if db[key] == nil then
			db[key] = value
		end
	end
	-- Saved links only cover items the seed does not have. A newer seed can take one over, so each
	-- load drops the saved links and waiting items it now covers.
	local seeded = ns.seed and ns.seed.taught or {}
	for itemID, recipeID in pairs(db.itemRecipe) do
		if seeded[itemID] then
			db.itemRecipe[itemID] = nil
			local items = db.recipeItems[recipeID]
			if items then
				tDeleteItem(items, itemID)
				if #items == 0 then db.recipeItems[recipeID] = nil end
			end
		end
	end
	for itemID in pairs(db.pendingItems) do
		if seeded[itemID] then db.pendingItems[itemID] = nil end
	end
	db.found = db.found or ns.NewLayer()
	db.shared = db.shared or ns.NewLayer()
	ns.db = db
	ns.InitFinds()
	ns.InitSettings()
	ns.ResumeWatch()
end)
