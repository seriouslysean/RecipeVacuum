local _, ns = ...

-- Adds unlearned recipes after Blizzard builds the list (it leaves them out even with Show Unlearned on, docs/client-notes.md, "Profession window"), as gray rows.

-- Copied from the local Group enum in Blizzard_Professions.lua.
local GROUP_LEARNED = 2

-- A category keeps its header when a recipe in it is learned or has a known source; the rest share MISCELLANEOUS, last.
-- The ID is ours: the game's category IDs are positive and -1 is its Favorites header (Blizzard_Professions.lua).
local MISCELLANEOUS_CATEGORY_ID = -2
-- Recipe rows in a category are ordered by fractions between 0 and 1; padding rows sit outside.
local ORDER_BEFORE_ROWS, ORDER_AFTER_ROWS = -1, 1

-- Whether the open view is one where the player's own unlearned recipes belong.
function ns.CanShowUnlearned()
	return Professions.InLocalCraftingMode()
end

local function IsListFilteredToCraftable()
	return C_TradeSkillUI.GetOnlyShowMakeableRecipes()
		or C_TradeSkillUI.GetOnlyShowSkillUpRecipes()
		or C_TradeSkillUI.AreAnyInventorySlotsFiltered()
end

-- Cached, since unlearned recipes change only on learning and Blizzard rebuilds on every TRADE_SKILL_LIST_UPDATE.
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

-- This profession's unlearned recipes as categories in Blizzard's order, sorted by ascending trivial skill; nil while the client loads.
local function GetUnlearnedCategories(professionInfo)
	local professionID = professionInfo.professionID
	if not C_TradeSkillUI.IsTradeSkillReady() then
		return nil
	end
	if cache[professionID] then
		return cache[professionID]
	end

	--@debug@
	-- Phase timings of an uncached build for the perf command: recipes, sources, grouping.
	local phaseStart = debugprofilestop()
	local phases = {}
	ns.coldBuildPhases = phases
	--@end-debug@

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
			ns.ReadSpecialization(recipeID) -- learned ones too, to detect a picked specialization
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
	--@debug@
	phases.recipes = debugprofilestop() - phaseStart
	phaseStart = debugprofilestop()
	--@end-debug@

	-- Sources first, since one known source keeps its whole category's header.
	local seen, rows = {}, {}
	for _, recipeInfo in ipairs(unlearned) do
		if not seen[recipeInfo.recipeID] then
			seen[recipeInfo.recipeID] = true
			recipeInfo.searchName = recipeInfo.name:lower()
			ns.SummarizeSources(recipeInfo)
			if recipeInfo.sourceTypes then
				established[recipeInfo.categoryID] = true
			end
			table.insert(rows, recipeInfo)
		end
	end

	--@debug@
	phases.sources, phases.unlearned = debugprofilestop() - phaseStart, #rows
	phaseStart = debugprofilestop()
	--@end-debug@

	local categories, byID = {}, {}
	for _, recipeInfo in ipairs(rows) do
		local categoryID = established[recipeInfo.categoryID] and recipeInfo.categoryID or MISCELLANEOUS_CATEGORY_ID
		local category = byID[categoryID]
		if not category then
			local categoryInfo = categoryID == MISCELLANEOUS_CATEGORY_ID
				and { categoryID = categoryID, name = MISCELLANEOUS, uiOrder = math.huge }
				or C_TradeSkillUI.GetCategoryInfo(categoryID)
			if categoryInfo then
				categoryInfo.group = GROUP_LEARNED
				categoryInfo.unlearned = true -- gray header without learned recipes
				category = { info = categoryInfo, recipes = {} }
				byID[categoryID] = category
				table.insert(categories, category)
			end
		end
		if category then
			-- Insert creates a fresh tree node around this reusable element data.
			table.insert(category.recipes, { recipeInfo = recipeInfo })
		end
	end

	table.sort(categories, SortCategories)
	for _, category in ipairs(categories) do
		table.sort(category.recipes, SortRecipeRows)
		-- SortCategoryData compares order first: keep cached positions between learned rows (0) and bottom padding (1), including after filtering.
		local divisor = #category.recipes + 1
		for index, row in ipairs(category.recipes) do
			row.order = index / divisor
		end
	end
	--@debug@
	phases.grouping = debugprofilestop() - phaseStart
	--@end-debug@
	if indexComplete and factionsComplete and linksComplete then
		cache[professionID] = categories
	end
	return categories
end

-- Recipes of each category matching the search, or nil; item level ranges ("~30", "10-20") leave unlearned recipes out.
local function GetMatches(categories, searchText)
	local nameFilter = C_TradeSkillUI.GetRecipeItemNameFilter()
	if searchText ~= "" and (nameFilter == nil or nameFilter == "") then
		return nil
	end
	local filteringSources = false
	for _, key in ipairs(ns.sourceFilterKeys) do
		if not ns.IsSourceShown(key) then
			filteringSources = true
			break
		end
	end
	local hidingUnavailable = not ns.db.showUnavailable
	if searchText == "" and not filteringSources and not hidingUnavailable then
		return #categories > 0 and categories or nil
	end
	local matches = {}
	for _, category in ipairs(categories) do
		local recipes = {}
		for _, elementData in ipairs(category.recipes) do
			local recipeInfo = elementData.recipeInfo
			if (searchText == "" or recipeInfo.searchName:find(searchText, 1, true))
				and (not filteringSources or ns.PassesSourceFilter(recipeInfo))
				and not (hidingUnavailable and ns.GetRecipeLock(recipeInfo.recipeID)) then
				table.insert(recipes, elementData)
			end
		end
		if #recipes > 0 then
			table.insert(matches, { info = category.info, recipes = recipes })
		end
	end
	return #matches > 0 and matches or nil
