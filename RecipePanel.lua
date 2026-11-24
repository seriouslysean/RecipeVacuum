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
	ns.AddSourceLines(GameTooltip, button.recipeInfo)
	GameTooltip:Show()
end

local function ShowSourceLine(form, recipeInfo)
	local button = form.RecipeSourceButton
	if not (recipeInfo and not recipeInfo.learned and form.Description:IsShown()) then
		return
	end
	ns.SummarizeSources(recipeInfo)
	button.recipeInfo = recipeInfo
	button.Text:SetText(TRADESKILL_UNLEARNED_RECIPE_HEADER)
	button:SetScript("OnEnter", SourceOnEnter)
	button:ClearAllPoints()
	button:SetPoint("TOPLEFT", form.Description, "BOTTOMLEFT", 0, SOURCE_LINE_GAP)
	button:Show()
	if form.Reagents:IsShown() then
		form.Reagents:ClearAllPoints()
		form.Reagents:SetPoint("TOPLEFT", form.Description, "BOTTOMLEFT", 0, REAGENTS_GAP_WITH_SOURCE)
	end
end

-- Mappable sources, each { label, mapID, x, y }.
local function MapTargets(recipeInfo)
	local targets = {}
	for _, observation in ipairs(ns.GetSources(recipeInfo) or {}) do
		local mapID, x, y = ns.SourcePosition(observation)
		if mapID and x and C_Map.CanSetUserWaypointOnMap(mapID) then
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
	mapMenu:SetPoint("RIGHT", mapButton, "RIGHT")
	mapMenu:SetText(SHOW_MAP or "Show Map")
	mapMenu:SetupMenu(MapMenu)
end

local function UpdateMap(page)
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

EventUtil.ContinueOnAddOnLoaded("Blizzard_Professions", function()
	local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
	if page then
		hooksecurefunc(page, "ValidateControls", UpdateMap)
		hooksecurefunc(page.SchematicForm, "Init", ShowSourceLine)
	end
end)
