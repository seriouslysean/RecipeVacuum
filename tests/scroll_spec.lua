-- Blizzard's real ScrollBox and tree data provider code with the addon's real Unlearned.lua and stub frames.
-- CraftingPage:Init mirrors Blizzard_ProfessionsCrafting.lua 899-922, 976-979.
-- RV_UI_SOURCE=<wow-ui-source checkout> busted        (RV_REPO defaults to .; RV_LEARNED, optional, sets the learned recipes)
local repo = os.getenv("RV_REPO") or "."
local ADDONS = assert(os.getenv("RV_UI_SOURCE"), "RV_UI_SOURCE: a checkout of Gethe/wow-ui-source") .. "/Interface/AddOns"
local UNLEARNED = repo .. "/Unlearned.lua"

-- The client's globals must be the real ones: Blizzard's files and the addon read them from there, while
-- busted gives each spec function a private environment that would hide them.
local G = getfenv(0)
local function real(fn)
	return function(...) setfenv(fn, G); return fn(...) end
end

describe("scroll position in the recipe list", function()
	local busted_it, busted_setup = it, setup
	local function it(name, fn) busted_it(name, real(fn)) end
	local function setup(fn) busted_setup(real(fn)) end

	local ROW, VISIBLE = 20, 400
	-- game data: one category, LEARNED known recipes and UNLEARNED_COUNT unknown ones
	local LEARNED, UNLEARNED_COUNT = tonumber(os.getenv("RV_LEARNED")) or 30, 450
	local WITNESSED = LEARNED + 5 -- one unlearned recipe the player saw at a trainer
	local MAX_REDRAWS = 20 -- a rebuild takes a handful; one per added row would be hundreds
	local scrollBox, redraws, recipes, allIDs, searchText, selection, formRecipe, page, ns

	setup(function()
		-- client globals the Blizzard files expect
		function securecallfunction(f, ...) return f(...) end
		function secureexecuterange(t, f, ...) for k, v in pairs(t) do f(k, v, ...) end end
		function wipe(t) for k in pairs(t) do t[k] = nil end return t end
		function tinsert(...) return table.insert(...) end
		function tremove(...) return table.remove(...) end
		function issecurevariable() return true end
		function debugprofilestop() return 0 end
		function strcmputf8i(a, b) return a < b and -1 or (a > b and 1 or 0) end
		function CaseAccentInsensitiveParse(text) return text:lower() end -- the test's names are plain English
		function hooksecurefunc(t, name, hook)
			local orig = t[name]
			t[name] = function(...) local r = { orig(...) }; hook(...); return unpack(r) end
		end
		-- helpers the client provides natively (not in the UI source)
		function Mixin(object, ...)
			for i = 1, select("#", ...) do
				for k, v in pairs((select(i, ...))) do object[k] = v end
			end
			return object
		end
		function CreateFromMixins(...) return Mixin({}, ...) end
		function math.round(v) return v < 0 and math.ceil(v - 0.5) or math.floor(v + 0.5) end
		function math.clamp(v, lo, hi) return math.min(math.max(v, lo), hi) end
		function math.normalize(v, a, b) return a == b and 0 or (v - a) / (b - a) end
		function math.saturate(v) return math.clamp(v, 0, 1) end
		function table.contains(t, item) for _, v in ipairs(t) do if v == item then return true end end return false end
		function table.indexof(t, item) for i, v in ipairs(t) do if v == item then return i end end end
		function table.removevalue(t, item)
			for i = #t, 1, -1 do if t[i] == item then table.remove(t, i) end end
		end
		InputUtil = { IsGamepadUIEnabled = function() return false end }
		TextureKitConstants = {}

		-- stub widgets: only size, scripts and attributes matter to the scroll math and callback registry
		local function Frame()
			local f = { w = 300, h = 0, scripts = {}, attributes = {} }
			local noop = function() end
			return setmetatable(f, { __index = function(_, k)
				if k == "GetSize" then return function(self) return self.w, self.h end end
				if k == "GetHeight" then return function(self) return self.h end end
				if k == "GetWidth" then return function(self) return self.w end end
				if k == "SetHeight" then return function(self, h) self.h = h end end
				if k == "GetFrameLevel" then return function() return 1 end end
				if k == "SetScript" then return function(self, name, fn) self.scripts[name] = fn end end
				if k == "GetScript" then return function(self, name) return self.scripts[name] end end
				if k == "GetAttribute" then return function(self, name) return self.attributes[name] end end
				if k == "SetAttribute" then return function(self, name, value)
					self.attributes[name] = value
					if self.scripts.OnAttributeChanged then self.scripts.OnAttributeChanged(self, name, value) end
				end end
				if type(k) == "string" and k:match("^%u") then return noop end
			end })
		end
		function CreateFrame() return Frame() end

		local function load(rel) assert(loadfile(ADDONS .. "/" .. rel))("Blizzard", {}) end
		for _, f in ipairs({ "Mixin.lua", "TableUtil.lua", "EnumUtil.lua", "FunctionUtil.lua", "MathUtil.lua",
			"CallbackRegistry.lua" }) do load("Blizzard_SharedXMLBase/" .. f) end
		load("Blizzard_SharedXML/DataProvider.lua")
		load("Blizzard_SharedXML/TreeListDataProvider.lua")

		function CreateFrameFactory()
			return {
				GetTemplateInfoCache = function()
					local info = { Row = { width = 300, height = 20 } }
					return { FlushTemplateInfos = function() end, GetTemplateInfos = function() return info end,
						GetTemplateInfo = function(_, template) return info[template] end }
				end,
				Create = function() return Frame(), true end,
				Release = function() end,
			}
		end
		for _, f in ipairs({ "ScrollController.lua", "ScrollBoxViewUtil.lua", "ScrollBoxPadding.lua", "ScrollBoxView.lua",
			"ScrollBoxStride.lua", "ScrollBoxListView.lua", "ScrollBoxLinearView.lua", "ScrollBoxTreeView.lua",
			"ScrollBox.lua" }) do load("Blizzard_SharedXML/Shared/Scroll/" .. f) end

		scrollBox = Mixin(Frame(), ScrollBoxListMixin)
		scrollBox.h = VISIBLE
		scrollBox.ScrollTarget = Frame()
		scrollBox.Shadows = Frame(); scrollBox.Shadows.Lower = Frame(); scrollBox.Shadows.Upper = Frame()
		scrollBox:OnLoad()
		local view = CreateScrollBoxListTreeListView(10, 0, 0, 0, 0, 0)
		view:SetElementFactory(function(factory) factory("Row", function() end) end)
		view:SetElementExtentCalculator(function() return ROW end) -- as Blizzard_ProfessionsRecipeList.lua:110
		scrollBox:Init(view)
		redraws = 0
		scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnUpdate, function() redraws = redraws + 1 end, {})

		-- game data: one category, LEARNED known recipes and UNLEARNED unknown ones
		recipes, allIDs = {}, {}
		for id = 1, LEARNED + UNLEARNED_COUNT do
			recipes[id] = { recipeID = id, name = ("Recipe %04d"):format(id), categoryID = 7, learned = id <= LEARNED,
				maxTrivialLevel = id }
			allIDs[id] = id
		end
		searchText = ""
		C_TradeSkillUI = {
			IsNPCCrafting = function() return false end, IsTradeSkillGuild = function() return false end,
			IsTradeSkillLinked = function() return false end, GetOnlyShowMakeableRecipes = function() return false end,
			GetOnlyShowSkillUpRecipes = function() return false end, AreAnyInventorySlotsFiltered = function() return false end,
			IsTradeSkillReady = function() return true end, GetAllRecipeIDs = function() return allIDs end,
			GetRecipeInfo = function(id) local c = {}; for k, v in pairs(recipes[id]) do c[k] = v end; return c end,
			IsRecipeInSkillLine = function() return true end,
			GetCategoryInfo = function(id) return { categoryID = id, name = "Category", uiOrder = 1 } end,
			GetRecipeItemNameFilter = function() return searchText end,
		}
		MISCELLANEOUS = "Miscellaneous"
		function UnitFactionGroup() return "Alliance" end
		EventUtil = { ContinueOnAddOnLoaded = function(_, f) f() end }

		Professions = { GetFirstRecipe = function(info) return info end, InLocalCraftingMode = function() return true end }
		-- stands in for Professions.GenerateCraftingDataProvider: learned recipes only, as on Forever
		function Professions.GenerateCraftingDataProvider()
			local provider = CreateTreeDataProvider()
			local category = provider:Insert({ categoryInfo = { categoryID = 7 }, group = 2 })
			for id = 1, LEARNED do
				category:Insert({ recipeInfo = C_TradeSkillUI.GetRecipeInfo(id), order = 0 })
			end
			return provider
		end

		selection, formRecipe = nil, nil
		page = {
			RecipeList = {
				ScrollBox = scrollBox,
				SearchBox = { GetText = function() return searchText end, HasText = function() return searchText ~= "" end },
				NoResultsText = Frame(),
				SelectRecipe = function(self, recipeInfo, scrollToRecipe)
					local node = scrollBox:FindElementDataByPredicate(function(n)
						local data = n:GetData()
						return data.recipeInfo and data.recipeInfo.recipeID == recipeInfo.recipeID
					end)
					selection = node
					if node then formRecipe = node:GetData().recipeInfo end
					if scrollToRecipe then scrollBox:ScrollToElementData(node) end
					return node
				end,
			},
			SchematicForm = { GetRecipeInfo = function() return formRecipe end },
			GetCollapses = function() return nil end,
		}
		-- Blizzard_ProfessionsCrafting.lua 899-922 and 976-979, without the parts that do not touch the list
		function page:Init(professionInfo)
			local oldProfessionInfo = self.professionInfo
			self.professionInfo = professionInfo
			local changedProfessionID = not oldProfessionInfo or oldProfessionInfo.professionID ~= professionInfo.professionID
			local searching = self.RecipeList.SearchBox:HasText()
			local dataProvider = Professions.GenerateCraftingDataProvider(professionInfo.professionID, searching)
			if searching or changedProfessionID then
				scrollBox:SetDataProvider(dataProvider, ScrollBoxConstants.DiscardScrollPosition)
			else
				scrollBox:SetDataProvider(dataProvider, ScrollBoxConstants.RetainScrollPosition)
			end
			selection = nil -- a new provider has no selection
			local current = (not changedProfessionID) and self.SchematicForm:GetRecipeInfo()
			if current then
				self.RecipeList:SelectRecipe(current, professionInfo.openRecipeID ~= nil)
			end
		end
		ProfessionsFrame = { CraftingPage = page }

		-- The addon's real source lookups, so the Self Found check below reads real code.
		Enum = { Profession = {}, ItemRecipeSubclass = {} }
		ns = { LEVEL = { SELF = 1, FRIENDS = 2, PUBLIC = 3 }, Perf = function() end, PerfMs = function() end, db = { showUnlearned = true, showUnavailable = true, sourceLevel = 2, met = { recipes = {}, items = {} }, pendingItems = {}, sourceFilter = { unknown = true }, recipeItems = {},
			found = { recipes = { [WITNESSED] = { { kind = "trainer", npc = 1 } } }, items = {} },
			shared = { recipes = {}, items = {} } },
			included = { recipes = {}, items = {} } }
		LibStub = LibStub or (function()
			dofile((UNLEARNED:gsub("Unlearned%.lua$", "Libs/LibStub/LibStub.lua")))
			return LibStub
		end)()
		GetLocale = GetLocale or function() return "enUS" end -- the client's language
		geterrorhandler = geterrorhandler or function() return error end
		dofile((UNLEARNED:gsub("Unlearned%.lua$", "Libs/AceLocale-3.0/AceLocale-3.0.lua")))
		assert(loadfile((UNLEARNED:gsub("Unlearned%.lua$", "Locales/enUS.lua"))))("RecipeVacuum", ns)
		ns.L = LibStub("AceLocale-3.0"):GetLocale("RecipeVacuum") -- set by Core.lua in the game
		assert(loadfile((UNLEARNED:gsub("Unlearned%.lua$", "Sources.lua"))))("RecipeVacuum", ns)
		ns.GetRecipeFaction = function() return "Alliance" end -- no tooltip data offline
		ns.GetRecipeLock = function() return false end
		ns.ReadSpecialization = function() return false end
		ns.HasSpecialization = function() return false end
		ns.Trace = function() end
		assert(loadfile(UNLEARNED))("RecipeVacuum", ns)
	end)

	local function offset() return scrollBox:GetDerivedScrollOffset() end
	local function near(label, got, want)
		assert(math.abs(got - want) < 0.5, ("%s: offset %.1f, want %.1f"):format(label, got, want))
	end

	it("open profession: top", function()
		page:Init({ professionID = 164 })
		near("open profession: top", offset(), 0)
	end)

	for _, target in ipairs({ 137, 3000, "the end of the range" }) do
		local at, label
		it("rebuild after craft, scrolled to " .. target, function()
			at = type(target) == "number" and target or scrollBox:GetDerivedScrollRange()
			label = ("rebuild after craft, scrolled to %d"):format(at)
			scrollBox:ScrollToOffset(at, ScrollBoxConstants.NoScrollInterpolation)
			redraws = 0
			page:Init({ professionID = 164 }) -- TRADE_SKILL_LIST_UPDATE after a craft
			near(label, offset(), at)
		end)
		-- The list is detached while rows are added; a redraw per added row is the lag this avoids.
		it("redraws in that rebuild, scrolled to " .. target, function()
			assert(redraws < MAX_REDRAWS, ("redraws in that rebuild: %d"):format(redraws))
		end)
	end

	-- selection survives, without moving the list
	it("rebuild with an unlearned recipe selected", function()
		scrollBox:ScrollToOffset(3000, ScrollBoxConstants.NoScrollInterpolation)
		page.RecipeList:SelectRecipe({ recipeID = LEARNED + 200 })
		page:Init({ professionID = 164 })
		near("rebuild with an unlearned recipe selected", offset(), 3000)
		assert(selection and selection:GetData().recipeInfo.recipeID == LEARNED + 200, "selection lost")
	end)

	-- collapsing a category changes the range between builds; the offset in use must still be the real one
	it("rebuild while collapsed list was at top", function()
		local header = scrollBox:GetDataProvider():GetRootNode():GetFirstNode()
		scrollBox:ScrollToOffset(3000, ScrollBoxConstants.NoScrollInterpolation)
		header:SetCollapsed(true)
		page:Init({ professionID = 164 })
		near("rebuild while collapsed list was at top", offset(), 0)
	end)

	-- Blizzard discards the position in these cases; so must the addon
	it("rebuild while searching: top", function()
		scrollBox:ScrollToOffset(3000, ScrollBoxConstants.NoScrollInterpolation)
		searchText = "recipe 04"
		page:Init({ professionID = 164 })
		near("rebuild while searching: top", offset(), 0)
	end)
	it("another profession: top", function()
		searchText = ""
		page:Init({ professionID = 164 })
		scrollBox:ScrollToOffset(3000, ScrollBoxConstants.NoScrollInterpolation)
		page:Init({ professionID = 165 })
		near("another profession: top", offset(), 0)
	end)

	-- unlearned recipes hidden: Blizzard's own (clamped) retain stands
	it("unlearned turned off: Blizzard's own clamp", function()
		scrollBox:ScrollToOffset(3000, ScrollBoxConstants.NoScrollInterpolation)
		ns.db.showUnlearned = false
		page:Init({ professionID = 165 })
		near("unlearned turned off: Blizzard's own clamp", offset(), math.min(3000, math.max(0, (LEARNED + 1) * ROW - VISIBLE)))
	end)

	-- Self Found lists only recipes the player witnessed, with every source still checked
	it("Self Found: only the witnessed unlearned recipe", function()
		ns.db.showUnlearned, ns.db.sourceLevel, ns.db.sourceFilter.unknown = true, 1, nil
		page:Init({ professionID = 165 })
		local unlearnedRows = 0
		for _, node in scrollBox:GetDataProvider():EnumerateEntireRange() do
			local recipeInfo = node:GetData().recipeInfo
			if recipeInfo and not recipeInfo.learned then unlearnedRows = unlearnedRows + 1 end
		end
		assert(unlearnedRows == 1, ("Self Found: only the witnessed unlearned recipe: rows %d, want 1"):format(unlearnedRows))
	end)

	-- Categories: one with a known source keeps its header; one with nothing learned or found shares the Miscellaneous header, last.
	it("Unknown categories share Miscellaneous, last", function()
		local SOURCED, STRAY = 9, 8
		for index, categoryID in ipairs({ STRAY, STRAY, STRAY, SOURCED, SOURCED }) do
			local id = 9000 + index
			recipes[id] = { recipeID = id, name = ("Extra %d"):format(index), categoryID = categoryID, learned = false, maxTrivialLevel = id }
			table.insert(allIDs, id)
		end
		ns.db.found.recipes[9004] = { { kind = "trainer", npc = 1 } }
		ns.db.sourceLevel, ns.db.sourceFilter.unknown = 2, true
		ns.ClearUnlearnedCache()
		page:Init({ professionID = 165 })
		local headers, perCategory, current = {}, {}, nil
		for _, node in scrollBox:GetDataProvider():EnumerateEntireRange() do
			local data = node:GetData()
			if data.categoryInfo then
				current = data.categoryInfo.categoryID
				table.insert(headers, data.categoryInfo)
			elseif data.recipeInfo and not data.recipeInfo.learned then
				perCategory[current] = (perCategory[current] or 0) + 1
			end
		end
		local last = headers[#headers]
		local MISCELLANEOUS_ID = -2 -- the addon's own; -1 is Blizzard's Favorites header
		local categoriesRight = perCategory[SOURCED] == 2 and perCategory[STRAY] == nil and perCategory[MISCELLANEOUS_ID] == 3
			and last.categoryID == MISCELLANEOUS_ID and last.name == MISCELLANEOUS
		assert(categoriesRight, ("Unknown categories share Miscellaneous, last: sourced %s, stray %s, miscellaneous %s, last header %s"):format(
			tostring(perCategory[SOURCED]), tostring(perCategory[STRAY]), tostring(perCategory[MISCELLANEOUS_ID]), tostring(last.name)))
	end)

	-- A recipe opened from a link that only the addon's rows hold is selected; Blizzard's Init falls back to the recipe already shown. Fails if the fallback stays selected.
	it("A recipe opened by link is selected", function()
		page.RecipeList:SelectRecipe({ recipeID = 1 })
		page:Init({ professionID = 165, openRecipeID = WITNESSED })
		assert(formRecipe ~= nil and formRecipe.recipeID == WITNESSED,
			("A recipe opened by link is selected: selected %s, want %d"):format(tostring(formRecipe and formRecipe.recipeID), WITNESSED))
	end)
end)
