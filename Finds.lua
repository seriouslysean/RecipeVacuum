local _, ns = ...

-- The account's self-found finds form one collection with an ID and a revision counter.
-- Every observation carries the revision of its last meaningful change; a peer that saved
-- revision N asks for everything after N. A new collection ID is issued whenever revisions
-- are renumbered (a migration or a reset), so peers that saved a higher number resync from
-- zero instead of believing they are current.

local revisions = {} -- in memory only: { { rev, observation, ref = "recipe" | "item", id }, ... } in rev order

local function NewCollectionID()
	return ("%d-%d"):format(GetServerTime(), math.random(1000000000))
end

function ns.MarkFind(observation, ref, id)
	local exchange = ns.db.exchange
	exchange.revision = exchange.revision + 1
	observation.rev = exchange.revision
	table.insert(revisions, { rev = observation.rev, observation = observation, ref = ref, id = id })
	ns.ScheduleFindOffer()
end

-- Rebuilds the revision index from the saved layer; it is derived data, so it is not saved.
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
		-- Saved revisions ahead of the counter mean the counter was reset: renumber.
		db.exchange.id, db.exchange.revision = NewCollectionID(), highest
	end
	for _, row in ipairs(unrevised) do
		db.exchange.revision = db.exchange.revision + 1
		row.observation.rev, row.rev = db.exchange.revision, db.exchange.revision
		table.insert(revisions, row)
	end
end

-- Wire rows carry IDs only: names of items, recipes and quests are read from each client in
-- its own language. NPC names are the one exception (no client lookup by NPC ID).
local function WireRow(row)
	local observation = row.observation
	local npc = ns.db.npcs[observation.npc] or {}
	local mapID, position
	for candidate, saved in pairs(npc.positions or {}) do
		if not position or (saved.seen or 0) > (position.seen or 0) then
			mapID, position = candidate, saved
		end
	end
	return {
		k = observation.kind, r = row.ref == "recipe" and row.id or nil, i = row.ref == "item" and row.id or nil,
		n = observation.npc, nm = npc.name, m = mapID, x = position and position.x, y = position and position.y,
		f = observation.faction, s = observation.seen, b = observation.build,
		sk = observation.skill, c = observation.cost, p = observation.price, l = observation.limited,
		sp = observation.spellID,
	}
end

-- Observations after revision `after`, oldest first, as wire rows: at most `limit` rows.
-- Returns the rows and the revision they cover through.
function ns.FindsSince(after, limit)
	local rows, through = {}, after
	for _, row in ipairs(revisions) do
		-- A row is stale when its observation changed again later; the newer row covers it.
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

-- Validation runs on every received row before anything is saved. Received data is only
-- parsed, never executed (the another addon 2021 incident ran received text through loadstring).
local function PositiveID(value)
	return type(value) == "number" and value > 0 and value < 2^32 and value == math.floor(value)
end

local function Coordinate(value)
	return value == nil or (type(value) == "number" and value >= 0 and value <= 1)
end

local FACTIONS = { Alliance = true, Horde = true }

local function ValidRow(row)
	if type(row) ~= "table" or not PositiveID(row.n) then return false end
	if row.k == "trainer" then
		if not PositiveID(row.r) or row.i ~= nil then return false end
	elseif row.k == "vendor" then
		if not PositiveID(row.i) or row.r ~= nil then return false end
	else
		return false
	end
	if row.nm ~= nil and (type(row.nm) ~= "string" or #row.nm > 64 or row.nm:find("[%c|]")) then return false end
	if row.m ~= nil and not (PositiveID(row.m) and C_Map.GetMapInfo(row.m)) then return false end
	if not (Coordinate(row.x) and Coordinate(row.y)) then return false end
	if row.f ~= nil and not FACTIONS[row.f] then return false end
	if row.s ~= nil and not (PositiveID(row.s) and row.s <= GetServerTime() + 300) then return false end
	for _, field in ipairs({ "b", "sk", "c", "p", "sp" }) do
		local value = row[field]
		if value ~= nil and not (type(value) == "number" and value >= 0 and value < 2^32) then return false end
	end
	if row.sp ~= nil and not PositiveID(row.sp) then return false end
	if row.l ~= nil and type(row.l) ~= "boolean" then return false end
	return true
end

-- Merges valid rows into the shared layer, newest observation winning per source.
-- Returns true when anything changed, false when nothing did, nil when the batch is invalid
-- (nothing is written then).
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
		ns.NoteNPC(db.npcs, row.n, row.nm, row.m, row.x, row.y, row.s)
		local bucket, id = row.r and db.shared.recipes or db.shared.items, row.r or row.i
		bucket[id] = bucket[id] or {}
		local observation
		for _, existing in ipairs(bucket[id]) do
			if existing.kind == row.k and existing.npc == row.n then
				observation = existing
				break
			end
		end
		if not observation or (row.s or 0) > (observation.seen or 0) then
			if not observation then
				observation = { kind = row.k, npc = row.n }
				table.insert(bucket[id], observation)
			end
			observation.faction, observation.seen, observation.build = row.f, row.s, row.b
			observation.skill, observation.cost, observation.price = row.sk, row.c, row.p
			observation.limited, observation.spellID = row.l, row.sp
			changed = true
		end
		if row.i and not db.itemRecipe[row.i] then
			db.pendingItems[row.i] = db.pendingItems[row.i] or { spellID = row.sp }
		end
	end
	return changed
end

StaticPopupDialogs.RECIPEVACUUM_EXPORT = {
	text = "Copy your personal recipe finds and send them to the toolkit maintainer as a .json file.",
	button1 = CLOSE, hasEditBox = true, timeout = 0, whileDead = true, hideOnEscape = true,
	OnShow = function(dialog, json)
		local editBox = dialog:GetEditBox()
		editBox:SetMaxLetters(0)
		editBox:SetText(json)
		editBox:SetFocus()
		editBox:HighlightText()
	end,
}

-- The export is an array of records, never a table with sparse numeric keys:
-- C_EncodingUtil.SerializeJSON rejects those (measured in game, 2026-11-22).
ns.EXPORT_FORMAT_VERSION = 2

function ns.ExportFinds()
	local rows = ns.FindsSince(0, math.huge)
	local _, build = GetBuildInfo()
	local json = C_EncodingUtil.SerializeJSON({
		format = "RecipeVacuum", version = ns.EXPORT_FORMAT_VERSION, exportBuild = build, locale = GetLocale(),
		observations = rows,
	})
	StaticPopup_Show("RECIPEVACUUM_EXPORT", nil, nil, json)
end
