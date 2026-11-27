local _, ns = ...
local L = ns.L

-- Works out which recipes a character has not learned, grouped by category, for Recipe Vacuum's own panel. It writes nothing into Blizzard's frames (docs/client-notes.md, "Gamepad").

-- A category keeps its header when a recipe in it is learned or has a known source; the rest share MISCELLANEOUS, last.
-- The ID is ours: the game's category IDs are positive and -1 is its Favorites header (Blizzard_Professions.lua).
local MISCELLANEOUS_CATEGORY_ID = -2

-- Two stages, each cleared by what changes its inputs: the client's answer (learning a recipe; a rank or cap change only refreshes
-- difficulty) and our source summaries (any change to the known sources). Window opens and source switches change neither
-- (docs/client-notes.md, "Panel").
local reads = {} -- stage one, [professionID] = { candidates, established, complete, skillChanges }
local cache = {} -- stage two, [professionID] = categories of a complete read
-- The read runs in slices, a few ms a frame, as a coroutine (the pattern addons use for long loops); one job per profession.
local jobs = {} -- [professionID] = { co, slices, ms, worst, stage, stageMs }
local partial = {} -- [professionID] = categories of a finished read whose data was incomplete, handed to the next call once
local listed = {} -- [professionID] = { categories, list, total }, built with the read
local SLICE_MS = 2 -- the read shares its first frame with the panel's other work, so a slice stays well under the 5 ms frame bar
local skillChanges = 0 -- raised when a profession's rank or cap changed, which moves every recipe's difficulty

