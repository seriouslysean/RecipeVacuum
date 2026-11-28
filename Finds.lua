-- GPL-3.0 with additional terms under section 7: README.md, "License".

local _, ns = ...
local L = ns.L
local wire = ns.toolkit.wire

-- Self-found finds are one collection with an ID and a revision counter; the toolkit's share keeps both and the
-- transport (docs/data.md, "Sharing"). This file is Recipe Vacuum's row shape: what a row says, what makes it valid, how it merges.

function ns.MarkFind(observation, ref, id)
	ns.share:Mark(observation, { ref = ref, id = id })
end

-- Derived from the saved layer, not saved.
function ns.InitFinds()
	local db = ns.db
	ns.share:Load(db, function(add)
		for ref, bucket in pairs({ recipe = db.found.recipes, item = db.found.items }) do
			for id, observations in pairs(bucket) do
				for _, observation in ipairs(observations) do
					add(observation, { ref = ref, id = id })
				end
			end
		end
	end)
end

-- Wire rows carry IDs; names are sent only for NPCs and objects. Keys: docs/data.md, "Sharing".
local MAX_NAME_LENGTH = 64 -- caps what a peer can send

-- Names a receiver would reject are left out, so one long name never stalls a peer's sync.
local function WireName(name)
	return name and wire.Name(name, MAX_NAME_LENGTH) and name or nil
end

local function WireRow(observation, context)
	local db = ns.db
	local named = observation.object and db.objects[observation.object] or db.npcs[observation.npc] or {}
	local mapID, position = ns.NewestPosition(named.positions)
	if observation.fishing then
		mapID, position = observation.fishing, { x = observation.x, y = observation.y }
	elseif observation.kind == "drop" then
		-- A drop carries its own spot or none, never the creature's latest one elsewhere.
		mapID, position = observation.map, observation.x and { x = observation.x, y = observation.y } or nil
	end
	return {
		k = observation.kind, r = context.ref == "recipe" and context.id or nil, i = context.ref == "item" and context.id or nil,
		n = observation.npc, nm = not observation.object and WireName(named.name) or nil,
		nf = not observation.object and named.faction or nil,
		o = observation.object, on = observation.object and WireName(named.name) or nil,
		ci = observation.container, fi = observation.fishing, z = observation.zone, q = observation.quest,
		m = mapID or observation.map, x = position and position.x, y = position and position.y,
		f = observation.faction, s = observation.seen, b = observation.build,
		sk = observation.skill, c = observation.cost, p = observation.price, l = observation.limited,
		sp = observation.spellID, ch = observation.choice, fn = observation.finisher, gi = observation.giverItem,
		a = observation.area, di = observation.instance, cn = observation.count,
	}
end

-- Validate every received row before saving; received data is parsed, never run as code (docs/data.md, "Sharing").
local PositiveID, OptionalID = wire.ID, function(value) return wire.Optional(wire.ID, value) end

local FACTIONS = { Alliance = true, Horde = true }
local NPC_FACTIONS = { Alliance = true, Horde = true, Neutral = true }

-- Identifying field by kind; nil when malformed.
local function SourceField(row)
	if row.k == "trainer" then
		return PositiveID(row.r) and row.i == nil and PositiveID(row.n) and "n"
	elseif row.k == "vendor" then
		return PositiveID(row.i) and row.r == nil and PositiveID(row.n) and "n"
	elseif row.k == "quest" then
		return PositiveID(row.i) and row.r == nil and PositiveID(row.q) and "q"
	elseif row.k == "drop" and PositiveID(row.i) and row.r == nil then
		local field
		for _, key in ipairs({ "n", "o", "ci", "fi", "z" }) do
			if row[key] ~= nil then
				if field or not PositiveID(row[key]) then return nil end
				field = key
			end
		end
		return field
	end
end

