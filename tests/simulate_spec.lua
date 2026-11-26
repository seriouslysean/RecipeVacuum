-- Offline specs for the current schema, drop and quest recording, and sharing of the new kinds.
-- RV_SAVE=<a RecipeVacuum saved-variables file> busted        (defaults to tests/fixtures/current.lua; RV_REPO defaults to .)
-- The specs build one addon instance step by step: `it` blocks run in file order and later ones read
-- what earlier ones set up.
local repo = os.getenv("RV_REPO") or "."
local savedFile = os.getenv("RV_SAVE") or repo .. "/tests/fixtures/current.lua"
-- The real clock: a fixed one falls behind the saves, and their finds then read as from the future.
local now = os.time()

-- The client's globals must be the real ones: the addon files read them from there, while busted gives
-- each spec function a private environment that would hide them.
local G = getfenv(0)
local function real(fn)
	return function(...) setfenv(fn, G); return fn(...) end
end

describe("simulation", function()
	local busted_it, busted_setup = it, setup
	local function it(name, fn) busted_it(name, real(fn)) end
	local function setup(fn) busted_setup(real(fn)) end

	local loaded, frames = {}, {}
	local UNKNOWN_MAP = 999999
	local TAILORING, TAILORING_PATTERN = 7, 2
	local nonRecipes = { [5] = true, [7] = true, [777] = true, [10456] = true } -- every other item is a recipe item
	-- Places: outdoors unless a test sets an instance; the subzone at any spot is area 40 unless set.
	local place = { instance = nil, area = 40 }
	local itemNames = { [10456] = "A Bulging Coin Purse" } -- names the client has loaded
	local target = {}
	local messages = {}
	local clock = 1000
	local rollLinks = {}
	local loot = {}
	local fishing = false
	local quest = {}
	local Rejected, load, boot, count -- defined in setup, where the client's globals are the real ones

	setup(function()
		-- A row the validation refuses is dropped on its own: nothing changes and it is counted as skipped.
		function Rejected(m, row) local changed, skipped = m.MergeFinds({ row }, 10) return changed == false and skipped == 1 end

		EventUtil = { ContinueOnAddOnLoaded = function(name, fn) loaded[#loaded + 1] = { name, fn } end }
		C_AddOns = { GetAddOnMetadata = function() return "Recipe Vacuum" end }
		GetServerTime = function() return now end
		GetBuildInfo = function() return "1.60.1", "71037", "", 16001 end
		C_Map = { GetMapInfo = function(id) return id and id > 0 and id ~= UNKNOWN_MAP and { name = "Map" .. id } or nil end,
		  GetBestMapForUnit = function() return 1429 end,
		  GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.25 end } end }
		wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
		function tDeleteItem(t, v) for i = #t, 1, -1 do if t[i] == v then table.remove(t, i) end end end
		function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end end
		function CopyTable(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
		function strsplit(sep, s) local out = {} for part in (s .. sep):gmatch("(.-)%" .. sep) do out[#out + 1] = part end return unpack(out) end
		issecretvalue = function() return false end
		Enum = { ItemClass = { Recipe = 9 }, LootSlotType = { Item = 1 }, Profession = { Tailoring = TAILORING },
		  ItemRecipeSubclass = { Tailoring = TAILORING_PATTERN },
		  TooltipDataLineType = {}, TooltipDataUsageRequirementType = {} }
		C_TradeSkillUI = { GetTradeSkillLineForRecipe = function() return 1 end, GetRecipeInfo = function() return nil end }
		C_SpellBook = { IsSpellKnown = function() return false end }
		IsInInstance = function() return place.instance ~= nil, place.instance and "party" or "none" end
		GetInstanceInfo = function() return "Dungeon", "party", 1, "", 5, 0, false, place.instance end
		C_MapExplorationInfo = { GetExploredAreaIDsAtPosition = function() return place.area and { place.area } or nil end }
		CreateVector2D = function(x, y) return { x = x, y = y } end
		GetRealZoneText = function(id) return "Instance" .. id end
		C_Map.GetAreaInfo = function(id) return "Area" .. id end
		BATTLE_PET_SOURCE_1, TRANSMOG_SOURCE_4 = "Drop", "World Drop"
		strcmputf8i = strcmputf8i or function(a, b) return a < b and -1 or (a > b and 1 or 0) end
		function tostringall(...) local out = {} for i = 1, select("#", ...) do out[i] = tostring((select(i, ...))) end return unpack(out) end
		function strjoin(sep, ...) return table.concat({ ... }, sep) end
		C_Item = { GetItemInfoInstant = function(x) local id = tonumber(x) or tonumber(tostring(x):match("item:(%d+)"))
		    return id, nil, nil, nil, nil, nonRecipes[id] and 7 or 9, TAILORING_PATTERN end,
		  GetItemIDByGUID = function(guid) return guid == "Item-1-0-ABC" and 10456 or nil end,
		  GetItemNameByID = function(id) return itemNames[id] end,
		  RequestLoadItemDataByID = function() end }
		C_Spell = { GetSpellName = function() return "Fishing" end }
		C_QuestLog = { GetTitleForQuestID = function(id) return "Quest Title " .. id end }
		UnitFactionGroup = function() return "Alliance", "Alliance" end
		UnitGUID = function(unit) return target[unit] end
		UnitName = function(unit) return target[unit .. "name"] end
		ChatTypeInfo = { SYSTEM = { r = 1, g = 1, b = 0 }, MONSTER_SAY = { r = 1, g = 1, b = 0.62 } }
		DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) messages[#messages + 1] = text end }
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
		C_Timer = { NewTimer = function() return { Cancel = function() end } end, After = function(_, fn) fn() end }
		GetTime = function() return clock end
		UNKNOWN = "Unknown"
		GetLootRollItemLink = function(rollID) return rollLinks[rollID] end
		CreateFrame = function() local f = { events = {} }
		  function f:RegisterEvent(e) self.events[e] = true end
		  function f:UnregisterEvent(e) self.events[e] = nil end
		  function f:SetScript(_, fn) self.script = fn end
		  frames[#frames + 1] = f; return f end
		GetNumLootItems = function() return #loot end
		GetLootSlotType = function(i) return loot[i].type end
		GetLootSlotLink = function(i) return loot[i].link end
		GetLootSourceInfo = function(i) return unpack(loot[i].sources) end
		IsFishingLoot = function() return fishing end
		GetQuestID = function() return quest.id end
		GetNumQuestRewards = function() return #quest.rewards end
		GetNumQuestChoices = function() return #quest.choices end
		GetQuestItemInfo = function(kind, i) local id = (kind == "reward" and quest.rewards or quest.choices)[i]
		  return "", 1, 1, 1, true, id end

		debugprofilestop = function() return 0 end -- the checkout build times itself
		function load(file, ns) local f = assert(loadfile(repo .. "/" .. file)); f("RecipeVacuum", ns) end
		function boot(saved)
		  RecipeVacuumDB = nil; loaded = {}; frames = {}
		  if saved then dofile(saved) end
		  local ns = { Perf = function() end, PerfMs = function() end, InitSettings = function() end, ResumeWatch = function() end, ScheduleFindOffer = function() end, SourcesChanged = function() end }
		  for _, file in ipairs({ "Data/Included.lua", "Core.lua", "Voice.lua", "Sources.lua", "Finds.lua", "Record.lua" }) do load(file, ns) end
		  ns.SourcesChanged = function() end
		  for _, entry in ipairs(loaded) do if entry[1] == "RecipeVacuum" then entry[2]() end end
		  return ns
		end
		function count(layer) local r, i = 0, 0 for _, l in pairs(layer.recipes) do r = r + #l end for _, l in pairs(layer.items) do i = i + #l end return r, i end
	end)

	-- 1. Schema 3 -> 4 on the owner's real save
	local a, db, before, beforeRecipes, beforeItems, beforeRevision
	it("schema is 12", function()
		dofile(savedFile); before = RecipeVacuumDB
		beforeRecipes, beforeItems = count(before.found)
		beforeRevision = before.exchange.revision
		a = boot(savedFile)
		db = a.db
		assert(db.schema == 12, "schema is 12")
	end)
	it("trainerNames dropped", function()
		assert(db.found.trainerNames == nil and db.shared.trainerNames == nil, "trainerNames dropped")
	end)
	-- Fails if the upgrade keeps NPCs no source names, or drops one a source does name.
	it("only NPCs a source names are kept, and none of those is lost", function()
		local named, strays, missing = {}, 0, 0
		for _, layer in ipairs({ db.found, db.shared }) do
			for _, bucket in ipairs({ layer.recipes, layer.items }) do
				for _, list in pairs(bucket) do for _, o in ipairs(list) do
					if o.npc then named[o.npc] = true end
					if o.finisher then named[o.finisher] = true end
				end end
			end
		end
		-- Rank trainers and quest givers are kept for the rank mark.
		for _, byCap in pairs(db.ranks) do for _, sources in pairs(byCap) do
			for npcID in pairs(sources.npcs) do named[npcID] = true end
			for _, giver in pairs(sources.quests) do named[giver] = true end
		end end
		for id in pairs(db.npcs) do if not named[id] then strays = strays + 1 end end
		for id in pairs(named) do if not db.npcs[id] then missing = missing + 1 end end
		local keptNPCs = 0 for _ in pairs(db.npcs) do keptNPCs = keptNPCs + 1 end
		assert(strays == 0 and missing == 0 and keptNPCs > 0, "only NPCs a source names are kept, and none of those is lost")
	end)
	it("found kept", function()
		local r, i = count(db.found)
		assert(r == beforeRecipes and i == beforeItems, ("found kept (%d recipes, %d items)"):format(r, i))
	end)
	it("revision unchanged by migration", function()
		assert(db.exchange.revision == beforeRevision, "revision unchanged by migration")
	end)
	it("objects table created", function()
		assert(type(db.objects) == "table", "objects table created")
	end)

	-- 2. Drops: creature, object, container, fishing; a non-recipe item is ignored
	local lootFrame, fire, obs, f4
	-- Two slots of one recipe from one creature are one sighting.
	it("creature drop saved once, as one sighting per loot window", function()
		for _, f in ipairs(frames) do if f.events.LOOT_READY then lootFrame = f end end
		fire = function(event, ...) lootFrame.script(lootFrame, event, ...) end
		target.target, target.targetname = "Creature-0-1-0-1-732-AAAA", "Murloc Lurker"
		loot = { { type = 1, link = "item:1000", sources = { "Creature-0-1-0-1-732-AAAA", 1 } },
		         { type = 1, link = "item:1000", sources = { "Creature-0-1-0-1-732-AAAA", 1 } },
		         { type = 1, link = "item:5", sources = { "Creature-0-1-0-1-732-AAAA", 1 } } }
		fire("LOOT_READY"); fire("LOOT_READY"); fire("LOOT_OPENED"); fire("LOOT_CLOSED")
		obs = db.found.items[1000]
		assert(obs and #obs == 1 and obs[1].kind == "drop"
			and obs[1].npc == 732 and obs[1].count == 1, "creature drop saved once, as one sighting per loot window")
	end)
	it("non-recipe item ignored", function()
		assert(db.found.items[5] == nil, "non-recipe item ignored")
	end)
	it("npc name and position noted", function()
		assert(db.npcs[732] and db.npcs[732].name == "Murloc Lurker" and db.npcs[732].positions[1429], "npc name and position noted")
	end)
	it("object drop saved", function()
		fire("UNIT_SPELLCAST_SENT", "player", "Battered Chest")
		loot = { { type = 1, link = "item:1000", sources = { "GameObject-0-1-0-1-106318-BBBB", 1 } } }
		fire("LOOT_READY"); fire("LOOT_CLOSED")
		assert(#db.found.items[1000] == 2 and db.objects[106318] and db.objects[106318].name == "Battered Chest", "object drop saved")
	end)
	-- Fails if an object opened without a cast takes the name of an older cast at something else.
	it("an object is not named after an old cast's target", function()
		fire("UNIT_SPELLCAST_SENT", "player", "Murloc Lurker")
		clock = clock + 30
		loot = { { type = 1, link = "item:1000", sources = { "GameObject-0-1-0-1-106319-DDDD", 1 } } }
		fire("LOOT_READY"); fire("LOOT_CLOSED")
		assert(db.objects[106319] and db.objects[106319].name == nil, "an object is not named after an old cast's target")
	end)
	it("container drop saved", function()
		table.remove(db.found.items[1000]) -- keep the sightings the checks below count
		loot = { { type = 1, link = "item:1000", sources = { "Item-1-0-ABC", 1 } } }
		fire("LOOT_READY"); fire("LOOT_CLOSED")
		assert(db.found.items[1000][3].container == 10456, "container drop saved")
	end)
	it("fishing kept by zone, not bobber", function()
		fishing = true
		loot = { { type = 1, link = "item:1000", sources = { "GameObject-0-1-0-1-35591-CCCC", 1 } } }
		fire("LOOT_READY"); fire("LOOT_CLOSED"); fishing = false
		f4 = db.found.items[1000][4]
		assert(f4 and f4.fishing == 1429 and f4.object == nil and f4.x == 0.5, "fishing kept by zone, not bobber")
	end)
	it("pending link noted", function()
		assert(db.pendingItems[1000] ~= nil, "pending link noted")
	end)
	-- Fails if the line loses the family's shape, the count, or who it came from.
	it("the announcement says what was taken in and from whom", function()
		assert(messages[1] ~= nil
			and messages[1]:find("Boltgrip's", 1, true) ~= nil and messages[1]:find("Recipe Vacuum", 1, true) ~= nil
			and messages[1]:find("whirs and rattles. Intake complete! 1 recipe from Murloc Lurker!", 1, true) ~= nil,
			"the announcement says what was taken in and from whom")
	end)

	-- 3. Quests: giver at detail, finisher at complete, choice flag kept
	local q
	it("quest saved once with giver and finisher", function()
		target.questnpc, target.questnpcname = "Creature-0-1-1-1-4784-DDDD", "Argent Guard Manados"
		quest = { id = 1199, rewards = {}, choices = { 2000, 7 } }
		fire("QUEST_DETAIL")
		target.questnpc, target.questnpcname = "Creature-0-1-1-1-1444-EEEE", "Brother Kristoff"
		fire("QUEST_COMPLETE")
		q = db.found.items[2000]
		assert(q and #q == 1 and q[1].quest == 1199 and q[1].npc == 4784 and q[1].finisher == 1444 and q[1].choice == true,
			"quest saved once with giver and finisher")
	end)
	-- Fails if a quest giver is saved for a quest with no recipe reward.
	it("quest NPCs are saved only with a recipe reward", function()
		target.questnpc, target.questnpcname = "Creature-0-1-1-1-9999-FFFF", "Innkeeper Farley"
		quest = { id = 77, rewards = {}, choices = { 7 } }
		fire("QUEST_DETAIL")
		assert(db.npcs[4784] ~= nil and db.npcs[1444] ~= nil and db.npcs[9999] == nil, "quest NPCs are saved only with a recipe reward")
	end)

	-- 3c. Profession ranks (Ranks.lua). Fails if a book used just before a cap rise is not kept as the source of
	-- that profession's rank from its old cap; if a rise long after a use, or two rises at once, are credited
	-- (two at once raised a Lua error before); or if a trainer's already-known step or a child skill line is
	-- recorded.
	describe("profession ranks", function()
		local hooks, caps, rankFrame, taught = {}, { [185] = 150, [186] = 75 }, nil, nil
		local stepType, stepSpell = "used", 4036
		it("a book used before a cap rise is that rank's source", function()
			hooksecurefunc = function(_, name, fn) hooks[name] = fn end
			C_Container = { GetContainerItemID = function() return 2000 end }
			GetProfessions = function() return nil, nil, nil, 1, 2 end
			GetProfessionInfo = function(index)
				if index == 1 then return "Mining", 0, 1, caps[186], 0, 0, 186 end
				return "Cooking", 0, 150, caps[185], 0, 0, 185
			end
			taught = a.GetTaughtRecipe
			a.GetTaughtRecipe = function() return false end -- item 2000 stands in for a book: it teaches no recipe
			local framesBefore = #frames
			load("Ranks.lua", a)
			rankFrame = frames[framesBefore + 1]
			rankFrame.script(rankFrame, "PLAYER_LOGIN")
			hooks.UseContainerItem(0, 1)
			caps[185] = 225
			rankFrame.script(rankFrame, "SKILL_LINES_CHANGED")
			local from150 = db.ranks[185] and db.ranks[185][150]
			assert(from150 and from150.items[2000] ~= nil, "a book used before a cap rise is that rank's source")
		end)
		it("a cap rise long after a use is not credited to it", function()
			hooks.UseContainerItem(0, 1)
			clock = clock + 60
			caps[185] = 300
			rankFrame.script(rankFrame, "SKILL_LINES_CHANGED")
			assert(db.ranks[185][225] == nil, "a cap rise long after a use is not credited to it")
		end)
		it("two caps rising at once are credited to nothing, without an error", function()
			hooks.UseContainerItem(0, 1)
			caps[185], caps[186] = 375, 150
			local ok = pcall(rankFrame.script, rankFrame, "SKILL_LINES_CHANGED")
			assert(ok and db.ranks[185][300] == nil
				and (db.ranks[186] == nil or db.ranks[186][75] == nil), "two caps rising at once are credited to nothing, without an error")
		end)
		-- Fails if an item whose data has not loaded is taken for a book: "no answer yet" is not "teaches nothing".
		it("an item not yet loaded is not taken for a book", function()
			a.GetTaughtRecipe = function() return nil end
			hooks.UseContainerItem(0, 1)
			caps[185] = 450
			rankFrame.script(rankFrame, "SKILL_LINES_CHANGED")
			assert(db.ranks[185][375] == nil, "an item not yet loaded is not taken for a book")
		end)
		-- Trainer steps: a "used" Apprentice Engineer step, and a Journeyman Mining step under skill line 2946.
		it("a trainer's already-known step is not recorded", function()
			a.GetTaughtRecipe = taught
			C_TooltipInfo = C_TooltipInfo or {}
			Enum.TooltipDataType = Enum.TooltipDataType or { Spell = 1 }
			GetTrainerServiceStepIndex = function() return 1 end
			GetTrainerServiceInfo = function() return "rank", stepType end
			C_TooltipInfo.GetTrainerService = function() return { type = Enum.TooltipDataType.Spell, id = stepSpell } end
			C_TradeSkillUI.GetTradeSkillLineForRecipe = function(spell)
				if spell == 2576 then return 2946, "Mining", 186 end
				return 202, "Engineering", nil
			end
			assert(a.NoteTrainerRank(1702) == false, "a trainer's already-known step is not recorded")
		end)
		it("a rank under a child skill line is kept under its profession, at the character's cap", function()
			stepType, stepSpell = "unavailable", 2576
			assert(a.NoteTrainerRank(5392) and db.ranks[186] and db.ranks[186][150] and db.ranks[186][150].npcs[5392] ~= nil
				and db.ranks[2946] == nil, "a rank under a child skill line is kept under its profession, at the character's cap")
		end)
	end)

	-- 3b. Group rolls: a recipe someone else looted is kept by zone; one the player looted adds nothing.
	-- Fails if a roll records no find, names a mob it cannot know, or doubles the player's own loot.
	local rolled
	it("a roll is kept by zone", function()
		rollLinks[1], rollLinks[2] = "item:3000", "item:1000"
		fire("START_LOOT_ROLL", 1)
		fire("START_LOOT_ROLL", 2) -- item 1000 was in the player's own loot window above
		rolled = db.found.items[3000]
		assert(rolled and #rolled == 1 and rolled[1].kind == "drop" and rolled[1].zone == 1429
			and rolled[1].npc == nil and select(1, a.SourceInfo(rolled[1])) == UNKNOWN, "a roll is kept by zone")
	end)
	it("a roll on an item the player looted adds nothing", function()
		local zoneRows = 0
		for _, o in ipairs(db.found.items[1000]) do if o.zone then zoneRows = zoneRows + 1 end end
		assert(zoneRows == 0, "a roll on an item the player looted adds nothing")
	end)

	-- 4. SourceInfo names each kind
	local function info(o) local n, p, m = a.SourceInfo(o); return n, p and next(p), m end
	it("SourceInfo creature", function() assert(info(obs[1]) == "Murloc Lurker", "SourceInfo creature") end)
	it("SourceInfo object", function() assert(info(db.found.items[1000][2]) == "Battered Chest", "SourceInfo object") end)
	it("SourceInfo container", function() assert(info(db.found.items[1000][3]) == "A Bulging Coin Purse", "SourceInfo container") end)
	it("SourceInfo fishing", function()
		assert(select(1, info(f4)) == "Fishing" and select(2, info(f4)) == 1429, "SourceInfo fishing")
	end)
	it("SourceInfo quest", function() assert(info(q[1]) == "Quest Title 1199", "SourceInfo quest") end)

	-- 4b. Specialization lock from the made item: an unmet skill requirement without a rank locks.
	-- Fails if a rank requirement or a met line locks, the answer comes before the item loads, or a later session rereads known items.
	describe("specialization lock", function()
		-- The tooltip's own red and white, as measured in game (ffff2020, ffffffff).
		local red, white = { r = 1, g = 0.125, b = 0.125 }, { r = 1, g = 1, b = 1 }
		local MADE = 5000 -- recipe N makes item MADE + N; recipe 5 makes nothing
		-- A Gnomish engineer: its own specialization's line is met, the other's is not.
		local requirements = {
			[1] = { { "Requires Goblin Engineer", red } },
			[2] = { { "Requires Engineering (300)", red } },
			[3] = { { "Requires Gnomish Engineer", white } },
			[4] = { { "Requires Engineering (260)", red }, { "Requires Goblin Engineer", red } },
		}
		local itemLoaded, itemReads, loadCallbacks = {}, 0, {}
		it("no answer while the made item loads", function()
			Enum.TooltipDataLineType.UsageRequirement = 1
			Enum.TooltipDataUsageRequirementType.Faction, Enum.TooltipDataUsageRequirementType.Skill = 1, 2
			C_TradeSkillUI = { GetRecipeSchematic = function(id) return { outputItemID = id ~= 5 and MADE + id or nil } end,
				GetTradeSkillLineForRecipe = function() return 202 end, GetRecipeInfo = function() return nil end }
			C_Item.IsItemDataCachedByID = function(id) return itemLoaded[id] == true end
			Item = { CreateFromItemID = function(_, id) return { ContinueOnItemLoad = function(_, fn) loadCallbacks[id] = fn end } end }
			C_Timer.After = function(_, fn) fn() end
			C_TooltipInfo = { GetItemByID = function(id)
				itemReads = itemReads + 1
				local lines = { { leftText = "Name" } }
				for _, l in ipairs(requirements[id - MADE] or {}) do
					table.insert(lines, { type = 1, requirementType = 2, leftText = l[1], leftColor = l[2] })
				end
				return { lines = lines }
			end }
			assert(a.GetRecipeLock(1) == nil and itemReads == 0, "no answer while the made item loads")
		end)
		it("no lock while no met specialization has been seen", function()
			itemLoaded[MADE + 1] = true
			loadCallbacks[MADE + 1]()
			assert(a.GetRecipeLock(1) == false, "no lock while no met specialization has been seen")
		end)
		-- The list build reads every recipe of the profession; the met line on recipe 3 shows the pick.
		it("specialization lock uses the made item's requirement line", function()
			for id = 2, 4 do itemLoaded[MADE + id] = true end
			for id = 1, 5 do a.ReadSpecialization(id) end
			assert(a.GetRecipeLock(1) == "Requires Goblin Engineer"
				and a.GetRecipeLock(2) == false and a.GetRecipeLock(3) == false and a.GetRecipeLock(4) == "Requires Goblin Engineer"
				and a.GetRecipeLock(5) == false, "specialization lock uses the made item's requirement line")
		end)
		-- Before a specialization is picked every such line is unmet, and nothing locks.
		it("no lock before a specialization is picked", function()
			local a3 = boot(nil)
			requirements[3][1][2] = red
			for id = 1, 5 do a3.ReadSpecialization(id) end
			assert(a3.GetRecipeLock(1) == false and a3.GetRecipeLock(3) == false
				and a3.GetRecipeLock(4) == false, "no lock before a specialization is picked")
			requirements[3][1][2] = white
		end)
		-- A later session: recipes known to need no specialization are not looked up again.
		it("kept facts spare the lookups", function()
			local kept = db.recipeFacts
			local a2 = boot(nil); a2.db.recipeFacts = kept
			itemReads = 0
			assert(a2.GetRecipeLock(2) == false and a2.GetRecipeLock(5) == false and itemReads == 0
				and a2.ReadSpecialization(3) == true and a2.GetRecipeLock(1) == "Requires Goblin Engineer" and itemReads == 2,
				"kept facts spare the lookups")
		end)
		it("a locked recipe gets the lock mark first, left of the source marks", function()
			local marks = {}
			local n = a.GetMarks({ lockReason = "x" }, marks)
			assert(n == 2 and marks[1] == "locked" and marks[2] == "unknown",
				"a locked recipe gets the lock mark first, left of the source marks")
		end)
	end)

	-- 5. Sharing: every new kind round-trips, re-merge is a no-op
	local rows, b, bFrames, s, sq, badFaction
	it("merge rows", function()
		rows = a.FindsSince(0, math.huge)
		b = boot(nil)
		bFrames = frames
		assert(b.MergeFinds(rows, #rows) == true, ("merge %d rows"):format(#rows))
	end)
	it("shared drop kinds intact", function()
		s = b.db.shared.items[1000]
		local kinds = {}
		for _, o in ipairs(s or {}) do kinds[o.npc and "npc" or o.object and "object" or o.container and "container" or o.fishing and "fishing"] = true end
		assert(kinds.npc and kinds.object and kinds.container and kinds.fishing, "shared drop kinds intact")
	end)
	it("shared object name", function()
		assert(b.db.objects[106318] and b.db.objects[106318].name == "Battered Chest", "shared object name")
	end)
	it("shared quest intact", function()
		sq = b.db.shared.items[2000]
		assert(sq and sq[1].quest == 1199 and sq[1].npc == 4784 and sq[1].finisher == 1444, "shared quest intact")
	end)
	it("re-merge changes nothing", function()
		assert(b.MergeFinds(rows, #rows) == false, "re-merge changes nothing")
	end)
	-- Fails if the quest giver's own faction is not saved, not shared, or a bad value is accepted.
	it("NPC faction saved and shared", function()
		assert(db.npcs[4784].faction == "Alliance" and b.db.npcs[4784].faction == "Alliance", "NPC faction saved and shared")
		badFaction = CopyTable(rows[1]); badFaction.nf = "Pirates"
	end)

	-- 2b. Drop places and scope. Fails if a drop loses its subzone, dungeon, own spot or count; if the same
	-- creature in another subzone merges into one sighting; or if the scope labels or Show Map rules
	-- stop following the thresholds (one creature; 2 creatures in one zone; 3 zones).
	describe("drop places and scope", function()
		local d, lf, firstRevision, seen, kill
		it("a repeat drop counts without a new revision", function()
			d = boot(nil)
			d.db.selfFound = true -- the option's default, which the stubbed settings page does not set
			for _, f in ipairs(frames) do if f.events.LOOT_READY then lf = f end end
			kill = function(guid, area, instance)
				place.area, place.instance = area, instance
				target.target = guid
				loot = { { type = 1, link = "item:2000", sources = { guid, 1 } } }
				lf.script(lf, "LOOT_READY"); lf.script(lf, "LOOT_CLOSED")
			end
			kill("Creature-0-1-0-1-900-A", 41)
			firstRevision = d.db.exchange.revision
			kill("Creature-0-1-0-1-900-A", 41)
			-- Fails if each repeat kill adds a revision: a farming session would grow every reply by one row a kill.
			assert(d.db.exchange.revision == firstRevision, "a repeat drop counts without a new revision")
		end)
		it("a drop keeps its subzone, its own spot and a count", function()
			seen = d.db.found.items[2000]
			assert(seen and #seen == 1 and seen[1].area == 41 and seen[1].map == 1429
				and seen[1].x == 0.5 and seen[1].count == 2, "a drop keeps its subzone, its own spot and a count")
		end)
		it("the same creature in another subzone is a separate sighting", function()
			kill("Creature-0-1-0-1-900-A", 42)
			assert(#d.db.found.items[2000] == 2, "the same creature in another subzone is a separate sighting")
		end)
		it("one creature is a single-creature drop", function()
			local single = d.DropScope(d.db.found.items[2000])
			assert(single.scope == "single" and single.times == 3 and single.creatures == 1 and single.places == 1,
				"one creature is a single-creature drop")
		end)
		it("two creatures in one zone is a zone drop", function()
			kill("Creature-0-1-0-1-901-B", 41)
			local zone = d.DropScope(d.db.found.items[2000])
			assert(zone.scope == "zone" and zone.place.kind == "map" and zone.place.id == 1429, "two creatures in one zone is a zone drop")
		end)
		it("a dungeon drop keeps the dungeon, not the subzone", function()
			kill("Creature-0-1-0-1-902-C", nil, 36)
			assert(d.db.found.items[2000][4].instance == 36 and d.db.found.items[2000][4].area == nil,
				"a dungeon drop keeps the dungeon, not the subzone")
		end)
		it("three zones is a world drop", function()
			local world = d.DropScope({ { kind = "drop", npc = 1, map = 1 }, { kind = "drop", npc = 2, map = 2 }, { kind = "drop", npc = 3, map = 3 } })
			assert(world.scope == "world" and world.places == 3, "three zones is a world drop")
		end)
		it("a shared drop carries its subzone, its own spot and its count", function()
			local sent = d.FindsSince(0, math.huge)
			local wired
			for _, row in ipairs(sent) do if row.i == 2000 and row.n == 900 and row.a == 41 then wired = row end end
			assert(wired and wired.cn == 2 and wired.x == 0.5 and wired.m == 1429, "a shared drop carries its subzone, its own spot and its count")
		end)
		-- Fails if one's own copy of a drop with no spot hides a friend's copy that has one: Show on Map gets nothing.
		it("the same drop seen twice shows the copy with a spot", function()
			d.db.found.items[3000] = { { kind = "drop", npc = 950, map = 1429 } }
			d.db.shared.items[3000] = { { kind = "drop", npc = 950, map = 1429, x = 0.25, y = 0.75 } }
			local listed = d.GetItemSources(3000)
			assert(listed and #listed == 1 and listed[1].x == 0.25, "the same drop seen twice shows the copy with a spot")
			place.area, place.instance = 40, nil
		end)
	end)
	-- Fails if one bad row makes the whole batch refused: the same batch is refused again on every ask, and
	-- nothing more arrives from that player.
	it("a bad row is dropped and the rest of its batch still merges", function()
		local m = boot(nil)
		local changed, skipped = m.MergeFinds({ { k = "vendor", i = 1000, n = 1, a = 5 }, { k = "vendor", i = 1000, n = 2 } }, 2)
		local vendors = {}
		for _, o in ipairs(m.db.shared.items[1000] or {}) do vendors[o.npc] = true end
		assert(changed == true and skipped == 1
			and vendors[2] and not vendors[1], "a bad row is dropped and the rest of its batch still merges")
	end)
	-- Fails if a row of a kind a newer version adds makes an older version refuse the whole batch, which would
	-- stop every later find from that player arriving.
	it("a row of an unknown kind is skipped and the rest merge", function()
		local m = boot(nil)
		local merged = m.MergeFinds({ { k = "rank", r = 3464, n = 1, s = 500 },
			{ k = "vendor", i = 1000, n = 4, m = 1429, x = 0.5, y = 0.5, s = 500 } }, 2)
		assert(merged == true and m.db.shared.items[1000] ~= nil
			and m.db.shared.recipes[3464] == nil, "a row of an unknown kind is skipped and the rest merge")
	end)
	-- Fails if two same-second reports of one drop merge into a spot neither stood at, or a drop without its
	-- own spot takes the creature's position on another map.
	describe("same-second drop reports", function()
		local m
		it("a drop's spot merges as one pair", function()
			m = boot(nil)
			m.MergeFinds({ { k = "drop", i = 1000, n = 77, m = 1429, x = 0.9, y = 0.1, s = 500 } }, 1)
			m.MergeFinds({ { k = "drop", i = 1000, n = 77, m = 1429, x = 0.1, y = 0.9, s = 500 } }, 1)
			local merged = m.db.shared.items[1000][1]
			assert((merged.x == 0.9 and merged.y == 0.1) or (merged.x == 0.1 and merged.y == 0.9), "a drop's spot merges as one pair")
		end)
		it("a drop without its own spot gets no pin from another map", function()
			m.db.npcs[78] = { name = "Elsewhere", positions = { [1430] = { x = 0.5, y = 0.5, seen = 1 } } }
			local _, positions, map = m.SourceInfo({ kind = "drop", npc = 78, map = 1429 })
			assert(positions == nil and map == 1429, "a drop without its own spot gets no pin from another map")
		end)
	end)

	-- 5b. Merging never loses detail. Fails if a newer row without a cost clears it, an older row cannot fill a gap, a newer value does not correct an older one, or a repeat counts as a change.
	describe("merging never loses detail", function()
		local m, newerNoCost, kept
		local function row(seen, extra)
			local wire = { k = "trainer", r = 7001, n = 9001, nm = "Teacher", m = 1, x = 0.5, y = 0.5, s = seen, b = 1 }
			for key, value in pairs(extra) do wire[key] = value end
			return wire
		end
		it("a merge fills gaps and keeps what was known", function()
			m = boot(nil)
			newerNoCost = row(200, { sk = 75 })
			m.MergeFinds({ row(100, { c = 500 }) }, 1)
			m.MergeFinds({ newerNoCost }, 1)
			m.MergeFinds({ row(50, { sp = 1234, c = 1 }) }, 1)
			kept = m.db.shared.recipes[7001][1]
			assert(kept.cost == 500 and kept.skill == 75 and kept.spellID == 1234 and kept.seen == 200,
				"a merge fills gaps and keeps what was known")
		end)
		it("the same facts again change nothing", function()
			assert(m.MergeFinds({ newerNoCost }, 1) == false, "the same facts again change nothing")
		end)
		it("a newer sighting corrects an older value", function()
			m.MergeFinds({ row(300, { c = 800 }) }, 1)
			assert(kept.cost == 800 and kept.seen == 300, "a newer sighting corrects an older value")
		end)
	end)
	-- 5c. Merge order does not matter. Fails if a later report about one field is lost because another field's report already advanced the record.
	it("reports merge to the same result in any order", function()
		local function report(seen, extra)
			local wire = { k = "trainer", r = 7002, n = 9002, nm = "Teacher", m = 1, x = 0.5, y = 0.5, s = seen, b = 1 }
			for key, value in pairs(extra) do wire[key] = value end
			return wire
		end
		local reports = { report(100, { c = 100 }), report(300, { sk = 75 }), report(200, { c = 200 }) }
		local function final(order)
			local side = boot(nil)
			for _, index in ipairs(order) do side.MergeFinds({ reports[index] }, 1) end
			local kept = side.db.shared.recipes[7002][1]
			return kept.cost, kept.skill, kept.seen
		end
		local cost1, skill1, seen1 = final({ 1, 2, 3 })
		local cost2, skill2, seen2 = final({ 3, 2, 1 })
		assert(cost1 == 200 and skill1 == 75 and seen1 == 300
			and cost2 == 200 and skill2 == 75 and seen2 == 300, "reports merge to the same result in any order")
	end)
	it("an unknown NPC faction is rejected", function()
		assert(Rejected(boot(nil), badFaction), "an unknown NPC faction is rejected")
	end)
	-- A source both received and seen firsthand is listed once: the same creature in the same place.
	it("own and shared find of one source listed once", function()
		b.db.sourceLevel, b.db.recipeItems[99] = 2, { 1000 }
		local sharedCreature
		for _, o in ipairs(s) do if o.npc == 732 then sharedCreature = o end end
		b.db.found.items[1000] = { { kind = "drop", npc = 732, seen = now, map = sharedCreature.map, area = sharedCreature.area,
			instance = sharedCreature.instance } }
		assert(#b.GetSources({ recipeID = 99 }) == #s, "own and shared find of one source listed once")
	end)
	-- Fails if the other faction's vendor or trainer is offered as a source (Deck, 2026-11-26: an Alliance character was shown Undercity's).
	it("the other faction's NPCs are no source", function()
		b.db.recipeItems[98] = nil
		b.db.npcs[4577] = { name = "Millie Gregorian", faction = "Horde", positions = {} }
		b.db.npcs[5174] = { name = "Springspindle Fizzlegear", faction = "Alliance", positions = {} }
		b.db.found.recipes[98] = { { kind = "vendor", npc = 4577, seen = now }, { kind = "vendor", npc = 5174, seen = now } }
		local sources = b.GetSources({ recipeID = 98 })
		assert(#sources == 1 and sources[1].npc == 5174, "only this faction's vendor")
	end)
	-- A received recipe item links to the recipe its tooltip data names once loaded. Fails if a link is made early, from anything but that ID, or for an item that teaches nothing.
	local RED_LINEN_BAG = 501
	local cached = {}
	it("link waits while an item's data loads", function()
		C_Item.IsItemDataCachedByID = function(id) return cached[id] == true end
		Enum.TooltipDataLineType.ItemSpellTriggerLearn = 38
		local teaches = { [2000] = RED_LINEN_BAG }
		C_TooltipInfo.GetItemByID = function(id)
			return { lines = { { type = 22, leftText = "Pattern" }, teaches[id] and { type = 38, spellID = teaches[id] } or nil } }
		end
		assert(b.LinkPending() == false and b.db.itemRecipe[2000] == nil, "link waits while an item's data loads")
	end)
	-- Fails if a second call reports completion while an item is still loading, or a failed load is never asked again.
	local requests = 0
	local function ItemDataResult(id, success)
		for _, f in ipairs(bFrames) do
			if f.events.ITEM_DATA_LOAD_RESULT then f.script(f, "ITEM_DATA_LOAD_RESULT", id, success) end
		end
	end
	it("an item still loading is not asked twice and keeps the link incomplete", function()
		C_Item.RequestLoadItemDataByID = function() requests = requests + 1 end
		assert(b.LinkPending() == false and requests == 0, "an item still loading is not asked twice and keeps the link incomplete")
	end)
	it("a failed load is asked again on a later call", function()
		for id in pairs(b.db.pendingItems) do ItemDataResult(id, false) end
		assert(b.LinkPending() == false and requests > 0, "a failed load is asked again on a later call")
	end)
	it("link made from the recipe ID in the item's tooltip", function()
		-- The client reports each item's data as it arrives.
		for id in pairs(b.db.pendingItems) do
			cached[id] = true
			ItemDataResult(id, true)
		end
		assert(b.LinkPending() == true and b.db.itemRecipe[2000] == RED_LINEN_BAG
			and b.db.recipeItems[RED_LINEN_BAG][1] == 2000 and b.db.pendingItems[2000] == nil,
			"link made from the recipe ID in the item's tooltip")
	end)
	it("an item that teaches nothing stays unlinked and is not asked again", function()
		assert(b.db.itemRecipe[1000] == nil and b.db.pendingItems[1000].none == true,
			"an item that teaches nothing stays unlinked and is not asked again")
	end)
	-- An item that never answers is asked three times at most, then stops blocking.
	it("a silent load is asked again after a while, three times at most", function()
		b.db.pendingItems[2999] = {}
		requests = 0
		local started = clock
		for _ = 1, 5 do
			b.LinkPending()
			clock = clock + 11
		end
		local complete = b.LinkPending()
		clock = started
		assert(requests == 3 and complete == true, "a silent load is asked again after a while, three times at most")
	end)

	-- Seed data answers before item data loads and stays out of the saved data. Fails if a seeded pair is ignored, or a seeded item gets a saved link or waits in pending.
	local d
	it("seed links an item with no item data loaded", function()
		local seedSave = { schema = 6, found = { recipes = {}, items = {} }, shared = { recipes = {}, items = {} },
			itemRecipe = { [7777] = 888, [9999] = 111 }, recipeItems = { [888] = { 7777 }, [111] = { 9999 } },
			pendingItems = { [7778] = {} }, npcs = {}, objects = {} }
		RecipeVacuumDB = nil
		loaded = {}; frames = {}
		local nsd = { Perf = function() end, PerfMs = function() end, InitSettings = function() end, ResumeWatch = function() end,
			ScheduleFindOffer = function() end, SourcesChanged = function() end, seed = { build = 71037, taught = { [7777] = 888, [7778] = 888 } } }
		RecipeVacuumDB = seedSave
		for _, file in ipairs({ "Data/Included.lua", "Core.lua", "Voice.lua", "Sources.lua", "Finds.lua", "Record.lua" }) do load(file, nsd) end
		for _, entry in ipairs(loaded) do if entry[1] == "RecipeVacuum" then entry[2]() end end
		d = nsd
		assert(d.GetSeededRecipe(7777) == 888, "seed links an item with no item data loaded")
	end)
	it("seed gives a recipe its items", function()
		local seededItems = d.GetRecipeItems(888)
		assert(seededItems and #seededItems == 2 and seededItems[1] == 7777, "seed gives a recipe its items")
	end)
	it("saved data keeps no link or waiting item the seed covers", function()
		assert(d.db.itemRecipe[7777] == nil and d.db.recipeItems[888] == nil
			and d.db.pendingItems[7778] == nil and d.db.itemRecipe[9999] == 111, "saved data keeps no link or waiting item the seed covers")
	end)

	-- 6. Validation rejects malformed new rows
	it("reject drop with two sources", function() assert(Rejected(b, { k = "drop", i = 1, n = 1, o = 2 }), "reject drop with two sources") end)
	it("reject quest without quest id", function() assert(Rejected(b, { k = "quest", i = 1 }), "reject quest without quest id") end)
	it("reject vendor carrying a quest", function() assert(Rejected(b, { k = "vendor", i = 1, n = 1, q = 5 }), "reject vendor carrying a quest") end)
	it("reject bad object name", function() assert(Rejected(b, { k = "drop", i = 1, o = 2, on = "x|cff" }), "reject bad object name") end)
	it("reject unknown fishing zone", function() assert(Rejected(b, { k = "drop", i = 1, fi = UNKNOWN_MAP }), "reject unknown fishing zone") end)
	it("reject an item that is not a recipe item", function() assert(Rejected(b, { k = "drop", i = 777, n = 1 }), "reject an item that is not a recipe item") end)
	it("reject a position with one coordinate", function() assert(Rejected(b, { k = "drop", i = 1, fi = 1, x = 0.5 }), "reject a position with one coordinate") end)
	it("reject a drop carrying a quest", function() assert(Rejected(b, { k = "drop", i = 1, n = 1, q = 5 }), "reject a drop carrying a quest") end)
	it("reject unknown roll zone", function() assert(Rejected(b, { k = "drop", i = 1, z = UNKNOWN_MAP }), "reject unknown roll zone") end)
	it("shared roll keeps its zone", function()
		assert(b.db.shared.items[3000] and b.db.shared.items[3000][1].zone == 1429, "shared roll keeps its zone")
	end)
	it("reject more rows than the limit", function() assert(b.MergeFinds(rows, #rows - 1) == nil, "reject more rows than the limit") end)

	-- 6b. Come across: a chat-linked or nearby-looted recipe is kept with how near it arrived and nothing else.
	-- Fails if a link is missed, a non-recipe is kept, who or where is saved, a farther sighting weakens a nearer one, or a recipe shows below its level.
	describe("come across", function()
		local h, known, chat, met
		it("links are noticed with how near they arrived", function()
			h = boot(nil)
			known = C_TradeSkillUI
			C_TradeSkillUI = { GetTradeSkillLineForRecipe = function(id) return id == 5555 and 202 or nil end }
			load("Heard.lua", h)
			local heard = frames[#frames]
			chat = function(event, text) heard.script(heard, event, text, "Someone-Realm") end
			chat("CHAT_MSG_PARTY", "look |cffffffff|Hitem:1000::::|h[Pattern: Test]|h|r and |Hitem:777::::|h[A Sword]|h")
			chat("CHAT_MSG_CHANNEL", "WTS |Henchant:5555|h[Engineering: Gizmo]|h and |Henchant:4444|h[Not a recipe]|h")
			chat("CHAT_MSG_CHANNEL", "again |Hitem:1000::::|h[Pattern: Test]|h")
			met = h.db.met
			assert(met.items[1000] == 2 and met.recipes[5555] == 3
				and met.items[777] == nil and met.recipes[4444] == nil, "links are noticed with how near they arrived")
		end)
		it("nothing about who or where is kept", function()
			local onlyLevels = true
			for _, bucket in pairs(met) do for _, value in pairs(bucket) do onlyLevels = onlyLevels and type(value) == "number" end end
			assert(onlyLevels, "nothing about who or where is kept")
		end)
		it("a nearer sighting replaces a farther one", function()
			chat("CHAT_MSG_GUILD", "mine |Henchant:5555|h[Engineering: Gizmo]|h")
			assert(met.recipes[5555] == 2, "a nearer sighting replaces a farther one")
		end)
		-- Fails if a stranger's whisper counts as a friend's: at the default level it would show the recipe.
		it("a stranger's whisper counts as public chat", function()
			h.IsTrusted = function() return false end -- Sharing.lua, not loaded here
			chat("CHAT_MSG_WHISPER", "psst |Hitem:1001::::|h[Pattern: Other]|h")
			assert(met.items[1001] == 3, "a stranger's whisper counts as public chat")
			C_TradeSkillUI = known
		end)
	end)

	-- 6c. The unlearned recipes panel, built on the owner's Steam Deck as a prototype.
	describe("panel", function()
		local pns, queue, buttons, traces, init, Fake, inLine
		local made = {} -- every stand-in frame, in creation order
		local function Flush() while #queue > 0 do table.remove(queue, 1)() end end
		local function Names()
			local names = {}
			for _, button in ipairs(buttons) do if button:IsShown() and rawget(button, "recipe") then names[#names + 1] = button.Label.text end end
			table.sort(names)
			return names
		end
		local function Bands()
			local bands = {}
			for _, button in ipairs(buttons) do if button:IsShown() and rawget(button, "band") then bands[#bands + 1] = button.band end end
			table.sort(bands)
			return bands
		end
		local function Builds()
			local builds = 0
			for _, line in ipairs(traces) do if line:find("UI panel shown", 1, true) then builds = builds + 1 end end
			return builds
		end
		local realCreateFrame
		it("loads on a stand-in window", function()
			pns = boot(nil)
			realCreateFrame = CreateFrame
			queue, buttons, traces = {}, {}, {}
			local meta = {}
			meta.__index = function(_, key)
				if key == "IsShown" then return function(o) local parent = rawget(o, "parent"); return rawget(o, "shown") ~= false and (not parent or parent:IsShown()) end end
				if key == "Show" or key == "Hide" then return function(o) o.shown = key == "Show" end end
				if key == "SetShown" then return function(o, v) o.shown = v end end
				if key == "SetText" then return function(o, v) o.text = v end end
				if key == "GetText" then return function(o) return rawget(o, "text") or "" end end
				if key == "SetScript" or key == "HookScript" then return function(o, name, fn) local scripts = rawget(o, "scripts") or {}; o.scripts = scripts; scripts[name] = fn end end
				if key == "CreateFontString" or key == "CreateTexture" or key == "CreateMaskTexture" then return function(o) return Fake(o) end end
				if key == "GetStringHeight" then return function() return 0 end end
				if key == "GetFrameLevel" then return function() return 1 end end
				return function() end
			end
			function Fake(parent) return setmetatable({ parent = parent }, meta) end
			-- The parts Blizzard's recipe list templates create (Blizzard_ProfessionsRecipeList.xml).
			local parts = {
				ProfessionsRecipeListRecipeTemplate = { "Label", "Count", "SkillUps", "LockedIcon" },
				ProfessionsRecipeListCategoryTemplate = { "RankBar", "ButtonText" },
				ScrollFrameTemplate = { "ScrollBar" },
				-- Blizzard_SharedXML SharedUIPanelTemplates.xml: the portrait frame's close button, background and top streaks.
				PortraitFrameTemplate = { "CloseButton", "Bg", "TopTileStreaks" },
				ProfessionsButtonTemplate = { "Icon", "IconBorder" }, -- Blizzard_ProfessionsTemplates.xml:42
			}
			CreateFrame = function(kind, _, parent, template)
				local f = Fake(parent)
				made[#made + 1] = f
				if kind == "Button" then f.shown = true; buttons[#buttons + 1] = f end
				for _, key in ipairs(parts[template] or {}) do f[key] = Fake(f) end
				if rawget(f, "ButtonText") then f.ButtonText.GetStringWidth = function() return 0 end end
				if rawget(f, "Rank") then f.Rank.Text = Fake(f.Rank) end
				return f
			end
			C_AddOns = { GetAddOnMetadata = function() return "@project-version@" end }
			RunNextFrame = function(fn) queue[#queue + 1] = fn end
			Enum.TradeskillRelativeDifficulty = { Optimal = 0, Medium = 1, Easy = 2, Trivial = 3 }
			Enum.UITextureSliceMode = { Stretched = 0, Tiled = 1 } -- UITextureConstantsDocumentation.lua
			local color = { GetRGB = function() return 1, 1, 1 end }
			color.WrapTextInColorCode = function(_, text) return text end
			HIGHLIGHT_FONT_COLOR, DISABLED_FONT_COLOR = color, color
			CaseAccentInsensitiveParse = function(text) return text:lower() end
			GetUIPanel = function() return nil end
			InCombatLockdown = function() return false end
			hooksecurefunc = function(owner, name, fn)
				if type(owner) == "string" then return end
				local original = owner[name]
				owner[name] = function(...) original(...); fn(...) end
			end
			C_Texture = { GetAtlasInfo = function() return nil end }
			debugprofilestop = os.clock
			ProfessionsFrame = Fake()
			ProfessionsFrame.CraftingPage = Fake(ProfessionsFrame)
			ProfessionsFrame.CraftingPage.Init = function() end
			ProfessionsFrame.CraftingPage.RecipeList = Fake(ProfessionsFrame.CraftingPage)
			ProfessionsFrame.CraftingPage.RecipeList.SearchBox = Fake()
			Professions = { InLocalCraftingMode = function() return true end, GetFirstRecipe = function(r) return r end }
			-- Four unlearned recipes: a known source, come across near, come across far, never seen.
			local recipes = { [101] = "Plans: Sourced", [102] = "Plans: Near", [103] = "Plans: Far", [104] = "Plans: Unseen",
			  [105] = "Plans: No Skill", [106] = "Plans: Later Expansion", [107] = "Plans: High" }
			inLine = { [106] = 999 } -- every other recipe is in the open skill line
			C_TradeSkillUI = { IsTradeSkillReady = function() return true end,
			  GetAllRecipeIDs = function() return { 101, 102, 103, 104, 105, 106, 107 } end,
			  GetRecipeInfo = function(id) return { recipeID = id, name = recipes[id], categoryID = 1, learned = false, maxTrivialLevel = id, icon = 1 } end,
			  IsRecipeInSkillLine = function(id, line) return (inLine[id] or line) == line end,
			  GetCategoryInfo = function() return { categoryID = 1, name = "Category", uiOrder = 1 } end,
			  GetOnlyShowMakeableRecipes = function() return false end, GetShowUnlearned = function() return true end,
			  GetOnlyShowSkillUpRecipes = function() return false end, GetOnlyShowFirstCraftRecipes = function() return false end,
			  GetRecipeSchematic = function() return nil end }
			load("Unlearned.lua", pns)
			pns.GetRecipeFaction = function() return false end -- read from tooltip data
			pns.GetRecipeLock = function() return false end
			pns.UpdateRankMark = function() end -- Ranks.lua is not loaded here
			pns.db.found.recipes[101] = { { kind = "trainer", count = 1, skill = 30 } }
			pns.db.met.recipes[102] = pns.LEVEL.FRIENDS
			pns.db.met.recipes[103] = pns.LEVEL.PUBLIC
			pns.Trace = function(text, ...) traces[#traces + 1] = text:format(...) end
			load("Panel.lua", pns)
			for _, entry in ipairs(loaded) do if entry[1] == "Blizzard_Professions" then entry[2]() end end
			init = function(skill) ProfessionsFrame.CraftingPage.Init(ProfessionsFrame.CraftingPage, { professionID = 164, skillLevel = skill or 40, maxSkillLevel = 75 }) end
		end)
		-- Fails if each Init of the crafting page, several in one frame as the window opens, rebuilds the list: the owner's window froze for 6 s.
		it("several Init calls in one frame build the list once", function()
			for _ = 1, 5 do init() end
			Flush()
			assert(Builds() == 1, "several Init calls in one frame build the list once")
		end)
		-- Fails if a heading says "Skill 76 to 150" where the game names the rank, or breaks where no rank spell is known.
		it("a band heading is the rank spell's subtext, or the skill range without one", function()
			local seed, spells = pns.seed, C_Spell
			pns.seed = { rankSpell = { [164] = { [2] = 3100 } } }
			local spellLoaded, waiting = false, nil
			C_Spell = {
				GetSpellSubtext = function(id) return id == 3100 and spellLoaded and "Journeyman" or "" end,
				IsSpellDataCached = function() return spellLoaded end,
			}
			local spellMixin = Spell
			Spell = { CreateFromSpellID = function() return { ContinueOnSpellLoad = function(_, fn) waiting = fn end } end }
			local ok, err = pcall(function()
				-- Fails if a rank the client has not spellLoaded yet stays on the fallback (Deck, 2026-11-26: only Apprentice showed).
				local filled
				assert(pns.BandTitle(164, 2, function() filled = pns.BandTitle(164, 2) end) == "Skill 76 to 150", "not spellLoaded yet")
				spellLoaded = true
				waiting()
				assert(filled == "Journeyman", "the rank spell's subtext once spellLoaded")
				assert(pns.BandTitle(164, 3) == "Skill 151 to 225", "a step with no spell")
				assert(pns.BandTitle(999, 2) == "Skill 76 to 150", "a profession with no spells")
			end)
			pns.seed, C_Spell, Spell = seed, spells, spellMixin
			assert(ok, err)
		end)
		-- Fails if the discovery count (found over total) counts the wrong recipes: found is what the show rule lists, total every unlearned
		-- candidate of the skill line, whichever category holds it.
		it("the discovery count is the listed recipes over every candidate of the skill line", function()
			local categories, isListed = pns.GetUnlearnedRecipes, pns.IsListed
			pns.IsListed = function(recipeInfo) return recipeInfo.listed end
			local cases = {
				{ name = "none found", categories = { { false, false } }, found = 0, total = 2 },
				{ name = "some found across categories", categories = { { true, false }, { true } }, found = 2, total = 3 },
				{ name = "all found", categories = { { true, true } }, found = 2, total = 2 },
				{ name = "nothing to learn", categories = {}, found = 0, total = 0 },
			}
			local ok, err = pcall(function()
				for _, case in ipairs(cases) do
					local built, id = {}, 0
					for _, flags in ipairs(case.categories) do
						local recipes = {}
						for _, listed in ipairs(flags) do
							id = id + 1
							recipes[#recipes + 1] = { recipeID = id, name = "R" .. id, requiredSkill = id, listed = listed }
						end
						built[#built + 1] = { recipes = recipes }
					end
					pns.GetUnlearnedRecipes = function() return built end
					local list, _, total = pns.GetListedRecipes({ professionID = 164 })
					assert(#list == case.found and total == case.total, case.name .. ": " .. #list .. "/" .. total)
				end
			end)
			pns.GetUnlearnedRecipes, pns.IsListed = categories, isListed
			assert(ok, err)
		end)
		-- Fails if recipes with no source and never come across, or come across beyond the level, are listed: 518 rows for Blacksmithing.
		it("lists only recipes with a known source or come across within the level", function()
			init(300)
			Flush()
			local names = Names()
			assert(#names == 2 and names[1] == "Plans: Near" and names[2] == "Plans: Sourced", "lists only recipes with a known source or come across within the level")
		end)
		-- Fails if a recipe lands in the wrong rank band, the lowest of two sources is not taken, a band above the character's skill starts open,
		-- or a band below it starts closed. Open bands list their recipes; closed ones only their heading.
		it("recipes land in their rank band and bands above the skill start collapsed", function()
			pns.db.met.recipes[105] = pns.LEVEL.FRIENDS
			pns.db.met.recipes[103] = pns.LEVEL.FRIENDS
			pns.db.met.recipes[102] = pns.LEVEL.FRIENDS
			pns.db.met.recipes[107] = pns.LEVEL.FRIENDS
			-- 101: trainer 30 and the seed 90, so 30; 102 at the band's top (75); 103 just past it; 105 has none, so its trivial level 105; 107 at 200.
			pns.seed = { taught = {}, learnSkill = { [101] = 90, [102] = 75, [103] = 76, [107] = 200 } }
			local cases = {
				{ skill = 1, bands = { 1, 2, 3 }, shown = { "Plans: Near", "Plans: Sourced" } },
				{ skill = 75, bands = { 1, 2, 3 }, shown = { "Plans: Near", "Plans: Sourced" } },
				{ skill = 76, bands = { 1, 2, 3 }, shown = { "Plans: Far", "Plans: Near", "Plans: No Skill", "Plans: Sourced" } },
				{ skill = 300, bands = { 1, 2, 3 }, shown = { "Plans: Far", "Plans: High", "Plans: Near", "Plans: No Skill", "Plans: Sourced" } },
			}
			for _, case in ipairs(cases) do
				pns.ClearUnlearnedCache()
				init(case.skill)
				Flush()
				assert(table.concat(Names(), ",") == table.concat(case.shown, ","), "skill " .. case.skill .. " shows " .. table.concat(Names(), ","))
				assert(table.concat(Bands(), ",") == table.concat(case.bands, ","), "skill " .. case.skill .. " has bands " .. table.concat(Bands(), ","))
			end
		end)
		-- Fails if events or Init calls with the same content rebuild the list: the owner's log showed "UI panel shown" every 2 to 30 seconds with
		-- no input, which re-anchored the rows under the gamepad cursor. A skill rise inside a band and a refreshed cache change no content.
		it("an event with unchanged content does not rebuild", function()
			pns.ClearUnlearnedCache()
			init(300)
			Flush()
			local builds = Builds()
			for skill = 301, 303 do
				pns.ClearUnlearnedCache()
				init(skill)
				init(skill)
				Flush()
			end
			assert(Builds() == builds, "an event with unchanged content does not rebuild")
		end)
		-- Fails if a recipe with many reagents grows the details until the list has fewer than 6 rows of room: the list is what the panel is for.
		it("many reagents leave the list its rows and scroll inside the details", function()
			local schematic = {} -- these stand-ins stay for the specs after: the selection and its details stay too
			local ok, err = pcall(function()
				PlaySound, SOUNDKIT = function() end, { UI_90_BLACKSMITHING_TREEITEMCLICK = 1 }
				ITEM_MIN_SKILL, TRADESKILL_REAGENT_COUNT, PROFESSIONS_REAGENT_CONTAINER_LABEL = "%s %d", "%d/%d", "Reagents:"
				RED_FONT_COLOR, TextureKitConstants, GameTooltip_Hide = HIGHLIGHT_FONT_COLOR, { IgnoreAtlasSize = 1 }, function() end
				Enum.CraftingReagentType = { Basic = 1 }
				WowStyle1FilterDropdownStateEnabled = "classic"
				C_Item = { GetItemCount = function() return 0 end, GetItemNameByID = function(id) return "Reagent " .. id end,
					GetItemIconByID = function() return 1 end, GetItemQualityByID = function() return 1 end }
				Professions = { InLocalCraftingMode = function() return true end, GetFirstRecipe = function(r) return r end,
					SetupOutputIconCommon = function() end, GetProfessionBackgroundAtlas = function() end }
				pns.SourceRows, pns.SortTargets = function() return {} end, function() end
				C_TradeSkillUI.GetRecipeSchematic = function() return schematic end
				local standIn = CreateFrame
				local function Measured(frame)
					frame.GetFontString = function() return Fake(frame) end
					frame.GetHeight, frame.GetVerticalScroll = function() return 0 end, function() return 0 end -- the list keeps the selected row in view
					return frame
				end
				CreateFrame = function(...) return Measured(standIn(...)) end
				for _, frame in ipairs(made) do Measured(frame) end
				local panel, detail = pns.PanelRankParent(), nil
				for _, frame in ipairs(made) do if rawget(frame, "ReagentsLabel") then detail = frame end end
				panel.GetTop, panel.GetBottom = function() return 800 end, function() return 100 end
				local list = ProfessionsFrame.CraftingPage.RecipeList
				list.GetTop, list.GetBottom = function() return 728 end, function() return 150 end -- 72 below the panel's top, 50 above its bottom
				detail.SetHeight = function(self, height) self.height = height end
				pns.ClearUnlearnedCache()
				init(300)
				Flush()
				local row
				for _, button in ipairs(buttons) do if button:IsShown() and rawget(button, "recipe") then row = row or button end end
				local function Pick(reagents)
					schematic.reagentSlotSchematics = {}
					for id = 1, reagents do schematic.reagentSlotSchematics[id] = { reagentType = 1, quantityRequired = 1, reagents = { { itemID = id } } } end
					detail.recipeID = nil
					row.scripts.OnClick(row, "LeftButton")
				end
				local room = 800 - 100 - 72 - 50
				Pick(8)
				assert(room - detail.height >= 6 * 21, "8 reagents leave the list " .. room - detail.height .. " high")
				Pick(2)
				assert(detail.height > 150 and detail.height < room - 6 * 21, "2 reagents fit without scrolling: " .. detail.height)
			end)
			schematic.reagentSlotSchematics = {}
			assert(ok, err)
		end)
		-- Fails if a recipe of another expansion's skill line shows, however found: 518 Blacksmithing rows came from the client's whole list.
		it("a recipe outside the open skill line never shows", function()
			pns.db.found.recipes[106] = { { kind = "trainer", count = 1, skill = 10 } }
			pns.seed.learnSkill[106] = 10
			pns.ClearUnlearnedCache()
			init(300)
			Flush()
			for _, name in ipairs(Names()) do assert(name ~= "Plans: Later Expansion", "shows a recipe of another skill line") end
			CreateFrame = realCreateFrame
		end)
	end)

	-- 7. Reload is stable
	it("reload keeps schema and revision", function()
		local savedDB = a.db
		RecipeVacuumDB = savedDB; loaded = {}
		local c = { Perf = function() end, PerfMs = function() end, InitSettings = function() end, ResumeWatch = function() end, ScheduleFindOffer = function() end, SourcesChanged = function() end }
		for _, file in ipairs({ "Data/Included.lua", "Core.lua", "Voice.lua", "Sources.lua", "Finds.lua", "Record.lua" }) do load(file, c) end
		for _, entry in ipairs(loaded) do if entry[1] == "RecipeVacuum" then entry[2]() end end
		assert(c.db.schema == 12 and c.db.exchange.revision == savedDB.exchange.revision, "reload keeps schema and revision")
	end)
end)
