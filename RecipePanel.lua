local _, ns = ...

-- The recipe panel for an unlearned recipe: Blizzard's own source line under the description
-- (RecipeSourceButton, which Forever never fills because GetRecipeSourceText is empty), and Show on
-- Map where Create sits (Create is hidden for unlearned recipes by ValidateControls).

-- Copied from ProfessionsRecipeSchematicFormMixin:Init: the source line sits 10 below the
-- description, and reagents move to 50 below it while the line shows (20 without).
local SOURCE_LINE_GAP = -10
local REAGENTS_GAP_WITH_SOURCE = -50

local function SelectedRecipe(page)
	local recipeInfo = page.SchematicForm:GetRecipeInfo()
	if recipeInfo and not recipeInfo.learned then
		ns.SummarizeSources(recipeInfo)
		return recipeInfo
	end
end

-- Same tooltip as Blizzard's source line: the source text as highlight lines, wrapped at 350.
local SOURCE_TOOLTIP_WIDTH = 350 -- copied from the same Init
local function SourceOnEnter(button)
	GameTooltip:SetOwner(button.Text, "ANCHOR_RIGHT")
	GameTooltip:SetCustomWordWrapMinWidth(SOURCE_TOOLTIP_WIDTH)
	button.recipeInfo.lockReason = ns.GetRecipeLock(button.recipeInfo.recipeID) or nil
	ns.AddSourceLines(GameTooltip, button.recipeInfo)
	GameTooltip:Show()
end

-- The recipe item (the pattern or plans that teach the recipe): icon and name at the pane's bottom
-- left, with Blizzard's own item tooltip and modified clicks.
local ITEM_ROW_X = 30 -- copied from AllocateBestQualityCheckbox's anchor in that XML
local ITEM_ICON_SIZE = 20
local ITEM_NAME_GAP = 6
local ITEM_ROW_END_GAP = 12 -- kept clear before Track Recipe

local itemRow

local function ItemOnEnter(row)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetItemByID(row.itemID)
	GameTooltip:Show()
end

local function ItemOnClick(row)
	local _, link = C_Item.GetItemInfo(row.itemID)
	if link then
		HandleModifiedItemClick(link)
	end
end

local function GetItemRow(form)
	if not itemRow then
		local track = form.TrackRecipeCheckbox
		itemRow = CreateFrame("Button", nil, form)
		itemRow:SetHeight(track:GetHeight())
		itemRow.Icon = itemRow:CreateTexture(nil, "ARTWORK")
		itemRow.Icon:SetSize(ITEM_ICON_SIZE, ITEM_ICON_SIZE)
		itemRow.Icon:SetPoint("LEFT")
		-- Track Recipe's own font, so the line reads as one.
		itemRow.Name = itemRow:CreateFontString(nil, "ARTWORK")
		itemRow.Name:SetFontObject(track.Text:GetFontObject())
		itemRow.Name:SetPoint("LEFT", itemRow.Icon, "RIGHT", ITEM_NAME_GAP, 0)
		itemRow.Name:SetPoint("RIGHT")
		itemRow.Name:SetJustifyH("LEFT")
		itemRow.Name:SetWordWrap(false)
		itemRow:SetScript("OnEnter", ItemOnEnter)
		itemRow:SetScript("OnLeave", GameTooltip_Hide)
		itemRow:SetScript("OnClick", ItemOnClick)
	end
	return itemRow
end

local function ShowItem(form, recipeInfo)
	local itemIDs = ns.GetRecipeItems(recipeInfo.recipeID)
	local itemID = itemIDs and itemIDs[1]
	-- Blizzard's own control has the corner when it shows.
	if not itemID or form.AllocateBestQualityCheckbox:IsShown() then
		return
	end
	local row, track = GetItemRow(form), form.TrackRecipeCheckbox
	row.itemID = itemID
	row.Icon:SetTexture(C_Item.GetItemIconByID(itemID))
	row.Name:SetText("")
	-- The name and quality load on demand (Blizzard's ItemMixin), so a later recipe may be showing.
	local item = Item:CreateFromItemID(itemID)
	item:ContinueOnItemLoad(function()
		if row.itemID == itemID then
			row.Name:SetText(item:GetItemQualityColor().color:WrapTextInColorCode(item:GetItemName()))
		end
	end)
	-- On Track Recipe's line, ending before it; without Track Recipe, at the pane's right edge.
	row:ClearAllPoints()
	row:SetPoint("BOTTOMLEFT", form, "BOTTOMLEFT", ITEM_ROW_X, track:GetBottom() - form:GetBottom())
	if track:IsShown() then
		row:SetPoint("RIGHT", track, "LEFT", -ITEM_ROW_END_GAP, 0)
	else
		row:SetPoint("RIGHT", form, "RIGHT", -ITEM_ROW_X, 0)
	end
	row:Show()
end

-- Same conditions as Blizzard's own source line (ProfessionsRecipeSchematicFormMixin:Init).
local function ShowSourceLine(form, recipeInfo, isRecraft)
	local button = form.RecipeSourceButton
	if itemRow then itemRow:Hide() end
	if not recipeInfo or recipeInfo.learned or isRecraft or form.isInspection or ProfessionsUtil.IsCraftingMinimized() then
		return
	end
	ns.SummarizeSources(recipeInfo)
	button.recipeInfo = recipeInfo
	button.Text:SetText(TRADESKILL_UNLEARNED_RECIPE_HEADER)
	button:SetScript("OnEnter", SourceOnEnter)
	button:ClearAllPoints()
	button:SetPoint("TOPLEFT", form.Description, "BOTTOMLEFT", 0, SOURCE_LINE_GAP)
	button:Show()
	ShowItem(form, recipeInfo)
	if form.Reagents:IsShown() then
		form.Reagents:ClearAllPoints()
		form.Reagents:SetPoint("TOPLEFT", form.Description, "BOTTOMLEFT", 0, REAGENTS_GAP_WITH_SOURCE)
	end
end

-- The other faction's NPCs stay in the source list but get no map target.
local OTHER_FACTION = { Alliance = "Horde", Horde = "Alliance" }

local function IsOtherFactionNPC(observation)
	local npc = ns.GetNPC(observation.npc)
	return npc and npc.faction ~= nil and npc.faction == OTHER_FACTION[UnitFactionGroup("player")]
end

-- Mappable sources, each { label, mapID, x, y }.
local function MapTargets(recipeInfo)
	local targets = {}
	for _, observation in ipairs(ns.GetSources(recipeInfo) or {}) do
		local mapID, x, y = ns.SourcePosition(observation)
		if mapID and x and C_Map.CanSetUserWaypointOnMap(mapID) and not IsOtherFactionNPC(observation) then
			local name = ns.SourceInfo(observation)
			local mapInfo = C_Map.GetMapInfo(mapID)
			table.insert(targets, {
				label = ("%s (%s)"):format(name or UNKNOWN, mapInfo and mapInfo.name or ""),
				mapID = mapID, x = x, y = y,
			})
		end
	end
	return targets
end

local function ShowOnMap(target)
	C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(target.mapID, target.x, target.y))
	C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	if not InCombatLockdown() then
		OpenMapToUserWaypoint()
	end
