local addonName, ns = ...
local L = ns.L

-- The player-facing list of unlearned recipes: a panel of our own beside the Professions window, never a write into Blizzard's list (docs/client-notes.md, "Gamepad").
-- Built as Field Guide Forever's list is (UI/List.lua): a Blizzard scroll frame and one real Button per row, so the Gamepad UI can focus rows and scroll them.
-- Rows and headings are Blizzard's own recipe list templates, so they look as its list does (docs/client-notes.md, "Panel").

local PANEL_WIDTH = 270 -- about 230 px are free beside the tab column at 1280x800; the quest tracker may be overlapped a little
local PANEL_GAP = 2 -- space between the tab column and the panel
-- The overview tab sits this far below the window's top (Blizzard_ProfessionsFrame.xml), so the panel lifts by the same.
local TAB_TOP_OFFSET = 60
local TITLE_HEIGHT = 40 -- the title and the count under it
local TITLE_GAP = 4
local CONTENT_PAD = 4
local SCROLLBAR_WIDTH = 22 -- room for UIPanelScrollFrameTemplate's bar to the right of the list
-- Blizzard_ProfessionsRecipeList.lua: view spacing, indent and pad; the element extents (20 per recipe, 20 + 5 per category).
local ROW_HEIGHT = 20
local HEADING_HEIGHT = 25
local ROW_SPACING = 1
local ROW_INDENT = 10
local LIST_PAD = 5
local ROW_PAD = 4
local SKILL_WIDTH = 22 -- room for a three-digit skill, right-aligned so the numbers line up
local MAX_MARKS = 1 + #ns.sourceOrder + 1 -- a lock, every source type, or the unknown mark
local ROW_TEMPLATE = "ProfessionsRecipeListRecipeTemplate"
local HEADING_TEMPLATE = "ProfessionsRecipeListCategoryTemplate"
-- Rows are made in steps of at most this much time and this many rows, so no frame from the panel nears 16 ms.
local BUILD_BUDGET_MS = 4
local ROWS_PER_STEP = 40
local RETRY_SECONDS = 1 -- once: the client may still be loading names and factions after the window opens
-- The inset template's border atlases (Blizzard_SharedXML NineSliceLayouts.lua, InsetFrameTemplate) give its content margins.
local INSET_EDGES = {
	left = { atlas = "!UI-Frame-InnerLeftTile", key = "width" },
	right = { atlas = "!UI-Frame-InnerRightTile", key = "width" },
	top = { atlas = "_UI-Frame-InnerTopTile", key = "height" },
	bottom = { atlas = "_UI-Frame-InnerBotTile", key = "height" },
}

local panel, scroll, child, empty, countText
local rows, headings = {}, {}
local items = {} -- what the list shows, in order: { band = n } for a heading, { recipe = info } for a row
local slots = {} -- the frame of each item once built
local toggled = {} -- [professionID .. ":" .. band] = open, for the session only: the player's own choices
local professionInfo
local wanted = false -- a character's own crafting page is open
local requested = false
local retried = false
local generation = 0 -- a newer build ends the steps of an older one
local shownSignature, builtProfession
local nextItem, buildMs, buildSteps, recipeCount, bandCount

