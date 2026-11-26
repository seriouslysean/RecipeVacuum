local _, ns = ...

-- Source marks on the right of unlearned rows, where Blizzard puts its status icons, with Blizzard's lock to their left.
local ICON_GAP = 4
local LABEL_PADDING = 2 * ICON_GAP
-- Marks sit in equal-width slots so they line up down the list.
local SLOT_SIZE = ns.MARK_SLOT_SIZE

local MAX_ICONS = #ns.sourceOrder + 1 -- every source type plus the lock

-- Row state is kept in a weak-keyed table, not on Blizzard's pooled rows.
local rowState = setmetatable({}, { __mode = "k" })

local function State(row)
	local state = rowState[row]
	if not state then
		state = {}
		rowState[row] = state
	end
	return state
end

-- One hover for the whole row: marks go to full strength and one tooltip lists every source. The marks take no mouse input.
local function SetRowStrength(row, full)
	for _, icon in ipairs(State(row).icons) do
		ns.SetMarkStrength(icon, full)
	end
end

-- Runs inside Blizzard's OnEnter and replaces its tooltip; other recipe lists send the same event, and their rows have no state here.
local function RowOnEnter(row)
	local recipeInfo = rowState[row] and rowState[row].recipe
	if recipeInfo then
		SetRowStrength(row, true)
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		ns.AddSourceLines(GameTooltip, recipeInfo)
		GameTooltip:Show()
	end
end

-- Blizzard's OnLeave has already hidden the tooltip.
local function RowOnLeave(row)
	if State(row).recipe then
		SetRowStrength(row, false)
	end
end

local function GetIcons(row)
	if not State(row).icons then
		State(row).icons = {}
		for index = 1, MAX_ICONS do
			local icon = CreateFrame("Frame", nil, row)
			icon:SetSize(SLOT_SIZE, SLOT_SIZE)
			icon.Texture = icon:CreateTexture(nil, "OVERLAY")
			icon.Texture:SetPoint("CENTER")
			State(row).icons[index] = icon
		end
		-- OnLeave only: the list sets each row's OnEnter again on every Init, dropping a hook (docs/client-notes.md, "Recipe list rows").
		row:HookScript("OnLeave", RowOnLeave)
		-- The lock and skill-up buttons leave through the row's OnLeave method (ProfessionsRecipeListRecipeMixin:OnLoad), so hook it too.
		hooksecurefunc(row, "OnLeave", RowOnLeave)
	end
	return State(row).icons
end

local function HideIcons(row)
	State(row).recipe = nil -- a pooled row showing a learned recipe
	for _, icon in ipairs(State(row).icons or {}) do
		icon:Hide()
	end
	if State(row).labelWidth then
		row.Label:SetWidth(State(row).labelWidth)
		State(row).labelWidth = nil
	end
end

local marks = {}

local function UpdateRow(row, node)
	local data = node and node.GetData and node:GetData()
	local recipeInfo = data and data.recipeInfo
	if not (recipeInfo and row.Label) then
		return
	end
	if recipeInfo.learned then
		HideIcons(row)
		return
	end

	-- Asked as the row is drawn, so only recipes in view have their made item looked up.
	recipeInfo.lockReason = ns.GetRecipeLock(recipeInfo.recipeID) or nil
	local count = ns.GetMarks(recipeInfo, marks)
	local icons = GetIcons(row)
	local locked = row.LockedIcon:IsShown()
	State(row).recipe = recipeInfo
	local anchor, anchorPoint = locked and row.LockedIcon or row, locked and "LEFT" or "RIGHT"
	-- Right to left, so the order reads left to right as in ns.sourceOrder.
	for index = 1, MAX_ICONS do
		local icon = icons[index]
		local mark = marks[count - index + 1]
		if mark then
			icon:ClearAllPoints()
			icon:SetPoint("RIGHT", anchor, anchorPoint, index == 1 and -ICON_GAP or -ns.MARK_SPACING, 0)
			ns.ApplyMark(icon, mark)
			ns.SetMarkStrength(icon, false)
			icon:Show()
			anchor, anchorPoint = icon, "LEFT"
		else
			icon:Hide()
		end
	end

	-- Blizzard sizes the label around its own icons on every Init; leave room for ours.
	State(row).labelWidth = State(row).labelWidth or row.Label:GetWidth()
	local countWidth = row.Count:IsShown() and row.Count:GetStringWidth() or 0
	local lockWidth = locked and row.LockedIcon:GetWidth() or 0
	local iconsWidth = count * (SLOT_SIZE + ns.MARK_SPACING) + ICON_GAP
	local maxWidth = row:GetWidth() - row.SkillUps:GetWidth() - lockWidth - countWidth - iconsWidth - LABEL_PADDING
	row.Label:SetWidth(math.max(1, math.min(State(row).labelWidth, maxWidth)))

	-- A redraw under a still pointer sends no new OnEnter, so the hovered row gets its hover back here.
	if row:IsMouseMotionFocus() then
		RowOnEnter(row)
	end
end

--@debug@
-- Timed in a checkout build; released builds call UpdateRow directly.
do
	local inner = UpdateRow
	UpdateRow = function(row, node)
		local started = debugprofilestop()
		inner(row, node)
		ns.Perf("row marks", started)
	end
end
--@end-debug@

local function GetScrollBox()
	local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
	return page and page.RecipeList and page.RecipeList.ScrollBox
end

function ns.RefreshRows()
	local scrollBox = GetScrollBox()
	if scrollBox then
		scrollBox:ForEachFrame(UpdateRow)
	end
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_Professions", function()
	local scrollBox = GetScrollBox()
	if not scrollBox then
		return
	end
	EventRegistry:RegisterCallback("Professions.RecipeListOnEnter", function(_, row)
		RowOnEnter(row)
	end, rowState)
	ScrollUtil.AddInitializedFrameCallback(scrollBox, function(_, row, node)
		State(row).labelWidth = nil -- Init restored Blizzard's width
		UpdateRow(row, node) -- the first callback argument is the object registered above
	end, ns)
	ns.RefreshRows()
end)
