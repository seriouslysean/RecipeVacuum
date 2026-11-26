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

-- The rank spells: SpellEffect rows of Effect 118 (SKILL_STEP) name the skill line in EffectMiscValue_0 and the step in
-- EffectBasePointsF (Blacksmithing 164: Apprentice 2018 step 1, Journeyman 3100 step 2). Where two spells share a step
-- (Forever's added 1235xxx spells beside the classic ones), the lowest spell ID is kept, the classic rank spell.
local SKILL_STEP_EFFECT = 118
local rankSpell, rankSpellFlat = {}, {}
local rankNote
do
	local url = ("https://wago.tools/db2/SpellEffect/csv?build=%s.%d"):format(GAME_VERSION, build)
	local csv = assert(io.popen("curl -fsS " .. ("%q"):format(url))):read("*a")
	assert(csv ~= "", "no table from " .. url)
	local columns
	local steps, ties = 0, 0
	for fields in CsvRows(csv) do
		if not columns then
			columns = {}
			for index, name in ipairs(fields) do columns[name] = index end
			for _, name in ipairs({ "SpellID", "Effect", "EffectMiscValue_0", "EffectBasePointsF" }) do
				assert(columns[name], "SpellEffect has no " .. name .. " column")
			end
		elseif tonumber(fields[columns.Effect]) == SKILL_STEP_EFFECT then
			local spellID = tonumber(fields[columns.SpellID])
			local line, step = tonumber(fields[columns.EffectMiscValue_0]), tonumber(fields[columns.EffectBasePointsF])
			if spellID and line and step then
				rankSpell[line] = rankSpell[line] or {}
				local old = rankSpell[line][step]
				if old then ties = ties + 1 end
				if not old or spellID < old then rankSpell[line][step] = spellID end
			end
		end
	end
	for line, bySteps in pairs(rankSpell) do
		for step, spellID in pairs(bySteps) do
			steps = steps + 1
			rankSpellFlat[line * 100 + step] = spellID
		end
	end
	rankNote = ("Game build %d: %d rank spells (Effect %d), %d steps with two spells took the lower ID."):format(build, steps, SKILL_STEP_EFFECT, ties)
end

-- The skill-up thresholds: SkillLineAbility rows give the skill where a recipe turns yellow (TrivialSkillLineRankLow) and where it turns
-- grey (TrivialSkillLineRankHigh); the green point between them is derived in the panel (docs/data.md, "Skill-up colors"). A recipe
-- with no rank high has none given and is left out. Where a spell has rows in two skill lines the lowest of each is kept.
local trivialLow, trivialHigh = {}, {}
local trivialNote
do
	local url = ("https://wago.tools/db2/SkillLineAbility/csv?build=%s.%d"):format(GAME_VERSION, build)
	local csv = assert(io.popen("curl -fsS -A 'Mozilla/5.0' " .. ("%q"):format(url))):read("*a")
	assert(csv ~= "", "no table from " .. url)
	local columns
	for fields in CsvRows(csv) do
		if not columns then
			columns = {}
			for index, name in ipairs(fields) do columns[name] = index end
			for _, name in ipairs({ "Spell", "TrivialSkillLineRankLow", "TrivialSkillLineRankHigh" }) do
				assert(columns[name], "SkillLineAbility has no " .. name .. " column")
			end
		else
			local spellID = tonumber(fields[columns.Spell])
			local low, high = tonumber(fields[columns.TrivialSkillLineRankLow]), tonumber(fields[columns.TrivialSkillLineRankHigh])
			if spellID and low and high and high > 0 then
				trivialLow[spellID] = math.min(trivialLow[spellID] or low, low)
				trivialHigh[spellID] = math.min(trivialHigh[spellID] or high, high)
			end
		end
	end
	local count = 0
	for _ in pairs(trivialHigh) do count = count + 1 end
	trivialNote = ("Game build %d: %d recipes with skill-up thresholds (SkillLineAbility)."):format(build, count)
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
local currentFlat = {}
for line, bySteps in pairs(current.rankSpell or {}) do
	for step, spellID in pairs(bySteps) do currentFlat[line * 100 + step] = spellID end
end
local rankAdded, rankProblems = Differences("rank spell of skill line * 100 + step", rankSpellFlat, currentFlat)
print(("rankSpell: %d pairs, %d added, %d removed or changed"):format(Count(rankSpellFlat), rankAdded, #rankProblems))
local lowAdded, lowProblems = Differences("trivial low of recipe", trivialLow, current.trivialLow or {})
local highAdded, highProblems = Differences("trivial high of recipe", trivialHigh, current.trivialHigh or {})
print(("trivialLow: %d pairs, %d added, %d removed or changed"):format(Count(trivialLow), lowAdded, #lowProblems))
print(("trivialHigh: %d pairs, %d added, %d removed or changed"):format(Count(trivialHigh), highAdded, #highProblems))
print(("learnSkill: %d pairs, %d added, %d removed or changed"):format(Count(learnSkill), skillAdded, #skillProblems))
if #taughtProblems + #skillProblems + #rankProblems + #lowProblems + #highProblems > 0 and not accept then
	for _, line in ipairs(taughtProblems) do print(line) end
	for _, line in ipairs(skillProblems) do print(line) end
	for _, line in ipairs(rankProblems) do print(line) end
	for _, line in ipairs(lowProblems) do print(line) end
	for _, line in ipairs(highProblems) do print(line) end
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
	("ns.seed = { build = %d, taughtNote = %q, learnNote = %q, rankNote = %q, trivialNote = %q,"):format(build, taughtNote, learnNote, rankNote, trivialNote),
	"\ttaught = {",
}
Rows(lines, taught)
lines[#lines + 1] = "\t},"
lines[#lines + 1] = "\tlearnSkill = {"
Rows(lines, learnSkill)
lines[#lines + 1] = "\t},"
lines[#lines + 1] = "\ttrivialLow = {"
Rows(lines, trivialLow)
lines[#lines + 1] = "\t},"
lines[#lines + 1] = "\ttrivialHigh = {"
Rows(lines, trivialHigh)
lines[#lines + 1] = "\t},"
lines[#lines + 1] = "\trankSpell = {"
local seedLines = {}
for line in pairs(rankSpell) do seedLines[#seedLines + 1] = line end
table.sort(seedLines)
for _, line in ipairs(seedLines) do
	local steps = {}
	for step in pairs(rankSpell[line]) do steps[#steps + 1] = step end
	table.sort(steps)
	local parts = {}
	for _, step in ipairs(steps) do parts[#parts + 1] = ("[%d]=%d,"):format(step, rankSpell[line][step]) end
	lines[#lines + 1] = ("\t\t[%d]={ %s },"):format(line, table.concat(parts, " "))
end
lines[#lines + 1] = "\t},"
lines[#lines + 1] = "}"
lines[#lines + 1] = ""
local out = assert(io.open(outPath, "w"))
out:write(table.concat(lines, "\n"))
out:close()
print(("wrote %s"):format(outPath))
