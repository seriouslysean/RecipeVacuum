local _, ns = ...
local L = ns.L

-- The player-facing list of unlearned recipes: a panel of our own beside the Professions window, never a write into Blizzard's list (docs/client-notes.md, "Gamepad").
-- Built as Field Guide Forever's list is (UI/List.lua): a Blizzard scroll frame and one real Button per row, so the Gamepad UI can focus rows and scroll them.
-- What the panel follows from the window, and why it builds a few rows a frame, is in docs/client-notes.md, "Panel".

local PANEL_WIDTH = 270 -- about 230 px are free beside the tab column at 1280x800; the quest tracker may be overlapped a little
local PANEL_GAP = 2 -- space between the tab column and the panel
-- The overview tab sits this far below the window's top (Blizzard_ProfessionsFrame.xml), so the panel lifts by the same.
local TAB_TOP_OFFSET = 60
local TITLE_HEIGHT = 66 -- the title, the step button under it and the count under that
local STEP_BUTTON_WIDTH = 110
local STEP_BUTTON_HEIGHT = 22 -- UIPanelButtonTemplate's own height
local STEP_BUTTON_GAP = 4
local CONTENT_PAD = 4
local SCROLLBAR_WIDTH = 22 -- room for UIPanelScrollFrameTemplate's bar to the right of the list
-- Blizzard's recipe row is 20 high (Blizzard_ProfessionsRecipeList.xml); two more hold an icon without crowding it.
local ROW_HEIGHT = 22
local ICON_SIZE = 20
local ROW_PAD = 4
local MAX_MARKS = 1 + #ns.sourceOrder + 1 -- a lock, every source type, or the unknown mark
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

-- Blizzard's own difficulty colors, by the recipe's difficulty for the player's skill (Blizzard_ProfessionsRecipeList.lua).
-- A trivial recipe has no entry there, and is drawn in the game's trivial color.
local DIFFICULTY_COLORS = {
	[Enum.TradeskillRelativeDifficulty.Optimal] = DIFFICULT_DIFFICULTY_COLOR,
	[Enum.TradeskillRelativeDifficulty.Medium] = FAIR_DIFFICULTY_COLOR,
	[Enum.TradeskillRelativeDifficulty.Easy] = EASY_DIFFICULTY_COLOR,
}

local panel, scroll, child, empty, countText, stepButton
local rows = {}
local entries = {} -- the recipes shown, in order
local professionInfo
local wanted = false -- a character's own crafting page is open
local requested = false
local retried = false
local generation = 0 -- a newer build ends the steps of an older one
local nextEntry, buildMs, buildSteps, foundCount

local function CreateRow(index)
	local row = CreateFrame("Button", nil, child)
	row:SetHeight(ROW_HEIGHT)
	row:SetHighlightAtlas("Options_List_Hover", "ADD") -- the highlight Blizzard's settings lists use

	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetSize(ICON_SIZE, ICON_SIZE)
	row.Icon:SetPoint("LEFT", ROW_PAD, 0)

	row.Name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.Name:SetPoint("LEFT", row.Icon, "RIGHT", ROW_PAD, 0)
	row.Name:SetJustifyH("LEFT")
	row.Name:SetWordWrap(false)

	-- The skill the list is ordered by, before the marks.
	row.Skill = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")

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

	row:SetScript("OnEnter", function(self)
		if not self.recipe then return end
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
		for slot = 1, self.markCount or 0 do
			ns.SetMarkStrength(marks[slot], false)
		end
		GameTooltip_Hide()
	end)
	-- One click pins the nearest source; a menu would taint (docs/client-notes.md, "Gamepad").
	row:SetScript("OnClick", function(self)
		if not self.recipe then return end
		local target = ns.MapTargets(self.recipe)[1]
		ns.Trace("UI row clicked: recipe %d, %s", self.recipe.recipeID, target and "pinned" or "no place to pin")
		if target then
			ns.ShowOnMap(target)
		end
	end)
	rows[index] = row
	return row
end

-- Grey when the recipe cannot be learned by this character, else the game's color for how it rates against their skill.
local function NameColor(recipeInfo)
	if recipeInfo.disabled or recipeInfo.lockReason then
		return DISABLED_FONT_COLOR
	end
	return DIFFICULTY_COLORS[recipeInfo.relativeDifficulty] or TRIVIAL_DIFFICULTY_COLOR
end

local function ShowRow(row, recipeInfo)
	row.recipe = recipeInfo
	recipeInfo.lockReason = ns.GetRecipeLock(recipeInfo.recipeID) or nil
	row.Icon:SetTexture(recipeInfo.icon)
	row.Name:SetText(recipeInfo.name)
	row.Name:SetTextColor(NameColor(recipeInfo):GetRGB())
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
	-- The skill number sits left of the marks, and the name stops where the number begins.
	row.Skill:SetPoint("RIGHT", row.marks[math.max(row.markCount, 1)].Texture, "LEFT", -ROW_PAD, 0)
	row.Name:SetPoint("RIGHT", row.Skill, "LEFT", -ROW_PAD, 0)
end

