-- Offline checks for the current schema, drop and quest recording, and sharing of the new kinds.
-- luajit tests/simulate.lua . <a RecipeVacuum saved-variables file>
local repo, savedFile = arg[1], arg[2]
local now = 1795470000
local loaded, frames = {}, {}
local function check(label, ok) print((ok and "PASS " or "FAIL ") .. label); if not ok then FAILED = true end end

-- client stubs
EventUtil = { ContinueOnAddOnLoaded = function(name, fn) loaded[#loaded + 1] = { name, fn } end }
C_AddOns = { GetAddOnMetadata = function() return "Recipe Vacuum" end }
GetServerTime = function() return now end
GetBuildInfo = function() return "1.60.1", "71037", "", 16001 end
local UNKNOWN_MAP = 999999
C_Map = { GetMapInfo = function(id) return id and id > 0 and id ~= UNKNOWN_MAP and { name = "Map" .. id } or nil end,
  GetBestMapForUnit = function() return 1429 end,
  GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.25 end } end }
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
function tDeleteItem(t, v) for i = #t, 1, -1 do if t[i] == v then table.remove(t, i) end end end
function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end end
function CopyTable(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
function strsplit(sep, s) local out = {} for part in (s .. sep):gmatch("(.-)%" .. sep) do out[#out + 1] = part end return unpack(out) end
issecretvalue = function() return false end
local TAILORING, TAILORING_PATTERN = 7, 2
Enum = { ItemClass = { Recipe = 9 }, LootSlotType = { Item = 1 }, Profession = { Tailoring = TAILORING },
  ItemRecipeSubclass = { Tailoring = TAILORING_PATTERN },
  TooltipDataLineType = {}, TooltipDataUsageRequirementType = {} }
local recipeItems = { [6342] = true, [1000] = true, [2000] = true }
local itemNames = { [10456] = "A Bulging Coin Purse" } -- names the client has loaded
C_Item = { GetItemInfoInstant = function(x) local id = tonumber(x) or tonumber(tostring(x):match("item:(%d+)"))
    return id, nil, nil, nil, nil, recipeItems[id] and 9 or 7, TAILORING_PATTERN end,
  GetItemIDByGUID = function(guid) return guid == "Item-1-0-ABC" and 10456 or nil end,
  GetItemNameByID = function(id) return itemNames[id] end,
  RequestLoadItemDataByID = function() end }
C_Spell = { GetSpellName = function() return "Fishing" end }
C_QuestLog = { GetTitleForQuestID = function(id) return "Quest Title " .. id end }
UnitFactionGroup = function() return "Alliance", "Alliance" end
local target = {}
UnitGUID = function(unit) return target[unit] end
UnitName = function(unit) return target[unit .. "name"] end
ChatTypeInfo = { SYSTEM = { r = 1, g = 1, b = 0 }, MONSTER_SAY = { r = 1, g = 1, b = 0.62 } }
local messages = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) messages[#messages + 1] = text end }
C_Timer = { NewTimer = function() return { Cancel = function() end } end, After = function(_, fn) fn() end }
local clock = 1000
GetTime = function() return clock end
UNKNOWN = "Unknown"
local rollLinks = {}
GetLootRollItemLink = function(rollID) return rollLinks[rollID] end
CreateFrame = function() local f = { events = {} }
  function f:RegisterEvent(e) self.events[e] = true end
  function f:UnregisterEvent(e) self.events[e] = nil end
  function f:SetScript(_, fn) self.script = fn end
  frames[#frames + 1] = f; return f end
local loot = {}
GetNumLootItems = function() return #loot end
GetLootSlotType = function(i) return loot[i].type end
GetLootSlotLink = function(i) return loot[i].link end
GetLootSourceInfo = function(i) return unpack(loot[i].sources) end
local fishing = false
IsFishingLoot = function() return fishing end
local quest = {}
GetQuestID = function() return quest.id end
GetNumQuestRewards = function() return #quest.rewards end
GetNumQuestChoices = function() return #quest.choices end
GetQuestItemInfo = function(kind, i) local id = (kind == "reward" and quest.rewards or quest.choices)[i]
  return "", 1, 1, 1, true, id end

debugprofilestop = function() return 0 end -- the checkout build times itself
local function load(file, ns) local f = assert(loadfile(repo .. "/" .. file)); f("RecipeVacuum", ns) end
local function boot(saved)
  RecipeVacuumDB = nil; loaded = {}; frames = {}
  if saved then dofile(saved) end
  local ns = { Perf = function() end, PerfMs = function() end, InitSettings = function() end, ResumeWatch = function() end, ScheduleFindOffer = function() end, SourcesChanged = function() end }
  for _, file in ipairs({ "Data/Included.lua", "Core.lua", "Voice.lua", "Sources.lua", "Finds.lua", "Record.lua" }) do load(file, ns) end
  ns.SourcesChanged = function() end
  for _, entry in ipairs(loaded) do if entry[1] == "RecipeVacuum" then entry[2]() end end
  return ns
end
local function count(layer) local r, i = 0, 0 for _, l in pairs(layer.recipes) do r = r + #l end for _, l in pairs(layer.items) do i = i + #l end return r, i end

-- 1. Schema 3 -> 4 on the owner's real save
dofile(savedFile); local before = RecipeVacuumDB
local beforeRecipes, beforeItems = count(before.found)
local beforeRevision = before.exchange.revision
local a = boot(savedFile)
local db = a.db
check("schema is 8", db.schema == 8)
check("trainerNames dropped", db.found.trainerNames == nil and db.shared.trainerNames == nil)
-- Fails if the upgrade keeps NPCs no source names (earlier versions saved every vendor opened), or
-- drops one a source does name.
local named, strays, missing = {}, 0, 0
for _, layer in ipairs({ db.found, db.shared }) do
  for _, bucket in ipairs({ layer.recipes, layer.items }) do
    for _, list in pairs(bucket) do for _, o in ipairs(list) do
      if o.npc then named[o.npc] = true end
      if o.finisher then named[o.finisher] = true end
    end end
  end
end
for id in pairs(db.npcs) do if not named[id] then strays = strays + 1 end end
for id in pairs(named) do if not db.npcs[id] then missing = missing + 1 end end
local savedNPCs = 0 for _ in pairs(before.npcs) do savedNPCs = savedNPCs + 1 end
local keptNPCs = 0 for _ in pairs(db.npcs) do keptNPCs = keptNPCs + 1 end
print(("  NPCs: %d saved before, %d kept"):format(savedNPCs, keptNPCs))
check("only NPCs a source names are kept, and none of those is lost", strays == 0 and missing == 0 and keptNPCs > 0)
local r, i = count(db.found)
check(("found kept (%d recipes, %d items)"):format(r, i), r == beforeRecipes and i == beforeItems)
check("revision unchanged by migration", db.exchange.revision == beforeRevision)
check("objects table created", type(db.objects) == "table")

-- 2. Drops: creature, object, container, fishing; a non-recipe item is ignored
local lootFrame
for _, f in ipairs(frames) do if f.events.LOOT_READY then lootFrame = f end end
local function fire(event, ...) lootFrame.script(lootFrame, event, ...) end
target.target, target.targetname = "Creature-0-1-0-1-732-AAAA", "Murloc Lurker"
loot = { { type = 1, link = "item:1000", sources = { "Creature-0-1-0-1-732-AAAA", 1 } },
         { type = 1, link = "item:5", sources = { "Creature-0-1-0-1-732-AAAA", 1 } } }
fire("LOOT_READY"); fire("LOOT_READY"); fire("LOOT_OPENED"); fire("LOOT_CLOSED")
local obs = db.found.items[1000]
check("creature drop saved once", obs and #obs == 1 and obs[1].kind == "drop" and obs[1].npc == 732)
check("non-recipe item ignored", db.found.items[5] == nil)
check("npc name and position noted", db.npcs[732] and db.npcs[732].name == "Murloc Lurker" and db.npcs[732].positions[1429])
fire("UNIT_SPELLCAST_SENT", "player", "Battered Chest")
loot = { { type = 1, link = "item:1000", sources = { "GameObject-0-1-0-1-106318-BBBB", 1 } } }
fire("LOOT_READY"); fire("LOOT_CLOSED")
check("object drop saved", #db.found.items[1000] == 2 and db.objects[106318] and db.objects[106318].name == "Battered Chest")
loot = { { type = 1, link = "item:1000", sources = { "Item-1-0-ABC", 1 } } }
fire("LOOT_READY"); fire("LOOT_CLOSED")
check("container drop saved", db.found.items[1000][3].container == 10456)
fishing = true
loot = { { type = 1, link = "item:1000", sources = { "GameObject-0-1-0-1-35591-CCCC", 1 } } }
fire("LOOT_READY"); fire("LOOT_CLOSED"); fishing = false
local f4 = db.found.items[1000][4]
check("fishing kept by zone, not bobber", f4 and f4.fishing == 1429 and f4.object == nil and f4.x == 0.5)
check("pending link noted", db.pendingItems[1000] ~= nil)
check("announce names the source", messages[1] and messages[1]:find("Murloc Lurker", 1, true) ~= nil)

-- 3. Quests: giver at detail, finisher at complete, choice flag kept
target.questnpc, target.questnpcname = "Creature-0-1-1-1-4784-DDDD", "Argent Guard Manados"
quest = { id = 1199, rewards = {}, choices = { 2000, 7 } }
fire("QUEST_DETAIL")
target.questnpc, target.questnpcname = "Creature-0-1-1-1-1444-EEEE", "Brother Kristoff"
fire("QUEST_COMPLETE")
local q = db.found.items[2000]
check("quest saved once with giver and finisher", q and #q == 1 and q[1].quest == 1199 and q[1].npc == 4784 and q[1].finisher == 1444 and q[1].choice == true)
-- Fails if a quest giver is saved for a quest with no recipe reward.
target.questnpc, target.questnpcname = "Creature-0-1-1-1-9999-FFFF", "Innkeeper Farley"
quest = { id = 77, rewards = {}, choices = { 7 } }
fire("QUEST_DETAIL")
check("quest NPCs are saved only with a recipe reward", db.npcs[4784] ~= nil and db.npcs[1444] ~= nil and db.npcs[9999] == nil)

-- 3b. Group rolls: a recipe someone else looted is kept by zone; one the player looted adds nothing.
-- Fails if a roll records no find, names a mob it cannot know, or doubles the player's own loot.
recipeItems[3000] = true
rollLinks[1], rollLinks[2] = "item:3000", "item:1000"
fire("START_LOOT_ROLL", 1)
fire("START_LOOT_ROLL", 2) -- item 1000 was in the player's own loot window above
local rolled = db.found.items[3000]
check("a roll is kept by zone", rolled and #rolled == 1 and rolled[1].kind == "drop" and rolled[1].zone == 1429
  and rolled[1].npc == nil and select(1, a.SourceInfo(rolled[1])) == UNKNOWN)
local zoneRows = 0
for _, o in ipairs(db.found.items[1000]) do if o.zone then zoneRows = zoneRows + 1 end end
check("a roll on an item the player looted adds nothing", zoneRows == 0)

-- 4. SourceInfo names each kind
local function info(o) local n, p, m = a.SourceInfo(o); return n, p and next(p), m end
check("SourceInfo creature", info(obs[1]) == "Murloc Lurker")
check("SourceInfo object", info(db.found.items[1000][2]) == "Battered Chest")
check("SourceInfo container", info(db.found.items[1000][3]) == "A Bulging Coin Purse")
check("SourceInfo fishing", select(1, info(f4)) == "Fishing" and select(2, info(f4)) == 1429)
check("SourceInfo quest", info(q[1]) == "Quest Title 1199")

-- 4b. Specialization lock: read from the item a recipe makes. An unmet skill requirement with no rank
-- locks, in the game's own words. Fails if a rank requirement locks (nearly every unlearned recipe
-- has one), a met one does, the answer is given before the item has loaded, or a later session reads
-- items it already knows need no specialization.
do
  -- The tooltip's own red and white, as measured in game (ffff2020, ffffffff).
  local red, white = { r = 1, g = 0.125, b = 0.125 }, { r = 1, g = 1, b = 1 }
  Enum.TooltipDataLineType.UsageRequirement = 1
  Enum.TooltipDataUsageRequirementType.Faction, Enum.TooltipDataUsageRequirementType.Skill = 1, 2
  local MADE = 5000 -- recipe N makes item MADE + N; recipe 5 makes nothing
  -- A Gnomish engineer: its own specialization's line is met, the other's is not.
  local requirements = {
    [1] = { { "Requires Goblin Engineer", red } },
    [2] = { { "Requires Engineering (300)", red } },
    [3] = { { "Requires Gnomish Engineer", white } },
    [4] = { { "Requires Engineering (260)", red }, { "Requires Goblin Engineer", red } },
  }
  C_TradeSkillUI = { GetRecipeSchematic = function(id) return { outputItemID = id ~= 5 and MADE + id or nil } end,
    GetTradeSkillLineForRecipe = function() return 202 end }
  local itemLoaded, itemReads, loadCallbacks = {}, 0, {}
  C_Item.IsItemDataCachedByID = function(id) return itemLoaded[id] == true end
  Item = { CreateFromItemID = function(_, id) return { ContinueOnItemLoad = function(_, fn) loadCallbacks[id] = fn end } end }
  C_Timer.After = function(_, fn) fn() end
  local refreshes = 0
  a.RefreshRows = function() refreshes = refreshes + 1 end
  C_TooltipInfo = { GetItemByID = function(id)
    itemReads = itemReads + 1
    local lines = { { leftText = "Name" } }
    for _, l in ipairs(requirements[id - MADE] or {}) do
      table.insert(lines, { type = 1, requirementType = 2, leftText = l[1], leftColor = l[2] })
    end
    return { lines = lines }
  end }
  check("no answer while the made item loads", a.GetRecipeLock(1) == nil and itemReads == 0)
  itemLoaded[MADE + 1] = true
  loadCallbacks[MADE + 1]()
  check("rows redraw once the made item has loaded", refreshes == 1)
  check("no lock while no met specialization has been seen", a.GetRecipeLock(1) == false)
  -- The list build reads every recipe of the profession; the met line on recipe 3 shows the pick.
  for id = 2, 4 do itemLoaded[MADE + id] = true end
  for id = 1, 5 do a.ReadSpecialization(id) end
  check("specialization lock uses the made item's requirement line", a.GetRecipeLock(1) == "Requires Goblin Engineer"
    and a.GetRecipeLock(2) == false and a.GetRecipeLock(3) == false and a.GetRecipeLock(4) == "Requires Goblin Engineer"
    and a.GetRecipeLock(5) == false)
  -- Before a specialization is picked every such line is unmet, and nothing locks.
  local a3 = boot(nil)
  requirements[3][1][2] = red
  for id = 1, 5 do a3.ReadSpecialization(id) end
  check("no lock before a specialization is picked", a3.GetRecipeLock(1) == false and a3.GetRecipeLock(3) == false
    and a3.GetRecipeLock(4) == false)
  requirements[3][1][2] = white
  -- A later session: recipes known to need no specialization are not looked up again.
  local kept = db.recipeFacts
  local a2 = boot(nil); a2.db.recipeFacts = kept
  itemReads = 0
  check("kept facts spare the lookups", a2.GetRecipeLock(2) == false and a2.GetRecipeLock(5) == false and itemReads == 0
    and a2.ReadSpecialization(3) == true and a2.GetRecipeLock(1) == "Requires Goblin Engineer" and itemReads == 2)
  local marks = {}
  local n = a.GetMarks({ lockReason = "x" }, marks)
  check("a locked recipe gets the lock mark first, left of the source marks", n == 2 and marks[1] == "locked" and marks[2] == "unknown")
end

-- 5. Sharing: every new kind round-trips, re-merge is a no-op
local rows = a.FindsSince(0, math.huge)
local b = boot(nil)
local bFrames = frames
check(("merge %d rows"):format(#rows), b.MergeFinds(rows, #rows) == true)
local s = b.db.shared.items[1000]
local kinds = {}
for _, o in ipairs(s or {}) do kinds[o.npc and "npc" or o.object and "object" or o.container and "container" or o.fishing and "fishing"] = true end
check("shared drop kinds intact", kinds.npc and kinds.object and kinds.container and kinds.fishing)
check("shared object name", b.db.objects[106318] and b.db.objects[106318].name == "Battered Chest")
local sq = b.db.shared.items[2000]
check("shared quest intact", sq and sq[1].quest == 1199 and sq[1].npc == 4784 and sq[1].finisher == 1444)
check("re-merge changes nothing", b.MergeFinds(rows, #rows) == false)
-- Fails if the quest giver's own faction is not saved, not shared, or a bad value is accepted.
check("NPC faction saved and shared", db.npcs[4784].faction == "Alliance" and b.db.npcs[4784].faction == "Alliance")
local badFaction = CopyTable(rows[1]); badFaction.nf = "Pirates"
-- 5b. Merging never loses detail. Fails if a newer row without a cost clears the cost, an older row
-- cannot fill a gap, a newer value does not correct an older one, or repeating a row counts as a change.
do
  local m = boot(nil)
  local function row(seen, extra)
    local wire = { k = "trainer", r = 7001, n = 9001, nm = "Teacher", m = 1, x = 0.5, y = 0.5, s = seen, b = 1 }
    for key, value in pairs(extra) do wire[key] = value end
    return wire
  end
  local newerNoCost = row(200, { sk = 75 })
  m.MergeFinds({ row(100, { c = 500 }) }, 1)
  m.MergeFinds({ newerNoCost }, 1)
  m.MergeFinds({ row(50, { sp = 1234, c = 1 }) }, 1)
  local kept = m.db.shared.recipes[7001][1]
  check("a merge fills gaps and keeps what was known", kept.cost == 500 and kept.skill == 75 and kept.spellID == 1234 and kept.seen == 200)
  check("the same facts again change nothing", m.MergeFinds({ newerNoCost }, 1) == false)
  m.MergeFinds({ row(300, { c = 800 }) }, 1)
  check("a newer sighting corrects an older value", kept.cost == 800 and kept.seen == 300)
end
check("an unknown NPC faction is rejected", boot(nil).MergeFinds({ badFaction }, 1) == nil)
-- A source both received and seen firsthand is listed once
b.db.sourceLevel, b.db.recipeItems[99] = 2, { 1000 }
b.db.found.items[1000] = { { kind = "drop", npc = 732, seen = now } }
check("own and shared find of one source listed once", #b.GetSources({ recipeID = 99 }) == #s)
-- A received recipe item links to the recipe its tooltip data names, once the item has loaded.
-- Fails if a link is made before the data loads, from anything but that ID, or for an item that
-- teaches nothing.
local RED_LINEN_BAG = 501
local cached = {}
C_Item.IsItemDataCachedByID = function(id) return cached[id] == true end
Enum.TooltipDataLineType.ItemSpellTriggerLearn = 38
local teaches = { [2000] = RED_LINEN_BAG }
C_TooltipInfo.GetItemByID = function(id)
  return { lines = { { type = 22, leftText = "Pattern" }, teaches[id] and { type = 38, spellID = teaches[id] } or nil } }
end
check("link waits while an item's data loads", b.LinkPending() == false and b.db.itemRecipe[2000] == nil)
-- Asked once: an item still loading neither blocks the list nor is requested again.
local requests = 0
C_Item.RequestLoadItemDataByID = function() requests = requests + 1 end
check("an unanswered item is not asked twice and no longer blocks", b.LinkPending() == true and requests == 0)
-- The client reports each item's data as it arrives.
for id in pairs(b.db.pendingItems) do
  cached[id] = true
  for _, f in ipairs(bFrames) do
    if f.events.ITEM_DATA_LOAD_RESULT then f.script(f, "ITEM_DATA_LOAD_RESULT", id, true) end
  end
end
check("link made from the recipe ID in the item's tooltip", b.LinkPending() == true and b.db.itemRecipe[2000] == RED_LINEN_BAG
  and b.db.recipeItems[RED_LINEN_BAG][1] == 2000 and b.db.pendingItems[2000] == nil)
check("an item that teaches nothing stays unlinked and is not asked again", b.db.itemRecipe[1000] == nil and b.db.pendingItems[1000].none == true)

-- Seed data answers before any item data loads, gives a recipe its items, and stays out of the saved
-- data. Fails if a seeded pair is ignored, or a seeded item gets a saved link or waits in pending.
local seedSave = { schema = 6, found = { recipes = {}, items = {} }, shared = { recipes = {}, items = {} },
  itemRecipe = { [7777] = 888, [9999] = 111 }, recipeItems = { [888] = { 7777 }, [111] = { 9999 } },
  pendingItems = { [7778] = {} }, npcs = {}, objects = {} }
local seedFile = os.tmpname()
local handle = io.open(seedFile, "w"); handle:write("RecipeVacuumDB = ..."); handle:close()
RecipeVacuumDB = nil
local d
do
  loaded = {}; frames = {}
  local nsd = { Perf = function() end, PerfMs = function() end, InitSettings = function() end, ResumeWatch = function() end,
    ScheduleFindOffer = function() end, SourcesChanged = function() end, seed = { build = 71037, taught = { [7777] = 888, [7778] = 888 } } }
  RecipeVacuumDB = seedSave
  for _, file in ipairs({ "Data/Included.lua", "Core.lua", "Voice.lua", "Sources.lua", "Finds.lua", "Record.lua" }) do load(file, nsd) end
  for _, entry in ipairs(loaded) do if entry[1] == "RecipeVacuum" then entry[2]() end end
  d = nsd
end
os.remove(seedFile)
check("seed links an item with no item data loaded", d.GetSeededRecipe(7777) == 888)
local seededItems = d.GetRecipeItems(888)
check("seed gives a recipe its items", seededItems and #seededItems == 2 and seededItems[1] == 7777)
check("saved data keeps no link or waiting item the seed covers", d.db.itemRecipe[7777] == nil and d.db.recipeItems[888] == nil
  and d.db.pendingItems[7778] == nil and d.db.itemRecipe[9999] == 111)

-- 6. Validation rejects malformed new rows
check("reject drop with two sources", b.MergeFinds({ { k = "drop", i = 1, n = 1, o = 2 } }, 10) == nil)
check("reject quest without quest id", b.MergeFinds({ { k = "quest", i = 1 } }, 10) == nil)
check("reject vendor carrying a quest", b.MergeFinds({ { k = "vendor", i = 1, n = 1, q = 5 } }, 10) == nil)
check("reject bad object name", b.MergeFinds({ { k = "drop", i = 1, o = 2, on = "x|cff" } }, 10) == nil)
check("reject unknown fishing zone", b.MergeFinds({ { k = "drop", i = 1, fi = UNKNOWN_MAP } }, 10) == nil)
check("reject a position with one coordinate", b.MergeFinds({ { k = "drop", i = 1, fi = 1, x = 0.5 } }, 10) == nil)
check("reject a drop carrying a quest", b.MergeFinds({ { k = "drop", i = 1, n = 1, q = 5 } }, 10) == nil)
check("reject unknown roll zone", b.MergeFinds({ { k = "drop", i = 1, z = UNKNOWN_MAP } }, 10) == nil)
check("shared roll keeps its zone", b.db.shared.items[3000] and b.db.shared.items[3000][1].zone == 1429)
check("reject more rows than the limit", b.MergeFinds(rows, #rows - 1) == nil)

-- 6b. Sources filter defaults: a recipe with no known source is hidden until Unknown is ticked; one
-- with a source shows until its type is unticked. Fails if the full game list shows by default.
do
  local kept = a.db.sourceFilter
  a.db.sourceFilter = {}
  local unknown, trained = {}, { sourceTypes = { trainer = true } }
  check("no-source recipes are hidden by default, sourced ones shown",
    a.PassesSourceFilter(unknown) == false and a.PassesSourceFilter(trained) == true)
  a.db.sourceFilter = { unknown = true, trainer = false }
  check("ticking Unknown shows them, unticking a type hides it",
    a.PassesSourceFilter(unknown) == true and a.PassesSourceFilter(trained) == false)
  a.db.sourceFilter = kept
end

-- 6c. Come across: a recipe linked in chat or looted nearby is kept with how near it arrived and
-- nothing else. Fails if a link is missed, a non-recipe is kept, who or where is saved, a farther
-- sighting weakens a nearer one, or a recipe shows below the level it arrived at.
do
  local h = boot(nil)
  StaticPopupDialogs = {}
  local known = C_TradeSkillUI
  C_TradeSkillUI = { GetTradeSkillLineForRecipe = function(id) return id == 5555 and 202 or nil end }
  load("Heard.lua", h)
  local heard = frames[#frames]
  local function chat(event, text) heard.script(heard, event, text, "Someone-Realm") end
  chat("CHAT_MSG_PARTY", "look |cffffffff|Hitem:1000::::|h[Pattern: Test]|h|r and |Hitem:777::::|h[A Sword]|h")
  chat("CHAT_MSG_CHANNEL", "WTS |Henchant:5555|h[Engineering: Gizmo]|h and |Henchant:4444|h[Not a recipe]|h")
  chat("CHAT_MSG_CHANNEL", "again |Hitem:1000::::|h[Pattern: Test]|h")
  local met = h.db.met
  check("links are noticed with how near they arrived", met.items[1000] == 2 and met.recipes[5555] == 3
    and met.items[777] == nil and met.recipes[4444] == nil)
  local onlyLevels = true
  for _, bucket in pairs(met) do for _, value in pairs(bucket) do onlyLevels = onlyLevels and type(value) == "number" end end
  check("nothing about who or where is kept", onlyLevels)
  chat("CHAT_MSG_GUILD", "mine |Henchant:5555|h[Engineering: Gizmo]|h")
  check("a nearer sighting replaces a farther one", met.recipes[5555] == 2)
  h.db.recipeItems[99] = { 1000 }
  local viaItem = { recipeID = 99, name = "x" }
  h.SummarizeSources(viaItem)
  h.db.sourceFilter, h.db.sourceLevel = {}, 2
  local shownAtFriends = h.PassesSourceFilter(viaItem)
  h.db.sourceLevel = 1
  check("a recipe come across shows at its level and not below", viaItem.met == 2 and shownAtFriends == true
    and h.PassesSourceFilter(viaItem) == false)
  C_TradeSkillUI = known
end

-- 7. Reload is stable
local savedDB = a.db
RecipeVacuumDB = savedDB; loaded = {}
local c = { Perf = function() end, PerfMs = function() end, InitSettings = function() end, ResumeWatch = function() end, ScheduleFindOffer = function() end, SourcesChanged = function() end }
for _, file in ipairs({ "Data/Included.lua", "Core.lua", "Voice.lua", "Sources.lua", "Finds.lua", "Record.lua" }) do load(file, c) end
for _, entry in ipairs(loaded) do if entry[1] == "RecipeVacuum" then entry[2]() end end
check("reload keeps schema and revision", c.db.schema == 8 and c.db.exchange.revision == savedDB.exchange.revision)
print(FAILED and "SOME CHECKS FAILED" or "ALL CHECKS PASSED")
os.exit(FAILED and 1 or 0)
