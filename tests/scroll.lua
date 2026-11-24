-- Offline check: Blizzard's real ScrollBox / tree data provider code + the addon's real Unlearned.lua,
-- with stub frames and a CraftingPage:Init that mirrors Blizzard_ProfessionsCrafting.lua 899-922, 976-979.
-- luajit tests/scroll.lua <wow-ui-source Interface/AddOns dir> Unlearned.lua
local ADDONS, UNLEARNED = arg[1], arg[2]

-- client globals the Blizzard files expect
function securecallfunction(f, ...) return f(...) end
function secureexecuterange(t, f, ...) for k, v in pairs(t) do f(k, v, ...) end end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function tinsert(...) return table.insert(...) end
function tremove(...) return table.remove(...) end
function issecurevariable() return true end
function debugprofilestop() return 0 end
function strcmputf8i(a, b) return a < b and -1 or (a > b and 1 or 0) end
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

local ROW, VISIBLE = 20, 400
local scrollBox = Mixin(Frame(), ScrollBoxListMixin)
scrollBox.h = VISIBLE
scrollBox.ScrollTarget = Frame()
scrollBox.Shadows = Frame(); scrollBox.Shadows.Lower = Frame(); scrollBox.Shadows.Upper = Frame()
scrollBox:OnLoad()
local view = CreateScrollBoxListTreeListView(10, 0, 0, 0, 0, 0)
view:SetElementFactory(function(factory) factory("Row", function() end) end)
view:SetElementExtentCalculator(function() return ROW end) -- as Blizzard_ProfessionsRecipeList.lua:110
scrollBox:Init(view)
local redraws = 0
scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnUpdate, function() redraws = redraws + 1 end, {})

-- game data: one category, LEARNED known recipes and UNLEARNED unknown ones
local LEARNED, UNLEARNED_COUNT = tonumber(arg[3]) or 30, 450
local recipes, allIDs = {}, {}
for id = 1, LEARNED + UNLEARNED_COUNT do
	recipes[id] = { recipeID = id, name = ("Recipe %04d"):format(id), categoryID = 7, learned = id <= LEARNED,
		maxTrivialLevel = id }
	allIDs[id] = id
end
local searchText = ""
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
function UnitFactionGroup() return "Alliance" end
EventUtil = { ContinueOnAddOnLoaded = function(_, f) f() end }

Professions = { GetFirstRecipe = function(info) return info end }
-- stands in for Professions.GenerateCraftingDataProvider: learned recipes only, as on Forever
function Professions.GenerateCraftingDataProvider()
	local provider = CreateTreeDataProvider()
	local category = provider:Insert({ categoryInfo = { categoryID = 7 }, group = 2 })
	for id = 1, LEARNED do
		category:Insert({ recipeInfo = C_TradeSkillUI.GetRecipeInfo(id), order = 0 })
	end
	return provider
end

