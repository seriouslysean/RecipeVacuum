local addonName, ns = ...

-- Saved data layout, schema 3. The four data layers (HANDOFF.md "Data model"):
--   game data      read from the client, cached in session memory only (Unlearned.lua);
--   included data  ns.included, shipped in Data/Included.lua;
--   self-found     RecipeVacuumDB.found;
--   shared         RecipeVacuumDB.shared, received from guild, group and friends.
-- found and shared are layers: { recipes = { [recipeID] = { observation, ... } },
-- items = { [recipe itemID] = { ... } }, trainerNames = { [lowercase name] = { ... } } }.
-- trainerNames only holds schema 1 trainer finds until they are linked to a recipe ID.
-- An observation: { kind = "trainer" | "vendor", npc = npcID, faction, seen (server time),
-- build, rev (found only), skill, cost | price, limited, spellID }.
-- NPC details are kept once, in npcs[npcID] = { name, positions = { [mapID] = { x, y, seen } } }.
local SCHEMA = 3

function ns.NewLayer()
	return { recipes = {}, items = {}, trainerNames = {} }
end

-- Option defaults live in Settings.lua; Blizzard's Settings API fills them in.
local defaults = {
	showUnlearned = true, -- Blizzard's standard default; Forever turns it off.
	sourceFilter = {},     -- [sourceType or "unknown"] = false when unchecked in the Sources filter
	npcs = {},
	itemRecipe = {},       -- [recipe itemID] = recipeID, linked when the profession is opened
	recipeItems = {},      -- [recipeID] = { recipe itemIDs }
	pendingItems = {},     -- [recipe itemID] = { name, spellID } until linked to a recipe
}

-- Records an NPC's name and where it was seen, keeping the newest position per map.
function ns.NoteNPC(npcs, npcID, name, mapID, x, y, seen)
	local npc = npcs[npcID]
	if not npc then
		npc = { positions = {} }
		npcs[npcID] = npc
	end
	if name then npc.name = name end
	if mapID and x and y then
		local position = npc.positions[mapID]
		if not position or (seen or 0) >= (position.seen or 0) then
			npc.positions[mapID] = { x = x, y = y, seen = seen }
		end
	end
end

-- Ordered migrations, one per schema number, as another addon (Modules/Migration.lua) and
-- another addon (another addon.lua, OnInitialize) upgrade their saves. Steps are kept forever so
-- a long-absent account still upgrades; each runs once and records its number.
local migrations = {}

-- Schema 1 used a lowercased recipe name as the bucket for both vendors and trainers.
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

-- Schema 3 splits self-found and shared finds into their own layers and keeps each NPC once.
-- Revisions are renumbered, so the collection gets a new ID and peers resync from zero.
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
			elseif type(key) == "string" and key:match("^name:") then
				bucket, id = layer.trainerNames, key:sub(6)
				observation.name = entry.name
			end
			if bucket and entry.type and entry.npcID then
				bucket[id] = bucket[id] or {}
				table.insert(bucket[id], observation)
			end
		end
	end
	db.found, db.shared, db.npcs = found, shared, npcs
	db.sources, db.exchange, db.probe = nil, nil, nil
end

EventUtil.ContinueOnAddOnLoaded(addonName, function()
	local db = RecipeVacuumDB or {}
	local version = db.schema or (db.sources and 1) or SCHEMA
	if version > SCHEMA then
		-- A save from a newer version: leave it untouched and run on an empty session copy.
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
end)
