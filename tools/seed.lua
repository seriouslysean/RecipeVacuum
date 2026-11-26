-- Builds Data/Seed.lua from what the working build read in game and from Blizzard's item table (docs/development.md, "Seeding").
-- The tables only grow unasked: a read that would remove or change a pair writes nothing and lists the
-- differences; --accept as a third argument is for once they are checked.
local savedPath, outPath, accept = arg[1], arg[2], arg[3] == "--accept"
assert(savedPath and outPath, "usage: luajit tools/seed.lua <saved variables file> <output file> [--accept]")
-- wago.tools names a build by its full version; the client is WoW Forever (product wowf), whose version is this and the seed's build.
local GAME_VERSION = "1.60.1"
dofile(savedPath)
local db = assert(RecipeVacuumDB, "no RecipeVacuumDB in this file")

local current = {}
local existing = loadfile(outPath)
if existing then
	local holder = {}
	existing("RecipeVacuum", holder)
	current = holder.seed or {}
end

-- The item scan: pairs plus the counts for the header. Without a scan, the current table is kept as it is.
local taught, taughtNote
local scan = db.devScan
if scan and scan.items and scan.teaches then
	local nothing, unanswered, count = 0, 0, 0
	taught = {}
	for _, itemID in ipairs(scan.items) do
		local recipeID = scan.teaches[itemID]
		if type(recipeID) == "number" and recipeID > 0 then
			taught[itemID], count = recipeID, count + 1
		elseif recipeID == false then
			nothing = nothing + 1
		else
			unanswered = unanswered + 1
		end
	end
	taughtNote = ("Game build %s: %d recipe items, %d teach a recipe, %d teach nothing, %d gave no answer."):format(
		tostring(scan.build), #scan.items, count, nothing, unanswered)
else
	taught = current.taught or {}
	taughtNote = current.taughtNote or "Kept from the previous seed."
end

-- The CSV's rows, each a list of fields; a quoted field may hold commas, line breaks and doubled quotes.
-- The same reader as the toolkit's tools/glossary.lua.
local function CsvRows(text)
	local position = 1
	return function()
		if position > #text then return nil end
		local fields = {}
		while true do
			local value
			if text:sub(position, position) == '"' then
				value, position = "", position + 1
				while true do
					local quote = assert(text:find('"', position, true), "unclosed quote in the table")
					value = value .. text:sub(position, quote - 1)
					position = quote + 1
					if text:sub(position, position) ~= '"' then break end
					value, position = value .. '"', position + 1
				end
			else
				local stop = text:find("[,\r\n]", position) or (#text + 1)
				value, position = text:sub(position, stop - 1), stop
			end
			fields[#fields + 1] = value
			local mark = text:sub(position, position)
			position = position + 1
			if mark == "\r" and text:sub(position, position) == "\n" then position = position + 1 end
			if mark ~= "," then return fields end
		end
	end
end

-- The skill each recipe is learned at: the lowest RequiredSkillRank among the recipe items that teach it.
-- A rank of 0 is no requirement and gives nothing, so the panel treats the recipe as unknown rather than free.
local build = scan and tonumber(scan.build) or current.build or 0
local learnSkill, learnNote
do
	local url = ("https://wago.tools/db2/ItemSparse/csv?build=%s.%d"):format(GAME_VERSION, build)
	local csv = assert(io.popen("curl -fsS " .. ("%q"):format(url))):read("*a")
	assert(csv ~= "", "no table from " .. url)
	local idColumn, rankColumn
	local ranks, itemsRead = {}, 0
	for fields in CsvRows(csv) do
		if not idColumn then
			for index, name in ipairs(fields) do
				if name == "ID" then idColumn = index elseif name == "RequiredSkillRank" then rankColumn = index end
			end
			assert(idColumn and rankColumn, "ItemSparse has no ID or RequiredSkillRank column")
		else
			local itemID = tonumber(fields[idColumn])
			if itemID and taught[itemID] then
				itemsRead = itemsRead + 1
				ranks[itemID] = tonumber(fields[rankColumn]) or 0
			end
		end
	end
	learnSkill = {}
	local unlisted = 0
	for itemID, recipeID in pairs(taught) do
		local rank = ranks[itemID]
		if rank == nil then
			unlisted = unlisted + 1
		elseif rank > 0 and (learnSkill[recipeID] == nil or rank < learnSkill[recipeID]) then
			learnSkill[recipeID] = rank
		end
	end
	local recipes = {}
	for _, recipeID in pairs(taught) do recipes[recipeID] = true end
	local recipeCount, skillCount = 0, 0
	for _ in pairs(recipes) do recipeCount = recipeCount + 1 end
	for _ in pairs(learnSkill) do skillCount = skillCount + 1 end
	learnNote = ("Game build %d: %d of %d taught recipes have a required skill; %d recipe items are not in ItemSparse."):format(
		build, skillCount, recipeCount, unlisted)
end

-- Compare the table with the seed on disk.
local function Differences(name, fresh, old)
	local added, problems = 0, {}
	for key, value in pairs(fresh) do
		if old[key] == nil then
			added = added + 1
		elseif old[key] ~= value then
			problems[#problems + 1] = ("  %s %d: %d -> %d"):format(name, key, old[key], value)
		end
	end
	for key, value in pairs(old) do
		if fresh[key] == nil then
			problems[#problems + 1] = ("  %s %d (%d) is no longer read"):format(name, key, value)
		end
	end
	table.sort(problems)
	return added, problems
end

local function Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
local taughtAdded, taughtProblems = Differences("taught item", taught, current.taught or {})
local skillAdded, skillProblems = Differences("learn skill of recipe", learnSkill, current.learnSkill or {})
print(("taught: %d pairs, %d added, %d removed or changed"):format(Count(taught), taughtAdded, #taughtProblems))
print(("learnSkill: %d pairs, %d added, %d removed or changed"):format(Count(learnSkill), skillAdded, #skillProblems))
if #taughtProblems + #skillProblems > 0 and not accept then
	for _, line in ipairs(taughtProblems) do print(line) end
	for _, line in ipairs(skillProblems) do print(line) end
	print("nothing written: check these against the game, then run again with --accept")
	os.exit(1)
end

-- Eight pairs to a line keeps the file small without one unreadable line.
local function Rows(lines, t)
	local keys = {}
	for key in pairs(t) do keys[#keys + 1] = key end
	table.sort(keys)
	local row = {}
	for index, key in ipairs(keys) do
		row[#row + 1] = ("[%d]=%d,"):format(key, t[key])
		if #row == 8 or index == #keys then
			lines[#lines + 1] = "\t\t" .. table.concat(row, " ")
			row = {}
		end
	end
end

local lines = {
	"local _, ns = ...",
	"",
	"-- Generated by tools/seed.lua from the game client; do not edit (docs/development.md, \"Seeding\").",
	"-- taught: " .. taughtNote,
	"-- learnSkill: " .. learnNote,
	("ns.seed = { build = %d, taughtNote = %q, learnNote = %q,"):format(build, taughtNote, learnNote),
	"\ttaught = {",
}
Rows(lines, taught)
lines[#lines + 1] = "\t},"
lines[#lines + 1] = "\tlearnSkill = {"
Rows(lines, learnSkill)
lines[#lines + 1] = "\t},"
lines[#lines + 1] = "}"
lines[#lines + 1] = ""
local out = assert(io.open(outPath, "w"))
out:write(table.concat(lines, "\n"))
out:close()
print(("wrote %s"):format(outPath))