-- A profession's rank and cap, as the skill bar reads them (GetProfessionInfo), to tell a skill event that moved nothing.
local function SkillSnapshot()
	local parts = {}
	for _, index in pairs({ GetProfessions() }) do
		local _, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(index)
		parts[#parts + 1] = ("%s:%s:%s"):format(tostring(skillLine), tostring(rank), tostring(maxRank))
	end
	table.sort(parts)
	return table.concat(parts, ",")
end
local skillSnapshot

local function ForgetSummaries(reason)
	wipe(cache)
	wipe(jobs) -- a running read sees its job gone and stops
	wipe(partial)
	ns.toolkit:Trace(ns.module, "UNLEARNED summaries cleared by %s, the client's answers kept", reason)
end

ns.toolkit:EventFrame(ns.module, {
	NEW_RECIPE_LEARNED = function()
		wipe(reads)
		ForgetSummaries("NEW_RECIPE_LEARNED")
		ns.ClearRecipeLocks()
	end,
	SKILL_LINES_CHANGED = function()
		ns.ClearRecipeLocks()
		local snapshot = SkillSnapshot()
		if snapshot == skillSnapshot then
			ns.toolkit:Trace(ns.module, "UNLEARNED SKILL_LINES_CHANGED moved no profession's rank or cap, nothing cleared")
			return
		end
		skillSnapshot = snapshot
		skillChanges = skillChanges + 1
		ForgetSummaries("a rank or cap change")
	end,
})

-- New recorded sources invalidate the cached source summaries.
function ns.ClearUnlearnedCache()
	ForgetSummaries("new sources")
end

local function SortByName(a, b)
	return strcmputf8i(a.name, b.name) < 0
end

local function SortCategories(a, b)
	if a.info.uiOrder ~= b.info.uiOrder then
		return a.info.uiOrder < b.info.uiOrder
	end
	return SortByName(a.info, b.info)
end

-- The skill a recipe is ordered and shown by: the skill to learn it where known, else the trivial level, the nearest threshold the client gives.
function ns.SkillOf(recipeInfo)
	return recipeInfo.requiredSkill or recipeInfo.maxTrivialLevel
end

local function SortRecipes(left, right)
	local leftSkill, rightSkill = ns.SkillOf(left), ns.SkillOf(right)
	if leftSkill ~= rightSkill then
		return leftSkill < rightSkill
	end
	local nameOrder = strcmputf8i(left.name, right.name)
	if nameOrder ~= 0 then
		return nameOrder < 0
	end
	return left.recipeID < right.recipeID
end

-- The time since the last mark goes to the stage that was running, so the trace names the slow one.
local function Charge(job)
	if not job then return end
	local now = debugprofilestop()
	job.stageMs[job.stage] = (job.stageMs[job.stage] or 0) + now - job.mark
	job.mark = now
end

local function Stage(job, name)
	if job then
		Charge(job)
		job.stage = name
	end
end

local function Yield(job)
	if job and debugprofilestop() - job.sliceStart >= SLICE_MS then
		Charge(job)
		coroutine.yield()
	end
end

-- What the panel lists for a profession: the unlearned recipes of the open skill line that pass the show rule (ns.IsListed), in one flat
-- list in skill-up order, and the total of the discovery count, every candidate before the show rule (docs/data.md, "Discovery").
local function BuildListed(professionID, categories, job)
	local list, total = {}, 0
	for _, category in ipairs(categories) do
		total = total + #category.recipes
		for _, recipeInfo in ipairs(category.recipes) do
			Yield(job)
			if ns.IsListed(recipeInfo) then
				table.insert(list, recipeInfo)
			end
		end
	end
	table.sort(list, SortRecipes)
	local entry = { categories = categories, list = list, total = total }
	listed[professionID] = entry
	return entry
end

-- Stage one: the client's answer for a profession, its unlearned candidates (another faction's left out) and the categories its
-- learned recipes establish.
local function ReadClient(professionID, job)
	local candidates, established = {}, {}
	local playerFaction = UnitFactionGroup("player")
	local indexComplete, factionsComplete = true, true
	local knownCount, knownNew = 0, 0
	for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs()) do
		Yield(job)
		local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
		-- A recipe without its name is as unloaded as no recipe: the sort and the search fold read the name.
		if not (recipeInfo and recipeInfo.name) then
			indexComplete = false
		-- professionID is the window's open skill line, so another expansion's recipes of the same profession are not candidates (docs/data.md, "Show rule").
		elseif C_TradeSkillUI.IsRecipeInSkillLine(recipeID, professionID) then
			-- A learned recipe is read only to find a picked specialization, and only until one is found;
			-- unlearned ones are read when listed.
			if recipeInfo.learned and not ns.HasSpecialization(recipeID) then
				ns.ReadSpecialization(recipeID)
			end
			if recipeInfo.learned then
				knownCount = knownCount + 1
				if ns.NoteKnown(recipeID) then knownNew = knownNew + 1 end
			end
			recipeInfo = Professions.GetFirstRecipe(recipeInfo)
			if recipeInfo and recipeInfo.learned then
				established[recipeInfo.categoryID] = true
			elseif recipeInfo then
				local faction = ns.GetRecipeFaction(recipeInfo.recipeID)
				if faction == nil then
					factionsComplete = false
				end
				-- Other-faction versions are left out, as Blizzard never lists them.
				if not (faction and faction ~= playerFaction) then
					table.insert(candidates, recipeInfo)
				end
			end
		end
	end
	ns.toolkit:Trace(ns.module, "UNLEARNED profession %d: %d known recipes marked met at Self Found, %d new", professionID, knownCount, knownNew)
	return { candidates = candidates, established = established, complete = indexComplete and factionsComplete, skillChanges = skillChanges }
end

-- A rank or cap change moves only each recipe's difficulty and whether it can raise skill, so those are read again for the candidates.
-- The change is marked as read only once every candidate answered: a nil answer (data not loaded yet) would keep the old difficulty
-- under the new stamp. True when it did.
local function RefreshSkill(professionID, read, job)
	local answered = true
	for _, recipeInfo in ipairs(read.candidates) do
		Yield(job)
		local fresh = C_TradeSkillUI.GetRecipeInfo(recipeInfo.recipeID)
		if fresh then
			recipeInfo.relativeDifficulty, recipeInfo.canSkillUp = fresh.relativeDifficulty, fresh.canSkillUp
		else
			answered = false
		end
	end
	if answered then read.skillChanges = skillChanges end
	ns.toolkit:Trace(ns.module, "UNLEARNED profession %d: difficulty read again for %d candidates%s", professionID, #read.candidates,
		answered and "" or ", some without data; read again on the next ask")
	return answered
