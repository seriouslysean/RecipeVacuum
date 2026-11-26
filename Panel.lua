local _, ns = ...
local L = ns.L

-- The player-facing list of unlearned recipes: a panel of our own beside the Professions window, never a write into Blizzard's list (docs/client-notes.md, "Gamepad").
-- Built as Field Guide Forever's list is (UI/List.lua): a Blizzard scroll frame and a fixed pool of our own Buttons, so the Gamepad UI can focus rows and scroll them.

local PANEL_WIDTH = 220 -- about 230 px are free beside the tab column at 1280x800 (docs/client-notes.md, "Panel")
local PANEL_GAP = 2 -- space between the tab column and the panel
-- The overview tab sits this far below the window's top (Blizzard_ProfessionsFrame.xml), so the panel lifts by the same.
local TAB_TOP_OFFSET = 60
local TITLE_HEIGHT = 28
local LIST_INSET_X, LIST_INSET_TOP, LIST_INSET_BOTTOM = 4, 6, 6
local SCROLLBAR_WIDTH = 22 -- room for UIPanelScrollFrameTemplate's bar to the right of the list
local ROW_HEIGHT = 20
local ROW_PAD = 4
local HEADER_COLOR = NORMAL_FONT_COLOR
local RETRY_SECONDS = 1 -- the recipe index loads after the window opens
local MAX_RETRIES = 10
local MAX_MARKS = 1 + #ns.sourceOrder + 1 -- a lock, every source type, or the unknown mark

local panel, scroll, child, empty
local rows = {}
local entries = {} -- flat list: { header = name } or { recipe = recipeInfo }
local professionInfo
local retries = 0

local function CreateRow(index)
	local row = CreateFrame("Button", nil, child)
	row:SetHeight(ROW_HEIGHT)
	row:SetHighlightAtlas("Options_List_Hover", "ADD") -- the highlight Blizzard's settings lists use

	row.Name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.Name:SetPoint("LEFT", ROW_PAD, 0)
	row.Name:SetJustifyH("LEFT")
	row.Name:SetWordWrap(false)

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
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		ns.AddSourceLines(GameTooltip, self.recipe, true)
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

local function ShowRow(row, entry)
	row.recipe = entry.recipe
	row:SetEnabled(entry.recipe ~= nil)
	if entry.header then
		row.Name:SetFontObject("GameFontNormal")
		row.Name:SetTextColor(HEADER_COLOR:GetRGB())
		row.Name:SetText(entry.header)
		row.Name:SetPoint("RIGHT", row, "RIGHT", -ROW_PAD, 0)
		row.markCount = 0
		for _, mark in ipairs(row.marks) do
			mark.Texture:Hide()
		end
		return
	end
	row.Name:SetFontObject("GameFontHighlightSmall")
	row.Name:SetTextColor(1, 1, 1)
	row.Name:SetText(entry.recipe.name)
	row.markCount = ns.GetMarks(entry.recipe, row.markNames)
	for slot, mark in ipairs(row.marks) do
		local name = row.markNames[slot]
		mark.Texture:SetShown(name ~= nil)
		if name then
			ns.ApplyMark(mark, name)
			ns.SetMarkStrength(mark, false)
		end
	end
	-- The name stops where the leftmost mark begins.
	row.Name:SetPoint("RIGHT", row.marks[math.max(row.markCount, 1)].Texture, "LEFT", -ROW_PAD, 0)
end

-- Only the rows in view are drawn, so a long list costs a screenful.
local function Redraw()
	local viewHeight = scroll:GetHeight()
	local first = math.floor(scroll:GetVerticalScroll() / ROW_HEIGHT) + 1
	local visible = math.ceil(viewHeight / ROW_HEIGHT) + 1
	for slot = 1, visible do
		local entry = entries[first + slot - 1]
		local row = rows[slot] or (entry and CreateRow(slot))
		if row then
			if entry then
				local top = -(first + slot - 2) * ROW_HEIGHT
				row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, top)
				row:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, top)
				ShowRow(row, entry)
			end
			row:SetShown(entry ~= nil)
		end
	end
	for slot = visible + 1, #rows do
		rows[slot]:Hide()
	end
end

local function Rebuild(categories)
	wipe(entries)
	for _, category in ipairs(categories) do
		entries[#entries + 1] = { header = category.info.name }
		for _, recipeInfo in ipairs(category.recipes) do
			entries[#entries + 1] = { recipe = recipeInfo }
		end
	end
	child:SetHeight(math.max(#entries * ROW_HEIGHT, 1))
	empty:SetShown(#entries == 0)
	scroll:SetVerticalScroll(0)
	Redraw()
	ns.Trace("UI panel shown with %d rows", #entries)
end

local function Refresh()
	if not (panel and panel:IsShown() and professionInfo) then return end
	local categories = ns.GetUnlearnedRecipes(professionInfo)
	if categories then
		retries = 0
		Rebuild(categories)
	elseif retries < MAX_RETRIES then
		retries = retries + 1
		C_Timer.After(RETRY_SECONDS, Refresh)
	end
end

local function CreatePanel()
	local window = ProfessionsFrame
	-- Under the window, so it shows and hides with it and the Gamepad UI treats it as part of it.
	panel = CreateFrame("Frame", nil, window, "InsetFrameTemplate")
	panel:SetWidth(PANEL_WIDTH)
	panel:SetPoint("TOPLEFT", window.ProfessionsOverviewTab, "TOPRIGHT", PANEL_GAP, TAB_TOP_OFFSET)
	panel:Hide()

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	title:SetPoint("TOP", 0, -ROW_PAD * 2)
	title:SetText(L["Unlearned Recipes"])

	-- UIPanelScrollFrameTemplate, as Field Guide Forever's list; a ScrollBox would hold our data in Blizzard's secure code.
	scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", LIST_INSET_X, -(TITLE_HEIGHT + LIST_INSET_TOP))
	scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR_WIDTH, LIST_INSET_BOTTOM)
	scroll:SetScript("OnVerticalScroll", Redraw)
	child = CreateFrame("Frame", nil, scroll)
	child:SetSize(PANEL_WIDTH - LIST_INSET_X - SCROLLBAR_WIDTH, 1)
	scroll:SetScrollChild(child)

	empty = panel:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	empty:SetPoint("TOP", scroll, "TOP", 0, -ROW_HEIGHT)
	empty:SetText(L["Nothing left to learn."])
	empty:Hide()

	panel:SetScript("OnShow", function(self)
		self:SetHeight(window:GetHeight())
		Refresh()
	end)
	return panel
end

-- Read-only post-hook: the window's own crafting page tells which profession is open.
local function OnInit(_, info)
	panel = panel or CreatePanel()
	professionInfo = info
	-- Only this character's own professions have recipes to learn.
	panel:SetShown(Professions.InLocalCraftingMode())
	retries = 0
	Refresh()
end

local learnedFrame = CreateFrame("Frame")
learnedFrame:RegisterEvent("NEW_RECIPE_LEARNED")
learnedFrame:SetScript("OnEvent", function()
	retries = 0
	Refresh()
end)

EventUtil.ContinueOnAddOnLoaded("Blizzard_Professions", function()
	local page = ProfessionsFrame.CraftingPage
	hooksecurefunc(page, "Init", OnInit)
	-- The overview page has no profession to list.
	page:HookScript("OnHide", function()
		if panel then panel:Hide() end
	end)
end)
