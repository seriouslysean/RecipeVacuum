local addonName, ns = ...
local L = ns.L

-- The player-facing list of unlearned recipes: a panel of our own beside the Professions window, never a write into Blizzard's list (docs/client-notes.md, "Gamepad").
-- Built as Field Guide Forever's list is (UI/List.lua): a Blizzard scroll frame and one real Button per row, so the Gamepad UI can focus rows and scroll them.
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
local RANK_BAR_FILL_INSET = 12
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
-- The details below the list, built as Blizzard_ProfessionsRecipeSchematicForm.xml lays its recipe out (docs/client-notes.md, "Panel").
local DETAIL_PAD = 8
local DETAIL_GAP = 2 -- between the list and the details, as the window's list and recipe pane (Blizzard_ProfessionsCrafting.xml:164)
local OUTPUT_SIZE = 47 -- ProfessionsOutputButtonTemplate (Blizzard_ProfessionsTemplates.xml:282)
local OUTPUT_TEXT_GAP = 14 -- the name's gap right of the output icon (Blizzard_ProfessionsRecipeSchematicForm.xml:193)
local OUTPUT_SUB_GAP = 5 -- the required skill under the name (:214)
local REAGENT_SIZE = 39 -- ProfessionsButtonTemplate (Blizzard_ProfessionsTemplates.xml:42)
local REAGENT_ROW = 43
local REAGENT_TEXT_GAP = 7
local SECTION_GAP = 8
local LABEL_HEIGHT = 16
local SOURCE_HEIGHT = 22
local PLACE_INDENT = 10 -- the opened places sit this far in under Show Map
local SOURCE_GAP = 2
local PLAIN_HEIGHT = 16
local PANEL_INNER_WIDTH = PANEL_WIDTH - 2 * FRAME_INSET

local panel, listArea, scroll, child, empty, rankBar, detail
local placedKey
local SelectRecipe -- defined with the details; a row tap selects through it
local selected -- the recipe whose details show: set by a tap, kept until another is tapped, the profession changes or it leaves the list
local detailSignature
local reagentRows, sourceButtons, plainTexts = {}, {}, {}
local mapButton -- one Show Map button for every source with a place
local mapOpen -- the list of places under it is open; a press toggles it, focus never does
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

local function CreateRow()
	local row = CreateFrame("Button", nil, child, ROW_TEMPLATE)
	row.Count:Hide()
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

-- Everything a row shows that does not move it, so a skill rise or new source updates a row without a rebuild.
local function ShowRow(row, recipeInfo)
	row.recipe = recipeInfo
	row:SetSelected(selected ~= nil and selected.recipeID == recipeInfo.recipeID) -- the template's own selected look
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
	heading:SetHeaderText(ns.BandTitle(professionInfo.professionID, item.band))
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
	ns.Trace("UI panel shown with %d rows under %d bands, built in %.1f ms over %d frames", recipeCount, bandCount, buildMs, buildSteps)
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
	local key = ("%s:%s:%s"):format(top, bottom, detailHeight)
	if key == placedKey then return end
	placedKey = key
	listArea:SetPoint("TOPLEFT", panel, "TOPLEFT", FRAME_INSET, -top)
	detail:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", FRAME_INSET, bottom)
	detail:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -FRAME_INSET, bottom)
	if detailHeight > 0 then
		listArea:SetPoint("BOTTOMRIGHT", detail, "TOPRIGHT", 0, DETAIL_GAP)
	else
		listArea:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -FRAME_INSET, bottom)
	end
end

-- Discovery as the window's own skill bar shows a skill: found of every recipe the character could still learn here.
local function UpdateDiscovery(found, total)
	local key = ("%s:%d:%d"):format(professionInfo.professionID, found, total)
	if key == shownDiscovery then return end
	shownDiscovery = key
	rankBar:Update({ profession = professionInfo.profession, professionName = professionInfo.professionName,
		skillLevel = found, maxSkillLevel = total, skillModifier = 0 })
	rankBar.Rank.Text:SetText(L["%d / %d discovered"]:format(found, total))
end

-- The first frame of a pool of one kind, made when needed; later ones are reused for another recipe.
local function Pooled(pool, index, make)
	pool[index] = pool[index] or make()
	return pool[index]
end

local function MakeReagentRow()
	local button = CreateFrame("ItemButton", nil, detail, "ProfessionsButtonTemplate")
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetItemByID(self.itemID)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button.Text = detail:CreateFontString(nil, "ARTWORK", "GameFontHighlight_NoShadow")
	button.Text:SetPoint("LEFT", button, "RIGHT", REAGENT_TEXT_GAP, 0)
	button.Text:SetWidth(PANEL_INNER_WIDTH - 2 * DETAIL_PAD - REAGENT_SIZE - REAGENT_TEXT_GAP)
	button.Text:SetJustifyH("LEFT")
	return button
end

local FillDetail -- defined below; a press on a place redraws the details

