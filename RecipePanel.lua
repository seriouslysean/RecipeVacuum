local _, ns = ...

-- Map pins for recipe sources. Recipe Vacuum writes nothing into Blizzard's frames and opens none of its windows: a pin is the user waypoint, super-tracked (docs/client-notes.md, "Gamepad").

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

-- Sets the waypoint and super-tracks it, as Blizzard's own pin links do (ItemRefHandlers.lua), then opens the map at it with
-- mouse and keyboard, measured clean on the Mac; under the Gamepad UI only once a Deck test passes (kit decision 0068).
function ns.ShowOnMap(target)
	ns.toolkit:Trace(ns.module, "map pin", "label", target.label, "map", target.mapID)
	if not C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(target.mapID, target.x, target.y)) then
		return
	end
	C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	ns.lastPin = target -- the working build's map-open test pins it again (decision 0068)
	ns.toolkit:Say(ns.module, ns.voice.pinned, target.label)
	if not ns.toolkit.IsGamepadUI() then
		OpenWorldMap(target.mapID)
	end
	ns.toolkit:Trace(ns.module, "map open", "map", target.mapID, "opened", not ns.toolkit.IsGamepadUI())
end