end

-- Data providers already added to, weak-keyed to keep our state off Blizzard's objects.
local added = setmetatable({}, { __mode = "k" })

-- A ScrollBox clips its scroll offset to a new provider's end (ScrollBoxBaseMixin:FullUpdateInternal) and Blizzard's rebuilt list is shorter, so the offset is read before Init swaps lists and restored after.
local offsetBeforeRebuild = 0
-- Profession of the last build, to tell a rebuild from a newly opened list as Init does.
local listProfessionID

-- Init builds its list with this just before handing it to the ScrollBox.
local function SaveScrollOffset()
	offsetBeforeRebuild = ProfessionsFrame.CraftingPage.RecipeList.ScrollBox:GetDerivedScrollOffset()
end

local function AddUnlearnedRecipes(page)
	local scrollBox = page.RecipeList.ScrollBox
	local professionID = page.professionInfo and page.professionInfo.professionID
	-- Init keeps the scroll position unless searching or the profession changed; so does this.
	local keepScroll = professionID == listProfessionID and not page.RecipeList.SearchBox:HasText()
	listProfessionID = professionID

	if not ns.db.showUnlearned or not ns.CanShowUnlearned() or IsListFilteredToCraftable() then
		return
	end

	local dataProvider = scrollBox:GetDataProvider()
	-- Init returns early for recrafting without a new list; never add twice.
	if not (professionID and dataProvider and dataProvider.GetRootNode) or added[dataProvider] then
		return
	end

	--@debug@
	local startTime = debugprofilestop()
	--@end-debug@
	local categories = GetUnlearnedCategories(page.professionInfo)
	local matches = categories and GetMatches(categories, page.RecipeList.SearchBox:GetText():lower())
	if not matches then
		return
	end

	-- Each insert redraws a shown ScrollBox, so detach while adding; that scrolls the view to the top.
	scrollBox:RemoveDataProvider()

	-- Blizzard's category nodes, so unlearned recipes join their own category.
	local categoryNodes = {}
	for _, node in dataProvider:EnumerateEntireRange() do
		local categoryInfo = node:GetData().categoryInfo
		if categoryInfo and categoryInfo.categoryID then
			categoryNodes[categoryInfo.categoryID] = node
		end
	end

	local root = dataProvider:GetRootNode()
	local collapses = page:GetCollapses()
	local openRecipeID, opened = page.professionInfo.openRecipeID, nil
	for _, category in ipairs(matches) do
		local categoryNode = categoryNodes[category.info.categoryID]
		local newCategory = not categoryNode
		if newCategory then
			-- No learned recipes here: gray header, sorted among Blizzard's categories.
			categoryNode = root:Insert({ categoryInfo = category.info, group = GROUP_LEARNED })
			categoryNode:Insert({ topPadding = true, order = ORDER_BEFORE_ROWS })
		end
		for _, elementData in ipairs(category.recipes) do
			categoryNode:Insert(elementData)
			if elementData.recipeInfo.recipeID == openRecipeID then
				opened = elementData.recipeInfo
			end
		end
		if newCategory then
			categoryNode:Insert({ bottomPadding = true, order = ORDER_AFTER_ROWS })
			if collapses and collapses[category.info.categoryID] then
				categoryNode:SetCollapsed(true)
			end
		end
	end
	added[dataProvider] = true

	scrollBox:SetDataProvider(dataProvider, ScrollBoxConstants.RetainScrollPosition)
	if keepScroll then
		-- Save the offset, change the list, reapply, as ScrollBoxDragBehavior does in ScrollUtil.lua.
		scrollBox:ScrollToOffset(offsetBeforeRebuild, ScrollBoxConstants.NoScrollInterpolation)
	end

	-- Reattaching clears the selection and Blizzard showed "No results"; put both back as Init leaves them, including its scroll to a link-opened recipe.
	page.RecipeList.NoResultsText:Hide() -- at least one match was inserted
	-- Blizzard's Init falls back to another recipe when a link names one only our rows hold (ProfessionsCraftingPageMixin:Init), so select it here.
	local selected = opened or page.SchematicForm:GetRecipeInfo()
	if selected then
		page.RecipeList:SelectRecipe(Professions.GetFirstRecipe(selected) or selected, openRecipeID ~= nil)
	end

	--@debug@
	ns.lastUnlearnedMs = debugprofilestop() - startTime
	local phases = ns.coldBuildPhases
	if phases and not phases.counted and phases.grouping then
		phases.counted = true
		ns.PerfMs("list build, cold", ns.lastUnlearnedMs)
		ns.PerfMs("  cold: recipes", phases.recipes)
		ns.PerfMs("  cold: sources", phases.sources)
		ns.PerfMs("  cold: grouping", phases.grouping)
	else
		ns.PerfMs("list build, warm", ns.lastUnlearnedMs)
	end
	-- Slowest is the first build after a reload or change, before the cache fills.
	ns.slowestUnlearnedMs = math.max(ns.slowestUnlearnedMs or 0, ns.lastUnlearnedMs)
	ns.unlearnedBuilds = (ns.unlearnedBuilds or 0) + 1
	--@end-debug@
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_Professions", function()
	hooksecurefunc(Professions, "GenerateCraftingDataProvider", SaveScrollOffset)
	hooksecurefunc(ProfessionsFrame.CraftingPage, "Init", AddUnlearnedRecipes)
end)
