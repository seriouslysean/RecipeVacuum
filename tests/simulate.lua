-- Offline checks for schema 4, drop and quest recording, and sharing of the new kinds.
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
ChatTypeInfo = { SYSTEM = { r = 1, g = 1, b = 0 } }
local messages = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) messages[#messages + 1] = text end }
C_Timer = { NewTimer = function() return { Cancel = function() end } end }
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

local function load(file, ns) local f = assert(loadfile(repo .. "/" .. file)); f("RecipeVacuum", ns) end
local function boot(saved)
  RecipeVacuumDB = nil; loaded = {}; frames = {}
  if saved then dofile(saved) end
  local ns = { InitSettings = function() end, ResumeWatch = function() end, ScheduleFindOffer = function() end, SourcesChanged = function() end }
  for _, file in ipairs({ "Data/Included.lua", "Core.lua", "Sources.lua", "Finds.lua", "Record.lua" }) do load(file, ns) end
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
check("schema is 4", db.schema == 4)
check("trainerNames dropped", db.found.trainerNames == nil and db.shared.trainerNames == nil)
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

-- 4. SourceInfo names each kind
local function info(o) local n, p, m = a.SourceInfo(o); return n, p and next(p), m end
check("SourceInfo creature", info(obs[1]) == "Murloc Lurker")
check("SourceInfo object", info(db.found.items[1000][2]) == "Battered Chest")
check("SourceInfo container", info(db.found.items[1000][3]) == "A Bulging Coin Purse")
check("SourceInfo fishing", select(1, info(f4)) == "Fishing" and select(2, info(f4)) == 1429)
check("SourceInfo quest", info(q[1]) == "Quest Title 1199")

-- 5. Sharing: every new kind round-trips, re-merge is a no-op
local rows = a.FindsSince(0, math.huge)
local b = boot(nil)
check(("merge %d rows"):format(#rows), b.MergeFinds(rows, #rows) == true)
local s = b.db.shared.items[1000]
local kinds = {}
for _, o in ipairs(s or {}) do kinds[o.npc and "npc" or o.object and "object" or o.container and "container" or o.fishing and "fishing"] = true end
check("shared drop kinds intact", kinds.npc and kinds.object and kinds.container and kinds.fishing)
check("shared object name", b.db.objects[106318] and b.db.objects[106318].name == "Battered Chest")
local sq = b.db.shared.items[2000]
check("shared quest intact", sq and sq[1].quest == 1199 and sq[1].npc == 4784 and sq[1].finisher == 1444)
check("re-merge changes nothing", b.MergeFinds(rows, #rows) == false)
-- A source both received and seen firsthand is listed once
b.db.shareWithFriends, b.db.recipeItems[99] = true, { 1000 }
b.db.found.items[1000] = { { kind = "drop", npc = 732, seen = now } }
check("own and shared find of one source listed once", #b.GetSources({ recipeID = 99 }) == #s)
-- A received recipe item links to its recipe once the client has loaded the item's name
local RED_LINEN_BAG = 501
local byName, inProfession = { ["red linen bag"] = { RED_LINEN_BAG } }, { [RED_LINEN_BAG] = "red linen bag" }
b.GetRecipeFaction = function() return false end -- a recipe both factions learn
itemNames[1000], itemNames[6342] = "Pattern: Something Else", "Pattern: Another"
check("link waits while an item name loads", b.LinkPending(byName, inProfession, TAILORING) == false and b.db.itemRecipe[2000] == nil)
itemNames[2000] = "Pattern: Red Linen Bag"
check("link made once the name is loaded", b.LinkPending(byName, inProfession, TAILORING) == true and b.db.itemRecipe[2000] == RED_LINEN_BAG
  and b.db.pendingItems[2000] == nil and b.db.pendingItems[1000] ~= nil)

-- 6. Validation rejects malformed new rows
check("reject drop with two sources", b.MergeFinds({ { k = "drop", i = 1, n = 1, o = 2 } }, 10) == nil)
check("reject quest without quest id", b.MergeFinds({ { k = "quest", i = 1 } }, 10) == nil)
check("reject vendor carrying a quest", b.MergeFinds({ { k = "vendor", i = 1, n = 1, q = 5 } }, 10) == nil)
check("reject bad object name", b.MergeFinds({ { k = "drop", i = 1, o = 2, on = "x|cff" } }, 10) == nil)
check("reject unknown fishing zone", b.MergeFinds({ { k = "drop", i = 1, fi = UNKNOWN_MAP } }, 10) == nil)
check("reject more rows than the limit", b.MergeFinds(rows, #rows - 1) == nil)

-- 7. Reload is stable
local savedDB = a.db
RecipeVacuumDB = savedDB; loaded = {}
local c = { InitSettings = function() end, ResumeWatch = function() end, ScheduleFindOffer = function() end, SourcesChanged = function() end }
for _, file in ipairs({ "Data/Included.lua", "Core.lua", "Sources.lua", "Finds.lua", "Record.lua" }) do load(file, c) end
for _, entry in ipairs(loaded) do if entry[1] == "RecipeVacuum" then entry[2]() end end
check("reload keeps schema and revision", c.db.schema == 4 and c.db.exchange.revision == savedDB.exchange.revision)
print(FAILED and "SOME CHECKS FAILED" or "ALL CHECKS PASSED")
os.exit(FAILED and 1 or 0)
