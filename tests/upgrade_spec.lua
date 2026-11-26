-- Upgrades an old save (schema 1 or 2) to the current schema and checks nothing recorded by ID is lost.
-- RV_OLD_SAVE=<saved file> busted        (defaults to tests/fixtures/schema2.lua; RV_REPO defaults to .)
local repo = os.getenv("RV_REPO") or "."
local saved = os.getenv("RV_OLD_SAVE") or repo .. "/tests/fixtures/schema2.lua"

-- The client's globals must be the real ones: the addon files read them from there, while busted gives
-- each spec function a private environment that would hide them.
local G = getfenv(0)
local function real(fn)
	return function(...) setfenv(fn, G); return fn(...) end
end

describe("upgrade of an old save", function()
	local busted_it, busted_setup = it, setup
	local function it(name, fn) busted_it(name, real(fn)) end
	local function setup(fn) busted_setup(real(fn)) end

	local db, oldItems, oldLinks

	setup(function()
		function tDeleteItem(t, v) for i = #t, 1, -1 do if t[i] == v then table.remove(t, i) end end end
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
		GetLocale = GetLocale or function() return "enUS" end -- the client's language
		geterrorhandler = geterrorhandler or function() return error end
		dofile(repo .. "/Libs/AceLocale-3.0/AceLocale-3.0.lua")
		assert(loadfile(repo .. "/Locales/enUS.lua"))("RecipeVacuum", {})
		dofile(repo .. "/Libs/JigBoltgripToolkit/JigBoltgripToolkit.lua")
		dofile(saved)

		-- What the old save holds, read before the migration changes it.
		oldItems, oldLinks = {}, {}
		for key in pairs(RecipeVacuumDB.sources or {}) do
			local itemID = type(key) == "string" and tonumber(key:match("^item:(%d+)$"))
			if itemID then oldItems[itemID] = true end
		end
		for itemID, recipeID in pairs(RecipeVacuumDB.itemRecipe or {}) do oldLinks[itemID] = recipeID end

		local ns = { Perf = function() end, PerfMs = function() end, InitSettings = function() end, ResumeWatch = function() end, ScheduleFindOffer = function() end }
		for _, f in ipairs({ "Data/Included.lua", "Core.lua", "Voice.lua", "Finds.lua" }) do assert(loadfile(repo .. "/" .. f))("RecipeVacuum", ns) end
		for _, fn in ipairs(loaded) do fn() end
		db = ns.db
	end)

	it("schema is current, old tables gone", function()
		assert(db.schema == 11 and db.sources == nil and db.found.trainerNames == nil, "schema is current, old tables gone")
	end)

	it("every recipe item recorded by ID is kept", function()
		local itemsKept = next(oldItems) ~= nil
		for itemID in pairs(oldItems) do
			itemsKept = itemsKept and (db.found.items[itemID] or db.shared.items[itemID]) ~= nil
		end
		assert(itemsKept, "every recipe item recorded by ID is kept")
	end)

	-- Links made from names are queued to be made again from the item's tooltip data (schema 6).
	it("old item to recipe links are queued for relinking by ID", function()
		local linksQueued = next(db.itemRecipe) == nil
		for itemID in pairs(oldLinks) do linksQueued = linksQueued and db.pendingItems[itemID] ~= nil end
		assert(linksQueued, "old item to recipe links are queued for relinking by ID")
	end)

	-- Every self-found observation names a known NPC and has its own revision, up to the counter.
	local count, sound = 0, true
	it("observations, each with an NPC and a revision", function()
		local revisions = {}
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
		assert(count > 0 and sound, ("%d observations, each with an NPC and a revision"):format(count))
	end)
	it("revision counter covers every observation", function()
		assert(db.exchange.revision == count, "revision counter covers every observation")
	end)
end)