end

-- Stage two: sources first, since one known source keeps its whole category's header; then the categories and the list.
local function Summarize(professionID, read, job)
	local established = {}
	for categoryID in pairs(read.established) do established[categoryID] = true end
	local seen, rows = {}, {}
	for _, recipeInfo in ipairs(read.candidates) do
		Yield(job)
		if not seen[recipeInfo.recipeID] then
			seen[recipeInfo.recipeID] = true
			-- The game's own fold (case and accents, any language); string.lower knows only A to Z.
			recipeInfo.searchName = CaseAccentInsensitiveParse(recipeInfo.name)
			ns.SummarizeSources(recipeInfo)
			if recipeInfo.sourceTypes then
				established[recipeInfo.categoryID] = true
			end
			table.insert(rows, recipeInfo)
		end
	end

	local categories, byID = {}, {}
	for _, recipeInfo in ipairs(rows) do
		Yield(job)
		local categoryID = established[recipeInfo.categoryID] and recipeInfo.categoryID or MISCELLANEOUS_CATEGORY_ID
		local category = byID[categoryID]
		if not category then
			local categoryInfo = categoryID == MISCELLANEOUS_CATEGORY_ID
				and { categoryID = categoryID, name = MISCELLANEOUS, uiOrder = math.huge }
				or C_TradeSkillUI.GetCategoryInfo(categoryID)
			if categoryInfo then
				category = { info = categoryInfo, recipes = {} }
				byID[categoryID] = category
				table.insert(categories, category)
			end
		end
		if category then
			table.insert(category.recipes, recipeInfo)
		end
	end

	table.sort(categories, SortCategories)
	for _, category in ipairs(categories) do
		Yield(job)
		table.sort(category.recipes, SortRecipes)
	end
	BuildListed(professionID, categories, job)
	return categories
end

-- The read itself. Returns the categories and whether the client's data was complete; job is nil outside a sliced run.
local function Read(professionID, job)
	-- Recorded recipe items link to their recipes first, so their sources count below.
	Stage(job, "links")
	local linksComplete = not next(ns.db.pendingItems) or ns.LinkPending(job and function() Yield(job) end)
	Yield(job)
	local read = reads[professionID]
	local skillComplete = true
	if not read then
		Stage(job, "client")
		read = ReadClient(professionID, job)
		-- An incomplete answer is not kept: names or factions are still loading.
		if read.complete then reads[professionID] = read end
	elseif read.skillChanges ~= skillChanges then
		Stage(job, "difficulty")
		skillComplete = RefreshSkill(professionID, read, job)
	end
	Stage(job, "summaries")
	return Summarize(professionID, read, job), read.complete and linksComplete and skillComplete
end