end

local function OnMapClick(button)
	local target = MapTargets(button.recipeInfo)[1]
	if target then
		ShowOnMap(target)
	end
end

-- Several places: the same arrow dropdown as the window's Filter button, one entry per source.
local function MapMenu(dropdown, rootDescription)
	-- SetupMenu builds the menu once right away, before any recipe is selected.
	if not dropdown.recipeInfo then return end
	for _, target in ipairs(MapTargets(dropdown.recipeInfo)) do
		rootDescription:CreateButton(target.label, function() ShowOnMap(target) end)
	end
end

local mapButton, mapMenu

local function CreateMapControls(page)
	mapButton = CreateFrame("Button", nil, page, page:GetButtonTemplate())
	mapButton:SetHeight(page.CreateButton:GetHeight())
	mapButton:SetPoint("BOTTOMRIGHT", page.CreateButton, "BOTTOMRIGHT")
	mapButton:SetTextToFit(SHOW_MAP or "Show Map")
	mapButton:SetWidth(math.max(mapButton:GetWidth(), page.CreateButton:GetWidth()))
	mapButton:SetScript("OnClick", OnMapClick)

	-- Several places: the arrow dropdown of the window's Filter button, at its own size.
	mapMenu = CreateFrame("DropdownButton", nil, page, "WowStyle1FilterDropdownTemplate")
	mapMenu:SetAllPoints(mapButton) -- the same place and size as Show Map, which it stands in for
	mapMenu:SetText(SHOW_MAP or "Show Map")
	mapMenu:SetupMenu(MapMenu)
end

-- ValidateControls runs on every bag and skill update while the window is open. The map controls
-- only change with the selected recipe, the known sources or the player's zone, so the rest is skipped.
local shownRecipeID, shownVersion, shownMapID

local function UpdateMap(page)
	local selected = page.SchematicForm:GetRecipeInfo()
	local recipeID = selected and not selected.learned and selected.recipeID or nil
	local mapID = C_Map.GetBestMapForUnit("player")
	if recipeID == shownRecipeID and ns.sourcesVersion == shownVersion and mapID == shownMapID
		and (mapButton or not recipeID) then
		return
	end
	shownRecipeID, shownVersion, shownMapID = recipeID, ns.sourcesVersion, mapID

	local recipeInfo = SelectedRecipe(page)
	if not mapButton then
		if not recipeInfo then return end
		CreateMapControls(page)
	end
	local targets = recipeInfo and #MapTargets(recipeInfo) or 0
	mapButton.recipeInfo, mapMenu.recipeInfo = recipeInfo, recipeInfo
	mapButton:SetShown(recipeInfo ~= nil and targets <= 1)
	mapButton:SetEnabled(targets == 1)
	mapMenu:SetShown(targets > 1)
	if targets > 1 then
		mapMenu:GenerateMenu()
	end
end

--@debug@
-- Timed in a checkout build (ns.Perf, Troubleshooting.lua).
do
	local innerMap, innerLine = UpdateMap, ShowSourceLine
	UpdateMap = function(...)
		local started = debugprofilestop()
		innerMap(...)
		ns.Perf("panel: map controls", started)
	end
	ShowSourceLine = function(...)
		local started = debugprofilestop()
		innerLine(...)
		ns.Perf("panel: source line", started)
	end
end
--@end-debug@

EventUtil.ContinueOnAddOnLoaded("Blizzard_Professions", function()
	local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
	if page then
		hooksecurefunc(page, "ValidateControls", UpdateMap)
		hooksecurefunc(page.SchematicForm, "Init", ShowSourceLine)
	end
end)
