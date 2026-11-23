local _, ns = ...

-- Forever's client leaves unlearned recipes out of C_TradeSkillUI.GetFilteredRecipeIDs()
-- even with Show Unlearned on, so Blizzard's list never gets them. After Blizzard builds the
-- list, add them to their own categories, after the learned recipes, as Blizzard's recipe
-- rows (which draw unlearned recipes gray).

-- Mirrors the local Group enum in Blizzard_ProfessionsTemplates/Blizzard_Professions.lua
-- (Favorite, Learned, UnlearnedDivider, Unlearned).
local GROUP_LEARNED = 2

-- Whether the open profession view is one where the player's own unlearned recipes belong.
function ns.CanShowUnlearned()
	return not (C_TradeSkillUI.IsNPCCrafting() or C_TradeSkillUI.IsTradeSkillGuild()
		or C_TradeSkillUI.IsTradeSkillLinked())
end

local function IsListFilteredToCraftable()
	return C_TradeSkillUI.GetOnlyShowMakeableRecipes()
		or C_TradeSkillUI.GetOnlyShowSkillUpRecipes()
		or C_TradeSkillUI.AreAnyInventorySlotsFiltered()
end

-- The unlearned recipes for each profession only change when the player learns something,
-- so look them up once and keep them until then. Blizzard rebuilds the list on every
-- TRADE_SKILL_LIST_UPDATE, which fires often.
local cache = {}

local cacheFrame = CreateFrame("Frame")
cacheFrame:RegisterEvent("NEW_RECIPE_LEARNED")
cacheFrame:RegisterEvent("SKILL_LINES_CHANGED")
cacheFrame:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED")
cacheFrame:SetScript("OnEvent", function()
	wipe(cache)
end)

-- New recorded sources change the cached source summaries.
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

local function SortRecipeRows(a, b)
	local left, right = a.recipeInfo, b.recipeInfo
	if left.maxTrivialLevel ~= right.maxTrivialLevel then
		return left.maxTrivialLevel < right.maxTrivialLevel
	end
	local nameOrder = strcmputf8i(left.name, right.name)
	if nameOrder ~= 0 then
		return nameOrder < 0
	end
	return left.recipeID < right.recipeID
end

-- Returns this profession's unlearned recipes as categories in Blizzard's order, each
-- holding its recipes sorted by ascending trivial skill, or nil while the client loads.
local function GetUnlearnedCategories(professionInfo)
	local professionID = professionInfo.professionID
	if not C_TradeSkillUI.IsTradeSkillReady() then
		return nil
	end
	if cache[professionID] then
		return cache[professionID]
	end

	-- One pass over the profession: unlearned recipes, flagged when another faction's, plus,
	-- only while recorded vendor items wait to be linked, a name and ID index to link them.
	local db = ns.db
	local pending = next(db.pendingItems) or next(db.found.trainerNames) or next(db.shared.trainerNames)
	local byName, inProfession = pending and {}, pending and {}
	local unlearned = {}
	local playerFaction = UnitFactionGroup("player")
	local indexComplete, factionsComplete = true, true
	for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs()) do
		local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
		if not recipeInfo then
			indexComplete = false
		elseif C_TradeSkillUI.IsRecipeInSkillLine(recipeID, professionID) then
			if pending then
				local nameKey = ns.NameKey(recipeInfo.name)
				byName[nameKey] = byName[nameKey] or {}
				table.insert(byName[nameKey], recipeInfo.recipeID)
				inProfession[recipeInfo.recipeID] = nameKey
			end
			recipeInfo = Professions.GetFirstRecipe(recipeInfo)
			if recipeInfo and not recipeInfo.learned then
				local faction = ns.GetRecipeFaction(recipeInfo.recipeID)
				if faction == nil then
					factionsComplete = false
				end
				-- Recipes the character can never learn stay in the list, marked, so the
				-- Unobtainable filter (off by default) can show them.
				recipeInfo.unobtainable = (faction and faction ~= playerFaction) or nil
				table.insert(unlearned, recipeInfo)
			end
		end
	end
	if pending and indexComplete then
		ns.LinkPending(byName, inProfession, professionInfo.profession)
	end

	local categories, byID, seen = {}, {}, {}
	for _, recipeInfo in ipairs(unlearned) do
		if not seen[recipeInfo.recipeID] then
			seen[recipeInfo.recipeID] = true
			local category = byID[recipeInfo.categoryID]
			if not category then
				local categoryInfo = C_TradeSkillUI.GetCategoryInfo(recipeInfo.categoryID)
				if categoryInfo then
					categoryInfo.group = GROUP_LEARNED
					categoryInfo.unlearned = true -- gray header when the category has no learned recipes
					category = { info = categoryInfo, recipes = {} }
					byID[recipeInfo.categoryID] = category
					table.insert(categories, category)
				end
			end
			if category then
				recipeInfo.searchName = recipeInfo.name:lower()
				ns.SummarizeSources(recipeInfo)
				-- Insert creates a fresh tree node around this reusable element data.
				table.insert(category.recipes, { recipeInfo = recipeInfo })
			end
		end
	end

	table.sort(categories, SortCategories)
	for _, category in ipairs(categories) do
		table.sort(category.recipes, SortRecipeRows)
		-- SortCategoryData compares order first. Keep each cached position between
		-- Blizzard's learned rows (0) and bottom padding (1), including after filtering.
		local divisor = #category.recipes + 1
		for index, row in ipairs(category.recipes) do
			row.order = index / divisor
		end
	end
	if indexComplete and factionsComplete then
		cache[professionID] = categories
	end
	return categories