-- The toolkit calls this for each row of a kind this version reads; false carries the reason the log shows.
local function ValidRow(row)
	if not SourceField(row) then return false, "has no valid source" end
	-- Local data answers both; an ID that is neither would wait in pendingItems for good.
	if row.i and not ns.IsRecipeItem(row.i) then return false, "item is not a recipe item" end
	if row.r and not C_TradeSkillUI.GetTradeSkillLineForRecipe(row.r) then return false, "recipe is unknown" end
	-- Each kind carries only its own identity: a quest ID on quests, a drop's origin on drops.
	-- Absent means nil: false is a value a peer can send, and it would be saved as the source.
	if row.k ~= "quest" and row.q ~= nil then return false, "carries a quest ID" end
	for _, field in ipairs({ "o", "ci", "fi", "z", "a", "di", "cn" }) do
		if row.k ~= "drop" and row[field] ~= nil then return false, "carries a drop's fields" end
	end
	if not (OptionalID(row.a) and OptionalID(row.di) and OptionalID(row.cn)) then return false, "bad area, instance or count" end
	if (row.x == nil) ~= (row.y == nil) then return false, "position has one coordinate" end
	if not (wire.Optional(wire.Name, row.nm, MAX_NAME_LENGTH) and wire.Optional(wire.Name, row.on, MAX_NAME_LENGTH)) then return false, "bad name" end
	if not (OptionalID(row.n) and OptionalID(row.fn) and OptionalID(row.gi)) then return false, "bad NPC, finisher or giver item" end
	if row.m ~= nil and not (PositiveID(row.m) and C_Map.GetMapInfo(row.m)) then return false, "unknown map" end
	if row.fi ~= nil and not (PositiveID(row.fi) and C_Map.GetMapInfo(row.fi)) then return false, "unknown fishing zone" end
	if row.z ~= nil and not (PositiveID(row.z) and C_Map.GetMapInfo(row.z)) then return false, "unknown roll zone" end
	if not (wire.Optional(wire.Coordinate, row.x) and wire.Optional(wire.Coordinate, row.y)) then return false, "coordinate out of range" end
	if row.f ~= nil and not FACTIONS[row.f] then return false, "bad faction" end
	if row.nf ~= nil and not NPC_FACTIONS[row.nf] then return false, "bad NPC faction" end
	if row.s ~= nil and not wire.Time(row.s) then return false, "seen time is not a past time" end
	for _, field in ipairs({ "b", "sk", "c", "p", "sp" }) do
		if not wire.Optional(wire.Number, row[field]) then return false, "bad " .. field end
	end
	if row.sp ~= nil and not PositiveID(row.sp) then return false, "bad spell" end
	if not (wire.Optional(wire.Flag, row.l) and wire.Optional(wire.Flag, row.ch)) then return false, "bad flag" end
	return true
end

-- Wire key of each identifying field, and the observation field it fills.
local IDENTITY = { n = "npc", o = "object", ci = "container", fi = "fishing", z = "zone", q = "quest" }

-- Wire key of each saved field of a shared observation.
local MERGED_FIELDS = {
	npc = "n", object = "o", container = "ci", fishing = "fi", zone = "z", quest = "q", faction = "f",
	skill = "sk", cost = "c", price = "p", limited = "l", spellID = "sp", choice = "ch", finisher = "fn",
	giverItem = "gi", map = "m", x = "x", y = "y", area = "a", instance = "di", count = "cn",
}

-- Row kinds this version reads; the toolkit skips the rest (docs/sharing.md, "Versions").
local KNOWN_KINDS = { trainer = true, vendor = true, quest = true, drop = true }
-- Shared sources one recipe keeps: a peer's rows cannot be checked against the game, so they cannot grow a recipe
-- without end (docs/data.md, "Sharing").
local MAX_SHARED_SOURCES = 64

