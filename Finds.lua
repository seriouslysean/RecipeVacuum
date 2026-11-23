local _, ns = ...

-- The revision belongs to the account's collection. Alts advertise the same collection,
-- and an interrupted recipient resumes after the last complete page it saved.
ns.findPageSize = 32

function ns.ForgetFind(entry)
	if entry.shareRevision then
		ns.db.exchange.keys[entry.shareRevision] = nil
	end
end

function ns.MarkFind(key, entry)
	local exchange = ns.db.exchange
	ns.ForgetFind(entry)
	exchange.revision = exchange.revision + 1
	entry.shareRevision = exchange.revision
	exchange.keys[entry.shareRevision] = key
	ns.ScheduleFindOffer()
end

function ns.InitFinds()
	local exchange = ns.db.exchange
	if exchange and exchange.keys then return end
	exchange = exchange or {
		id = ("%d-%d"):format(GetServerTime(), math.random(1000000000)),
		revision = 0, received = {},
	}
	ns.db.exchange, exchange.keys = exchange, {}
	for key, entries in pairs(ns.db.sources) do
		for _, entry in ipairs(entries) do
			if entry.origin == "self" then
				if entry.shareRevision then
					exchange.keys[entry.shareRevision] = key
				else
					ns.MarkFind(key, entry)
				end
			end
		end
	end
end

-- Use an allowlist for both exchange and export. Personal settings and session context
-- never belong to an observation. Provenance is assigned by the receiving account.
local fields = {
	type = "string", npcID = "number", npcName = "string", faction = "string",
	mapID = "number", x = "number", y = "number", seen = "number",
	name = "string", skill = "number", cost = "number",
	itemID = "number", itemName = "string", recipeName = "string", spellID = "number",
	price = "number", limited = "boolean", linkedRecipeID = "number",
}

local function Observation(key, entry)
	local row = { key = key }
	for field in pairs(fields) do row[field] = entry[field] end
	if row.itemID and not row.recipeName then
		local pending = ns.db.pendingItems[row.itemID]
		row.recipeName = pending and pending.name
		if not row.recipeName and row.itemName then
			row.recipeName = row.itemName:match("^.-:%s*(.+)$") or row.itemName
		end
		if not row.recipeName and not row.spellID then
			row.linkedRecipeID = ns.db.itemRecipe[row.itemID]
		end
	end
	return row
end

function ns.FindPage(after, selection)
	local exchange = ns.db.exchange
	local last = math.min(after + (selection and #selection or ns.findPageSize), exchange.revision)
	local rows = {}
	for revision = after + 1, last do
		local offset = revision - after
		local key = exchange.keys[revision]
		if key and (not selection or selection:sub(offset, offset) == "1") then
			for _, entry in ipairs(ns.db.sources[key]) do
				if entry.shareRevision == revision then
					local row = selection and Observation(key, entry) or { offset, key, entry.npcID, entry.spellID }
					table.insert(rows, row)
					break
				end
			end
		end
	end
	return last, rows
end

local function PositiveID(value)
	return type(value) == "number" and value > 0 and value < 2^32 and value == math.floor(value)
end

-- A peer can share an entire trainer catalog we have already seen. Compare the small
-- list of identities first; the next whisper requests only the missing observations.
function ns.SelectFinds(identities, size)
	if type(identities) ~= "table" then return nil end
	local selection = {}
	for i = 1, size do selection[i] = "0" end
	for _, identity in ipairs(identities) do
		if type(identity) ~= "table" then return nil end
		local offset, key, npcID, spellID = unpack(identity)
		if not PositiveID(offset) or offset > size or not PositiveID(npcID)
			or not (PositiveID(key) or type(key) == "string")
			or (spellID and not PositiveID(spellID)) then return nil end
		local needed = true
		for _, entry in ipairs(ns.db.sources[key] or {}) do
			if entry.npcID == npcID then
				needed = entry.origin ~= "self" and spellID ~= nil and entry.spellID == nil
				break
			end
		end
		if needed then selection[offset] = "1" end
	end
	return table.concat(selection)
end

local function ValidRow(row)
	if type(row) ~= "table" or not PositiveID(row.npcID) then return false end
	for field, kind in pairs(fields) do
		local value = row[field]
		if value ~= nil and type(value) ~= kind then return false end
		if kind == "string" and value and (#value > 1024 or value:find("[%c|]")) then return false end
	end
	if row.type == "trainer" then
		return PositiveID(row.key) or (type(row.key) == "string" and #row.key <= 1029
			and row.key:match("^name:.+") and not row.key:find("[%c|]"))
	end
	return row.type == "vendor" and PositiveID(row.itemID) and row.key == ns.ItemKey(row.itemID)
		and (not row.spellID or PositiveID(row.spellID))
		and (not row.linkedRecipeID or PositiveID(row.linkedRecipeID))
end

local function Merge(row)
	local db, key = ns.db, row.key
	local entries = db.sources[key]
	if not entries then
		entries = {}
		db.sources[key] = entries
	end
	local entry
	for _, found in ipairs(entries) do
		if found.type == row.type and found.npcID == row.npcID then entry = found; break end
	end
	if entry and entry.origin == "self" then return false end
	local changed = false
	if not entry then
		entry = { origin = "shared" }
		table.insert(entries, entry)
	end
	for field in pairs(fields) do
		if entry[field] == nil and row[field] ~= nil then
			entry[field] = row[field]
			changed = true
		end
	end
	if entry.itemID and not db.itemRecipe[entry.itemID] then
		local pending = db.pendingItems[entry.itemID] or {}
		pending.name = pending.name or (entry.recipeName and entry.recipeName:lower())
		pending.spellID = pending.spellID or entry.spellID
		pending.linkedRecipeID = pending.linkedRecipeID or entry.linkedRecipeID
		db.pendingItems[entry.itemID] = pending
	end
	return changed
end

function ns.MergeFindPage(rows)
	if type(rows) ~= "table" or #rows > ns.findPageSize then return nil end
	local count = 0
	for i, row in pairs(rows) do
		if not PositiveID(i) or i > #rows or not ValidRow(row) then return nil end
		count = count + 1
	end
	if count ~= #rows then return nil end
	local changed = false
	for _, row in ipairs(rows) do
		if Merge(row) then changed = true end
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

function ns.ExportFinds()
	local observations = {}
	for key, entries in pairs(ns.db.sources) do
		for _, entry in ipairs(entries) do
			if entry.origin == "self" then table.insert(observations, Observation(key, entry)) end
		end
	end
	local _, build = GetBuildInfo()
	local json = C_EncodingUtil.SerializeJSON({
		format = "RecipeVacuum", version = 1, exportBuild = build, locale = GetLocale(),
		observations = observations,
	})
	StaticPopup_Show("RECIPEVACUUM_EXPORT", nil, nil, json)
end
