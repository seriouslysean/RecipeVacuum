-- Prints Blizzard's profession window against our panel from a `layout` record (docs/development.md, "Working build").
-- Every number is in pixels from its pane's own top-left; differences over 1 px are flagged. Records are kept one per
-- "Profession / Recipe"; with no name the newest is shown, and --list names them all.
--   luajit tools/layout-diff.lua <SavedVariables/RecipeVacuum.lua> [--list | "Engineering / Reagent Bot"]
local path, wanted = arg[1], arg[2]
assert(path, "usage: luajit tools/layout-diff.lua <SavedVariables/RecipeVacuum.lua> [--list | name]")
local TOLERANCE = 1
dofile(path)
local layouts = assert(RecipeVacuumDB and RecipeVacuumDB.devLayout, "no devLayout in this file; open a profession in a working build, then /reload")
local names, newest = {}, nil
for key, record in pairs(layouts) do
	names[#names + 1] = key
	local when = record.when or key
	if not newest or when > (layouts[newest].when or newest) then newest = key end
end
table.sort(names)
if wanted == "--list" then
	for _, key in ipairs(names) do print(("%s  %s  %s"):format(layouts[key].when or "?", tostring(layouts[key].version), key)) end
	return
end
local name = wanted or newest
local record = assert(name and layouts[name], "no record named " .. tostring(name) .. "; --list shows them")
print(("%s | %s | %s | build %s | scales: window %.3f, panel %.3f"):format(name, tostring(record.when), tostring(record.version),
	tostring(record.build), record.windowScale or 0, record.panelScale or 0))

local FIELDS = { "left", "top", "width", "height", "stringWidth", "stringHeight", "lines", "fontSize", "wrapWidth" }
local TEXT = { "fontObject", "fontFlags", "justifyH", "justifyV", "atlas", "texture", "wordWrap" }

local function Format(value)
	if type(value) == "number" then return ("%.1f"):format(value) end
	return value == nil and "-" or tostring(value)
end

local rows, flagged = {}, 0
for _, pair in ipairs(record.pairs) do
	local blizzard, ours = pair.blizzard or {}, pair.ours or {}
	if blizzard.missing or ours.missing then
		rows[#rows + 1] = { pair.pane, pair.measure, "(" .. (blizzard.missing and "Blizzard" or "ours") .. " missing)", "", "", "", "" }
	else
		for _, field in ipairs(FIELDS) do
			local first, second = blizzard[field], ours[field]
			if first ~= nil or second ~= nil then
				local difference = type(first) == "number" and type(second) == "number" and second - first or nil
				local flag = (difference == nil and first ~= second) or (difference and math.abs(difference) > TOLERANCE)
				flagged = flagged + (flag and 1 or 0)
				rows[#rows + 1] = { pair.pane, pair.measure, field, Format(first), Format(second),
					difference and ("%+.1f"):format(difference) or "", flag and "<<" or "" }
			end
		end
		for _, field in ipairs(TEXT) do
			local first, second = blizzard[field], ours[field]
			if first ~= nil or second ~= nil then
				local flag = first ~= second
				flagged = flagged + (flag and 1 or 0)
				rows[#rows + 1] = { pair.pane, pair.measure, field, Format(first), Format(second), "", flag and "<<" or "" }
			end
		end
	end
end

local widths = { 0, 0, 0, 0, 0, 0, 0 }
local header = { "pane", "measure", "field", "Blizzard", "ours", "diff px", "" }
table.insert(rows, 1, header)
for _, row in ipairs(rows) do
	for column, text in ipairs(row) do widths[column] = math.max(widths[column], #text) end
end
for _, row in ipairs(rows) do
	local cells = {}
	for column, text in ipairs(row) do cells[column] = text .. (" "):rep(widths[column] - #text) end
	print((table.concat(cells, "  "):gsub("%s+$", "")))
end
print(("%d flagged (difference over %d px, or text that differs)"):format(flagged, TOLERANCE))