local function MakeSourceButton()
	local button = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
	button:SetSize(PANEL_INNER_WIDTH - 2 * DETAIL_PAD - PLACE_INDENT, SOURCE_HEIGHT)
	-- One source's pin, exactly: a button pins what it names, then the list closes (docs/client-notes.md, "Panel").
	button:SetScript("OnClick", function(self)
		ns.Trace("UI source pressed: %s", self.source.label)
		ns.ShowOnMap(self.source.target)
		mapOpen = false
		FillDetail()
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, self.source.place)
		GameTooltip_AddNormalLine(GameTooltip, L["Press to mark this place on your map."])
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	return button
end

-- The game's own Show Map label (SHOW_MAP, QuestMapFrame.xml). One place pins it; several open the list of places under the
-- button. Our own Buttons throughout: a Blizzard menu would taint the Gamepad UI (docs/client-notes.md, "Gamepad").
local function MakeMapButton()
	local button = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
	button:SetSize(PANEL_INNER_WIDTH - 2 * DETAIL_PAD, SOURCE_HEIGHT)
	button:SetText(SHOW_MAP)
	button:SetScript("OnClick", function(self)
		if self.single then
			ns.Trace("UI source pressed: %s", self.single.label)
			ns.ShowOnMap(self.single.target)
		else
			mapOpen = not mapOpen
			FillDetail()
		end
	end)
	button:SetScript("OnEnter", function(self)
		if not self.single then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, self.single.place)
		GameTooltip_AddNormalLine(GameTooltip, L["Press to mark this place on your map."])
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	return button
end

local function MakePlainText()
	local text = detail:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	text:SetWidth(PANEL_INNER_WIDTH - 2 * DETAIL_PAD)
	text:SetJustifyH("LEFT")
	text:SetHeight(PLAIN_HEIGHT)
	return text
end