local function CreateRow()
	local row = CreateFrame("Button", nil, child, ROW_TEMPLATE)
	row.Count:Hide()
	row.SkillUps:Hide()

	-- The skill the list is ordered by comes first: it is what the list is about.
	row.Skill = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	row.Skill:SetPoint("LEFT", ROW_PAD, 0)
	row.Skill:SetWidth(SKILL_WIDTH)
	row.Skill:SetJustifyH("RIGHT")
	row.Label:ClearAllPoints()
	row.Label:SetPoint("LEFT", row.Skill, "RIGHT", ROW_PAD, 0)
	row.Label:SetWordWrap(false)

	-- Marks stack from the right edge, in display order from the left.
	local marks = {}
	row.marks = marks
	for slot = 1, MAX_MARKS do
		local texture = row:CreateTexture(nil, "ARTWORK")
		marks[slot] = { Texture = texture }
		if slot == 1 then
			texture:SetPoint("RIGHT", row, "RIGHT", -ROW_PAD, 0)
		else
			texture:SetPoint("RIGHT", marks[slot - 1].Texture, "LEFT", -ROW_PAD, 0)
		end
	end
	row.markNames = {}

	-- Ours in place of Blizzard's, which would select a recipe in its own list.
	row:SetScript("OnEnter", function(self)
		if not self.recipe then return end
		self.Label:SetVertexColor(HIGHLIGHT_FONT_COLOR:GetRGB())
		for slot = 1, self.markCount do
			ns.SetMarkStrength(marks[slot], true)
		end
		-- The game's own tooltip for what the recipe makes, so other addons' tooltip hooks run, then our source lines.
		local recipeID = self.recipe.recipeID
		local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
		local itemID = schematic and schematic.outputItemID
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if itemID then
			GameTooltip:SetItemByID(itemID)
		else
			GameTooltip:SetSpellByID(recipeID)
		end
		GameTooltip_AddBlankLineToTooltip(GameTooltip)
		ns.AddSourceLines(GameTooltip, self.recipe, true, true)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function(self)
		if self.recipe then self.Label:SetVertexColor(self.color:GetRGB()) end
		for slot = 1, self.markCount or 0 do
			ns.SetMarkStrength(marks[slot], false)
		end
		GameTooltip_Hide()
	end)
	-- One click pins the nearest source; a menu would taint (docs/client-notes.md, "Gamepad").
	row:SetScript("OnClick", function(self, button)
		if not self.recipe or button == "RightButton" then return end
		local target = ns.MapTargets(self.recipe)[1]
		ns.Trace("UI row clicked: recipe %d, %s", self.recipe.recipeID, target and "pinned" or "no place to pin")
		if target then
			ns.ShowOnMap(target)
		end
	end)
	rows[#rows + 1] = row
	return row
end

local Request -- defined below; a heading click asks for a rebuild through it

local function BandKey(band)
	return professionInfo.professionID .. ":" .. band
end

-- A band is open when the player chose so; otherwise when it holds the character's skill or lies below it.
local function IsOpen(band)
	local chosen = toggled[BandKey(band)]
	if chosen ~= nil then return chosen end
	return band <= ns.BandOf(professionInfo.skillLevel or 0)
end

local function CreateHeading()
	local heading = CreateFrame("Button", nil, child, HEADING_TEMPLATE)
	heading.RankBar:Hide() -- Blizzard's skill line progress bar; a band has none
	-- The template's own OnEnter and OnLeave stay: they only light the title and the marker.
	heading:SetScript("OnClick", function(self)
		toggled[BandKey(self.band)] = not IsOpen(self.band)
		ns.Trace("UI band %d %s", self.band, toggled[BandKey(self.band)] and "opened" or "closed")
		Request()
	end)
	headings[#headings + 1] = heading
	return heading
end

-- White when the character's skill can learn it now, grey when not yet or not at all. Skill-up colors would
-- mislead: a recipe not yet learned cannot be made, so it gives no skill.
local function NameColor(recipeInfo)
	local skill = professionInfo and professionInfo.skillLevel or 0
	if recipeInfo.disabled or recipeInfo.lockReason or (recipeInfo.requiredSkill or 0) > skill then
		return DISABLED_FONT_COLOR
	end
	return HIGHLIGHT_FONT_COLOR
end

-- Everything a row shows that does not move it, so a skill rise or new source updates a row without a rebuild.
local function ShowRow(row, recipeInfo)
	row.recipe = recipeInfo
	recipeInfo.lockReason = ns.GetRecipeLock(recipeInfo.recipeID) or nil
	row.Label:SetText(recipeInfo.name)
	row.color = NameColor(recipeInfo)
	if not row:IsMouseMotionFocus() then row.Label:SetVertexColor(row.color:GetRGB()) end
	row.Skill:SetText(ns.SkillOf(recipeInfo))
	row.markCount = ns.GetMarks(recipeInfo, row.markNames)
	for slot, mark in ipairs(row.marks) do
		local name = row.markNames[slot]
		mark.Texture:SetShown(name ~= nil)
		if name then
			ns.ApplyMark(mark, name)
			ns.SetMarkStrength(mark, false)
		end
	end
	-- The name stops where the marks begin.
	row.Label:SetPoint("RIGHT", row.marks[math.max(row.markCount, 1)].Texture, "LEFT", -ROW_PAD, 0)
end

local function ShowHeading(heading, item)
	heading.band = item.band
	local first = (item.band - 1) * ns.RANK_BAND + 1
	local text = L["Skill %d to %d"]:format(first, first + ns.RANK_BAND - 1)
	if not item.open then
		text = text .. L[" (%d)"]:format(item.count)
	end
	heading:SetHeaderText(text)
	heading:UpdateCollapsedState(not item.open)
end

local function Finish()
	ns.Trace("UI panel shown with %d rows under %d bands, built in %.1f ms over %d frames", recipeCount, bandCount, buildMs, buildSteps)
	--@debug@
	ns.PerfMs("panel build", buildMs)
	--@end-debug@
end

-- One frame per item, all in the scroll child: the Gamepad UI moves between frames that exist and scrolls the
-- frame to reach one out of view, so a screenful of relabelled rows left it stuck at the last one shown.
-- Frames are kept and reused across professions, and made a few a frame so opening the window never stalls.
local function BuildStep(buildGeneration)
	if buildGeneration ~= generation or not panel:IsShown() then return end
	local started = debugprofilestop()
	local made = 0
	while nextItem <= #items and made < ROWS_PER_STEP and (made == 0 or debugprofilestop() - started < BUILD_BUDGET_MS) do
		local item = items[nextItem]
		local frame
		if item.recipe then
			frame = rows[item.rowIndex] or CreateRow()
			frame:SetPoint("TOPLEFT", child, "TOPLEFT", ROW_INDENT, -item.top)
			frame:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -item.top)
			frame:SetHeight(ROW_HEIGHT)
			ShowRow(frame, item.recipe)
		else
			frame = headings[item.headingIndex] or CreateHeading()
			frame:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -item.top)
			frame:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -item.top)
			frame:SetHeight(HEADING_HEIGHT)
			ShowHeading(frame, item)
		end
		frame:Show()
		slots[nextItem] = frame
		nextItem = nextItem + 1
		made = made + 1
	end
	buildMs = buildMs + (debugprofilestop() - started)
	buildSteps = buildSteps + 1
	if nextItem <= #items then
		RunNextFrame(function() BuildStep(buildGeneration) end)
	else
		Finish()
	end