-- The checked rows into the shared layer, newest per source. Returns whether anything changed.
function ns.MergeFinds(rows)
	local db, changed, capped = ns.db, false, 0
	for _, row in ipairs(rows) do
		local wireField = SourceField(row)
		local field, value = IDENTITY[wireField], row[wireField]
		local bucket, id = row.r and db.shared.recipes or db.shared.items, row.r or row.i
		bucket[id] = bucket[id] or {}
		local observation = ns.FindSource(bucket[id], { kind = row.k, [field] = value, map = row.m, area = row.a,
			instance = row.di })
		if not observation and #bucket[id] >= MAX_SHARED_SOURCES then
			capped = capped + 1
		else
			if row.n then
				ns.NoteNPC(db.npcs, row.n, row.nm, not row.o and row.m, row.x, row.y, row.s, true)
				-- A peer only fills in a faction we have not seen ourselves.
				if not db.npcs[row.n].faction then ns.NoteNPCFaction(row.n, row.nf) end
			end
			if row.o then ns.NoteNPC(db.objects, row.o, row.on, row.m, row.x, row.y, row.s, true) end
			if not observation then
				observation = { kind = row.k, [field] = value, map = row.k == "drop" and row.m or nil }
				table.insert(bucket[id], observation)
				changed = true
			end
			-- Per field, with the time it was learned (observation.at): fill what is missing, let a newer sighting correct, never clear.
			-- Reports reach the same result in any order; repeating the same facts changes nothing.
			local at = observation.at
			if not at then
				at = {}
				for name in pairs(MERGED_FIELDS) do
					if observation[name] ~= nil then at[name] = observation.seen or 0 end
				end
				observation.at = at
			end
			local seen = row.s or 0
			for name, key in pairs(MERGED_FIELDS) do
				local incoming = row[key]
				if incoming ~= nil and name ~= "x" and name ~= "y" then
					local current, learned = observation[name], at[name]
					-- Equal times: the higher value wins, so every player settles on the same one.
					local tie = seen == learned and incoming ~= current and tostring(incoming) > tostring(current)
					if current == nil or seen > learned or tie then
						if incoming ~= current then
							observation[name] = incoming
							changed = true
						end
						at[name] = seen
					end
				end
			end
			-- A fishing spot and a creature or object drop keep their own position, merged as one pair so two
			-- reports never combine into a spot nobody stood at; other sources use the NPC's.
			if row.x and (row.fi or (row.k == "drop" and (row.n or row.o))) then
				local learned = at.x
				local incoming, current = ("%s,%s"):format(row.x, row.y), observation.x and ("%s,%s"):format(observation.x, observation.y)
				local tie = seen == learned and incoming ~= current and incoming > current
				if current == nil or seen > learned or tie then
					if incoming ~= current then
						observation.x, observation.y = row.x, row.y
						changed = true
					end
					at.x, at.y = seen, seen
				end
			end
			if seen > (observation.seen or 0) then
				observation.seen, observation.build = seen, row.b or observation.build
			end
			if row.i and not db.itemRecipe[row.i] and not ns.GetSeededRecipe(row.i) then
				db.pendingItems[row.i] = db.pendingItems[row.i] or {}
			end
		end
	end
	if capped > 0 then ns.toolkit:Trace(ns.module, "sources capped", "rows", capped, "limit", MAX_SHARED_SOURCES) end
	return changed
end

-- Export an array, not a table with sparse numeric keys: C_EncodingUtil.SerializeJSON rejects those.
ns.EXPORT_FORMAT_VERSION = 3
local EXPORT_FORMAT = "RecipeVacuum" -- the export's format name, which readers match on

function ns.ExportFinds()
	local rows = ns.share:Since(0, math.huge)
	local json = C_EncodingUtil.SerializeJSON({
		format = EXPORT_FORMAT, version = ns.EXPORT_FORMAT_VERSION, exportBuild = ns.BUILD, locale = GetLocale(),
		observations = rows,
	})
	ns.toolkit:ShowText(
		ns.module.title .. ": " .. L["Recipe Sources"], json)
end

-- The saved collection and revisions are Recipe Vacuum's; the toolkit's share runs the exchange. Protocol 2 is
-- the wire this addon has always spoken (prefix RecipeVacuum2): raise it only when a row's meaning changes.
ns.share = ns.toolkit:NewShare(ns.module, {
	protocol = 2,
	kinds = KNOWN_KINDS,
	wire = WireRow,
	validate = ValidRow,
	-- Looked up when called, so the working build's timing wrapper counts it.
	merge = function(rows) return ns.MergeFinds(rows) end,
	sending = function() return ns.db.shareFinds end,
	receiving = function() return ns.db.sourceLevel >= ns.LEVEL.FRIENDS end,
	changed = function() ns.SourcesChanged() end,
})
