function tDeleteItem(t, v) for i = #t, 1, -1 do if t[i] == v then table.remove(t, i) end end end
-- Upgrades an old save (schema 1 or 2) to the current schema and checks nothing recorded by ID is lost.
-- luajit tests/upgrade.lua . <saved file>
local repo, saved = arg[1], arg[2]
local loaded = {}
EventUtil = { ContinueOnAddOnLoaded = function(_, fn) loaded[#loaded + 1] = fn end }
C_AddOns = { GetAddOnMetadata = function() return "Recipe Vacuum" end }
GetBuildInfo = function() return "1.60.1", "71037" end
GetServerTime = function() return 1795470000 end
C_Map = { GetMapInfo = function(id) return { name = "Map" .. id } end }
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
ChatTypeInfo = { MONSTER_SAY = { r = 1, g = 1, b = 0.62 } }
-- The real toolkit library, through the real LibStub, prints the addon's chat lines.
SlashCmdList = {}
function CreateColor(r, g, b) return { r = r, g = g, b = b } end
RAID_CLASS_COLORS = { DRUID = { r = 1, g = 0.49, b = 0.04 } }
dofile(repo .. "/Libs/LibStub/LibStub.lua")
dofile(repo .. "/Libs/JigBoltgripToolkit/JigBoltgripToolkit.lua")
dofile(saved)

-- What the old save holds, read before the migration changes it.
local oldItems, oldLinks = {}, {}
for key in pairs(RecipeVacuumDB.sources or {}) do
	local itemID = type(key) == "string" and tonumber(key:match("^item:(%d+)$"))
	if itemID then oldItems[itemID] = true end
end
for itemID, recipeID in pairs(RecipeVacuumDB.itemRecipe or {}) do oldLinks[itemID] = recipeID end

local ns = { Perf = function() end, PerfMs = function() end, InitSettings = function() end, ResumeWatch = function() end, ScheduleFindOffer = function() end }
for _, f in ipairs({ "Data/Included.lua", "Core.lua", "Voice.lua", "Finds.lua" }) do assert(loadfile(repo .. "/" .. f))("RecipeVacuum", ns) end
for _, fn in ipairs(loaded) do fn() end
local db = ns.db

local failed = false
local function check(label, ok) print((ok and "PASS " or "FAIL ") .. label); failed = failed or not ok end

check("schema is current, old tables gone", db.schema == 8 and db.sources == nil and db.found.trainerNames == nil)
local itemsKept = next(oldItems) ~= nil
for itemID in pairs(oldItems) do
	itemsKept = itemsKept and (db.found.items[itemID] or db.shared.items[itemID]) ~= nil
end
check("every recipe item recorded by ID is kept", itemsKept)
-- Links made from names are queued to be made again from the item's tooltip data (schema 6).
local linksQueued = next(db.itemRecipe) == nil
for itemID in pairs(oldLinks) do linksQueued = linksQueued and db.pendingItems[itemID] ~= nil end
check("old item to recipe links are queued for relinking by ID", linksQueued)

-- Every self-found observation names a known NPC and has its own revision, up to the counter.
local count, sound, revisions = 0, true, {}
for _, bucket in ipairs({ db.found.recipes, db.found.items }) do
	for _, observations in pairs(bucket) do
		for _, observation in ipairs(observations) do
			count = count + 1
			sound = sound and observation.kind ~= nil and db.npcs[observation.npc] ~= nil
				and observation.rev ~= nil and not revisions[observation.rev]
			revisions[observation.rev or 0] = true
		end
	end
end
check(("%d observations, each with an NPC and a revision"):format(count), count > 0 and sound)
check("revision counter covers every observation", db.exchange.revision == count)

print(failed and "UPGRADE CHECKS FAILED" or "ALL UPGRADE CHECKS PASSED")
os.exit(failed and 1 or 0)