end

-- The recipes of each category that match the search, or nil when none match. Blizzard's
-- search box also takes item level ranges ("~30", "10-20"); unlearned recipes are left out
-- of those searches.
local function GetMatches(categories, searchText)
	local nameFilter = C_TradeSkillUI.GetRecipeItemNameFilter()
	if searchText ~= "" and (nameFilter == nil or nameFilter == "") then
		return nil
	end
	local filteringSources = false
	for _, enabled in pairs(ns.db.sourceFilter) do
		if enabled == false then
			filteringSources = true
			break
		end
	end
	if searchText == "" and not filteringSources then
		return #categories > 0 and categories or nil
	end
	local matches = {}
	for _, category in ipairs(categories) do
		local recipes = {}
		for _, elementData in ipairs(category.recipes) do
			local recipeInfo = elementData.recipeInfo
			if (searchText == "" or recipeInfo.searchName:find(searchText, 1, true))
				and (not filteringSources or ns.PassesSourceFilter(recipeInfo)) then
				table.insert(recipes, elementData)
			end
		end
		if #recipes > 0 then
			table.insert(matches, { info = category.info, recipes = recipes })
		end
	end
	return #matches > 0 and matches or nil
end

-- Data providers this addon has already added to. A weak-keyed side table keeps our state
-- off Blizzard's objects.
local added = setmetatable({}, { __mode = "k" })

local function AddUnlearnedRecipes(page)
	if not ns.db.showUnlearned or not ns.CanShowUnlearned() or IsListFilteredToCraftable() then
		return
	end

	local scrollBox = page.RecipeList.ScrollBox
	local dataProvider = scrollBox:GetDataProvider()
	local professionID = page.professionInfo and page.professionInfo.professionID
	-- Init returns early for recrafting without building a new list; never add twice.
	if not (professionID and dataProvider and dataProvider.GetRootNode) or added[dataProvider] then
		return
	end

	local startTime = debugprofilestop()
	local categories = GetUnlearnedCategories(page.professionInfo)
	local matches = categories and GetMatches(categories, page.RecipeList.SearchBox:GetText():lower())
	if not matches then
		return
	end

	-- Every insert into a data provider that a ScrollBox is showing makes it redraw at once.
	-- Detach it while adding, then reattach it, so the list redraws once.
	scrollBox:RemoveDataProvider()

	-- Blizzard's category nodes, so unlearned recipes join the category they belong to.
	local categoryNodes = {}
	for _, node in dataProvider:EnumerateEntireRange() do
		local categoryInfo = node:GetData().categoryInfo
		if categoryInfo and categoryInfo.categoryID then
			categoryNodes[categoryInfo.categoryID] = node
		end
	end

	local root = dataProvider:GetRootNode()
	local collapses = page:GetCollapses()
	for _, category in ipairs(matches) do
		local categoryNode = categoryNodes[category.info.categoryID]
		local newCategory = not categoryNode
		if newCategory then
			-- No learned recipes here: a gray header, sorted among Blizzard's categories.
			categoryNode = root:Insert({ categoryInfo = category.info, group = GROUP_LEARNED })
			categoryNode:Insert({ topPadding = true, order = -1 })
		end
		for _, elementData in ipairs(category.recipes) do
			categoryNode:Insert(elementData)
		end
		if newCategory then
			categoryNode:Insert({ bottomPadding = true, order = 1 })
			if collapses and collapses[category.info.categoryID] then
				categoryNode:SetCollapsed(true)
			end
		end
	end
	added[dataProvider] = true

	scrollBox:SetDataProvider(dataProvider, ScrollBoxConstants.RetainScrollPosition)

	-- Reattaching clears the list's selection, and Blizzard showed "No results" before the
	-- unlearned recipes were added. Put both back the way Blizzard's Init leaves them.
	page.RecipeList.NoResultsText:Hide() -- at least one match was inserted
	local selected = page.SchematicForm:GetRecipeInfo()
	if selected then
		page.RecipeList:SelectRecipe(Professions.GetFirstRecipe(selected) or selected, false)
	end

	ns.lastUnlearnedMs = debugprofilestop() - startTime
	ns.unlearnedBuilds = (ns.unlearnedBuilds or 0) + 1
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_Professions", function()
	hooksecurefunc(ProfessionsFrame.CraftingPage, "Init", AddUnlearnedRecipes)
end)