local function StageLine(job)
	local names = {}
	for name in pairs(job.stageMs) do names[#names + 1] = name end
	table.sort(names)
	for index, name in ipairs(names) do names[index] = ("%s %.1f"):format(name, job.stageMs[name]) end
	return table.concat(names, ", ")
end

-- Runs one slice of a job; true once it has finished. A job that was cleared meanwhile stops without a result.
local function Slice(professionID, job)
	if jobs[professionID] ~= job then return true end
	job.sliceStart = debugprofilestop()
	job.mark = job.sliceStart
	local ok, categories, complete = coroutine.resume(job.co)
	Charge(job)
	local ms = debugprofilestop() - job.sliceStart
	job.slices, job.ms = job.slices + 1, job.ms + ms
	if ms > job.worst then job.worst, job.worstStage = ms, job.stage end
	--@debug@
	ns.PerfMs("unlearned slice", ms)
	--@end-debug@
	if not ok then
		jobs[professionID] = nil
		geterrorhandler()(categories)
		return true
	end
	if coroutine.status(job.co) ~= "dead" then return false end
	jobs[professionID] = nil
	if complete then
		cache[professionID] = categories
	else
		partial[professionID] = categories
	end
	ns.toolkit:Trace(ns.module, "UNLEARNED profession %d read in %d slices, %.1f ms in all (%s), worst slice %.1f ms in %s, %s", professionID,
		job.slices, job.ms, StageLine(job), job.worst, tostring(job.worstStage), complete and "cached" or "data incomplete, not cached")
	return true
end

local function NextSlice(professionID, job)
	if Slice(professionID, job) then
		-- The panel held back while the read ran; it draws now.
		if ns.RequestUpdate then ns.RequestUpdate() end
	else
		RunNextFrame(function() NextSlice(professionID, job) end)
	end
end

-- This profession's unlearned recipes as categories in Blizzard's order, each { info, recipes } with recipes sorted by ascending skill (ns.SkillOf).
-- nil while the client loads or while the read runs across frames; the panel asks again when it ends (ns.RequestUpdate).
function ns.GetUnlearnedRecipes(professionInfo)
	local professionID = professionInfo.professionID
	if not C_TradeSkillUI.IsTradeSkillReady() then
		return nil
	end
	if cache[professionID] then
		return cache[professionID]
	end
	if partial[professionID] then
		local categories = partial[professionID]
		partial[professionID] = nil
		return categories
	end
	if jobs[professionID] then
		return nil
	end
	local job = { slices = 0, ms = 0, worst = 0, sliceStart = 0, mark = 0, stage = "start", stageMs = {} }
	job.co = coroutine.create(function() return Read(professionID, job) end)
	jobs[professionID] = job
	if not Slice(professionID, job) then
		RunNextFrame(function() NextSlice(professionID, job) end)
		return nil
	end
	return cache[professionID] or partial[professionID] and ns.GetUnlearnedRecipes(professionInfo)
end

-- What the panel lists for a profession (BuildListed, built with the read). The second result is true once the client's data was
-- complete; the third is the discovery total.
function ns.GetListedRecipes(professionInfo)
	local categories = ns.GetUnlearnedRecipes(professionInfo)
	if not categories then
		return nil
	end
	local professionID = professionInfo.professionID
	local entry = listed[professionID]
	if not (entry and entry.categories == categories) then
		entry = BuildListed(professionID, categories)
	end
	return entry.list, cache[professionID] ~= nil, entry.total
end

-- The panel groups recipes by the rank caps of a profession (75, 150, 225, 300); band 1 is skill 1 to 75.
ns.RANK_BAND = 75

function ns.BandOf(skill)
	return math.max(1, math.ceil(skill / ns.RANK_BAND))
end

-- A band's heading: the rank its rank spell names (docs/data.md, "Rank spells"), else the skill range. onLoad
-- runs when that spell's data arrives: ranks above the character's are not loaded until asked for.
function ns.BandTitle(professionID, band, onLoad)
	local ranks = ns.seed and ns.seed.rankSpell and ns.seed.rankSpell[professionID]
	local spellID = ranks and ranks[band]
	if spellID then
		-- A rank spell is named after its profession; the rank (Apprentice, Journeyman) is the spell's subtext.
		local name = C_Spell.GetSpellSubtext(spellID)
		if name and name ~= "" then
			return name
		end
		if onLoad and not C_Spell.IsSpellDataCached(spellID) then
			Spell:CreateFromSpellID(spellID):ContinueOnSpellLoad(onLoad)
		end
	end
	local first = (band - 1) * ns.RANK_BAND + 1
	return L["Skill %d to %d"]:format(first, first + ns.RANK_BAND - 1)
end
