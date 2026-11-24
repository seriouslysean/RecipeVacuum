local _, ns = ...

-- Marks on the right of unlearned rows, where Blizzard puts its status icons. One icon per source type
-- in ns.sourceOrder, or the search glass when none is known, with Blizzard's lock to their left when
-- the recipe needs a specialization the character lacks.
local ICON_GAP = 4
-- Marks are centered in equal-width slots so they line up down the list.
local SLOT_SIZE = ns.MARK_SLOT_SIZE

local MAX_ICONS = #ns.sourceOrder + 1 -- every source type, plus the lock
--@debug@
MAX_ICONS = MAX_ICONS + 1 -- /recipevacuum marks shows every mark at once
--@end-debug@

-- Per-row state in a weak-keyed table, not on Blizzard's pooled rows.
local rowState = setmetatable({}, { __mode = "k" })

local function State(row)
	local state = rowState[row]
	if not state then
		state = {}
		rowState[row] = state
	end
	return state
end

-- One hover for the whole row: its marks go to full strength and one tooltip lists every source.
-- The marks take no mouse input, so the pointer and clicks reach Blizzard's row as usual.
local function SetRowStrength(row, full)
	for _, icon in ipairs(State(row).icons) do
		ns.SetMarkStrength(icon, full)
	end
end

-- After Blizzard's own OnEnter, whose tooltip (the full name of a shortened label) ours replaces: the
-- recipe's name is our title.
local function RowOnEnter(row)
	local recipeInfo = State(row).recipe
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
		row:HookScript("OnEnter", RowOnEnter)
		row:HookScript("OnLeave", RowOnLeave)
	end
	return State(row).icons
end

local function HideIcons(row)
	State(row).recipe = nil -- a pooled row now showing a learned recipe: our hover does nothing
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

	-- Asked as the row is drawn, so only recipes scrolled into view have their made item looked up.
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
			ns.SetMarkStrength(icon, row:IsMouseOver())
			--@debug@
			if ns.PreviewLook then
				ns.PreviewLook(icon.Texture, data, mark)
			end
			--@end-debug@
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
	local maxWidth = row:GetWidth() - row.SkillUps:GetWidth() - lockWidth - countWidth - iconsWidth - 2 * ICON_GAP
	row.Label:SetWidth(math.max(1, math.min(State(row).labelWidth, maxWidth)))
end

--@debug@
-- Timed in a checkout build (ns.Perf, Troubleshooting.lua); released builds call UpdateRow directly.
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
	ScrollUtil.AddInitializedFrameCallback(scrollBox, function(_, row, node)
		State(row).labelWidth = nil -- Init restored Blizzard's width on this pooled row
		UpdateRow(row, node) -- first callback argument is the owner
	end, ns)
	ns.RefreshRows()
end)
