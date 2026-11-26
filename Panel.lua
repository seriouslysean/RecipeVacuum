local addonName, ns = ...
local L = ns.L

-- The player-facing list of unlearned recipes: a panel of our own beside the Professions window, never a write into Blizzard's list (docs/client-notes.md, "Gamepad").
-- A Blizzard scroll frame and one real Button per row, so the Gamepad UI can focus rows and scroll them (docs/client-notes.md, "Panel").
-- Rows and headings are Blizzard's own recipe list templates, so they look as its list does (docs/client-notes.md, "Panel").

-- Blizzard_ProfessionsCrafting.xml:138-139: the window's recipe list sits 5 px in from its frame's left and bottom.
-- Here that inset is on both sides, so the portrait frame's border does not eat the list's width (docs/client-notes.md, "Panel").
local FRAME_INSET = 5
local LIST_WIDTH = 242 -- usable width of the list between its left inset and the scroll bar column
-- Blizzard_ProfessionsRecipeList.xml:61-66 (ProfessionsRecipeListTemplate.ScrollBox): the list's left inset, the
-- column right of it that the scroll bar fills and the gap below it.
local LIST_LEFT = 8
local SCROLLBAR_WIDTH = 20
local LIST_BOTTOM_INSET = 5
local PANEL_WIDTH = LIST_WIDTH + LIST_LEFT + SCROLLBAR_WIDTH + 2 * FRAME_INSET -- about 230 px are free beside the tab column at 1280x800; the quest tracker may be overlapped a little
-- NineSliceLayouts.lua:20 (PortraitFrameTemplate): the top left and bottom left corners stand this far outside the frame, so
-- the panel keeps that much extra from the tab column and the corner never covers a tab.
local CORNER_OVERHANG = 13
local PANEL_GAP = 2 + CORNER_OVERHANG -- space between the tab column and the panel
-- The overview tab sits this far below the window's top (Blizzard_ProfessionsFrame.xml), so the panel lifts by the same.
local TAB_TOP_OFFSET = 60
-- Blizzard_ProfessionsCrafting.xml:199 (RankBar, TOPLEFT y=-40): where the window's own content starts below its title strip.
-- The frame's top edge art (NineSliceLayouts.lua:24, drawn over the frame's own layers) is taller than the 21 px at which the
-- background starts (SharedUIPanelTemplates.xml:629), so nothing sits higher than this.
local CONTENT_TOP = 40
-- Blizzard_ProfessionsCrafting.xml:157 (RecipeList TOPLEFT y=-72): where the window's list starts; read from the window when shown.
local LIST_TOP_DEFAULT = 72
-- Blizzard_ProfessionsRecipeList.lua: view spacing, indent and pad; the element extents (20 per recipe, 20 + 5 per category).
local ROW_HEIGHT = 20
local HEADING_HEIGHT = 25
local ROW_SPACING = 1
-- Blizzard_ProfessionsRecipeList.lua:127-133 and Blizzard_Professions.lua:960-974: an open category holds a 1 px element above
-- its recipes and a 10 px one below them, each followed by the list's spacing.
local TOP_PAD = 1
local BOTTOM_PAD = 10
local ROW_INDENT = 10
local LIST_PAD = 5 -- top, bottom and right pad of the list's view (:15, CreateScrollBoxListTreeListView)
local ROW_PAD = 4
-- Blizzard_SharedXML/ListTemplates.xml:35 (the title's left inset) and the gap the count keeps after it.
local HEADING_TEXT_LEFT = 8
local COUNT_GAP = 4
-- Blizzard_ProfessionsRecipeList.xml:140-145,167-172: a row's SkillUps slot (26 x 15, 9 left of the row) and the
-- label's 4 px gap after it. The skill number takes that slot, right-aligned so the numbers line up.
local SKILL_WIDTH = 26
local SKILL_HEIGHT = 15
local SKILL_X = -9
local LABEL_GAP = 4
-- Blizzard_ProfessionsRankBar.xml:21: the fill is 12 px narrower than the bar's art.
local BAR_CAP = 16 -- each end of the skill bar art kept at its own size: past its 3 px clipped corners, where the art is even
local BAR_FILL_LEFT, BAR_FILL_TOP, BAR_FILL_INSET = 5, 3, 12 -- Blizzard_ProfessionsRankBar.xml: the fill at 5, -3, 441 of 453
local RANK_BAR_HEIGHT = 18 -- the window's rank bar, whose line ours keeps
-- SharedUIPanelTemplates.xml:581-585: the window's 62 px portrait hangs 5 left of and 7 above its frame's corner. The icon's ring
-- takes the same share of its size.
local PORTRAIT_SIZE, PORTRAIT_LEFT = 62, 5
-- The discovery bar is centered on the panel under the title, as the window centers its skill bar, and as wide as that allows
-- while clearing the portrait ring on the left by RANK_BAR_CLEARANCE (docs/client-notes.md, "Panel").
local RANK_BAR_CLEARANCE = 4
local RANK_BAR_LEFT = PORTRAIT_SIZE - PORTRAIT_LEFT + RANK_BAR_CLEARANCE
local BAR_WIDTH = PANEL_WIDTH - 2 * RANK_BAR_LEFT
local MAX_MARKS = 1 + #ns.sourceOrder + 1 -- a lock, every source type, or the unknown mark
local ROW_TEMPLATE = "ProfessionsRecipeListRecipeTemplate"
local HEADING_TEMPLATE = "ProfessionsRecipeListCategoryTemplate"
-- Rows are made in steps of at most this much time and this many rows, so no frame from the panel nears 16 ms.
local BUILD_BUDGET_MS = 4
local ROWS_PER_STEP = 40
local WAIT_SECONDS = 1 -- at most: the client may still be loading names and factions when the window opens; the list waits instead of redrawing
-- Frames made ahead of need, out of combat, a few a frame (docs/client-notes.md, "Panel"), so a profession only fills frames that exist.
local POOL_ROWS = 60
local POOL_HEADINGS = 8
-- The window's own art under Camelot, which hides the list's inset border and the schematic's inset frame (docs/client-notes.md, "Panel"):
-- the page atlas at 3, -21 (Blizzard_ProfessionsFrame.xml:71) and the schematic's sliced border (Blizzard_ProfessionsRecipeSchematicForm.xml:8).
local PAGE_ATLAS, PAGE_LEFT, PAGE_TOP, PAGE_WIDTH, PAGE_RIGHT_GAP = "Profession-Background-Template2", 3, 21, 665, 5
local PAGE_BOTTOM_GAP = 3 -- the page's 570 height in the window's 594
local WINDOW_BACKGROUND = "Profession-Background-Overview" -- Camelot/Blizzard_ProfessionsFrame.lua:137
local FORM_BORDER_ATLAS, FORM_SLICE = "common-insideframe", 53
-- The details' icon hangs off its pane where the window's portrait ring hangs off the window: the frame places that ring's corner art at
-- -13, 16 (NineSliceLayouts.lua:20), the ring spanning 5 to 71 of the 95 px art.
local RING_FROM, RING_TO = 5, 71 -- the portrait ring within its 95 px corner art
local RING_SIZE = RING_TO - RING_FROM
local OUTPUT_RING_INSET = (58 - 47) / 2 -- the output ring's drawn edge to its button (ProfessionsOutputButtonTemplate, 47 px)
-- The window's frame line is its edge; the pane frame's line sits inside the box's edge, so the ring moves by that much more to
-- hang off the line as the portrait does (measured against the window's portrait on the Deck).
local LINE_IN_LEFT, LINE_IN_TOP = 2, 5
local RING_LEFT = 13 - RING_FROM + LINE_IN_LEFT -- the ring's offset past the box's left, as the frame's corner piece less the art's own margin
local RING_RISE = 16 - RING_FROM - LINE_IN_TOP
local ICON_LEVEL = 600 -- above the list's whole tree and every frame of ours, so the ring draws over both boxes' borders
-- The pane's text and reagents as the live window places them, measured with /recipevacuum layout (build 71139; docs/client-notes.md,
-- "Panel"): name 27.5 below the pane's top and 14 right of the output icon, the requirement 5 under it; the "Reagents:" label's top at
-- 108 (lower if the text above runs long), its icons 25.5 under that, 28 in, 45 apart, each name 46 right of its icon.
local OUTPUT_LEFT = -RING_LEFT + OUTPUT_RING_INSET
local NAME_TOP = 27.5
local NAME_LEFT = OUTPUT_LEFT + 47 + 14
local OUTPUT_SUB_GAP = 5
local DETAIL_GAP = RING_RISE + 2 -- the ring hangs into the gap above the box, so the list ends above it
local DETAIL_BOTTOM = 20 -- content ends this far above the pane's bottom (:62), clear of the border's corner art
local REAGENTS_TOP, REAGENTS_LEFT = 108, 27
local REAGENTS_BELOW_TEXT = 41.5 -- the label's top under the requirement line's bottom, as measured
local REAGENTS_LABEL_HEIGHT = 20
local REAGENT_ICON_BELOW_LABEL = 25.5
local REAGENT_LEFT, REAGENT_PITCH = 28, 45
local REAGENT_SIZE = 39 -- ProfessionsButtonTemplate (Blizzard_ProfessionsTemplates.xml:42)
local REAGENT_TEXT_GAP = 46 - REAGENT_SIZE
local REAGENT_NAME_WIDTH, REAGENT_NAME_HEIGHT = 108, 36 -- Blizzard_ProfessionsRecipeReagentSlotBase.xml:20
-- Show Map sits in the strip under the box as the window's Create button does: 7 above the bottom, the pane ending 38 above it
-- (Blizzard_ProfessionsCrafting.lua:1036; 594 less the pane's 72 top and 484 height).
local BUTTON_BOTTOM = 7
local SOURCE_HEIGHT = 28 -- the window's Create button, measured
local STRIP_HEIGHT = 38
local PANEL_INNER_WIDTH = PANEL_WIDTH - 2 * FRAME_INSET

local panel, listArea, scroll, child, empty, rankBar, detail
local placedKey
local stripShown -- the details leave the strip under their box for Show Map
local SelectRecipe -- defined with the details; a row tap selects through it
local selected -- the recipe whose details show: set by a tap, kept until another is tapped, the profession changes or it leaves the list
local detailSignature
local reagentRows, sourceButtons = {}, {}
local mapButton, mapMore -- Show Map: a plain button for one place, the dropdown-looking one for several
local placeMenu -- the floating list of places under mapMore
local mapOpen -- that list is open; a press toggles it, focus never does
local shownDiscovery
local rows, headings = {}, {}
local items = {} -- what the list shows, in order: { band = n } for a heading, { recipe = info } for a row
local slots = {} -- the frame of each item once built
local toggled = {} -- [professionID .. ":" .. band] = open, for the session only: the player's own choices
local professionInfo
local wanted = false -- a character's own crafting page is open
local requested = false
local waitUntil -- when the wait for the client's data ends, for the open profession
local waitQueued = false
local generation = 0 -- a newer build ends the steps of an older one
local shownSignature, builtProfession
local nextItem, buildMs, buildSteps, recipeCount, bandCount

-- Right from a row goes to the details and left from the details goes back to the row, through Blizzard's own jump overrides
-- (Blizzard_GamepadSmartNavigation/Utility.lua:414-500; docs/client-notes.md, "Gamepad"). An override set from addon code is
-- honoured only out of combat (SmartNavigation.lua:1503-1520) and setting one in combat is refused, so none is touched then.
local navSet = {} -- [frame] = { [direction] = true } the overrides set on it
local navPending = false -- a change waited for the end of combat
local function NavAvailable()
	return SMART_NAV_INPUT_DIRECTION and SmartNavigation_AddJumpNavigationOverride and SmartNavigation_ClearJumpNavigationOverridesInDirection
end

local function ClearNav()
	if not NavAvailable() then return end
	if InCombatLockdown() then
		navPending = true
		return
	end
	for frame, directions in pairs(navSet) do
		for direction in pairs(directions) do
			SmartNavigation_ClearJumpNavigationOverridesInDirection(frame, direction)
		end
	end
	wipe(navSet)
end

local function SetNav(frame, direction, target)
	SmartNavigation_AddJumpNavigationOverride(frame, direction, target)
	navSet[frame] = navSet[frame] or {}
	navSet[frame][direction] = true
end

-- Only the rows of the open list lead to the details, and every control in the details leads back to the selected row (the
-- first one when none is). Run whenever the selection, the rows or the details change.
local function SyncNav()
	if not NavAvailable() then return end
	if InCombatLockdown() then
		navPending = true
		return
	end
	navPending = false
	ClearNav()
	if not (panel and panel:IsShown() and detail:IsShown()) then return end
	local mapShown = mapMore and mapMore:IsShown() and mapMore or mapButton
	local into = mapShown and mapShown:IsShown() and mapShown:IsEnabled() and mapShown or detail.Output
	local first, chosen, rowCount = nil, nil, 0
	for index = 1, math.min((nextItem or 1) - 1, #items) do
		local item = items[index]
		if item.recipe then
			SetNav(slots[index], SMART_NAV_INPUT_DIRECTION.RIGHT, into)
			rowCount = rowCount + 1
			first = first or slots[index]
			if selected and item.recipe.recipeID == selected.recipeID then chosen = slots[index] end
		end
	end
	local back = chosen or first
	if not back then return end
	local controls = { detail.Output, mapButton, mapMore }
	for _, list in ipairs({ reagentRows, sourceButtons }) do
		for _, button in ipairs(list) do controls[#controls + 1] = button end
	end
	local count = 0
	for _, control in ipairs(controls) do
		if control:IsShown() then
			SetNav(control, SMART_NAV_INPUT_DIRECTION.LEFT, back)
			count = count + 1
		end
	end
	-- The open list is reached down from its button and walked with up and down; left from an entry goes back (above).
	if placeMenu and placeMenu:IsShown() then
		local previous = mapMore
		for _, button in ipairs(sourceButtons) do
			if button:IsShown() then
				SetNav(previous, SMART_NAV_INPUT_DIRECTION.DOWN, button)
				SetNav(button, SMART_NAV_INPUT_DIRECTION.UP, previous)
				previous = button
			end
		end
	end
	ns.Trace("UI nav override set: %d rows to the details, %d controls back", rowCount, count)
end

-- ANCHOR_RIGHT would clamp the tooltip over the panel at the screen's edge; with no room on the right it goes to the left
-- of the panel, level with the hovered frame (docs/client-notes.md, "Panel").
local TOOLTIP_ROOM = 340 -- a typical item tooltip's width
function ns.OwnTooltip(owner)
	GameTooltip:SetOwner(owner, "ANCHOR_NONE")
	GameTooltip:ClearAllPoints()
	if UIParent:GetRight() - panel:GetRight() < TOOLTIP_ROOM then
		GameTooltip:SetPoint("TOPRIGHT", owner, "TOPLEFT", -(owner:GetLeft() - panel:GetLeft()), 0)
	else
		GameTooltip:SetPoint("TOPLEFT", owner, "TOPLEFT", panel:GetRight() - owner:GetLeft(), 0)
	end
end

local function CreateRow()
	local row = CreateFrame("Button", nil, child, ROW_TEMPLATE)
	row.SkillUps:Hide()

	-- The skill the list is ordered by comes first: it is what the list is about.
	row.Skill = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	row.Skill:SetPoint("LEFT", SKILL_X, 0)
	row.Skill:SetSize(SKILL_WIDTH, SKILL_HEIGHT)
	row.Skill:SetJustifyH("RIGHT")
	row.Label:ClearAllPoints()
	row.Label:SetPoint("LEFT", row.Skill, "RIGHT", LABEL_GAP, 0)
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
		self.Count:SetVertexColor(HIGHLIGHT_FONT_COLOR:GetRGB())
		for slot = 1, self.markCount do
			ns.SetMarkStrength(marks[slot], true)
		end
		-- The game's own tooltip for what the recipe makes, so other addons' tooltip hooks run, then our source lines.
		local recipeID = self.recipe.recipeID
		local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
		local itemID = schematic and schematic.outputItemID
		ns.OwnTooltip(self)
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
		if self.recipe then
			self.Label:SetVertexColor(self.color:GetRGB())
			self.Count:SetVertexColor(self.color:GetRGB())
		end
		for slot = 1, self.markCount or 0 do
			ns.SetMarkStrength(marks[slot], false)
		end
		GameTooltip_Hide()
	end)
	-- A tap selects, as Blizzard's list does (Blizzard_ProfessionsRecipeList.lua:46-62); the details below hold the sources. A menu would taint (docs/client-notes.md, "Gamepad").
	row:SetScript("OnClick", function(self, button)
		if not self.recipe or button == "RightButton" then return end
		PlaySound(SOUNDKIT.UI_90_BLACKSMITHING_TREEITEMCLICK)
		SelectRecipe(self.recipe)
	end)
	row:Hide() -- hidden until a build places it
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
	-- The count after the name, smaller and dim as Blizzard's rows show theirs, so it is not part of the title font.
	heading.Count = heading:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	-- The template's own OnEnter and OnLeave stay: they only light the title and the marker.
	heading:SetScript("OnClick", function(self)
		toggled[BandKey(self.band)] = not IsOpen(self.band)
		ns.Trace("UI band %d %s", self.band, toggled[BandKey(self.band)] and "opened" or "closed")
		Request()
	end)
	heading:Hide()
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

-- How many the bags and bank could make, as Blizzard's rows show it in brackets (Blizzard_ProfessionsRecipeList.lua, SetCraftableCount).
-- The client counts only learned recipes, so an unlearned one is counted from its basic reagents. A reagent list never changes, so it is
-- read once per recipe.
local recipeNeeds = {}
local function CraftableCount(recipeID)
	local needs = recipeNeeds[recipeID]
	if not needs then
		needs = {}
		local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
		for _, slot in ipairs(schematic and schematic.reagentSlotSchematics or {}) do
			local reagent = slot.reagentType == Enum.CraftingReagentType.Basic and slot.reagents[1]
			if reagent and reagent.itemID then needs[#needs + 1] = { reagent.itemID, slot.quantityRequired } end
		end
		recipeNeeds[recipeID] = needs
	end
	if #needs == 0 then return 0 end
	local count = math.huge
	for _, need in ipairs(needs) do
		count = math.min(count, math.floor(C_Item.GetItemCount(need[1], true) / need[2]))
	end
	return count
end

-- Everything a row shows that does not move it, so a skill rise or new source updates a row without a rebuild.
local function ShowRow(row, recipeInfo)
	row.recipe = recipeInfo
	row:SetSelected(selected ~= nil and selected.recipeID == recipeInfo.recipeID) -- the template's own selected look
	recipeInfo.lockReason = ns.GetRecipeLock(recipeInfo.recipeID) or nil
	row.Label:SetText(recipeInfo.name)
	row.color = NameColor(recipeInfo)
	if not row:IsMouseMotionFocus() then
		row.Label:SetVertexColor(row.color:GetRGB())
		row.Count:SetVertexColor(row.color:GetRGB())
	end
	local count = CraftableCount(recipeInfo.recipeID)
	row.Count:SetShown(count > 0)
	if count > 0 then row.Count:SetFormattedText(" [%d] ", count) end
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
	-- The name stops where the count and the marks begin, as Blizzard's row trims its label for the count.
	local room = row.marks[math.max(row.markCount, 1)].Texture:GetLeft()
	room = room and room - ROW_PAD - row.Label:GetLeft() - (count > 0 and row.Count:GetStringWidth() or 0)
	row.Label:SetWidth(0)
	row.Label:SetWidth(room and math.min(room, row.Label:GetStringWidth()) or row.Label:GetStringWidth())
end

local function ShowHeading(heading, item)
	heading.band = item.band
	local professionID = professionInfo.professionID
	heading:SetHeaderText(ns.BandTitle(professionID, item.band, function()
		-- Only if the heading still shows this band when the rank's name arrives.
		if heading.band == item.band and professionInfo and professionInfo.professionID == professionID then
			ShowHeading(heading, item)
		end
	end))
	heading.Count:SetShown(not item.open)
	if not item.open then
		heading.Count:SetText(L["[%d]"]:format(item.count))
		heading.Count:SetPoint("LEFT", heading, "LEFT", HEADING_TEXT_LEFT + heading.ButtonText:GetStringWidth() + COUNT_GAP, 0)
	end
	heading:UpdateCollapsedState(not item.open)
end

local function Finish()
	empty:SetShown(#items == 0)
	scroll:SetAlpha(1) -- the whole list at once
	SyncNav()
	ns.Trace("UI panel shown with %d rows under %d bands, built in %.1f ms over %d frames", recipeCount, bandCount, buildMs, buildSteps)
	--@debug@
	if ns.OnPanelDrawn then ns.OnPanelDrawn(professionInfo and professionInfo.professionID, selected and selected.recipeID) end
	--@end-debug@
	--@debug@
	ns.PerfMs("panel build", buildMs)
	--@end-debug@
end

-- One frame per item, all in the scroll child: the Gamepad UI moves between frames that exist and scrolls the
-- frame to reach one out of view, so a screenful of relabelled rows left it stuck at the last one shown.
-- Frames are kept and reused across professions, and made a few a frame so opening the window never stalls.
local function BuildStep(buildGeneration)
	if buildGeneration ~= generation then return end
	if not panel:IsShown() then
		shownSignature = nil -- an unfinished build is made again when the panel shows
		return
	end
	local started = debugprofilestop()
	-- Only making a frame is limited; filling one that exists is cheap, so a pooled list is one pass.
	local made = 0
	while nextItem <= #items and (made == 0 or (made < ROWS_PER_STEP and debugprofilestop() - started < BUILD_BUDGET_MS)) do
		local item = items[nextItem]
		local frame
		if item.recipe then
			if not rows[item.rowIndex] then made = made + 1 end
			frame = rows[item.rowIndex] or CreateRow()
			frame:SetPoint("TOPLEFT", child, "TOPLEFT", ROW_INDENT, -item.top)
			frame:SetPoint("TOPRIGHT", child, "TOPRIGHT", -LIST_PAD, -item.top)
			frame:SetHeight(ROW_HEIGHT)
			ShowRow(frame, item.recipe)
		else
			if not headings[item.headingIndex] then made = made + 1 end
			frame = headings[item.headingIndex] or CreateHeading()
			frame:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -item.top)
			frame:SetPoint("TOPRIGHT", child, "TOPRIGHT", -LIST_PAD, -item.top)
			frame:SetHeight(HEADING_HEIGHT)
			ShowHeading(frame, item)
		end
		frame:Show()
		slots[nextItem] = frame
		nextItem = nextItem + 1
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
			top = top + TOP_PAD + ROW_SPACING
			for at = index, last do
				rowCount = rowCount + 1
				newItems[#newItems + 1] = { recipe = found[at], top = top, rowIndex = rowCount }
				parts[#parts + 1] = found[at].recipeID
				top = top + ROW_HEIGHT + ROW_SPACING
			end
			top = top + BOTTOM_PAD + ROW_SPACING
		end
		index = last + 1
	end
	return newItems, table.concat(parts, ","), rowCount, headingCount, top + LIST_PAD
end

-- The list area sits where the crafting page's own list does: its top and bottom are read when shown (the window can be a
-- different size) and only re-anchored when they change. The details, when open, take their height from the bottom and the list
-- ends above them (docs/client-notes.md, "Panel").
local function PlaceList()
	local theirs = ProfessionsFrame.CraftingPage.RecipeList
	local panelTop, panelBottom = panel:GetTop(), panel:GetBottom()
	local listTop, listBottom = theirs:GetTop(), theirs:GetBottom()
	if not (panelTop and panelBottom and listTop and listBottom) then return end
	local top = math.max(panelTop - listTop, CONTENT_TOP)
	local bottom = math.max(listBottom - panelBottom, FRAME_INSET)
	local detailHeight = detail:IsShown() and detail:GetHeight() or 0
	local boxBottom = bottom + (stripShown and STRIP_HEIGHT - FRAME_INSET or 0)
	local key = ("%s:%s:%s:%s"):format(top, bottom, detailHeight, boxBottom)
	if key == placedKey then return end
	placedKey = key
	listArea:SetPoint("TOPLEFT", panel, "TOPLEFT", FRAME_INSET, -top)
	detail:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", FRAME_INSET, boxBottom)
	detail:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -FRAME_INSET, boxBottom)
	-- The list's background is always drawn at the list's full height and cut off where the details begin: squeezed into a shorter
	-- list, its dark bottom fade showed as a bar above the box. It runs into the gap the ring hangs into, down to the box.
	listArea.BackgroundFrame:SetHeight(panelTop - panelBottom - top - bottom)
	listArea.Clip:ClearAllPoints()
	listArea.Clip:SetPoint("TOPLEFT")
	if detailHeight > 0 then
		listArea:SetPoint("BOTTOMRIGHT", detail, "TOPRIGHT", 0, DETAIL_GAP)
		listArea.Clip:SetPoint("BOTTOMRIGHT", 0, -DETAIL_GAP)
	else
		listArea:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -FRAME_INSET, bottom)
		listArea.Clip:SetPoint("BOTTOMRIGHT")
	end
end

-- Discovery, as a challenge's progress: found of every recipe the character could still learn here.
local function UpdateDiscovery(found, total)
	local key = ("%s:%d:%d"):format(professionInfo.professionID, found, total)
	if key == shownDiscovery then return end
	shownDiscovery = key
	-- The fill's width is the share found, as the skill bar's mask shows its share.
	local share = total > 0 and math.min(found / total, 1) or 0
	rankBar.Fill:SetShown(share > 0)
	rankBar.Mask:SetWidth(math.max(BAR_WIDTH * share, 1)) -- GetMaskWidth: the bar's width times the share
	rankBar.text:SetText(L["%d / %d discovered"]:format(found, total))
end

-- The first frame of a pool of one kind, made when needed; later ones are reused for another recipe.
local function Pooled(pool, index, make)
	pool[index] = pool[index] or make()
	return pool[index]
end

local function MakeReagentRow()
	local button = CreateFrame("ItemButton", nil, detail, "ProfessionsButtonTemplate")
	button:SetScript("OnEnter", function(self)
		ns.OwnTooltip(self)
		GameTooltip:SetItemByID(self.itemID)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button.Text = detail:CreateFontString(nil, "ARTWORK", "GameFontHighlight_NoShadow")
	button.Text:SetPoint("LEFT", button, "RIGHT", REAGENT_TEXT_GAP, 0)
	button.Text:SetSize(REAGENT_NAME_WIDTH, REAGENT_NAME_HEIGHT) -- Blizzard's slot name box, so long names wrap as the pane's do
	button.Text:SetJustifyH("LEFT")
	return button
end

local FillDetail -- defined below; a press on a place redraws the details

-- Blizzard's own dropdown art, for whichever menu family the client loaded (Blizzard_Menu/Classic or Mainline MenuTemplates):
-- the filter button's background bleed past its box (WowStyle1FilterDropdownTemplate) and the menu's background, shade and inset
-- (the Generate and GetInset of the style that button's menu uses). Read when first needed; we never call Blizzard's Menu system.
local MENU_ART = {
	classic = { bleed = 2, bg = "common-dropdown-classic-b-bg", bgTopLeft = { -3, 1 }, bgBottomRight = { 3, -4 },
		shade = { 7, -4, -8, 8 }, inset = { left = 14, top = 14, right = 14, bottom = 14 } },
	mainline = { bleed = 4, bg = "common-dropdown-bg", bgTopLeft = { -10, 3 }, bgBottomRight = { 10, -3 }, alpha = .925,
		inset = { left = 8, top = 8, right = 8, bottom = 15 } },
}
local function MenuArt()
	-- The family's own state constants name its atlases (Classic/MenuConstants.lua, MenuConstants.lua).
	return WowStyle1FilterDropdownStateEnabled:find("classic", 1, true) and MENU_ART.classic or MENU_ART.mainline
end
local PLACE_ENTRY_HEIGHT = 20 -- one entry of Blizzard's menus (11_0_0_MenuImplementationGuide.lua)
local MENU_OFFSET_X, MENU_OFFSET_Y = 6, 2 -- the filter button's menuPointX and menuPointY (WowStyle1FilterDropdownTemplate)
-- Blizzard_Menu/MenuVariants.lua:41-50: a menu entry's hover.
local MENU_HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local ClosePlaces, UpdatePlaceMenu

local function MakeSourceButton()
	local button = CreateFrame("Button", nil, placeMenu)
	button:SetHeight(PLACE_ENTRY_HEIGHT)
	button:SetHighlightTexture(MENU_HIGHLIGHT, "ADD")
	-- A Button has no font string until given one; SetText("") does not make it.
	local text = button:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	button:SetFontString(text)
	text:SetPoint("LEFT")
	text:SetPoint("RIGHT")
	text:SetJustifyH("LEFT")
	text:SetWordWrap(false)
	-- One source's pin, exactly: an entry pins what it names, then the list closes (docs/client-notes.md, "Panel").
	button:SetScript("OnClick", function(self)
		ns.Trace("UI source pressed: %s", self.source.label)
		ns.ShowOnMap(self.source.target)
		ClosePlaces()
	end)
	button:SetScript("OnEnter", function(self)
		ns.OwnTooltip(self)
		GameTooltip_SetTitle(GameTooltip, self.source.place)
		GameTooltip_AddNormalLine(GameTooltip, L["Press to mark this place on your map."])
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	return button
end

-- Every source, one line each: "who, type" left and its place right (none for a source with no place). The hint only when a press pins.
local function ShowMapTooltip(self)
	ns.OwnTooltip(self)
	for _, source in ipairs(self.sources) do
		GameTooltip:AddDoubleLine(source.label, source.place or "", HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
			NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
	end
	if self.single then
		GameTooltip_AddBlankLineToTooltip(GameTooltip)
		GameTooltip_AddNormalLine(GameTooltip, L["Press to mark this place on your map."])
	end
	GameTooltip:Show()
end

-- The floating list of places, drawn as Blizzard's dropdown menu is: its background art and inset, under the button, on its own
-- strata so it covers whatever it drops over and never changes the details' layout.
local function MakePlaceMenu()
	local art = MenuArt()
	local menu = CreateFrame("Frame", nil, panel)
	menu:SetFrameStrata("DIALOG")
	menu:EnableMouse(true)
	menu:Hide()
	local bg = menu:CreateTexture(nil, "BACKGROUND")
	bg:SetAtlas(art.bg)
	bg:SetPoint("TOPLEFT", unpack(art.bgTopLeft))
	bg:SetPoint("BOTTOMRIGHT", unpack(art.bgBottomRight))
	bg:SetAlpha(art.alpha or 1)
	if art.shade then
		local shade = menu:CreateTexture(nil, "BACKGROUND", nil, -1)
		shade:SetColorTexture(0, 0, 0, .8)
		shade:SetPoint("TOPLEFT", bg, "TOPLEFT", art.shade[1], art.shade[2])
		shade:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", art.shade[3], art.shade[4])
	end
	-- Escape closes it and is not passed on, so it does not also close the Professions window; every other key goes on.
	menu:EnableKeyboard(true)
	menu:SetScript("OnKeyDown", function(self, key)
		local escape = key == "ESCAPE"
		self:SetPropagateKeyboardInput(not escape)
		if escape then ClosePlaces() end
	end)
	-- A press anywhere else closes it, as Blizzard's menus do; the button's own press toggles.
	menu:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
	menu:SetScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
	menu:SetScript("OnEvent", function(self)
		if not (self:IsMouseOver() or (mapMore and mapMore:IsMouseOver())) then ClosePlaces() end
	end)
	return menu
end

-- The several-places button: the window's Filter button's own art (state atlases from Blizzard_Menu's constants, arrow included),
-- on a Button of ours, so no Blizzard menu is ever set up on it.
local function MakeMapMore()
	local art = MenuArt()
	local button = CreateFrame("Button", nil, detail)
	button:SetSize(PANEL_INNER_WIDTH, SOURCE_HEIGHT)
	button:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", FRAME_INSET, BUTTON_BOTTOM)
	button.Background = button:CreateTexture(nil, "BACKGROUND")
	button.Background:SetPoint("TOPLEFT", -art.bleed, art.bleed)
	button.Background:SetPoint("BOTTOMRIGHT", art.bleed, -art.bleed)
	-- The Filter button's own fonts: gold, grey when disabled (WowStyle1FilterDropdownTemplate's baseFontObject and disableFontObject).
	button:SetNormalFontObject("GameFontNormal")
	button:SetDisabledFontObject("GameFontDisable")
	button:SetText(MAP_PIN)
	local text = button:GetFontString()
	text:ClearAllPoints()
	text:SetPoint("LEFT", 12, 0)
	text:SetPoint("RIGHT", -24, 0) -- the arrow's room
	text:SetJustifyH("CENTER")
	button:SetPushedTextOffset(2, -1) -- WowStyle1FilterDropdownMixin:OnLoad's displacement
	local function Look(self)
		local over, down = self:IsMouseOver(), self:GetButtonState() == "PUSHED"
		local atlas = WowStyle1FilterDropdownStateEnabled
		if over and down then atlas = WowStyle1FilterDropdownStateDownOver
		elseif over then atlas = WowStyle1FilterDropdownStateOver
		elseif down then atlas = WowStyle1FilterDropdownStateDown end
		self.Background:SetAtlas(atlas, TextureKitConstants.UseAtlasSize)
	end
	Look(button)
	button:SetScript("OnClick", function()
		mapOpen = not mapOpen
		UpdatePlaceMenu()
	end)
	button:HookScript("OnMouseDown", Look)
	button:HookScript("OnMouseUp", Look)
	button:SetScript("OnEnter", function(self) Look(self); ShowMapTooltip(self) end)
	button:SetScript("OnLeave", function(self) Look(self); GameTooltip_Hide() end)
	return button
end

-- The game's own word for what a press does, Map Pin (MAP_PIN): it places the map pin and focuses it, and never opens the map. One place is a plain button that pins it;
-- several are the dropdown-looking button above, which opens the list of places. Our own Buttons throughout: a Blizzard menu
-- would taint the Gamepad UI (docs/client-notes.md, "Gamepad").
local function MakeMapButton()
	local button = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
	button:SetSize(PANEL_INNER_WIDTH, SOURCE_HEIGHT)
	button:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", FRAME_INSET, BUTTON_BOTTOM) -- the window's action buttons sit at the bottom of their page
	button:SetText(MAP_PIN)
	button:SetScript("OnClick", function(self)
		if self.single then
			ns.Trace("UI source pressed: %s", self.single.label)
			ns.ShowOnMap(self.single.target)
		end
	end)
	-- A disabled button still shows its tooltip: the sources are the reason it is disabled.
	button:SetMotionScriptsWhileDisabled(true)
	button:SetScript("OnEnter", ShowMapTooltip)
	button:SetScript("OnLeave", GameTooltip_Hide)
	return button
end

-- Opens or closes the floating list to match mapOpen: down from the button like Blizzard's dropdown menus, above it when the
-- screen has no room below (the flip of Blizzard_Menu/Menu.lua FlipPositionIfOffscreen).
UpdatePlaceMenu = function()
	local places = mapMore and mapMore:IsShown() and mapMore.places
	if not (mapOpen and places and #places > 1) then
		mapOpen = false
		if placeMenu then placeMenu:Hide() end
		SyncNav()
		return
	end
	placeMenu = placeMenu or MakePlaceMenu()
	local inset = MenuArt().inset
	local width = mapMore:GetWidth()
	placeMenu:SetSize(width, #places * PLACE_ENTRY_HEIGHT + inset.top + inset.bottom)
	for index, source in ipairs(places) do
		local button = Pooled(sourceButtons, index, MakeSourceButton)
		button.source = source
		button:SetWidth(width - inset.left - inset.right)
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", placeMenu, "TOPLEFT", inset.left, -inset.top - (index - 1) * PLACE_ENTRY_HEIGHT)
		button:SetText(source.label)
		button:Show()
	end
	for index = #places + 1, #sourceButtons do sourceButtons[index]:Hide() end
	placeMenu:ClearAllPoints()
	placeMenu:SetPoint("TOPLEFT", mapMore, "BOTTOMLEFT", MENU_OFFSET_X, MENU_OFFSET_Y)
	placeMenu:Show()
	local bottom = placeMenu:GetBottom()
	if bottom and bottom < 0 then
		placeMenu:ClearAllPoints()
		placeMenu:SetPoint("BOTTOMLEFT", mapMore, "TOPLEFT", MENU_OFFSET_X, -MENU_OFFSET_Y)
	end
	SyncNav()
end

ClosePlaces = function()
	if not mapOpen then return end
	mapOpen = false
	UpdatePlaceMenu()
end

-- What the details show: the made item, the basic reagents with what the character holds, and every source (those with a place
-- first, the player's zone first among them).
local function DetailData(recipeInfo)
	local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeInfo.recipeID, false)
	local data = { schematic = schematic, reagents = {}, plain = {}, places = {}, sources = {} }
	local targets, rowOf = {}, {}
	for _, row in ipairs(ns.SourceRows(recipeInfo)) do
		if row.target then
			targets[#targets + 1] = row.target
			rowOf[row.target] = row
		else
			data.plain[#data.plain + 1] = row
		end
	end
	ns.SortTargets(targets) -- the player's zone first
	for _, target in ipairs(targets) do data.places[#data.places + 1] = rowOf[target] end
	for _, list in ipairs({ data.places, data.plain }) do
		for _, source in ipairs(list) do data.sources[#data.sources + 1] = source end
	end
	local parts = { recipeInfo.recipeID }
	for _, slot in ipairs(schematic and schematic.reagentSlotSchematics or {}) do
		local reagent = slot.reagentType == Enum.CraftingReagentType.Basic and slot.reagents[1]
		if reagent and reagent.itemID then
			local entry = { itemID = reagent.itemID, need = slot.quantityRequired, have = C_Item.GetItemCount(reagent.itemID, true) }
			entry.name = C_Item.GetItemNameByID(reagent.itemID)
			data.reagents[#data.reagents + 1] = entry
			parts[#parts + 1] = ("%d:%d:%d:%s"):format(entry.itemID, entry.have, entry.need, entry.name or "")
		end
	end
	for _, source in ipairs(data.plain) do parts[#parts + 1] = source.label .. "-" end
	for _, source in ipairs(data.places) do parts[#parts + 1] = source.label .. "+" end
	parts[#parts + 1] = ":" .. (professionInfo.skillLevel or 0)
	return data, table.concat(parts, ",")
end

local itemWatch -- item names arrive later; the details are drawn again when they do, and only while one is missing

local function HideDetail()
	detailSignature = nil
	detail:Hide()
	PlaceList()
	ClosePlaces()
	SyncNav()
end

-- Draws the selected recipe in the details. The height is exactly the content, so the list above takes the rest.
FillDetail = function()
	if not selected then
		if detail:IsShown() then HideDetail() end
		return
	end
	local data, signature = DetailData(selected)
	if signature == detailSignature then return end
	detailSignature = signature
	local schematic = data.schematic
	local itemID = schematic and schematic.outputItemID
	detail.itemID = itemID
	detail.recipeID = selected.recipeID
	Professions.SetupOutputIconCommon(detail.Output, schematic and schematic.quantityMin or 1, schematic and schematic.quantityMax or 1,
		selected.icon, itemID, itemID and C_Item.GetItemQualityByID(itemID) or 1)
	detail.Name:SetText(selected.name)
	local skill = selected.requiredSkill
	detail.Sub:SetShown(skill ~= nil)
	if skill then
		-- Colored as an item tooltip colors its requirement line: red while the skill is short (docs/client-notes.md, "Panel").
		local color = (professionInfo.skillLevel or 0) >= skill and HIGHLIGHT_FONT_COLOR or RED_FONT_COLOR
		detail.Sub:SetText(color:WrapTextInColorCode(ITEM_MIN_SKILL:format(professionInfo.professionName, skill)))
	end
	-- The window's schematic background for this profession (Blizzard_ProfessionsCrafting.lua:1032).
	detail.Background:SetAtlas(Professions.GetProfessionBackgroundAtlas(professionInfo) or "Professions-background-summarylist", TextureKitConstants.IgnoreAtlasSize)
	-- Top-down from whichever ends lower, the ring or the name block. The box is exactly this tall; Show Map is below it.
	local top = math.max(RING_SIZE - RING_RISE, NAME_TOP + detail.Name:GetStringHeight()
		+ (skill and OUTPUT_SUB_GAP + detail.Sub:GetStringHeight() or 0))
	local textBottom = NAME_TOP + detail.Name:GetStringHeight() + OUTPUT_SUB_GAP + detail.Sub:GetHeight()

	local missing = false
	detail.ReagentsLabel:SetShown(#data.reagents > 0)
	if #data.reagents > 0 then
		top = math.max(REAGENTS_TOP, textBottom + REAGENTS_BELOW_TEXT)
		detail.ReagentsLabel:SetPoint("TOPLEFT", detail, "TOPLEFT", REAGENTS_LEFT, -top)
		top = top + REAGENT_ICON_BELOW_LABEL
	end
	for index, entry in ipairs(data.reagents) do
		local button = Pooled(reagentRows, index, MakeReagentRow)
		button.itemID = entry.itemID
		button:SetPoint("TOPLEFT", detail, "TOPLEFT", REAGENT_LEFT, -top)
		button.Icon:SetTexture(C_Item.GetItemIconByID(entry.itemID))
		local quality = C_Item.GetItemQualityByID(entry.itemID)
		if quality then button:SetSlotQuality(quality) else button.IconBorder:Hide() end
		local color = entry.have >= entry.need and HIGHLIGHT_FONT_COLOR or RED_FONT_COLOR
		button.Text:SetText(color:WrapTextInColorCode(("%s %s"):format(TRADESKILL_REAGENT_COUNT:format(entry.have, entry.need), entry.name or "")))
		button:Show()
		button.Text:Show()
		missing = missing or not entry.name
		top = top + REAGENT_PITCH
	end
	for index = #data.reagents + 1, #reagentRows do
		reagentRows[index]:Hide()
		reagentRows[index].Text:Hide()
	end
	if #data.reagents > 0 then top = top - REAGENT_PITCH + REAGENT_SIZE end -- the last icon's bottom

	-- The sources are the button's tooltip, not lines in the box. With none to pin it stays, disabled, so the tooltip still tells them.
	mapButton = mapButton or MakeMapButton()
	mapMore = mapMore or MakeMapMore()
	local several = #data.places > 1
	mapButton:SetShown(#data.sources > 0 and not several)
	mapButton:SetEnabled(#data.places > 0)
	mapButton.sources = data.sources
	mapButton.single = #data.places == 1 and data.places[1] or nil
	mapMore:SetShown(several)
	mapMore.sources = data.sources
	mapMore.places = data.places
	stripShown = #data.sources > 0

	detail:SetHeight(top + DETAIL_BOTTOM)
	detail:Show()
	PlaceList()
	UpdatePlaceMenu() -- the list floats: it never takes height from the details
	--@debug@
	if ns.OnPanelDrawn then ns.OnPanelDrawn(professionInfo and professionInfo.professionID, selected.recipeID) end
	--@end-debug@
	if missing then
		itemWatch:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	else
		itemWatch:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
	end
end

-- The row stays in view when the list above shrinks to make room for the details.
local function KeepInView()
	local top
	for _, item in ipairs(items) do
		if item.recipe and item.recipe.recipeID == selected.recipeID then top = item.top end
	end
	if not top then return end
	local view, current = scroll:GetHeight(), scroll:GetVerticalScroll()
	if top < current then
		scroll:SetVerticalScroll(top)
	elseif top + ROW_HEIGHT > current + view then
		scroll:SetVerticalScroll(top + ROW_HEIGHT - view)
	end
end

SelectRecipe = function(recipeInfo)
	selected = recipeInfo
	ClosePlaces()
	ns.Trace("UI recipe selected: %d", recipeInfo.recipeID)
	for index = 1, math.min((nextItem or 1) - 1, #items) do
		if items[index].recipe then slots[index]:SetSelected(items[index].recipe.recipeID == recipeInfo.recipeID) end
	end
	FillDetail()
	SyncNav() -- the details may be unchanged while the row to go back to is not
	RunNextFrame(function() if selected then KeepInView() end end)
end

-- A selected recipe that left the list (a filter, a search) is cleared; one still there is the list's current copy of it.
local function ReconcileSelection(found)
	if not selected then return end
	local kept
	for _, recipeInfo in ipairs(found) do
		if recipeInfo.recipeID == selected.recipeID then kept = recipeInfo break end
	end
	selected = kept
end

local function Update()
	requested = false
	if not (panel and panel:IsShown() and professionInfo) then return end
	PlaceList()
	local list, complete, total = ns.GetListedRecipes(professionInfo)
	-- Not ready: the client's list update comes back through the events below.
	if not list then return end
	-- Names or factions still loading: hold the list back for up to WAIT_SECONDS, then show what there is. The
	-- client's own events end the wait early, so the list is drawn once rather than shown and redrawn.
	if not complete then
		waitUntil = waitUntil or (GetTime() + WAIT_SECONDS)
		local left = waitUntil - GetTime()
		if left > 0 then
			if builtProfession ~= professionInfo.professionID then scroll:SetAlpha(0) end
			if not waitQueued then
				waitQueued = true
				C_Timer.After(left, function() waitQueued = false; Request() end)
			end
			return
		end
	end
	UpdateDiscovery(#list, total)
	local found, search = CollectRecipes(list)
	ReconcileSelection(found)
	FillDetail()
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
	ClearNav() -- the rows are reused for other recipes; the build's end sets them again
	nextItem, buildMs, buildSteps = 1, 0, 0
	child:SetHeight(math.max(height, 1))
	empty:Hide()
	scroll:SetAlpha(0) -- shown by Finish, once every frame is placed
	if builtProfession ~= professionInfo.professionID then
		builtProfession = professionInfo.professionID
		scroll:SetVerticalScroll(0)
	end
	for index = rowCount + 1, #rows do rows[index]:Hide() end
	for index = headingCount + 1, #headings do headings[index]:Hide() end
	BuildStep(generation)
end

-- Frames ahead of need, a few a frame and never in combat, so a profession's first show only fills them.
local function Prewarm()
	if #rows >= POOL_ROWS and #headings >= POOL_HEADINGS then return end
	if InCombatLockdown() or nextItem and nextItem <= #items then
		C_Timer.After(WAIT_SECONDS, Prewarm) -- a build in progress makes frames itself
		return
	end
	local started = debugprofilestop()
	local made = 0
	while made < ROWS_PER_STEP and debugprofilestop() - started < BUILD_BUDGET_MS and (#rows < POOL_ROWS or #headings < POOL_HEADINGS) do
		if #headings < POOL_HEADINGS then CreateHeading() else CreateRow() end
		made = made + 1
	end
	RunNextFrame(Prewarm)
end

-- However many times the window rebuilds its page in a frame, the panel asks once, on the next.
Request = function()
	if requested then return end
	requested = true
	RunNextFrame(Update)
end

local function CreatePanel()
	local window = ProfessionsFrame
	-- Under the window, so it shows and hides with it and the Gamepad UI treats it as part of it. The window itself
	-- is a PortraitFrameTemplate (Blizzard_ProfessionsFrameBase.xml:5), so the panel has the same border and title strip.
	panel = CreateFrame("Frame", nil, window, "PortraitFrameTemplate")
	panel:SetWidth(PANEL_WIDTH)
	panel:SetPoint("TOPLEFT", window.ProfessionsOverviewTab, "TOPRIGHT", PANEL_GAP, TAB_TOP_OFFSET)
	panel:Hide()
	-- The panel follows the Professions window and never closes on its own.
	panel.CloseButton:Hide()
	panel:SetTitleOffsets(nil, -FRAME_INSET)
	-- The name and, dim like a model number, the version; a working build has no version to show. The template's
	-- title is one string, so the version is a color escape in it rather than a second font string.
	local version = C_AddOns.GetAddOnMetadata(addonName, "Version")
	version = version and not version:find("@", 1, true) and version or L["dev"]
	panel:SetTitle(ns.title .. " " .. DISABLED_FONT_COLOR:WrapTextInColorCode(version))
	-- One place for the icon: the TOC's IconTexture, which the addon list shows too.
	panel:SetPortraitToAsset(C_AddOns.GetAddOnMetadata(addonName, "IconTexture"))

	-- The window's own page art under everything: its background, no top streaks, and the left share of the page atlas that
	-- holds the title band and the list's dark ground (docs/client-notes.md, "Panel").
	if SetTextureWithAddressModeOptions then SetTextureWithAddressModeOptions(panel.Bg, WINDOW_BACKGROUND) end
	panel.TopTileStreaks:Hide()
	local page = panel:CreateTexture(nil, "BACKGROUND", nil, -3)
	local pageInfo = C_Texture.GetAtlasInfo(PAGE_ATLAS)
	if pageInfo then
		local share = (PANEL_WIDTH - PAGE_LEFT - PAGE_RIGHT_GAP) / PAGE_WIDTH
		page:SetTexture(pageInfo.file)
		page:SetTexCoord(pageInfo.leftTexCoord, pageInfo.leftTexCoord + (pageInfo.rightTexCoord - pageInfo.leftTexCoord) * share,
			pageInfo.topTexCoord, pageInfo.bottomTexCoord)
		page:SetPoint("TOPLEFT", panel, "TOPLEFT", PAGE_LEFT, -PAGE_TOP)
		page:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAGE_RIGHT_GAP, PAGE_BOTTOM_GAP)
	end

	-- The list area as the window's recipe list draws it under Camelot: the summary list atlas, no border (Blizzard_ProfessionsRecipeList.xml:10).
	listArea = CreateFrame("Frame", nil, panel)
	listArea.Clip = CreateFrame("Frame", nil, listArea)
	listArea.Clip:SetClipsChildren(true)
	listArea.Clip:SetFrameLevel(listArea:GetFrameLevel()) -- under the list's rows, which sit a level above
	listArea.BackgroundFrame = CreateFrame("Frame", nil, listArea.Clip)
	listArea.BackgroundFrame:SetPoint("TOPLEFT")
	listArea.BackgroundFrame:SetPoint("TOPRIGHT")
	listArea.BackgroundFrame:SetHeight(1)
	listArea.Background = listArea.BackgroundFrame:CreateTexture(nil, "BACKGROUND")
	listArea.Background:SetAtlas("Professions-background-summarylist")
	listArea.Background:SetAllPoints()
	listArea:SetPoint("TOPLEFT", panel, "TOPLEFT", FRAME_INSET, -LIST_TOP_DEFAULT)
	listArea:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -FRAME_INSET, FRAME_INSET)

	-- The window's skill bar art (Professions-skillbar-bg and -frame, placed as Blizzard_ProfessionsRankBar.xml does), sliced past its
	-- 3 px clipped corners (measured on the Deck) to keep its edges at our width; the fill is the Legacy challenge bar's still one,
	-- since the template's fills are each profession's own animated art and its code recolors them.
	rankBar = CreateFrame("Frame", nil, panel)
	rankBar:SetSize(BAR_WIDTH, RANK_BAR_HEIGHT)
	-- Each art is three pieces cut from its atlas by texture coordinates: both ends at their own size, the even middle stretched.
	-- The engine's slice margins clipped the ends here, so the cut is ours and in the atlas's own pixels.
	for key, atlas in pairs({ Background = "Professions-skillbar-bg", Border = "Professions-skillbar-frame" }) do
		local info = C_Texture.GetAtlasInfo(atlas)
		local holder = CreateFrame("Frame", nil, rankBar)
		holder:SetPoint("TOPLEFT")
		holder:SetSize(BAR_WIDTH, info and info.height or RANK_BAR_HEIGHT)
		holder:SetFrameLevel(rankBar:GetFrameLevel() + (key == "Background" and 0 or 2))
		if info then
			local layer = key == "Background" and "BACKGROUND" or "OVERLAY"
			local span = info.rightTexCoord - info.leftTexCoord
			local capShare = BAR_CAP / info.width
			local pieces = {
				{ "LEFT", info.leftTexCoord, info.leftTexCoord + span * capShare, BAR_CAP },
				{ "MIDDLE", info.leftTexCoord + span * capShare, info.rightTexCoord - span * capShare },
				{ "RIGHT", info.rightTexCoord - span * capShare, info.rightTexCoord, BAR_CAP },
			}
			local previous
			for _, piece in ipairs(pieces) do
				local texture = holder:CreateTexture(nil, layer)
				texture:SetTexture(info.file)
				texture:SetTexCoord(piece[2], piece[3], info.topTexCoord, info.bottomTexCoord)
				texture:SetPoint("TOP")
				texture:SetPoint("BOTTOM")
				if piece[1] == "LEFT" then
					texture:SetPoint("LEFT")
					texture:SetWidth(piece[4])
				elseif piece[1] == "RIGHT" then
					texture:SetPoint("RIGHT")
					texture:SetWidth(piece[4])
					previous:SetPoint("RIGHT", texture, "LEFT")
				else
					texture:SetPoint("LEFT", previous, "RIGHT")
				end
				previous = texture
			end
		end
		rankBar[key] = holder
	end
	-- The fill sits where the template's does: 5 in, 3 down, 12 narrower than the bar (Blizzard_ProfessionsRankBar.xml).
	-- Background under the fill, the frame over it and the text over all, by frame level, as the template's sublevels order them.
	local fillLayer = CreateFrame("Frame", nil, rankBar)
	fillLayer:SetAllPoints()
	fillLayer:SetFrameLevel(rankBar:GetFrameLevel() + 1)
	local textLayer = CreateFrame("Frame", nil, rankBar)
	textLayer:SetAllPoints()
	textLayer:SetFrameLevel(rankBar:GetFrameLevel() + 3)
	-- The fill spans the bar under the skill bar's own mask, set as the template sets it (Blizzard_ProfessionsRankBar.xml: Fill and
	-- Mask, at its atlas size, LEFT of the fill plus 1, clamped to black past its edges); the mask's width is the share shown.
	rankBar.Fill = fillLayer:CreateTexture(nil, "ARTWORK")
	rankBar.Fill:SetAtlas("Legacy-Progressbar-Fill")
	rankBar.Fill:SetPoint("TOPLEFT", BAR_FILL_LEFT, -BAR_FILL_TOP)
	rankBar.Fill:SetSize(BAR_WIDTH - BAR_FILL_INSET, RANK_BAR_HEIGHT)
	rankBar.Mask = fillLayer:CreateMaskTexture()
	local maskInfo = C_Texture.GetAtlasInfo("Professions-skillbar-mask")
	if maskInfo then
		rankBar.Mask:SetTexture(maskInfo.file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		rankBar.Mask:SetTexCoord(maskInfo.leftTexCoord, maskInfo.rightTexCoord, maskInfo.topTexCoord, maskInfo.bottomTexCoord)
		rankBar.Mask:SetHeight(maskInfo.height)
	end
	rankBar.Mask:SetPoint("LEFT", rankBar.Fill, "LEFT", 1, 0)
	rankBar.Fill:AddMaskTexture(rankBar.Mask)
	rankBar.text = textLayer:CreateFontString(nil, "OVERLAY", "Number12FontOutline") -- the skill bar's own font
	rankBar.text:SetPoint("CENTER", 0, -BAR_FILL_TOP)
	rankBar:SetPoint("CENTER", panel, "TOP", 0, -(CONTENT_TOP + RANK_BAR_HEIGHT / 2))
	rankBar:EnableMouse(true)
	rankBar:SetScript("OnEnter", function(self)
		ns.OwnTooltip(self)
		GameTooltip_AddNormalLine(GameTooltip, L["Recipes found out of all the ones you can still learn in this profession."])
		GameTooltip:Show()
	end)
	rankBar:SetScript("OnLeave", GameTooltip_Hide)

	-- The recipe's details, drawn as the window's recipe pane is, under the list and sized to their content (FillDetail).
	detail = CreateFrame("Frame", nil, panel)
	detail.Background = detail:CreateTexture(nil, "BACKGROUND")
	detail.Background:SetAllPoints()
	detail.Border = detail:CreateTexture(nil, "BORDER")
	detail.Border:SetAtlas(FORM_BORDER_ATLAS)
	detail.Border:SetAllPoints()
	detail.Border:SetTextureSliceMargins(FORM_SLICE, FORM_SLICE, FORM_SLICE, FORM_SLICE)
	detail.Border:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
	detail:Hide()
	-- The made item as the window's recipe pane shows it (its output icon and brown ring), placed where the portrait's ring would hang so
	-- it hangs off the pane's frame line. The ring is 68 px around the 47 px button and drawn about 58 across.
	detail.Output = CreateFrame("Button", nil, detail, "ProfessionsOutputButtonTemplate")
	detail.Output:SetPoint("TOPLEFT", detail, "TOPLEFT", OUTPUT_LEFT, RING_RISE - OUTPUT_RING_INSET)
	detail.Output:SetFrameLevel(ICON_LEVEL)
	detail.Output:SetScript("OnEnter", function(self)
		ns.OwnTooltip(self)
		if detail.itemID then GameTooltip:SetItemByID(detail.itemID) else GameTooltip:SetSpellByID(detail.recipeID) end
		GameTooltip:Show()
	end)
	detail.Output:SetScript("OnLeave", GameTooltip_Hide)
	local textWidth = PANEL_INNER_WIDTH - NAME_LEFT - FRAME_INSET
	detail.Name = detail:CreateFontString(nil, "ARTWORK", "GameFontHighlightMed2")
	detail.Name:SetPoint("TOPLEFT", detail, "TOPLEFT", NAME_LEFT, -NAME_TOP)
	detail.Name:SetWidth(textWidth)
	detail.Name:SetJustifyH("LEFT")
	detail.Name:SetJustifyV("TOP")
	detail.Sub = detail:CreateFontString(nil, "ARTWORK", "GameFontNormal") -- the pane's own requirement line font, measured
	detail.Sub:SetPoint("TOPLEFT", detail.Name, "BOTTOMLEFT", 0, -OUTPUT_SUB_GAP)
	detail.Sub:SetWidth(textWidth)
	detail.Sub:SetJustifyH("LEFT")
	detail.ReagentsLabel = detail:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	detail.ReagentsLabel:SetText(PROFESSIONS_REAGENT_CONTAINER_LABEL)
	detail.ReagentsLabel:SetHeight(REAGENTS_LABEL_HEIGHT)
	detail.ReagentsLabel:SetJustifyH("LEFT")
	itemWatch = CreateFrame("Frame")
	itemWatch:SetScript("OnEvent", function() detailSignature = nil; FillDetail() end)

	-- A plain scroll frame (a ScrollBox would hold our data in Blizzard's secure code) with Blizzard's minimal
	-- scroll bar, the one its recipe list uses: the thumb is sized to the share of the list in view.
	scroll = CreateFrame("ScrollFrame", nil, listArea, "ScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", listArea, "TOPLEFT", LIST_LEFT, 0)
	-- Placed as the recipe list places its bar, right of the list (Blizzard_ProfessionsRecipeList.xml), and hidden
	-- while the whole list fits.
	scroll.ScrollBar:ClearAllPoints()
	scroll.ScrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 0, 0)
	scroll.ScrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 0, 0)
	scroll.ScrollBar:SetHideIfUnscrollable(true)
	child = CreateFrame("Frame", nil, scroll)
	child:SetSize(LIST_WIDTH, 1)
	scroll:SetScrollChild(child)
	-- The scroll bar's column is only reserved while the bar shows; hidden, the rows use the full width. The bar sets
	-- its own shown state, so the frame follows it (rows are anchored to the child, which follows the frame).
	local function PlaceScroll()
		scroll:SetPoint("BOTTOMRIGHT", listArea, "BOTTOMRIGHT", scroll.ScrollBar:IsShown() and -SCROLLBAR_WIDTH or 0, LIST_BOTTOM_INSET)
	end
	scroll.ScrollBar:HookScript("OnShow", PlaceScroll)
	scroll.ScrollBar:HookScript("OnHide", PlaceScroll)
	scroll:HookScript("OnSizeChanged", function(_, width) child:SetWidth(width) end)
	PlaceScroll()

	empty = listArea:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	empty:SetPoint("TOP", scroll, "TOP", 0, -ROW_HEIGHT)
	empty:SetText(L["Nothing left to learn."])
	empty:Hide()

	panel:HookScript("OnHide", function()
		mapOpen = false
		ClearNav()
	end)
	panel:SetScript("OnShow", function(self)
		self:SetHeight(window:GetHeight())
		placedKey = nil -- the window may have changed size
		shownDiscovery = nil
		Request()
	end)
	return panel
end

-- The rank mark's parent (Ranks.lua), nil until the panel exists.
function ns.PanelRankParent()
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
	if not panel then
		panel = CreatePanel()
		Prewarm()
		ns.UpdateRankMark() -- Ranks.lua's own hook ran before the panel existed
	end
	if not (professionInfo and professionInfo.professionID == info.professionID) then
		waitUntil = nil
		selected = nil -- the details close with the profession
		FillDetail()
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
for _, event in ipairs({ "PLAYER_REGEN_ENABLED", "NEW_RECIPE_LEARNED", "SKILL_LINES_CHANGED", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED",
	"BAG_UPDATE_DELAYED" }) do -- bags change the counts; the same content refreshes rows in place
	eventFrame:RegisterEvent(event)
end
eventFrame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_ENABLED" then
		if navPending then SyncNav() end
	else
		Request()
	end
end)

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

--@debug@
-- The layout command measures our frames beside Blizzard's (Troubleshooting.lua, docs/development.md "Working build").
function ns.DevPanelParts()
	return { panel = panel, listArea = listArea, scroll = scroll, rankBar = rankBar, detail = detail, rows = rows, headings = headings,
		reagentRows = reagentRows, mapButton = mapButton, mapMore = mapMore }
end
--@end-debug@