end

-- The window's own filters, read where they can apply to a recipe not yet learned (docs/client-notes.md, "Panel").
local function CollectRecipes(list)
	local found = {}
	-- "Have materials" and "Show unlearned" are left out: nothing here is makeable, and Forever turns Show
	-- unlearned off by default, which emptied the panel. Skill-up reads the difficulty color, since a recipe
	-- not yet learned never reports that it can skill up.
	local search = CaseAccentInsensitiveParse(ProfessionsFrame.CraftingPage.RecipeList.SearchBox:GetText())
	local skillUpOnly = C_TradeSkillUI.GetOnlyShowSkillUpRecipes()
	local firstCraftOnly = C_TradeSkillUI.GetOnlyShowFirstCraftRecipes()
	for _, recipeInfo in ipairs(list) do
		if (search == "" or recipeInfo.searchName:find(search, 1, true))
			and not (skillUpOnly and recipeInfo.relativeDifficulty == Enum.TradeskillRelativeDifficulty.Trivial)
			and not (firstCraftOnly and not recipeInfo.firstCraft) then
			found[#found + 1] = recipeInfo
		end
	end
	return found, search
end

-- The list as items with their tops, and a signature of what it shows: the recipes in order, which bands are open
-- and the search. Equal signatures need no rebuild and no re-anchoring (docs/client-notes.md, "Panel").
local function LayOut(found, search)
	local newItems, parts, top = {}, { professionInfo.professionID, search }, LIST_PAD
	local rowCount, headingCount = 0, 0
	local index = 1
	while index <= #found do
		local band = ns.BandOf(ns.SkillOf(found[index]))
		local last = index
		while found[last + 1] and ns.BandOf(ns.SkillOf(found[last + 1])) == band do last = last + 1 end
		local open = IsOpen(band)
		headingCount = headingCount + 1
		newItems[#newItems + 1] = { band = band, open = open, count = last - index + 1, top = top, headingIndex = headingCount }
		parts[#parts + 1] = (open and "+" or "-") .. band .. "x" .. (last - index + 1)
		top = top + HEADING_HEIGHT + ROW_SPACING
		if open then
			for at = index, last do
				rowCount = rowCount + 1
				newItems[#newItems + 1] = { recipe = found[at], top = top, rowIndex = rowCount }
				parts[#parts + 1] = found[at].recipeID
				top = top + ROW_HEIGHT + ROW_SPACING
			end
		end
		index = last + 1
	end
	return newItems, table.concat(parts, ","), rowCount, headingCount, top + LIST_PAD
end

local function Update()
	requested = false
	if not (panel and panel:IsShown() and professionInfo) then return end
	local list, complete = ns.GetListedRecipes(professionInfo)
	-- Not ready: the client's list update comes back through the events below.
	if not list then return end
	if not complete and not retried then
		retried = true
		C_Timer.After(RETRY_SECONDS, Request)
	end
	local found, search = CollectRecipes(list)
	local newItems, signature, rowCount, headingCount, height = LayOut(found, search)
	local built = nextItem or 1
	items = newItems
	if signature == shownSignature then
		-- Same content: refresh what is shown in place and leave every frame where it is.
		for index = 1, math.min(built - 1, #items) do
			if items[index].recipe then ShowRow(slots[index], items[index].recipe) end
		end
		return
	end
	shownSignature = signature
	recipeCount, bandCount = rowCount, headingCount
	generation = generation + 1
	nextItem, buildMs, buildSteps = 1, 0, 0
	child:SetHeight(math.max(height, 1))
	empty:SetShown(#items == 0)
	countText:SetText(L["%d found"]:format(#found))
	if builtProfession ~= professionInfo.professionID then
		builtProfession = professionInfo.professionID
		scroll:SetVerticalScroll(0)
	end
	for index = rowCount + 1, #rows do rows[index]:Hide() end
	for index = headingCount + 1, #headings do headings[index]:Hide() end
	BuildStep(generation)
end

-- However many times the window rebuilds its page in a frame, the panel asks once, on the next.
Request = function()
	if requested then return end
	requested = true
	RunNextFrame(Update)
end

local function EdgeSize(edge)
	local info = C_Texture.GetAtlasInfo(edge.atlas)
	return info and info[edge.key] or 0
end

local function CreatePanel()
	local window = ProfessionsFrame
	-- Under the window, so it shows and hides with it and the Gamepad UI treats it as part of it.
	panel = CreateFrame("Frame", nil, window, "InsetFrameTemplate")
	panel:SetWidth(PANEL_WIDTH)
	panel:SetPoint("TOPLEFT", window.ProfessionsOverviewTab, "TOPRIGHT", PANEL_GAP, TAB_TOP_OFFSET)
	panel:Hide()

	local left, right = EdgeSize(INSET_EDGES.left) + CONTENT_PAD, EdgeSize(INSET_EDGES.right) + CONTENT_PAD
	local top, bottom = EdgeSize(INSET_EDGES.top) + CONTENT_PAD, EdgeSize(INSET_EDGES.bottom) + CONTENT_PAD

	-- The name and, smaller and dim like a model number, the version; a working build has no version to show.
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	title:SetPoint("TOPLEFT", left, -top)
	title:SetText(ns.title)
	local version = C_AddOns.GetAddOnMetadata(addonName, "Version")
	local model = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	model:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", TITLE_GAP, 0)
	model:SetText(version and not version:find("@", 1, true) and version or L["dev"])
	countText = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	countText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -TITLE_GAP)

	-- UIPanelScrollFrameTemplate, as Field Guide Forever's list; a ScrollBox would hold our data in Blizzard's secure code.
	scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", left, -(top + TITLE_HEIGHT))
	scroll:SetPoint("BOTTOMRIGHT", -(right + SCROLLBAR_WIDTH), bottom)
	scroll.scrollBarHideable = true -- the template's own switch: the bar shows only when the list is taller than the view
	child = CreateFrame("Frame", nil, scroll)
	child:SetSize(PANEL_WIDTH - left - right - SCROLLBAR_WIDTH, 1)
	scroll:SetScrollChild(child)

	empty = panel:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	empty:SetPoint("TOP", scroll, "TOP", 0, -ROW_HEIGHT)
	empty:SetText(L["Nothing left to learn."])
	empty:Hide()

	panel:SetScript("OnShow", function(self)
		self:SetHeight(window:GetHeight())
		Request()
	end)
	return panel
end

-- Another window opened beside Professions takes the center slot; the panel steps aside for it. Read after
-- Blizzard has laid its windows out. The Gamepad UI shows one window at a time, so this never triggers there.
local function UpdateVisibility()
	if not panel then return end
	local center = GetUIPanel("center")
	panel:SetShown(wanted and not (center and center ~= ProfessionsFrame))
end

-- Read-only post-hook: the window's own crafting page tells which profession is open. It runs once per
-- rebuild of the page, and several times when the window opens, so it only asks for one rebuild of ours.
local function OnInit(_, info)
	panel = panel or CreatePanel()
	if not (professionInfo and professionInfo.professionID == info.professionID) then
		retried = false
	end
	professionInfo = info
	-- Only this character's own professions have recipes to learn.
	wanted = Professions.InLocalCraftingMode()
	UpdateVisibility()
	Request()
end

-- The events that change what the window lists: its own list update (also sent by a filter change), the data
-- source switching, and learning or a skill change (docs/client-notes.md, "Panel").
local eventFrame = CreateFrame("Frame")
for _, event in ipairs({ "NEW_RECIPE_LEARNED", "SKILL_LINES_CHANGED", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED" }) do
	eventFrame:RegisterEvent(event)
end
eventFrame:SetScript("OnEvent", Request)

hooksecurefunc("UpdateUIPanelPositions", UpdateVisibility)

EventUtil.ContinueOnAddOnLoaded("Blizzard_Professions", function()
	local page = ProfessionsFrame.CraftingPage
	hooksecurefunc(page, "Init", OnInit)
	-- The window's search box drives the same filter the list uses.
	page.RecipeList.SearchBox:HookScript("OnTextChanged", Request)
	-- The overview page has no profession to list.
	page:HookScript("OnHide", function()
		wanted = false
		UpdateVisibility()
	end)
end)
