local addonName, ns = ...

-- Saved data layout, schema 4. Layers: game data (session memory only, Unlearned.lua),
-- ns.included (Data/Included.lua), RecipeVacuumDB.found (self), RecipeVacuumDB.shared (peers).
-- found and shared: { recipes = { [recipeID] = { observation, ... } }, items = { [recipe itemID] = { ... } } }
-- Observation: { kind = "trainer" | "vendor" | "drop" | "quest", one id field, faction, seen (server
-- time), build, rev (found only), details }:
--   trainer, vendor: npc; skill, cost | price, limited, spellID
--   drop: npc | object | container (itemID) | fishing (mapID); map, x, y
--   quest: quest; npc (giver), finisher, giverItem, choice, map
-- NPCs and objects are stored once: npcs[npcID], objects[objectID] = { name, positions = { [mapID] = { x, y, seen } } }
local SCHEMA = 4

function ns.NewLayer()
	return { recipes = {}, items = {} }
end

-- Option defaults live in Settings.lua.
local defaults = {
	showUnlearned = true, -- Blizzard default; Forever turns it off
	sourceFilter = {},     -- [sourceType or "unknown"] = false when unchecked in the Sources filter
	npcs = {},
	objects = {},
	itemRecipe = {},       -- [recipe itemID] = recipeID, linked when the profession is opened
	recipeItems = {},      -- [recipeID] = { recipe itemIDs }
	pendingItems = {},     -- [recipe itemID] = { name, spellID } until linked to a recipe
}

-- Keeps the newest position per map.
function ns.NoteNPC(npcs, npcID, name, mapID, x, y, seen, keepName)
	local npc = npcs[npcID]
	if not npc then
		npc = { positions = {} }
		npcs[npcID] = npc
	end
	-- Peers only fill a missing name, so a guildmate's client language never replaces ours.
	if name and not (keepName and npc.name) then npc.name = name end
	if mapID and x and y then
		local position = npc.positions[mapID]
		if not position or (seen or 0) >= (position.seen or 0) then
			npc.positions[mapID] = { x = x, y = y, seen = seen }
		end
	end
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

EventUtil.ContinueOnAddOnLoaded(addonName, function()
	local db = RecipeVacuumDB or {}
	local version = db.schema or (db.sources and 1) or SCHEMA
	if version > SCHEMA then
		-- Newer save: leave it alone and run on an empty session copy.
		ns.newerSave = true
		db = {}
		version = SCHEMA
		print(("%s: saved data is from a newer version; it was left unchanged."):format(
			C_AddOns.GetAddOnMetadata(addonName, "Title")))
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
	db.found = db.found or ns.NewLayer()
	db.shared = db.shared or ns.NewLayer()
	ns.db = db
	ns.InitFinds()
	ns.InitSettings()
	ns.ResumeWatch()
end)
