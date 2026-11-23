local _, ns = ...

-- Marks on the right of unlearned rows, where Blizzard puts its own status icons (the lock).
-- One icon per known source type, in ns.sourceOrder; Blizzard's search glass when no source
-- is known yet; its red X when the character can never learn the recipe. Blizzard's skill-up
-- arrow on the left is left alone.
local ICON_SIZE = 14
local ICON_GAP = 4
local MAX_ICONS = #ns.sourceOrder

-- Our per-row state, kept in a weak-keyed side table instead of on Blizzard's pooled rows.
local rowState = setmetatable({}, { __mode = "k" })

local function State(row)
	local state = rowState[row]
	if not state then
		state = {}
		rowState[row] = state
	end
	return state
end

local function IconOnEnter(icon)
	local row = icon:GetParent()
	row:OnEnter()
	GameTooltip:SetOwner(icon, "ANCHOR_RIGHT")
	ns.AddSourceLines(GameTooltip, State(row).recipe)
	GameTooltip:Show()
end

local function IconOnLeave(icon)
	icon:GetParent():OnLeave()
end

local function IconOnClick(icon, button, down)
	icon:GetParent():Click(button, down)
end

local function GetIcons(row)
	if not State(row).icons then
		State(row).icons = {}
		for index = 1, MAX_ICONS do
			local icon = CreateFrame("Button", nil, row)
			icon:SetSize(ICON_SIZE, ICON_SIZE)
			icon.Texture = icon:CreateTexture(nil, "OVERLAY")
			icon.Texture:SetAllPoints()
			icon:SetScript("OnEnter", IconOnEnter)
			icon:SetScript("OnLeave", IconOnLeave)
			icon:SetScript("OnClick", IconOnClick)
			State(row).icons[index] = icon
		end
	end
	return State(row).icons
end

local function HideIcons(row)
	for _, icon in ipairs(State(row).icons or {}) do
		icon:Hide()
	end
	if State(row).labelWidth then
		row.Label:SetWidth(State(row).labelWidth)
		State(row).labelWidth = nil
	end
end

local previewIndex = 0
local marks = {}

-- The marks a row shows, filled into the shared marks list; returns how many.
local function GetMarks(recipeInfo)
	wipe(marks)
	if recipeInfo.unobtainable then
		marks[1] = "unobtainable"
	elseif ns.preview then
		previewIndex = previewIndex % #ns.sourceOrder + 1
		marks[1] = ns.sourceOrder[previewIndex]
	elseif recipeInfo.sourceTypes then
		for _, sourceType in ipairs(ns.sourceOrder) do
			if recipeInfo.sourceTypes[sourceType] then
				marks[#marks + 1] = sourceType
			end
		end
	else
		marks[1] = "unknown"
	end
	return #marks
end

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

	local count = GetMarks(recipeInfo)
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
			icon:SetPoint("RIGHT", anchor, anchorPoint, index == 1 and -ICON_GAP or -1, 0)
			if icon.mark ~= mark then
				ns.SetSourceTexture(icon.Texture, mark)
				icon.mark = mark
			end
			icon:Show()
			anchor, anchorPoint = icon, "LEFT"
		else
			icon:Hide()
		end
	end

	-- Blizzard sizes the label around its own right-side icons on every Init; leave room for ours.
	State(row).labelWidth = State(row).labelWidth or row.Label:GetWidth()
	local countWidth = row.Count:IsShown() and row.Count:GetStringWidth() or 0
	local lockWidth = locked and row.LockedIcon:GetWidth() or 0
	local iconsWidth = count * (ICON_SIZE + 1) + ICON_GAP
	local maxWidth = row:GetWidth() - row.SkillUps:GetWidth() - lockWidth - countWidth - iconsWidth - 2 * ICON_GAP
	row.Label:SetWidth(math.max(1, math.min(State(row).labelWidth, maxWidth)))
end

local function GetScrollBox()
	local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
	return page and page.RecipeList and page.RecipeList.ScrollBox
end

function ns.RefreshRows()
	local scrollBox = GetScrollBox()
	if scrollBox then
		previewIndex = 0
		scrollBox:ForEachFrame(UpdateRow)
	end
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_Professions", function()
	local scrollBox = GetScrollBox()
	if not scrollBox then
		return
	end
	ScrollUtil.AddInitializedFrameCallback(scrollBox, function(_, row, node)
		State(row).labelWidth = nil -- Init just restored Blizzard's width on this pooled row.
		UpdateRow(row, node) -- the callback's first argument is the owner
	end, ns)
	ns.RefreshRows()
end)
