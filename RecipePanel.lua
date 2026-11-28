local _, ns = ...

-- Map pins for recipe sources. Recipe Vacuum writes nothing into Blizzard's frames: a pin is the user waypoint, super-tracked, and
-- the map opens through the game's own /mappin from a secure button (docs/client-notes.md, "Gamepad").

-- One source's pin, or nil when it has no place this character can be sent to.
function ns.SourceTarget(observation)
	local mapID, x, y = ns.SourcePosition(observation)
	if mapID and x and C_Map.CanSetUserWaypointOnMap(mapID) and not ns.IsOtherFactionNPC(observation) then
		local name = ns.SourceInfo(observation) or UNKNOWN
		local place = ns.PlaceName(observation, C_Map.GetMapInfo(mapID)) -- a drop names its subzone
		return { label = ("%s (%s)"):format(name, place), name = name, place = place, mapID = mapID, x = x, y = y }
	end
end

-- The zone the player is in first, then by label.
function ns.SortTargets(targets)
	local here = C_Map.GetBestMapForUnit("player")
	table.sort(targets, function(left, right)
		if (left.mapID == here) ~= (right.mapID == here) then
			return left.mapID == here
		end
		return strcmputf8i(left.label, right.label) < 0
	end)
end

-- Drops follow their scope (docs/data.md, "Drops"): one creature is pinned where it was killed; a zone or world drop has no one place to pin.
local function IsPinnable(observation, scope)
	return observation.kind ~= "drop" or observation.fishing or (scope and scope.scope == "single")
end

-- Mappable sources, each { label, mapID, x, y }.
function ns.MapTargets(recipeInfo)
	local targets = {}
	local entries = ns.GetSources(recipeInfo) or {}
	local scope = ns.DropScope(entries)
	for _, observation in ipairs(entries) do
		local target = IsPinnable(observation, scope) and ns.SourceTarget(observation)
		if target then
			table.insert(targets, target)
		end
	end
	ns.SortTargets(targets)
	return targets
end

-- The recipe's sources as the details list them, each { label, target, place }: "who, type" as the source tooltip names it, the pin
-- when it has a place (nil otherwise, shown as plain text) and the place's name. Drops with no one creature are one row naming the scope.
function ns.SourceRows(recipeInfo)
	local rows = {}
	local entries = ns.GetSources(recipeInfo) or {}
	local scope = ns.DropScope(entries)
	local scopeShown = false
	for _, observation in ipairs(entries) do
		if IsPinnable(observation, scope) or observation.container then
			local name = ns.SourceInfo(observation)
			local target = IsPinnable(observation, scope) and ns.SourceTarget(observation) or nil
			local mapID = ns.SourcePosition(observation)
			rows[#rows + 1] = {
				label = ("%s, %s"):format(name or UNKNOWN, ns.sourceTypes[observation.kind].label),
				target = target,
				place = ns.PlaceName(observation, mapID and C_Map.GetMapInfo(mapID)),
			}
		elseif not scopeShown and scope then
			scopeShown = true
			rows[#rows + 1] = { label = ns.DropHeader(scope) }
		end
	end
	return rows
end

-- As Blizzard's own pin links do (ItemRefHandlers.lua). Never opens the map: from addon code that taints the Gamepad UI (kit
-- decision 0068).
function ns.ShowOnMap(target)
	ns.toolkit:Trace(ns.module, "map pin", "label", target.label, "map", target.mapID)
	if not C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(target.mapID, target.x, target.y)) then
		return
	end
	C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	ns.toolkit:Say(ns.module, ns.voice.pinned, target.name, target.place) -- the place in the sentence, as Tackletron says its zone
end

-- The game's own /mappin opens the map in Blizzard's code, the one open measured clean on the Deck (kit decision 0068).
local shields = {} -- [control] = the secure button over it

local function Place(shield)
	local control = shield.control
	if InCombatLockdown() then return end
	if shield.target and control:IsVisible() then
		shield:SetAttribute("macrotext", ("%s %d %.1f %.1f"):format(SLASH_MAPPIN1, shield.target.mapID, shield.target.x * 100,
			shield.target.y * 100))
		shield:ClearAllPoints()
		shield:SetAllPoints(control)
		shield:SetFrameStrata(control:GetFrameStrata())
		shield:SetFrameLevel(control:GetFrameLevel() + 5)
		shield:Show()
	else
		shield:Hide()
		shield:ClearAllPoints()
	end
end

local function MakeShield(control)
	local shield = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
	shield.control = control
	shield:Hide()
	shield:RegisterForClicks("AnyUp", "AnyDown")
	shield:SetAttribute("type", "macro")
	shield:SetScript("PreClick", function(_, _, down)
		if down and control:IsEnabled() then control:SetButtonState("PUSHED") end
	end)
	shield:SetScript("PostClick", function(_, _, down)
		ns.toolkit:Trace(ns.module, "map opened", "down", down, "shown", WorldMapFrame and WorldMapFrame:IsShown(),
			"map", WorldMapFrame and WorldMapFrame:GetMapID())
		if down then return end
		control:SetButtonState("NORMAL")
		control:Click()
	end)
	shield:SetScript("OnEnter", function()
		control:LockHighlight()
		local enter = control:GetScript("OnEnter")
		if enter then enter(control) end
	end)
	shield:SetScript("OnLeave", function()
		control:UnlockHighlight()
		local leave = control:GetScript("OnLeave")
		if leave then leave(control) end
	end)
	control:HookScript("OnShow", function() Place(shield) end)
	control:HookScript("OnHide", function() Place(shield) end)
	shields[control] = shield
	return shield
end

function ns.PinShield(control, target)
	local shield = shields[control] or MakeShield(control)
	shield.target = target
	Place(shield)
end

function ns.PinNavFrame(control)
	local shield = control and shields[control]
	return shield and shield:IsShown() and shield or control
end

-- Protected frames cannot be hidden or moved in combat, so they go before it (PLAYER_REGEN_DISABLED); Map Pin is greyed out until it ends.
function ns.HidePinShields()
	for _, shield in pairs(shields) do
		shield:Hide()
		shield:ClearAllPoints()
	end
end

function ns.RestorePinShields()
	for _, shield in pairs(shields) do Place(shield) end
end
