local _, ns = ...

-- Map pins for recipe sources. Recipe Vacuum writes nothing into Blizzard's frames and opens none of its windows: a pin is the user waypoint, super-tracked (docs/client-notes.md, "Gamepad").

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

-- Mappable sources, each { label, mapID, x, y }.
-- Drops follow their scope (docs/data.md, "Drops"): one creature is pinned where it was killed; a zone or world drop has no one place to pin.
function ns.MapTargets(recipeInfo)
	local targets = {}
	local entries = ns.GetSources(recipeInfo) or {}
	local scope = ns.DropScope(entries)
	for _, observation in ipairs(entries) do
		local pinned = observation.kind ~= "drop" or observation.fishing or (scope and scope.scope == "single")
		local target = pinned and ns.SourceTarget(observation)
		if target then
			table.insert(targets, target)
		end
	end
	ns.SortTargets(targets)
	return targets
end

-- Sets the waypoint and super-tracks it, as Blizzard's own pin links do (ItemRefHandlers.lua); nothing follows a pin that was not set. The world map is never opened: opening it from addon code taints (docs/client-notes.md, "Gamepad").
function ns.ShowOnMap(target)
	ns.Trace("UI pin: %s (map %s)", tostring(target.label), tostring(target.mapID))
	if not C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(target.mapID, target.x, target.y)) then
		return
	end
	C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	local pinned = ns.voice.pinned
	ns.Say(pinned.noise, pinned.report:format(target.label))
end
