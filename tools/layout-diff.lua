-- Prints Blizzard's profession window against our panel from a `layout` record (docs/development.md, "Working build").
-- Every number is in pixels from its pane's own top-left; differences over 1 px are flagged. Every record is kept as
-- "Profession / Recipe @ time"; a view name ("Engineering / Reagent Bot") picks its newest record, no name the newest of all,
-- --list names them all.
--   luajit tools/layout-diff.lua <SavedVariables/RecipeVacuum.lua> [--list | "Engineering / Reagent Bot" | full record name]
local path, wanted = arg[1], arg[2]
assert(path, "usage: luajit tools/layout-diff.lua <SavedVariables/RecipeVacuum.lua> [--list | name]")
local TOLERANCE = 1
dofile(path)
local layouts = assert(RecipeVacuumDB and RecipeVacuumDB.devLayout, "no devLayout in this file; open a profession in a working build, then /reload")
local names = {}
for key in pairs(layouts) do names[#names + 1] = key end
table.sort(names, function(a, b) return (layouts[a].when or a) < (layouts[b].when or b) end)
if wanted == "--list" then
	for _, key in ipairs(names) do print(("%s  %s"):format(tostring(layouts[key].version), key)) end
	return
end
local name
for _, key in ipairs(names) do
	if not wanted or key == wanted or key:sub(1, #wanted + 3) == wanted .. " @ " then name = key end
end
local record = assert(name and layouts[name], "no record named " .. tostring(wanted) .. "; --list shows them")
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
