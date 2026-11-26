local _, ns = ...

-- Source line and Show on Map for a selected unlearned recipe; Forever never fills Blizzard's RecipeSourceButton (docs/client-notes.md, "Profession window").

-- Copied from ProfessionsRecipeSchematicFormMixin:Init: the source line sits 10 below the description, reagents 50 below while it shows.
local SOURCE_LINE_GAP = -10
local REAGENTS_GAP_WITH_SOURCE = -50

local function SelectedRecipe(page)
	local recipeInfo = page.SchematicForm:GetRecipeInfo()
	if recipeInfo and not recipeInfo.learned then
		ns.SummarizeSources(recipeInfo)
		return recipeInfo
	end
end

-- Same tooltip as Blizzard's source line, wrapped at 350.
local SOURCE_TOOLTIP_WIDTH = 350 -- copied from the same Init
local sourceLineRecipe -- kept here, not on Blizzard's button

local function SourceOnEnter(button)
	GameTooltip:SetOwner(button.Text, "ANCHOR_RIGHT")
	GameTooltip:SetCustomWordWrapMinWidth(SOURCE_TOOLTIP_WIDTH)
	sourceLineRecipe.lockReason = ns.GetRecipeLock(sourceLineRecipe.recipeID) or nil
	ns.AddSourceLines(GameTooltip, sourceLineRecipe, true)
	GameTooltip:Show()
end

-- The recipe item (the pattern or plans that teach it): icon and name at the pane's bottom left, with Blizzard's item tooltip and modified clicks.
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
	-- Name and quality load on demand (Blizzard's ItemMixin), so a later recipe may be showing.
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
	sourceLineRecipe = recipeInfo
	button.Text:SetText(TRADESKILL_UNLEARNED_RECIPE_HEADER)
	-- Blizzard sets this button's OnEnter on every Init (ProfessionsRecipeSchematicFormMixin:Init), so setting it after is the same pattern; a hook would not survive.
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

function ns.IsOtherFactionNPC(observation)
	local npc = ns.GetNPC(observation.npc)
	return npc and npc.faction ~= nil and npc.faction == OTHER_FACTION[UnitFactionGroup("player")]
end

-- One source's pin, or nil when it has no place this character can be sent to.
function ns.SourceTarget(observation)
	local mapID, x, y = ns.SourcePosition(observation)
	if mapID and x and C_Map.CanSetUserWaypointOnMap(mapID) and not ns.IsOtherFactionNPC(observation) then
		local name = ns.SourceInfo(observation)
		local mapInfo = C_Map.GetMapInfo(mapID)
		return {
			label = ("%s (%s)"):format(name or UNKNOWN, ns.PlaceName(observation, mapInfo)), -- a drop names its subzone
			mapID = mapID, x = x, y = y,
		}
	end
end

-- Mappable sources, each { label, mapID, x, y }.
-- Drops follow their scope (docs/data.md, "Drops"): one creature is pinned where it was killed, a zone
-- drop opens its zone, a world drop has no place to show.
local function MapTargets(recipeInfo)
	local targets = {}
	local entries = ns.GetSources(recipeInfo) or {}
	local scope = ns.DropScope(entries)
	if scope and scope.scope == "zone" and scope.place then
		-- A dungeon zone drop opens the map recorded inside that dungeon, when a sighting has one.
		local mapID = scope.place.kind == "map" and scope.place.id or nil
		for _, observation in ipairs(entries) do
			if not mapID and observation.instance == scope.place.id then mapID = observation.map end
		end
		if mapID then
			table.insert(targets, { label = ns.DropPlaceName(scope.place.kind, scope.place.id), mapID = mapID, zoneOnly = true })
		end
	end
	for _, observation in ipairs(entries) do
		local pinned = observation.kind ~= "drop" or observation.fishing or (scope and scope.scope == "single")
		local target = pinned and ns.SourceTarget(observation)
		if target then
			table.insert(targets, target)
		end
	end
	-- The zone the player is in first, then by label.
	local here = C_Map.GetBestMapForUnit("player")
	table.sort(targets, function(left, right)
		if (left.mapID == here) ~= (right.mapID == here) then
			return left.mapID == here
		end
		return strcmputf8i(left.label, right.label) < 0
	end)
	return targets
end

function ns.ShowOnMap(target)
	if target.zoneOnly then
		if not InCombatLockdown() then
			OpenWorldMap(target.mapID)
		end
		return
	end
	-- As Blizzard's own pin links do (ItemRefHandlers.lua): nothing follows a pin that was not set.
	if not C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(target.mapID, target.x, target.y)) then
		return
	end
	C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	if not InCombatLockdown() then
		OpenMapToUserWaypoint()
	end
end

local function OnMapClick(button)
	local target = MapTargets(button.recipeInfo)[1]
	if target then
		ns.ShowOnMap(target)
	end
end

-- Several places: the same arrow dropdown as the window's Filter button, one entry per source.
-- About twelve entries show before the menu scrolls (20 per entry, as Blizzard's menu guide sizes it).
local MAP_MENU_ENTRY_HEIGHT, MAP_MENU_ENTRIES = 20, 12
local MAP_MENU_MAX_HEIGHT = MAP_MENU_ENTRY_HEIGHT * MAP_MENU_ENTRIES
local function MapMenu(dropdown, rootDescription)
	-- SetupMenu builds the menu once right away, before any recipe is selected.
	if not dropdown.recipeInfo then return end
	rootDescription:SetScrollMode(MAP_MENU_MAX_HEIGHT) -- Blizzard's own menu scrolling, past this height
	for _, target in ipairs(MapTargets(dropdown.recipeInfo)) do
		rootDescription:CreateButton(target.label, function() ns.ShowOnMap(target) end)
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

	-- The arrow dropdown of the window's Filter button keeps the template's size, so one anchor places it; stretching it left the text off center.
	mapMenu = CreateFrame("DropdownButton", nil, page, "WowStyle1FilterDropdownTemplate")
	mapMenu:SetPoint("RIGHT", mapButton, "RIGHT")
	mapMenu:SetText(SHOW_MAP or "Show Map")
	mapMenu:SetupMenu(MapMenu)
end

-- ValidateControls runs on every bag and skill update (docs/client-notes.md, "Profession window"); the map controls change only with the selected recipe, sources or zone, so skip the rest.
local shownRecipeID, shownVersion, shownMapID

local function UpdateMap(page)
	local selected = page.SchematicForm:GetRecipeInfo()
	local recipeID = selected and not selected.learned and selected.recipeID or nil
	-- Blizzard hides the create buttons for a recipe not known but leaves them enabled, and the gamepad's
	-- Create press still clicks them (Blizzard_ProfessionsFrame.lua, CanCreate). A learned recipe re-enables them.
	if recipeID then
		page.CreateButton:SetEnabled(false)
		page.CreateAllButton:SetEnabled(false)
	end
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
-- Timed in a checkout build.
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