local function Finish()
	for index = #entries + 1, #rows do
		rows[index]:Hide()
	end
	ns.Trace("UI panel shown with %d rows of %d found, built in %.1f ms over %d frames", #entries, foundCount, buildMs, buildSteps)
	--@debug@
	ns.PerfMs("panel build", buildMs)
	--@end-debug@
end

-- One row per entry, all in the scroll child: the Gamepad UI moves between rows that exist and scrolls the
-- frame to reach one out of view, so a screenful of relabelled rows left it stuck at the last one shown.
-- Rows are kept and reused across professions, and made a few a frame so opening the window never stalls.
local function BuildStep(buildGeneration)
	if buildGeneration ~= generation or not panel:IsShown() then return end
	local started = debugprofilestop()
	local made = 0
	while nextEntry <= #entries and made < ROWS_PER_STEP and (made == 0 or debugprofilestop() - started < BUILD_BUDGET_MS) do
		local row = rows[nextEntry] or CreateRow(nextEntry)
		local top = -(nextEntry - 1) * ROW_HEIGHT
		row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, top)
		row:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, top)
		ShowRow(row, entries[nextEntry])
		row:Show()
		nextEntry = nextEntry + 1
		made = made + 1
	end
	buildMs = buildMs + (debugprofilestop() - started)
	buildSteps = buildSteps + 1
	if nextEntry <= #entries then
		RunNextFrame(function() BuildStep(buildGeneration) end)
	else
		Finish()
	end
end

-- The window's own filters, read where they can apply to a recipe not yet learned (docs/client-notes.md, "Panel").
local function CollectEntries(list)
	wipe(entries)
	local step = ns.CurrentStep()
	-- "Have materials" and "Show unlearned" are left out: nothing here is makeable, and Forever turns Show
	-- unlearned off by default, which emptied the panel. Skill-up reads the difficulty color, since a recipe
	-- not yet learned never reports that it can skill up.
	local search = CaseAccentInsensitiveParse(ProfessionsFrame.CraftingPage.RecipeList.SearchBox:GetText())
	local skillUpOnly = C_TradeSkillUI.GetOnlyShowSkillUpRecipes()
	local firstCraftOnly = C_TradeSkillUI.GetOnlyShowFirstCraftRecipes()
	for _, recipeInfo in ipairs(list) do
		if ns.FitsStep(recipeInfo, step, professionInfo)
			and (search == "" or recipeInfo.searchName:find(search, 1, true))
			and not (skillUpOnly and recipeInfo.relativeDifficulty == Enum.TradeskillRelativeDifficulty.Trivial)
			and not (firstCraftOnly and not recipeInfo.firstCraft) then
			entries[#entries + 1] = recipeInfo
		end
	end
end

local Request -- defined below; Update schedules its one retry through it

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
	CollectEntries(list)
	foundCount = #list
	stepButton:SetText(ns.CurrentStep().name)
	generation = generation + 1
	nextEntry, buildMs, buildSteps = 1, 0, 0
	child:SetHeight(math.max(#entries * ROW_HEIGHT, 1))
	empty:SetShown(#entries == 0)
	countText:SetText(L["%d of %d found"]:format(#entries, foundCount))
	scroll:SetVerticalScroll(0)
	for index = #entries + 1, #rows do
		rows[index]:Hide()
	end
	BuildStep(generation)
end

-- However many times the window rebuilds its page in a frame, the panel rebuilds once, on the next.
Request = function()
	if requested then return end
	requested = true
	RunNextFrame(Update)
end

-- Names every step with its sentence and marks the current one; a plain tooltip, since a menu would taint.
local function ShowStepTooltip(button)
	local _, current = ns.CurrentStep()
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, L["Recipes to Show"])
	for index, step in ipairs(ns.steps) do
		GameTooltip_AddColoredLine(GameTooltip, index == current and L["%s (current)"]:format(step.name) or step.name,
			index == current and GREEN_FONT_COLOR or NORMAL_FONT_COLOR)
		GameTooltip_AddColoredLine(GameTooltip, step.tip, HIGHLIGHT_FONT_COLOR)
	end
	GameTooltip:Show()
end

-- One click, or A on the gamepad, takes the next step and wraps; a real Button, as the Gamepad UI needs.
local function StepClicked(button)
	local _, current = ns.CurrentStep()
	local step = ns.steps[current % #ns.steps + 1]
	ns.db.panelStep = step.key
	ns.Trace("UI step changed to %s", step.key)
	Request()
	if GameTooltip:GetOwner() == button then ShowStepTooltip(button) end
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

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	title:SetPoint("TOP", 0, -top)
	title:SetText(L["Unlearned Recipes"])
	countText = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")

	stepButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	stepButton:SetSize(STEP_BUTTON_WIDTH, STEP_BUTTON_HEIGHT)
	stepButton:SetPoint("TOP", title, "BOTTOM", 0, -STEP_BUTTON_GAP)
	stepButton:SetScript("OnClick", StepClicked)
	stepButton:SetScript("OnEnter", ShowStepTooltip)
	stepButton:SetScript("OnLeave", GameTooltip_Hide)
	countText:SetPoint("TOP", stepButton, "BOTTOM", 0, -STEP_BUTTON_GAP)

	-- UIPanelScrollFrameTemplate, as Field Guide Forever's list; a ScrollBox would hold our data in Blizzard's secure code.
	scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", left, -(top + TITLE_HEIGHT))
	scroll:SetPoint("BOTTOMRIGHT", -(right + SCROLLBAR_WIDTH), bottom)
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