-- What the details show: the made item, the basic reagents with what the character holds, and every source.
local function DetailData(recipeInfo)
	local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeInfo.recipeID, false)
	local data = { schematic = schematic, reagents = {}, plain = {}, places = {} }
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
	parts[#parts + 1] = (mapOpen and "open" or "shut") .. ":" .. (professionInfo.skillLevel or 0)
	return data, table.concat(parts, ",")
end

local itemWatch -- item names arrive later; the details are drawn again when they do, and only while one is missing

local function HideDetail()
	detailSignature = nil
	detail:Hide()
	PlaceList()
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
	local top = DETAIL_PAD
	local header = math.max(OUTPUT_SIZE, detail.Name:GetStringHeight() + (skill and OUTPUT_SUB_GAP + detail.Sub:GetStringHeight() or 0))
	top = top + header

	local missing = false
	detail.ReagentsLabel:SetShown(#data.reagents > 0)
	if #data.reagents > 0 then
		top = top + SECTION_GAP
		detail.ReagentsLabel:SetPoint("TOPLEFT", detail, "TOPLEFT", DETAIL_PAD, -top)
		top = top + LABEL_HEIGHT
	end
	for index, entry in ipairs(data.reagents) do
		local button = Pooled(reagentRows, index, MakeReagentRow)
		button.itemID = entry.itemID
		button:SetPoint("TOPLEFT", detail, "TOPLEFT", DETAIL_PAD, -top)
		button.Icon:SetTexture(C_Item.GetItemIconByID(entry.itemID))
		local quality = C_Item.GetItemQualityByID(entry.itemID)
		if quality then button:SetSlotQuality(quality) else button.IconBorder:Hide() end
		local color = entry.have >= entry.need and HIGHLIGHT_FONT_COLOR or RED_FONT_COLOR
		button.Text:SetText(color:WrapTextInColorCode(("%s %s"):format(TRADESKILL_REAGENT_COUNT:format(entry.have, entry.need), entry.name or "")))
		button:Show()
		button.Text:Show()
		missing = missing or not entry.name
		top = top + REAGENT_ROW
	end
	for index = #data.reagents + 1, #reagentRows do
		reagentRows[index]:Hide()
		reagentRows[index].Text:Hide()
	end

	if #data.plain + #data.places > 0 then top = top + SECTION_GAP end
	for index, source in ipairs(data.plain) do
		local text = Pooled(plainTexts, index, MakePlainText)
		text:SetPoint("TOPLEFT", detail, "TOPLEFT", DETAIL_PAD, -top)
		text:SetText(source.label)
		text:Show()
		top = top + PLAIN_HEIGHT + SOURCE_GAP
	end
	for index = #data.plain + 1, #plainTexts do plainTexts[index]:Hide() end

	mapButton = mapButton or MakeMapButton()
	local several = #data.places > 1
	mapButton:SetShown(#data.places > 0)
	if #data.places > 0 then
		mapButton.single = not several and data.places[1] or nil
		mapButton:SetPoint("TOPLEFT", detail, "TOPLEFT", DETAIL_PAD, -top)
		top = top + SOURCE_HEIGHT + SOURCE_GAP
	end
	local shown = several and mapOpen and #data.places or 0
	for index = 1, shown do
		local button = Pooled(sourceButtons, index, MakeSourceButton)
		button.source = data.places[index]
		button:SetPoint("TOPLEFT", detail, "TOPLEFT", DETAIL_PAD + PLACE_INDENT, -top)
		button:SetText(button.source.label)
		button:Show()
		top = top + SOURCE_HEIGHT + SOURCE_GAP
	end
	for index = shown + 1, #sourceButtons do sourceButtons[index]:Hide() end

	detail:SetHeight(top + DETAIL_PAD)
	detail:Show()
	PlaceList()
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
	mapOpen = false
	ns.Trace("UI recipe selected: %d", recipeInfo.recipeID)
	for index = 1, math.min((nextItem or 1) - 1, #items) do
		if items[index].recipe then slots[index]:SetSelected(items[index].recipe.recipeID == recipeInfo.recipeID) end
	end
	FillDetail()
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

	-- The list area as Blizzard's recipe list draws it: the summary list atlas behind, the inset border around
	-- (Blizzard_ProfessionsRecipeList.xml:10, :23-30). The inset template's own marble is hidden under the atlas.
	listArea = CreateFrame("Frame", nil, panel, "InsetFrameTemplate")
	listArea.Bg:Hide()
	listArea.Background = listArea:CreateTexture(nil, "BACKGROUND")
	listArea.Background:SetAtlas("Professions-background-summarylist")
	listArea.Background:SetAllPoints()
	listArea:SetPoint("TOPLEFT", panel, "TOPLEFT", FRAME_INSET, -LIST_TOP_DEFAULT)
	listArea:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -FRAME_INSET, FRAME_INSET)

	-- The window's own skill bar template (Blizzard_ProfessionsCrafting.xml:197), at its height and strata and in the band above
	-- the list. The template's width is its art's, so its parts are widened as its overrideWidth path does (Blizzard_ProfessionsRankBar.lua:105-112).
	rankBar = CreateFrame("Frame", nil, panel, "ProfessionsRankBarTemplate")
	rankBar.ownerManagesEvents = true -- it shows discovery here, not the window's skill, so the skill events do not drive it
	rankBar:SetFrameStrata("HIGH")
	rankBar.ExpansionDropdownButton:Hide() -- its menu picks the window's expansion
	rankBar:SetPoint("TOPLEFT", panel, "TOPLEFT", FRAME_INSET, -CONTENT_TOP)
	rankBar:SetWidth(PANEL_INNER_WIDTH)
	rankBar.Background:SetWidth(PANEL_INNER_WIDTH)
	rankBar.Border:SetWidth(PANEL_INNER_WIDTH)
	rankBar.Fill:SetWidth(PANEL_INNER_WIDTH - RANK_BAR_FILL_INSET)
	rankBar:EnableMouse(true)
	rankBar:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_AddNormalLine(GameTooltip, L["Recipes found out of all the ones you can still learn in this profession."])
		GameTooltip:Show()
	end)
	rankBar:SetScript("OnLeave", GameTooltip_Hide)

	-- The recipe's details, drawn as the list area is, under the list and sized to their content (FillDetail).
	detail = CreateFrame("Frame", nil, panel, "InsetFrameTemplate")
	detail.Bg:Hide()
	detail.Background = detail:CreateTexture(nil, "BACKGROUND")
	detail.Background:SetAtlas("Professions-background-summarylist")
	detail.Background:SetAllPoints()
	detail:Hide()
	detail.Output = CreateFrame("Button", nil, detail, "ProfessionsOutputButtonTemplate")
	detail.Output:SetPoint("TOPLEFT", detail, "TOPLEFT", DETAIL_PAD, -DETAIL_PAD)
	detail.Output:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if detail.itemID then GameTooltip:SetItemByID(detail.itemID) else GameTooltip:SetSpellByID(detail.recipeID) end
		GameTooltip:Show()
	end)
	detail.Output:SetScript("OnLeave", GameTooltip_Hide)
	local textWidth = PANEL_INNER_WIDTH - 2 * DETAIL_PAD - OUTPUT_SIZE - OUTPUT_TEXT_GAP
	detail.Name = detail:CreateFontString(nil, "ARTWORK", "GameFontHighlightMed2")
	detail.Name:SetPoint("TOPLEFT", detail.Output, "TOPRIGHT", OUTPUT_TEXT_GAP, 0)
	detail.Name:SetSize(textWidth, 0)
	detail.Name:SetJustifyH("LEFT")
	detail.Name:SetJustifyV("TOP")
	detail.Sub = detail:CreateFontString(nil, "ARTWORK", "GameTooltipText")
	detail.Sub:SetPoint("TOPLEFT", detail.Name, "BOTTOMLEFT", 0, -OUTPUT_SUB_GAP)
	detail.Sub:SetWidth(textWidth)
	detail.Sub:SetJustifyH("LEFT")
	detail.ReagentsLabel = detail:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	detail.ReagentsLabel:SetText(PROFESSIONS_REAGENT_CONTAINER_LABEL)
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

	panel:SetScript("OnShow", function(self)
		self:SetHeight(window:GetHeight())
		placedKey = nil -- the window may have changed size
		shownDiscovery = nil
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
	if not panel then
		panel = CreatePanel()
		Prewarm()
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