local selection, formRecipe
local page = {
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
local WITNESSED = LEARNED + 5 -- one unlearned recipe the player saw at a trainer
local ns = { db = { showUnlearned = true, shareWithFriends = true, pendingItems = {}, sourceFilter = {}, recipeItems = {},
	found = { recipes = { [WITNESSED] = { { kind = "trainer", npc = 1 } } }, items = {} },
	shared = { recipes = {}, items = {} } },
	included = { recipes = {}, items = {} } }
assert(loadfile((UNLEARNED:gsub("Unlearned%.lua$", "Sources.lua"))))("RecipeVacuum", ns)
ns.GetRecipeFaction = function() return "Alliance" end -- no tooltip data offline
assert(loadfile(UNLEARNED))("RecipeVacuum", ns)

local MAX_REDRAWS = 20 -- a rebuild takes a handful; one per added row would be hundreds
local failed = false
local function check(label, got, want)
	local ok = math.abs(got - want) < 0.5
	failed = failed or not ok
	print(("%-58s offset %7.1f  want %7.1f  %s"):format(label, got, want, ok and "ok" or "FAIL"))
end
local function offset() return scrollBox:GetDerivedScrollOffset() end

print(("learned %d, unlearned %d, row %d px, window %d px"):format(LEARNED, UNLEARNED_COUNT, ROW, VISIBLE))
page:Init({ professionID = 164 })
check("open profession: top", offset(), 0)
print(("rows %d, scroll range %d px"):format(scrollBox:GetDataProviderSize(), scrollBox:GetDerivedScrollRange()))

for _, target in ipairs({ 137, 3000, scrollBox:GetDerivedScrollRange() }) do
	scrollBox:ScrollToOffset(target, ScrollBoxConstants.NoScrollInterpolation)
	redraws = 0
	page:Init({ professionID = 164 }) -- TRADE_SKILL_LIST_UPDATE after a craft
	check(("rebuild after craft, scrolled to %d"):format(target), offset(), target)
	-- The list is detached while rows are added; a redraw per added row is the lag this avoids.
	local fewRedraws = redraws < MAX_REDRAWS
	failed = failed or not fewRedraws
	print(("   redraws in that rebuild: %d %s"):format(redraws, fewRedraws and "ok" or "FAIL"))
end

-- selection survives, without moving the list
scrollBox:ScrollToOffset(3000, ScrollBoxConstants.NoScrollInterpolation)
page.RecipeList:SelectRecipe({ recipeID = LEARNED + 200 })
page:Init({ professionID = 164 })
check("rebuild with an unlearned recipe selected", offset(), 3000)
assert(selection and selection:GetData().recipeInfo.recipeID == LEARNED + 200, "selection lost")
print("   selection kept: recipe " .. selection:GetData().recipeInfo.recipeID)

-- collapsing a category changes the range between builds; the offset in use must still be the real one
local header = scrollBox:GetDataProvider():GetRootNode():GetFirstNode()
scrollBox:ScrollToOffset(3000, ScrollBoxConstants.NoScrollInterpolation)
header:SetCollapsed(true)
page:Init({ professionID = 164 })
check("rebuild while collapsed list was at top", offset(), 0)

-- Blizzard discards the position in these cases; so must the addon
scrollBox:ScrollToOffset(3000, ScrollBoxConstants.NoScrollInterpolation)
searchText = "recipe 04"
page:Init({ professionID = 164 })
check("rebuild while searching: top", offset(), 0)
searchText = ""
page:Init({ professionID = 164 })
scrollBox:ScrollToOffset(3000, ScrollBoxConstants.NoScrollInterpolation)
page:Init({ professionID = 165 })
check("another profession: top", offset(), 0)

-- unlearned recipes hidden: Blizzard's own (clamped) retain stands
scrollBox:ScrollToOffset(3000, ScrollBoxConstants.NoScrollInterpolation)
ns.db.showUnlearned = false
page:Init({ professionID = 165 })
check("unlearned turned off: Blizzard's own clamp", offset(), math.min(3000, math.max(0, (LEARNED + 1) * ROW - VISIBLE)))

-- Self Found lists only recipes the player witnessed, with every source still checked
ns.db.showUnlearned, ns.db.shareWithFriends = true, false
page:Init({ professionID = 165 })
local unlearnedRows = 0
for _, node in scrollBox:GetDataProvider():EnumerateEntireRange() do
	local recipeInfo = node:GetData().recipeInfo
	if recipeInfo and not recipeInfo.learned then unlearnedRows = unlearnedRows + 1 end
end
local selfFoundOnly = unlearnedRows == 1
failed = failed or not selfFoundOnly
print(("%-58s rows %d, want 1  %s"):format("Self Found: only the witnessed unlearned recipe", unlearnedRows, selfFoundOnly and "ok" or "FAIL"))

print(failed and "CHECKS FAILED" or "ALL SCROLL CHECKS PASSED")
os.exit(failed and 1 or 0)
