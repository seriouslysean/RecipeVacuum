local _, ns = ...

-- Self-found finds are one collection with an ID and a revision counter; renumbering revisions issues a new ID so peers resync.

local revisions = {} -- session only: { { rev, observation, ref = "recipe" | "item", id } } in rev order

-- A collection ID is its creation time and a random number below this.
local COLLECTION_ID_RANGE = 1000000000

local function NewCollectionID()
	return ("%d-%d"):format(GetServerTime(), math.random(COLLECTION_ID_RANGE))
end

function ns.MarkFind(observation, ref, id)
	local exchange = ns.db.exchange
	exchange.revision = exchange.revision + 1
	observation.rev = exchange.revision
	table.insert(revisions, { rev = observation.rev, observation = observation, ref = ref, id = id })
	ns.ScheduleFindOffer()
end

-- Derived from the saved layer, not saved.
function ns.InitFinds()
	local db = ns.db
	if not db.exchange then
		db.exchange = { id = NewCollectionID(), revision = 0, received = {} }
	end
	wipe(revisions)
	local unrevised = {}
	for ref, bucket in pairs({ recipe = db.found.recipes, item = db.found.items }) do
		for id, observations in pairs(bucket) do
			for _, observation in ipairs(observations) do
				local row = { rev = observation.rev, observation = observation, ref = ref, id = id }
				table.insert(observation.rev and revisions or unrevised, row)
			end
		end
	end
	table.sort(revisions, function(a, b) return a.rev < b.rev end)
	local highest = revisions[#revisions] and revisions[#revisions].rev or 0
	if highest > db.exchange.revision then
		-- A counter behind its revisions was reset: renumber.
		db.exchange.id, db.exchange.revision = NewCollectionID(), highest
	end
	for _, row in ipairs(unrevised) do
		db.exchange.revision = db.exchange.revision + 1
		row.observation.rev, row.rev = db.exchange.revision, db.exchange.revision
		table.insert(revisions, row)
	end
end

-- Wire rows carry IDs; names are sent only for NPCs and objects. Keys: docs/data.md, "Sharing".
local MAX_NAME_LENGTH = 64 -- caps what a peer can send

-- Names a receiver would reject are left out, so one long name never stalls a peer's sync.
local function WireName(name)
	return name and #name <= MAX_NAME_LENGTH and name or nil
end

local function WireRow(row)
	local observation = row.observation
	local db = ns.db
	local named = observation.object and db.objects[observation.object] or db.npcs[observation.npc] or {}
	local mapID, position = ns.NewestPosition(named.positions)
	if observation.fishing then
		mapID, position = observation.fishing, { x = observation.x, y = observation.y }
	elseif observation.kind == "drop" then
		-- A drop carries its own spot or none, never the creature's latest one elsewhere (Astra review).
		mapID, position = observation.map, observation.x and { x = observation.x, y = observation.y } or nil
	end
	return {
		k = observation.kind, r = row.ref == "recipe" and row.id or nil, i = row.ref == "item" and row.id or nil,
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

-- Rows after revision `after`, oldest first, up to `limit`; returns the rows and the revision they cover.
function ns.FindsSince(after, limit)
	local rows, through = {}, after
	for _, row in ipairs(revisions) do
		-- Stale: the observation changed again and a newer row covers it.
		if row.rev > after and row.observation.rev == row.rev then
			if #rows >= limit then
				return rows, through
			end
			table.insert(rows, WireRow(row))
			through = row.rev
		end
	end
	return rows, ns.db.exchange.revision
end

-- Validate every received row before saving; received data is parsed, never executed (another addon 2021 ran it through loadstring).
local function PositiveID(value)
	return type(value) == "number" and value > 0 and value < ns.MAX_WIRE_NUMBER and value == math.floor(value)
end

local function Coordinate(value)
	return value == nil or (type(value) == "number" and value >= 0 and value <= 1)
end

local FACTIONS = { Alliance = true, Horde = true }
local NPC_FACTIONS = { Alliance = true, Horde = true, Neutral = true }
local CLOCK_SKEW = 300 -- seconds a peer's clock may run ahead

local function ValidName(value)
	return value == nil or (type(value) == "string" and #value <= MAX_NAME_LENGTH and not value:find("[%c|]"))
end

local function OptionalID(value)
	return value == nil or PositiveID(value)
end

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

local function ValidRow(row)
	if type(row) ~= "table" or not SourceField(row) then return false end
	-- Local data answers both; an ID that is neither would wait in pendingItems for good.
	if row.i and not ns.IsRecipeItem(row.i) then return false end
	if row.r and not C_TradeSkillUI.GetTradeSkillLineForRecipe(row.r) then return false end
	-- Each kind carries only its own identity: a quest ID on quests, a drop's origin on drops.
	if row.k ~= "quest" and row.q then return false end
	if row.k ~= "drop" and (row.o or row.ci or row.fi or row.z or row.a or row.di or row.cn) then return false end
	if not (OptionalID(row.a) and OptionalID(row.di) and OptionalID(row.cn)) then return false end
	if (row.x == nil) ~= (row.y == nil) then return false end
	if not (ValidName(row.nm) and ValidName(row.on)) then return false end
	if not (OptionalID(row.n) and OptionalID(row.fn) and OptionalID(row.gi)) then return false end
	if row.m ~= nil and not (PositiveID(row.m) and C_Map.GetMapInfo(row.m)) then return false end
	if row.fi ~= nil and not C_Map.GetMapInfo(row.fi) then return false end
	if row.z ~= nil and not C_Map.GetMapInfo(row.z) then return false end
	if not (Coordinate(row.x) and Coordinate(row.y)) then return false end
	if row.f ~= nil and not FACTIONS[row.f] then return false end
	if row.nf ~= nil and not NPC_FACTIONS[row.nf] then return false end
	if row.s ~= nil and not (PositiveID(row.s) and row.s <= GetServerTime() + CLOCK_SKEW) then return false end
	for _, field in ipairs({ "b", "sk", "c", "p", "sp" }) do
		local value = row[field]
		if value ~= nil and not (type(value) == "number" and value >= 0 and value < ns.MAX_WIRE_NUMBER) then return false end
	end
	if row.sp ~= nil and not PositiveID(row.sp) then return false end
	if row.l ~= nil and type(row.l) ~= "boolean" then return false end
	if row.ch ~= nil and type(row.ch) ~= "boolean" then return false end
	return true
end

-- Wire key of each identifying field, and the observation field it fills.
local IDENTITY = { n = "npc", o = "object", ci = "container", fi = "fishing", z = "zone", q = "quest" }

-- Merges valid rows into the shared layer, newest per source; true if anything changed, false if not, nil for an invalid batch (nothing written).
-- Wire key of each saved field of a shared observation.
local MERGED_FIELDS = {
	npc = "n", object = "o", container = "ci", fishing = "fi", zone = "z", quest = "q", faction = "f",
	skill = "sk", cost = "c", price = "p", limited = "l", spellID = "sp", choice = "ch", finisher = "fn",
	giverItem = "gi", map = "m", x = "x", y = "y", area = "a", instance = "di", count = "cn",
}

function ns.MergeFinds(rows, maxRows)
	if type(rows) ~= "table" or #rows > maxRows then return nil end
	local count = 0
	for index, row in pairs(rows) do
		if not PositiveID(index) or index > #rows or not ValidRow(row) then return nil end
		count = count + 1
	end
	if count ~= #rows then return nil end
	local db, changed = ns.db, false
	for _, row in ipairs(rows) do
		local wireField = SourceField(row)
		local field, value = IDENTITY[wireField], row[wireField]
		if row.n then
			ns.NoteNPC(db.npcs, row.n, row.nm, not row.o and row.m, row.x, row.y, row.s, true)
			-- A peer only fills in a faction we have not seen ourselves.
			if not db.npcs[row.n].faction then ns.NoteNPCFaction(row.n, row.nf) end
		end
		if row.o then ns.NoteNPC(db.objects, row.o, row.on, row.m, row.x, row.y, row.s, true) end
		local bucket, id = row.r and db.shared.recipes or db.shared.items, row.r or row.i
		bucket[id] = bucket[id] or {}
		local observation
		for _, existing in ipairs(bucket[id]) do
			if existing.kind == row.k and existing[field] == value
				and (row.k ~= "drop" or ns.SamePlace(existing, { map = row.m, area = row.a, instance = row.di })) then
				observation = existing
				break
			end
		end
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
		-- reports never combine into a spot nobody stood at (Astra review); other sources use the NPC's.
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
	return changed
end

-- Export an array, not a table with sparse numeric keys: C_EncodingUtil.SerializeJSON rejects those.
ns.EXPORT_FORMAT_VERSION = 3

function ns.ExportFinds()
	local rows = ns.FindsSince(0, math.huge)
	local json = C_EncodingUtil.SerializeJSON({
		format = "RecipeVacuum", version = ns.EXPORT_FORMAT_VERSION, exportBuild = ns.BUILD, locale = GetLocale(),
		observations = rows,
	})
	LibStub("JigBoltgripToolkit-1.0"):ShowText(
		ns.title .. ": " .. ns.voice.exportTitle, json)
end
