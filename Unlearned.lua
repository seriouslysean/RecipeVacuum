local _, ns = ...

-- Works out which recipes a character has not learned, grouped by category, for Recipe Vacuum's own panel. It writes nothing into Blizzard's frames (docs/client-notes.md, "Gamepad").

-- A category keeps its header when a recipe in it is learned or has a known source; the rest share MISCELLANEOUS, last.
-- The ID is ours: the game's category IDs are positive and -1 is its Favorites header (Blizzard_Professions.lua).
local MISCELLANEOUS_CATEGORY_ID = -2

-- Cached, since unlearned recipes change only on learning, a new source or a choice of specialization.
local cache = {}

local cacheFrame = CreateFrame("Frame")
cacheFrame:RegisterEvent("NEW_RECIPE_LEARNED")
cacheFrame:RegisterEvent("SKILL_LINES_CHANGED")
cacheFrame:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED")
cacheFrame:SetScript("OnEvent", function()
	wipe(cache)
	ns.ClearRecipeLocks()
end)

-- New recorded sources invalidate the cached source summaries.
function ns.ClearUnlearnedCache()
	wipe(cache)
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

local function SortRecipes(left, right)
	if left.maxTrivialLevel ~= right.maxTrivialLevel then
		return left.maxTrivialLevel < right.maxTrivialLevel
	end
	local nameOrder = strcmputf8i(left.name, right.name)
	if nameOrder ~= 0 then
		return nameOrder < 0
	end
	return left.recipeID < right.recipeID
end

-- This profession's unlearned recipes as categories in Blizzard's order, each { info, recipes } with recipes sorted by ascending trivial skill; nil while the client loads.
function ns.GetUnlearnedRecipes(professionInfo)
	local professionID = professionInfo.professionID
	if not C_TradeSkillUI.IsTradeSkillReady() then
		return nil
	end
	if cache[professionID] then
		return cache[professionID]
	end

	-- Recorded recipe items link to their recipes first, so their sources count below.
	local linksComplete = not next(ns.db.pendingItems) or ns.LinkPending()

	-- One pass over unlearned recipes, leaving out another faction's.
	local unlearned, established = {}, {}
	local playerFaction = UnitFactionGroup("player")
	local indexComplete, factionsComplete = true, true
	for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs()) do
		local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
		if not recipeInfo then
			indexComplete = false
		elseif C_TradeSkillUI.IsRecipeInSkillLine(recipeID, professionID) then
			-- A learned recipe is read only to find a picked specialization, and only until one is found;
			-- unlearned ones are read when listed.
			if recipeInfo.learned and not ns.HasSpecialization(recipeID) then
				ns.ReadSpecialization(recipeID)
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
					table.insert(unlearned, recipeInfo)
				end
			end
		end
	end

	-- Sources first, since one known source keeps its whole category's header.
	local seen, rows = {}, {}
	for _, recipeInfo in ipairs(unlearned) do
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
		table.sort(category.recipes, SortRecipes)
	end
	if indexComplete and factionsComplete and linksComplete then
		cache[professionID] = categories
	end
	return categories
end

-- What the panel lists for a profession: the unlearned recipes that pass the show rule (ns.IsListed), in one flat
-- list in skill-up order. The second result is true once the client's data was complete, so the list will not change.
-- Built once per cached categories table, which is replaced whenever the sources or the character's recipes change.
local listed = {}

function ns.GetListedRecipes(professionInfo)
	local categories = ns.GetUnlearnedRecipes(professionInfo)
	if not categories then
		return nil
	end
	local professionID = professionInfo.professionID
	local entry = listed[professionID]
	if not (entry and entry.categories == categories) then
		local list = {}
		for _, category in ipairs(categories) do
			for _, recipeInfo in ipairs(category.recipes) do
				if ns.IsListed(recipeInfo) then
					table.insert(list, recipeInfo)
				end
			end
		end
		table.sort(list, SortRecipes)
		entry = { categories = categories, list = list }
		listed[professionID] = entry
	end
	return entry.list, cache[professionID] ~= nil
end
