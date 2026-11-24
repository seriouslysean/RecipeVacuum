local addonName, ns = ...

-- Saved data layout and migrations: docs/data.md.
local SCHEMA = 8

ns.title = C_AddOns.GetAddOnMetadata(addonName, "Title")
ns.BUILD = tonumber((select(2, GetBuildInfo())))

-- Wire limit: IDs, revisions and times must be below this (unsigned 32 bit).
ns.MAX_WIRE_NUMBER = 2^32

-- How near knowledge arrived, and how far the player listens; each level includes the ones before (docs/data.md, "Levels").
ns.LEVEL = { SELF = 1, FRIENDS = 2, PUBLIC = 3 }
ns.levelNames = { "Self Found", "Friends", "Public" }
-- Player-facing wording for each level (docs/voice.md, "Plain text"): the options cards and the help tip.
ns.levelText = {
	"Short range. Tracks only what you see for yourself.",
	"Medium range. Also tracks what your party, guild and friends find.",
	"Long range. Also tracks recipes people link in chat.",
}
ns.levelHeard = { "only you", "you and your friends", "everyone nearby" }

function ns.NewLayer()
	return { recipes = {}, items = {} }
end

-- Option defaults live in Settings.lua.
local defaults = {
	showUnlearned = true, -- Blizzard default; Forever turns it off
	sourceLevel = ns.LEVEL.FRIENDS,
	met = { recipes = {}, items = {} }, -- come across without a source: [recipeID or recipe itemID] = ns.LEVEL
	sourceFilter = {},     -- [sourceType or "unknown"] = true or false once set in the Sources filter (ns.IsSourceShown)
	showUnavailable = true,
	npcs = {},
	objects = {},
	-- Links made in play, only for recipe items the seed (Data/Seed.lua) does not have:
	itemRecipe = {},       -- [recipe itemID] = recipeID
	recipeItems = {},      -- [recipeID] = { recipe itemIDs }
	pendingItems = {},     -- [recipe itemID] = {} until its data loads and names the recipe it teaches
-- recipeFacts: per-build facts from recipe tooltips (Sources.lua), rebuilt on a new game build.
}

-- Chat lines use the NPC speech color (ChatTypeInfo.MONSTER_SAY), with no "says:" and no brackets, which Forever uses for player names.
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
	-- A peer only fills gaps: it never replaces our NPC name or a position the player saw.
	if name and not (fromPeer and npc.name) then npc.name = name end
	if mapID and x and y then
		local position = npc.positions[mapID]
		if not position or (not fromPeer and (seen or 0) >= (position.seen or 0)) then
			npc.positions[mapID] = { x = x, y = y, seen = seen }
		end
	end
end

-- Keeps the map from pointing at the other faction's trainer or vendor; unknown stays nil.
function ns.NoteNPCFaction(npcID, faction)
	local npc = ns.db.npcs[npcID]
	if npc and faction then npc.faction = faction end
end

-- One migration per schema number, in order (as other addons do); never remove one.
local migrations = {}

-- Schema 2 reads schema 1 vendors and trainers keyed by lowercased recipe name.
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

-- Schema 3 splits self-found and shared layers and keeps each NPC once; renumbered revisions get a new collection ID so peers resync.
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
			if bucket and entry.type and entry.npcID then
				bucket[id] = bucket[id] or {}
				table.insert(bucket[id], observation)
			end
		end
	end
	db.found, db.shared, db.npcs = found, shared, npcs
	db.sources, db.exchange, db.probe = nil, nil, nil
end

-- Schema 4 drops trainer finds keyed by name; revisiting the trainer records them by recipe ID.
migrations[4] = function(db)
	for _, layer in ipairs({ db.found, db.shared }) do
		if layer then layer.trainerNames = nil end
	end
end

-- Schema 5 keeps only the NPCs and objects a saved source names.
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

-- Schema 6 links recipe items by the ID in the item's tooltip data, so every link is made again.
migrations[6] = function(db)
	for itemID in pairs(db.itemRecipe or {}) do
		db.pendingItems[itemID] = {}
	end
	for _, pending in pairs(db.pendingItems) do
		pending.name, pending.spellID = nil, nil
	end
	db.itemRecipe, db.recipeItems = {}, {}
end

-- Schema 7 drops the Full Color Source Icons option.
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
	-- A newer seed can take over saved links and waiting items, so each load drops the ones it covers.
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
